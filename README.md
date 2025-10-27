# Vib SNS

Vib SNS is a Flutter prototype inspired by the Nintendo 3DS “StreetPass Eexperience. The focus is on the moment of encountering nearby players—checking their profile, sending a like, and following—while other features such as full authentication are intentionally deferred.

## Highlights

- Publishes the local user’s presence (location, profile metadata, BLE beacon id) to Firestore and keeps it fresh while the app is running.
- Combines coarse GPS distance (Geolocator) with high-precision BLE proximity (flutter_blue_plus + flutter_ble_peripheral) to mimic StreetPass-style contact detection.
- Falls back to mock StreetPass *and* mock BLE streams when Firebase/Bluetooth aren’t available so the UI remains testable.
- Uses Provider for shared application state and Material 3 for the UI layer.

## Getting started

```bash
flutter pub get
```

### Enable “real EStreetPass behaviour

1. Create a Firebase project and register the app (Android/iOS/Web as needed).
2. Place the native config files: `android/app/google-services.json` and/or `ios/Runner/GoogleService-Info.plist`.
3. Generate `lib/firebase_options.dart` with FlutterFire:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
4. Ensure Cloud Firestore is enabled. Presence documents are stored under the `streetpass_presences` collection with the following shape:

   ```json
   {
     "profile": {
       "id": "device-id",
       "displayName": "You",
       "bio": "...",
       "homeTown": "...",
       "favoriteGames": ["Splatoon 3", "Mario Kart 8 Deluxe"],
       "avatarColor": 305419896,
       "following": false,
       "receivedLikes": 0
     },
     "lat": 35.0,
     "lng": 135.0,
     "lastUpdatedMs": 1690000000000,
     "active": true
   }
   ```

   Development-only rules (do not use in production):

   ```text
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /streetpass_presences/{deviceId} {
         allow read, write;
       }
     }
   }
   ```

5. Request location and Bluetooth permissions:
   - **Android**: add the following to `AndroidManifest.xml` (adjust for minSdk/targetSdk as needed):
     ```xml
     <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
     <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
     <uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
     <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
     <uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
     ```
     If you target Android 12+, add `android:usesPermissionFlags="neverForLocation"` to `BLUETOOTH_SCAN` where appropriate.
   - **iOS**: add `NSLocationWhenInUseUsageDescription`, `NSBluetoothAlwaysUsageDescription`, and `NSBluetoothPeripheralUsageDescription` to `Info.plist`.

Launch the app with:

```bash
flutter run
```

You will receive a location permission prompt on first launch. Denying it keeps the app in an error state until permission is granted.

## How it works

- `FirestoreStreetPassService` updates the device’s presence (including a BLE beacon id) and polls for nearby users. GPS distance is computed locally via the Geolocator plugin.
- `BleProximityScannerImpl` advertises a compact beacon UUID and continuously scans for matching UUIDs via flutter_blue_plus, converting RSSI into a sub-metre distance estimate.
- `EncounterManager` fuses GPS and BLE signals, upgrading encounters to “nearby” once a BLE hit is observed and exposing follow/like toggles to the UI.
- `MockStreetPassService` / `MockBleProximityScanner` keep the UI interactive when Firebase or Bluetooth is unavailable.
- `LocalProfileLoader` persists the local profile (display name, hometown, favourite games, avatar colour, beacon id) with SharedPreferences so each device keeps a consistent identity.

## Next steps

1. Sync likes/follows back to Firestore or another backend so they persist across sessions.
2. Provide a profile editor or onboarding experience to customise the local presence.
3. Explore alternative proximity transports (Bluetooth, Nearby Connections) for offline encounters.
4. Optimise polling cadence and background behaviour to balance discovery with battery life.

