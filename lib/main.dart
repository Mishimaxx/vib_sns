import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'models/profile.dart';
import 'screens/home_shell.dart';
import 'screens/name_setup_screen.dart';
import 'services/ble_proximity_scanner.dart';
import 'services/ble_proximity_scanner_impl.dart';
import 'services/firestore_streetpass_service.dart';
import 'services/mock_ble_proximity_scanner.dart';
import 'services/mock_streetpass_service.dart';
import 'services/streetpass_service.dart';
import 'state/encounter_manager.dart';
import 'state/local_profile_loader.dart';
import 'state/profile_controller.dart';
import 'state/runtime_config.dart';

const _downloadUrl = String.fromEnvironment('DOWNLOAD_URL', defaultValue: '');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  StreetPassService streetPassService;
  var usesMockService = false;

  BleProximityScanner bleProximityScanner;
  var usesMockBle = false;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    streetPassService = FirestoreStreetPassService();
  } catch (error) {
    streetPassService = MockStreetPassService();
    usesMockService = true;
  }

  final hasName = await LocalProfileLoader.hasDisplayName();
  final localProfile = await LocalProfileLoader.loadOrCreate();
  final profileController = ProfileController(
    profile: localProfile,
    needsSetup: !hasName,
  );

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
      localProfile: localProfile,
      bleProximityScanner: bleProximityScanner,
      profileController: profileController,
      runtimeConfig: StreetPassRuntimeConfig(
        usesMockService: usesMockService,
        usesMockBle: usesMockBle,
        downloadUrl: _downloadUrl,
      ),
    ),
  );
}

class VibSnsApp extends StatelessWidget {
  const VibSnsApp({
    super.key,
    required this.streetPassService,
    required this.localProfile,
    required this.bleProximityScanner,
    required this.profileController,
    required this.runtimeConfig,
  });

  final StreetPassService streetPassService;
  final Profile localProfile;
  final BleProximityScanner bleProximityScanner;
  final ProfileController profileController;
  final StreetPassRuntimeConfig runtimeConfig;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ProfileController>.value(value: profileController),
        Provider<StreetPassRuntimeConfig>.value(value: runtimeConfig),
        ChangeNotifierProvider(
          create: (_) => EncounterManager(
            streetPassService: streetPassService,
            localProfile: localProfile,
            bleScanner: bleProximityScanner,
            usesMockBackend: runtimeConfig.usesMockService,
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
      colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.light),
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
