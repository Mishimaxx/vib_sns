import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'download_qr_screen.dart';
import 'encounter_list_screen.dart';
import 'notifications_screen.dart';
import '../services/streetpass_service.dart';
import '../state/encounter_manager.dart';
import '../state/local_profile_loader.dart';
import '../state/notification_manager.dart';
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
    NotificationsScreen(),
    _ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final unreadCount = context.watch<NotificationManager>().unreadCount;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _pages[_currentIndex],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '\u30db\u30fc\u30e0',
          ),
          const NavigationDestination(
            icon: Icon(Icons.radio),
            selectedIcon: Icon(Icons.radio_button_checked),
            label: '\u3059\u308c\u9055\u3044',
          ),
          NavigationDestination(
            icon: _buildNotificationIcon(unreadCount, selected: false),
            selectedIcon: _buildNotificationIcon(unreadCount, selected: true),
            label: '\u901a\u77e5',
          ),
          const NavigationDestination(
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

  static Widget _buildNotificationIcon(int unreadCount,
      {required bool selected}) {
    final icon =
        Icon(selected ? Icons.notifications : Icons.notifications_none);
    if (unreadCount <= 0) {
      return icon;
    }
    final displayLabel = unreadCount > 99 ? '99+' : '$unreadCount';
    return Badge(
      label: Text(displayLabel),
      child: icon,
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
    final theme = Theme.of(context);
    final palette = _HomePalette.fromTheme(theme);
    final metrics = _computeMetrics(context.watch<EncounterManager>());
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: const Text('🏠 \u30db\u30fc\u30e0'),
        backgroundColor: palette.background,
        elevation: 0,
        scrolledUnderElevation: 0,
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
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '\u4eca\u65e5\u306e\u6c17\u914d',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: palette.onSurface.withValues(alpha: 0.6),
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '\u9759\u304b\u306a\u7a7a\u6c17\u306e\u4e2d\u3067\u3001\u4eca\u65e5\u306e\u51fa\u4f1a\u3044\u3092\u305d\u3063\u3068\u632f\u308a\u8fd4\u308a\u307e\u3059\u3002',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Text(
                    '\u4eca\u65e5\u306e\u30cf\u30a4\u30e9\u30a4\u30c8',
                    style: theme.textTheme.titleMedium?.copyWith(
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _HighlightsRow(
                    palette: palette,
                    metrics: metrics,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

_HomeMetrics _computeMetrics(EncounterManager manager) {
  final encounters = manager.encounters;
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final todaysEncounters = encounters
      .where((encounter) => encounter.encounteredAt.isAfter(todayStart))
      .length;

  final occurrences = <String, int>{};
  for (final encounter in encounters) {
    final key = encounter.profile.id;
    if (key.isEmpty) continue;
    occurrences.update(key, (value) => value + 1, ifAbsent: () => 1);
  }
  final reencounters = occurrences.values.where((count) => count > 1).length;

  final resonance = encounters.where((encounter) => encounter.liked).length;

  return _HomeMetrics(
    todaysEncounters: todaysEncounters,
    reencounters: reencounters,
    resonance: resonance,
  );
}

class _HomeMetrics {
  const _HomeMetrics({
    required this.todaysEncounters,
    required this.reencounters,
    required this.resonance,
  });

  final int todaysEncounters;
  final int reencounters;
  final int resonance;
}

class _HomePalette {
  _HomePalette({
    required this.background,
    required this.onSurface,
    required this.primaryAccent,
    required this.secondaryAccent,
    required this.tertiaryAccent,
  });

  final Color background;
  final Color onSurface;
  final Color primaryAccent;
  final Color secondaryAccent;
  final Color tertiaryAccent;

  factory _HomePalette.fromTheme(ThemeData theme) {
    final scheme = theme.colorScheme;
    return _HomePalette(
      background: Color.alphaBlend(
          scheme.primary.withValues(alpha: 0.02), scheme.surface),
      onSurface: scheme.onSurface,
      primaryAccent: scheme.primary,
      secondaryAccent: scheme.secondary,
      tertiaryAccent: scheme.tertiary,
    );
  }
}

class _HighlightsRow extends StatelessWidget {
  const _HighlightsRow({
    required this.palette,
    required this.metrics,
  });

  final _HomePalette palette;
  final _HomeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _HighlightTile(
        label: '\u3059\u308c\u9055\u3044\u4eba\u6570',
        value: '${metrics.todaysEncounters}\u4eba',
        accent: palette.primaryAccent,
        textColor: palette.onSurface,
      ),
      _HighlightTile(
        label: '\u518d\u4f1a',
        value: '${metrics.reencounters}\u4eba',
        accent: palette.secondaryAccent,
        textColor: palette.onSurface,
      ),
      _HighlightTile(
        label: '\u5171\u9cf4\u6570',
        value: metrics.resonance.toString(),
        accent: palette.tertiaryAccent,
        textColor: palette.onSurface,
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          const SizedBox(width: 4),
          for (var i = 0; i < tiles.length; i++) ...[
            tiles[i],
            if (i != tiles.length - 1) const SizedBox(width: 16),
          ],
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _HighlightTile extends StatelessWidget {
  const _HighlightTile({
    required this.label,
    required this.value,
    required this.accent,
    required this.textColor,
  });

  final String label;
  final String value;
  final Color accent;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: accent,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
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
    final notificationManager = context.read<NotificationManager>();
    try {
      // If the user is authenticated, call the server-side function to
      // delete their profile and related server-side data before clearing
      // local state. We catch and continue on error to avoid blocking logout.
      final user = FirebaseAuth.instance.currentUser;
      var serverDeleted = false;
      if (user != null) {
        try {
          debugPrint(
              'HomeShell._logout: calling deleteUserProfile for profileId=${controller.profile.id} beaconId=${controller.profile.beaconId}');
          final callable =
              FirebaseFunctions.instance.httpsCallable('deleteUserProfile');
          final result = await callable.call(<String, dynamic>{
            'profileId': controller.profile.id,
            'beaconId': controller.profile.beaconId,
          });
          debugPrint(
              'HomeShell._logout: deleteUserProfile result=${result.data}');
          serverDeleted = true;
        } catch (e, st) {
          debugPrint('deleteUserProfile failed: $e');
          debugPrintStack(stackTrace: st);
        }
      }

      // Sign out from Firebase Auth.
      debugPrint('HomeShell._logout: signing out FirebaseAuth');
      await FirebaseAuth.instance.signOut();

      if (serverDeleted) {
        // Wipe local identity only if server-side deletion succeeded. This
        // prevents generating a fresh device id/profile when the server
        // couldn't delete the old one (which was causing profile proliferation).
        debugPrint(
            'HomeShell._logout: resetting local profile with wipeIdentity=true');
        await LocalProfileLoader.resetLocalProfile(wipeIdentity: true);
        final refreshed = await LocalProfileLoader.loadOrCreate();
        debugPrint(
            'HomeShell._logout: new local profile id=${refreshed.id} beaconId=${refreshed.beaconId}');
        // Do not bootstrap profile on logout and avoid re-subscribing to server
        // stats so that follower/following/likes counts are reset locally.
        await manager.switchLocalProfile(refreshed, skipSync: true);
        await notificationManager.resetForProfile(refreshed);
        // Reset UI-visible stats to zero on logout.
        controller.updateStats(
            followersCount: 0, followingCount: 0, receivedLikes: 0);
        controller.updateProfile(refreshed, needsSetup: true);
      } else {
        // Server deletion failed or wasn't attempted (no auth). Keep the local
        // identity to avoid creating a new profile doc on next start. Still
        // clear local UI-visible stats and reset managers to a neutral state.
        debugPrint(
            'HomeShell._logout: server deletion failed or not attempted; keeping local identity to avoid creating extra profiles');
        final currentLocal = controller.profile;
        await manager.switchLocalProfile(currentLocal, skipSync: true);
        await notificationManager.resetForProfile(currentLocal);
        controller.updateStats(
            followersCount: 0, followingCount: 0, receivedLikes: 0);
        controller.updateProfile(currentLocal, needsSetup: true);
      }
    } finally {
      if (mounted) {
        setState(() => _loggingOut = false);
      }
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
