const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

// Helper: delete collection in batches
async function deleteCollection(colRef, batchSize = 500) {
  const query = colRef.limit(batchSize);
  let deleted = 0;
  do {
    const snapshot = await query.get();
    if (snapshot.empty) break;
    const batch = db.batch();
    snapshot.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    deleted = snapshot.size;
    console.log(`Deleted batch of ${deleted} from ${colRef.path}`);
  } while (deleted >= batchSize);
}

async function deleteProfileAndReferences(profileId, beaconId = null) {
  const profiles = db.collection('profiles');
  const myRef = profiles.doc(profileId);

  // Remove followers/likes entries referencing this profile under other profiles
  const otherProfilesSnap = await profiles.get();
  for (const other of otherProfilesSnap.docs) {
    if (other.id === profileId) continue;
    const followerRef = profiles.doc(other.id).collection('followers').doc(profileId);
    const likeRef = profiles.doc(other.id).collection('likes').doc(profileId);
    try { await followerRef.delete(); } catch (e) { /* ignore */ }
    try { await likeRef.delete(); } catch (e) { /* ignore */ }
  }

  // Delete subcollections under the profile
  try { await deleteCollection(myRef.collection('followers')); } catch (e) { /* ignore */ }
  try { await deleteCollection(myRef.collection('following')); } catch (e) { /* ignore */ }
  try { await deleteCollection(myRef.collection('likes')); } catch (e) { /* ignore */ }

  // Delete streetpass_presences referencing deviceId or beaconId
  try {
    const presencesByDevice = await db.collection('streetpass_presences').where('deviceId', '==', profileId).get();
    for (const p of presencesByDevice.docs) { await p.ref.delete(); }
  } catch (e) { /* ignore */ }
  if (beaconId) {
    try {
      const presencesByBeacon = await db.collection('streetpass_presences').where('beaconId', '==', beaconId).get();
      for (const p of presencesByBeacon.docs) { await p.ref.delete(); }
    } catch (e) { /* ignore */ }
  }

  // Delete notifications where actorId == profileId (if notifications collection exists)
  try {
    const notifs = await db.collection('notifications').where('actorId', '==', profileId).get();
    for (const n of notifs.docs) { await n.ref.delete(); }
  } catch (e) { /* ignore */ }

  // Finally delete the profile doc itself
  await myRef.delete();
}

exports.deleteUserProfile = functions.https.onCall(async (data, context) => {
  // Only authenticated users can call this
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'The function must be called while authenticated.');
  }

  const uid = context.auth.uid;
  // Allow caller to optionally pass a profileId, but require that the profile
  // belongs to the caller. If not passed, try to find profile with authUid == uid.
  const requestedProfileId = data.profileId || null;
  let targetProfileId = requestedProfileId;
  let beaconId = data.beaconId || null;

  if (!targetProfileId) {
    // Try to find a profile document that has authUid == uid
    const profiles = db.collection('profiles');
    const q = await profiles.where('authUid', '==', uid).limit(1).get();
    if (!q.empty) {
      targetProfileId = q.docs[0].id;
    }
  }

  if (!targetProfileId) {
    // As a last resort, allow deletion if a profile doc has id == uid
    const maybe = await db.collection('profiles').doc(uid).get();
    if (maybe.exists) {
      targetProfileId = uid;
    }
  }

  if (!targetProfileId) {
    throw new functions.https.HttpsError('not-found', 'No profile found for this authenticated user.');
  }

  // Verify ownership: ensure profile.authUid == uid if authUid field exists
  try {
    const profileSnapshot = await db.collection('profiles').doc(targetProfileId).get();
    if (profileSnapshot.exists) {
      const dataSnap = profileSnapshot.data() || {};
      if (dataSnap.authUid && dataSnap.authUid !== uid) {
        throw new functions.https.HttpsError('permission-denied', 'You are not allowed to delete this profile.');
      }
      // If beaconId not provided, try to read it from doc
      if (!beaconId && dataSnap.beaconId) {
        beaconId = dataSnap.beaconId;
      }
    }
  } catch (err) {
    throw new functions.https.HttpsError('internal', 'Failed to validate profile ownership.');
  }

  // Perform deletion
  try {
    await deleteProfileAndReferences(targetProfileId, beaconId);
    // Optionally, if using Firebase Auth, delete the user account as well
    // (requires stronger permissions; leave to operator decision). We do not
    // delete the Auth user here to avoid surprising side effects.
    return { success: true, profileId: targetProfileId };
  } catch (err) {
    console.error('Deletion failed', err);
    throw new functions.https.HttpsError('internal', 'Failed to delete profile');
  }
});
