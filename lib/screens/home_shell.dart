import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'download_qr_screen.dart';
import 'encounter_list_screen.dart';
import '../services/streetpass_service.dart';
import '../state/encounter_manager.dart';
import '../state/local_profile_loader.dart';
import '../state/profile_controller.dart';
import 'profile_edit_screen.dart';
import '../models/profile.dart';
import '../widgets/profile_info_tile.dart';
import '../widgets/profile_stats_row.dart';
import 'profile_follow_list_sheet.dart';
import 'profile_view_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 1;
  bool _autoStartAttempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoStartStreetPass();
    });
  }

  final List<Widget> _pages = const [
    _TimelineScreen(),
    EncounterListScreen(),
    _ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _pages[_currentIndex],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '\u30db\u30fc\u30e0',
          ),
          NavigationDestination(
            icon: Icon(Icons.radio),
            selectedIcon: Icon(Icons.radio_button_checked),
            label: '\u3059\u308c\u9055\u3044',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '\u30d7\u30ed\u30d5\u30a3\u30fc\u30eb',
          ),
        ],
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
      ),
    );
  }

  Future<void> _autoStartStreetPass() async {
    if (_autoStartAttempted || !mounted) return;
    _autoStartAttempted = true;
    final manager = context.read<EncounterManager>();
    if (manager.isRunning) return;
    try {
      await manager.start();
    } on StreetPassException catch (error) {
      if (!mounted) return;
      _showStreetPassSnack(error.message);
    } catch (_) {
      if (!mounted) return;
      _showStreetPassSnack(
          '\u3059\u308c\u9055\u3044\u901a\u4fe1\u306e\u8d77\u52d5\u306b\u5931\u6557\u3057\u307e\u3057\u305f\u3002\u8a2d\u5b9a\u3092\u78ba\u8a8d\u3057\u3066\u304f\u3060\u3055\u3044\u3002');
    }
  }

  void _showStreetPassSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TimelineScreen extends StatelessWidget {
  const _TimelineScreen();

  @override
  Widget build(BuildContext context) {
    final cards = List.generate(
      3,
      (index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                offset: const Offset(0, 6),
                blurRadius: 20,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '\u30a4\u30f3\u30b9\u30d4\u30ec\u30fc\u30b7\u30e7\u30f3 #${index + 1}',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  '\u3086\u308b\u304f\u3064\u306a\u304c\u308b\u4eca\u65e5\u306e\u8a71\u984c\u3092\u30e1\u30e2\u3059\u308b\u30b9\u30da\u30fc\u30b9\u3067\u3059\u3002'
                  '\u3059\u308c\u9055\u3044\u304b\u3089\u5f97\u305f\u30a2\u30a4\u30c7\u30a2\u3092\u3053\u3053\u3067\u307e\u3068\u3081\u3066\u307f\u307e\u3057\u3087\u3046\u3002',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('\u30db\u30fc\u30e0'),
        actions: [
          IconButton(
            tooltip: '\u30c0\u30a6\u30f3\u30ed\u30fc\u30c9QR\u3092\u8868\u793a',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DownloadQrScreen()),
              );
            },
            icon: const Icon(Icons.qr_code_2),
          ),
          IconButton(
            tooltip: '\u30cf\u30a4\u30e9\u30a4\u30c8\u3092\u56fa\u5b9a',
            onPressed: () {},
            icon: const Icon(Icons.push_pin_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 10, bottom: 80),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '\u4eca\u65e5\u306e\u30cf\u30a4\u30e9\u30a4\u30c8',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          ...cards,
        ],
      ),
    );
  }
}

class _ProfileScreen extends StatefulWidget {
  const _ProfileScreen();

  @override
  State<_ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<_ProfileScreen> {
  bool _loggingOut = false;

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    final controller = context.read<ProfileController>();
    final manager = context.read<EncounterManager>();
    try {
      await _resetWithTimeout(manager);
      await LocalProfileLoader.resetLocalProfile();
      final refreshed = await LocalProfileLoader.loadOrCreate();
      controller.updateProfile(refreshed, needsSetup: true);
    } finally {
      if (mounted) {
        setState(() => _loggingOut = false);
      }
    }
  }

  Future<void> _resetWithTimeout(EncounterManager manager) async {
    try {
      await manager.reset().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      debugPrint('Encounter reset timed out; continuing logout');
    } catch (error, stackTrace) {
      debugPrint('Failed to reset encounters on logout: $error\n$stackTrace');
    }
  }

  void _openRelationsSheet(
    Profile profile,
    ProfileFollowSheetMode mode,
  ) {
    final navigator = Navigator.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return ProfileFollowListSheet(
          targetId: profile.id,
          viewerId: profile.id,
          mode: mode,
          onProfileTap: (remoteProfile) {
            navigator.push(
              MaterialPageRoute(
                builder: (_) => ProfileViewScreen(
                  profileId: remoteProfile.id,
                  initialProfile: remoteProfile,
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = context.watch<ProfileController>().profile;
    final bio = _displayOrPlaceholder(profile.bio);
    final homeTown = _displayOrPlaceholder(profile.homeTown);
    final hobbies = _hobbiesOrPlaceholder(profile.favoriteGames);
    return Scaffold(
      appBar: AppBar(
        title: const Text('\u30d7\u30ed\u30d5\u30a3\u30fc\u30eb'),
        actions: [
          IconButton(
            tooltip: '\u7de8\u96c6',
            onPressed: () async {
              final controller = context.read<ProfileController>();
              final messenger = ScaffoldMessenger.of(context);
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) =>
                      ProfileEditScreen(profile: controller.profile),
                ),
              );
              if (!mounted) return;
              if (result == true) {
                messenger.showSnackBar(
                  const SnackBar(
                      content: Text(
                          '\u30d7\u30ed\u30d5\u30a3\u30fc\u30eb\u3092\u66f4\u65b0\u3057\u307e\u3057\u305f\u3002')),
                );
              }
            },
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF4C7),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Icon(Icons.person, size: 42),
                          ),
                          const SizedBox(width: 18),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.displayName,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '\u30b5\u30de\u30ea\u30fc\u3092\u7de8\u96c6\u3057\u3066\n\u3042\u306a\u305f\u3089\u3057\u3055\u3092\u5c4a\u3051\u307e\u3057\u3087\u3046\u3002',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          )
                        ],
                      ),
                      const SizedBox(height: 24),
                      ProfileStatsRow(
                        profile: profile,
                        onFollowersTap: () => _openRelationsSheet(
                          profile,
                          ProfileFollowSheetMode.followers,
                        ),
                        onFollowingTap: () => _openRelationsSheet(
                          profile,
                          ProfileFollowSheetMode.following,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        '\u30b9\u30c6\u30fc\u30bf\u30b9',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      ProfileInfoTile(
                        icon: Icons.mood,
                        title: '\u4e00\u8a00\u30b3\u30e1\u30f3\u30c8',
                        value: bio,
                      ),
                      ProfileInfoTile(
                        icon: Icons.place_outlined,
                        title: '\u6d3b\u52d5\u30a8\u30ea\u30a2',
                        value: homeTown,
                      ),
                      ProfileInfoTile(
                        icon: Icons.palette_outlined,
                        title: '\u8da3\u5473',
                        value: hobbies,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _loggingOut ? null : _logout,
                icon: const Icon(Icons.logout),
                label: _loggingOut
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('\u30ed\u30b0\u30a2\u30a6\u30c8'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _displayOrPlaceholder(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == '\u672a\u767b\u9332') {
    return '\u672a\u767b\u9332';
  }
  return trimmed;
}

String _hobbiesOrPlaceholder(List<String> hobbies) {
  if (hobbies.isEmpty) {
    return '\u672a\u767b\u9332';
  }
  return hobbies.join(', ');
}
