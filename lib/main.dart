import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'utils/color_extensions.dart';
import 'package:permission_handler/permission_handler.dart';

import 'firebase_options.dart';
import 'models/profile.dart';
import 'screens/home_shell.dart';
import 'screens/name_setup_screen.dart';
import 'services/ble_proximity_scanner.dart';
import 'services/ble_proximity_scanner_impl.dart';
import 'services/firestore_streetpass_service.dart';
import 'services/firestore_profile_interaction_service.dart';
import 'services/mock_ble_proximity_scanner.dart';
import 'services/mock_profile_interaction_service.dart';
import 'services/mock_streetpass_service.dart';
import 'services/profile_interaction_service.dart';
import 'services/streetpass_service.dart';
import 'state/encounter_manager.dart';
import 'state/emotion_map_manager.dart';
import 'state/local_profile_loader.dart';
import 'state/profile_controller.dart';
import 'state/runtime_config.dart';
import 'state/notification_manager.dart';
import 'state/timeline_manager.dart';

const _downloadUrl = String.fromEnvironment('DOWNLOAD_URL', defaultValue: '');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  StreetPassService streetPassService;
  ProfileInteractionService interactionService;
  var usesMockService = false;

  BleProximityScanner bleProximityScanner;
  var usesMockBle = false;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    streetPassService = FirestoreStreetPassService();
    interactionService = FirestoreProfileInteractionService();
  } catch (error) {
    streetPassService = MockStreetPassService();
    interactionService = MockProfileInteractionService();
    usesMockService = true;
  }

  final hasName = await LocalProfileLoader.hasDisplayName();

  // Ensure there is an authenticated user so server-side deletion can be
  // performed on logout. If no auth is present, sign in anonymously.
  try {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  } catch (e) {
    debugPrint('Anonymous sign-in failed: $e');
  }

  final localProfile = await LocalProfileLoader.loadOrCreate();
  await _ensureNotificationPermission();

  // If the user is authenticated, attach the auth UID to the profile document
  // so server-side Callable Functions can validate ownership. We write the
  // authUid into the profiles/{id} doc (merge) when present.
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser != null) {
    try {
      debugPrint(
          'main: persisting authUid=${currentUser.uid} for localProfile.id=${localProfile.id} displayName="${localProfile.displayName}"');
      await FirebaseFirestore.instance
          .collection('profiles')
          .doc(localProfile.id)
          .set({'authUid': currentUser.uid}, SetOptions(merge: true));
      debugPrint('main: persisted authUid for profile ${localProfile.id}');
    } catch (e) {
      debugPrint('Failed to persist authUid on profile: $e');
    }
  }

  debugPrint(
      'main: about to bootstrapProfile for localProfile.id=${localProfile.id} beaconId=${localProfile.beaconId} authUid=${currentUser?.uid} hasName=$hasName');

  // Avoid creating a Firestore profile doc for unauthenticated users who
  // haven't set a display name yet. Creating a new device id (e.g. after
  // a wipe) while anonymous sign-in is unavailable caused many profiles to
  // appear in Firestore. Only bootstrap when we have an auth user or the
  // local profile already has a display name.
  if (currentUser != null || hasName) {
    await interactionService.bootstrapProfile(localProfile);
  } else {
    debugPrint(
        'main: skipping bootstrapProfile because no auth and no displayName');
  }
  final profileController = ProfileController(
    profile: localProfile,
    needsSetup: !hasName,
  );
  final notificationManager = NotificationManager(
    interactionService: interactionService,
    localProfile: localProfile,
  );
  final timelineManager = TimelineManager(profileController: profileController);
  final emotionMapManager =
      EmotionMapManager(profileController: profileController);

  try {
    if (kIsWeb) {
      throw UnsupportedError('BLE scanning is not supported on web.');
    }
    bleProximityScanner = BleProximityScannerImpl();
  } catch (_) {
    bleProximityScanner = MockBleProximityScanner();
    usesMockBle = true;
  }

  runApp(
    VibSnsApp(
      streetPassService: streetPassService,
      interactionService: interactionService,
      localProfile: localProfile,
      bleProximityScanner: bleProximityScanner,
      profileController: profileController,
      notificationManager: notificationManager,
      runtimeConfig: StreetPassRuntimeConfig(
        usesMockService: usesMockService,
        usesMockBle: usesMockBle,
        downloadUrl: _downloadUrl,
      ),
      timelineManager: timelineManager,
      emotionMapManager: emotionMapManager,
    ),
  );
}

Future<void> _ensureNotificationPermission() async {
  if (kIsWeb) {
    return;
  }
  final status = await Permission.notification.status;
  if (status.isGranted || status.isLimited) {
    return;
  }
  await Permission.notification.request();
}

class VibSnsApp extends StatelessWidget {
  const VibSnsApp({
    super.key,
    required this.streetPassService,
    required this.interactionService,
    required this.localProfile,
    required this.bleProximityScanner,
    required this.profileController,
    required this.notificationManager,
    required this.runtimeConfig,
    required this.timelineManager,
    required this.emotionMapManager,
  });

  final StreetPassService streetPassService;
  final ProfileInteractionService interactionService;
  final Profile localProfile;
  final BleProximityScanner bleProximityScanner;
  final ProfileController profileController;
  final NotificationManager notificationManager;
  final StreetPassRuntimeConfig runtimeConfig;
  final TimelineManager timelineManager;
  final EmotionMapManager emotionMapManager;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ProfileController>.value(
            value: profileController),
        ChangeNotifierProvider<NotificationManager>.value(
            value: notificationManager),
        ChangeNotifierProvider<TimelineManager>.value(value: timelineManager),
        ChangeNotifierProvider<EmotionMapManager>.value(
            value: emotionMapManager),
        Provider<StreetPassRuntimeConfig>.value(value: runtimeConfig),
        Provider<ProfileInteractionService>(
          create: (_) => interactionService,
          dispose: (_, service) => service.dispose(),
        ),
        ChangeNotifierProvider(
          create: (_) => EncounterManager(
            streetPassService: streetPassService,
            localProfile: localProfile,
            bleScanner: bleProximityScanner,
            usesMockBackend: runtimeConfig.usesMockService,
            profileController: profileController,
            interactionService: interactionService,
            notificationManager: notificationManager,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Vib SNS',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: const _RootGate(),
      ),
    );
  }

  ThemeData _buildTheme() {
    const accent = Color(0xFFFFC400);
    final base = ThemeData(
      useMaterial3: true,
      colorScheme:
          ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.light),
    );
    return base.copyWith(
      scaffoldBackgroundColor: Colors.white,
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: accent.withValues(alpha: 0.15),
        backgroundColor: Colors.white,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: false,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: Colors.black87,
        displayColor: Colors.black87,
      ),
    );
  }
}

class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final needsSetup = context.watch<ProfileController>().needsSetup;
    return needsSetup ? const NameSetupScreen() : const HomeShell();
  }
}
