/**
 * Firestore cleanup script to delete a profile and its related references.
 *
 * Usage:
 * 1. Create a service account key with Firestore Admin permissions and save it
 *    as `serviceAccountKey.json` next to this script (or set GOOGLE_APPLICATION_CREDENTIALS).
 * 2. Install dependencies: `npm install firebase-admin` (run in this folder or project root).
 * 3. Run:
 *    node tools/delete_profile.js --profileId=<PROFILE_ID> [--beaconId=<BEACON_ID>] [--project=<PROJECT_ID>]
 *
 * WARNING: This will permanently delete data. Take a Firestore export backup before running.
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const argv = require('minimist')(process.argv.slice(2));
const profileId = argv.profileId || argv.p;
const beaconId = argv.beaconId || argv.b;
const projectId = argv.project || argv.projectId;

if (!profileId) {
  console.error('Missing --profileId argument');
  process.exit(2);
}

// Initialize admin SDK. If GOOGLE_APPLICATION_CREDENTIALS is set, that will be used.
if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  const keyPath = path.join(__dirname, 'serviceAccountKey.json');
  if (fs.existsSync(keyPath)) {
    process.env.GOOGLE_APPLICATION_CREDENTIALS = keyPath;
  }
}

const initOptions = {};
if (projectId) initOptions.projectId = projectId;
admin.initializeApp(initOptions);
const db = admin.firestore();

async function deleteDocIfExists(ref) {
  try {
    await ref.delete();
    console.log('Deleted', ref.path);
  } catch (err) {
    if (err.code === 5 || err.code === 'not-found') {
      // ignore
    } else {
      console.warn('Failed to delete', ref.path, err.message || err);
    }
  }
}

async function deleteCollection(collRef, batchSize = 500) {
  const query = collRef.limit(batchSize);
  return new Promise(async (resolve, reject) => {
    try {
      let deleted = 0;
      do {
        const snapshot = await query.get();
        if (snapshot.size === 0) {
          break;
        }
        const batch = db.batch();
        snapshot.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        deleted = snapshot.size;
        console.log(`Deleted batch of ${deleted} from ${collRef.path}`);
      } while (deleted >= batchSize);
      resolve();
    } catch (err) {
      reject(err);
    }
  });
}

async function removeProfileReferences(profileId) {
  const profilesCol = db.collection('profiles');

  console.log('Scanning profiles to remove follower/like references...');
  const snapshot = await profilesCol.select().get();
  for (const doc of snapshot.docs) {
    const otherId = doc.id;
    if (otherId === profileId) continue;
    // Delete followers/{profileId} under each profile
    const followerRef = profilesCol.doc(otherId).collection('followers').doc(profileId);
    await deleteDocIfExists(followerRef);
    // Delete likes/{profileId} under each profile
    const likeRef = profilesCol.doc(otherId).collection('likes').doc(profileId);
    await deleteDocIfExists(likeRef);
  }

  // Delete any following/likes/followers subcollections under the profile itself
  const myProfileRef = profilesCol.doc(profileId);
  console.log('Deleting subcollections under profiles/' + profileId);
  await deleteCollection(myProfileRef.collection('followers'));
  await deleteCollection(myProfileRef.collection('following'));
  await deleteCollection(myProfileRef.collection('likes'));

  // Delete any streetpass_presences that reference this device or beacon
  if (beaconId) {
    console.log('Removing streetpass_presences for beaconId:', beaconId);
    const presences = await db.collection('streetpass_presences').where('beaconId', '==', beaconId).get();
    for (const p of presences.docs) {
      await deleteDocIfExists(p.ref);
    }
  }
  // deviceId field scan
  console.log('Removing streetpass_presences for deviceId:', profileId);
  const presences2 = await db.collection('streetpass_presences').where('deviceId', '==', profileId).get();
  for (const p of presences2.docs) {
    await deleteDocIfExists(p.ref);
  }

  // Optionally remove other cross references (notifications, encounters) if present
  try {
    const notifications = db.collection('notifications');
    const notifs = await notifications.where('actorId', '==', profileId).get();
    for (const n of notifs.docs) {
      await deleteDocIfExists(n.ref);
    }
  } catch (err) {
    // ignore if collection doesn't exist
  }

  // Finally delete the profile document itself
  console.log('Deleting profile document:', profileId);
  await deleteDocIfExists(myProfileRef);
}

async function main() {
  console.log('This operation is destructive. Make sure you have a backup.');
  console.log('profileId:', profileId, 'beaconId:', beaconId || '<none>');
  const confirm = await promptYesNo('Proceed with deletion? (y/N): ');
  if (!confirm) {
    console.log('Aborted by user.');
    process.exit(0);
  }

  try {
    await removeProfileReferences(profileId);
    console.log('Deletion completed.');
  } catch (err) {
    console.error('Failed to complete deletion:', err);
    process.exit(1);
  }
}

function promptYesNo(question) {
  return new Promise((resolve) => {
    process.stdout.write(question);
    process.stdin.setEncoding('utf8');
    process.stdin.once('data', (data) => {
      const answer = data.toString().trim().toLowerCase();
      resolve(answer === 'y' || answer === 'yes');
    });
  });
}

main();
