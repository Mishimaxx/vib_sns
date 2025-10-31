import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/encounter.dart';
import '../services/streetpass_service.dart';
import '../state/encounter_manager.dart';
import '../state/runtime_config.dart';
import '../widgets/encounter_map.dart';
import '../widgets/like_button.dart';
import '../widgets/profile_avatar.dart';
import 'encounter_detail_screen.dart';

class EncounterListScreen extends StatefulWidget {
  const EncounterListScreen({super.key});

  @override
  State<EncounterListScreen> createState() => _EncounterListScreenState();
}

class _EncounterListScreenState extends State<EncounterListScreen> {
  bool _scanAttempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureStreetPassStarted();
    });
  }

  Future<void> _ensureStreetPassStarted() async {
    final manager = context.read<EncounterManager>();
    if (manager.isRunning) return;
    try {
      await manager.start();
      if (mounted) {
        setState(() {
          _scanAttempted = true;
        });
      }
    } on StreetPassException catch (error) {
      if (mounted) {
        setState(() => _scanAttempted = true);
      }
      _showSnack(error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _scanAttempted = true);
      }
      _showSnack(
          '\u3059\u308c\u9055\u3044\u901a\u4fe1\u3092\u958b\u59cb\u3067\u304d\u307e\u305b\u3093\u3067\u3057\u305f\u3002\u8a2d\u5b9a\u3092\u78ba\u8a8d\u3057\u3066\u304f\u3060\u3055\u3044\u3002');
    }
  }

  Future<void> _handleScanPressed() async {
    final manager = context.read<EncounterManager>();
    setState(() => _scanAttempted = true);
    try {
      await manager.reset();
      await manager.start();
      _showSnack(
          '\u8fd1\u304f\u306e\u30d7\u30ec\u30a4\u30e4\u30fc\u3092\u30b9\u30ad\u30e3\u30f3\u3057\u3066\u3044\u307e\u3059...');
    } on StreetPassException catch (error) {
      _showSnack(error.message);
    } catch (_) {
      _showSnack(
          '\u901a\u4fe1\u306e\u521d\u671f\u5316\u306b\u5931\u6557\u3057\u307e\u3057\u305f\u3002');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final runtimeConfig = context.watch<StreetPassRuntimeConfig>();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('\u3059\u308c\u9055\u3044\u30ed\u30b0'),
          actions: [
            IconButton(
              onPressed: _handleScanPressed,
              icon: const Icon(Icons.wifi_tethering),
              tooltip: '\u3059\u308c\u9055\u3044\u691c\u7d22',
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.list_alt),
                text: '\u30ea\u30b9\u30c8',
              ),
              Tab(
                icon: Icon(Icons.map_outlined),
                text: '\u30de\u30c3\u30d7',
              ),
            ],
          ),
        ),
        body: Consumer<EncounterManager>(
          builder: (context, manager, _) {
            if (manager.errorMessage != null) {
              return _ErrorMessage(message: manager.errorMessage!);
            }
            if (!manager.isRunning) {
              return _LoadingMessage(
                attempted: _scanAttempted,
                onRetry: _handleScanPressed,
              );
            }

            final encounters = manager.encounters;

            List<Widget> buildBanners() {
              return [
                if (runtimeConfig.usesMockService)
                  const _BannerMessage(
                    icon: Icons.info_outline,
                    text:
                        '\u73fe\u5728\u306f\u30c7\u30e2\u30e2\u30fc\u30c9\u3067\u52d5\u4f5c\u3057\u3066\u3044\u307e\u3059\u3002Firebase\u9023\u643a\u5f8c\u306b\u5b9f\u969b\u306e\u3059\u308c\u9055\u3044\u304c\u53ef\u80fd\u306b\u306a\u308a\u307e\u3059\u3002',
                  ),
                if (runtimeConfig.usesMockBle)
                  const _BannerMessage(
                    icon: Icons.bluetooth_disabled_outlined,
                    text:
                        'BLE\u8fd1\u63a5\u691c\u77e5\u306f\u73fe\u5728\u30c7\u30e2\u30c7\u30fc\u30bf\u3067\u52d5\u4f5c\u4e2d\u3067\u3059\u3002\u5b9f\u6a5f\u3067\u306fBluetooth\u3092\u6709\u52b9\u306b\u3057\u3066\u304f\u3060\u3055\u3044\u3002',
                  ),
              ];
            }

            final listTab = Column(
              children: [
                ...buildBanners(),
                if (encounters.isEmpty)
                  Expanded(
                    child: _EmptyEncountersMessage(
                      scanAttempted: _scanAttempted,
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      itemBuilder: (context, index) {
                        final encounter = encounters[index];
                        return _EncounterTile(encounter: encounter);
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemCount: encounters.length,
                    ),
                  ),
              ],
            );

            final mapTab = Column(
              children: [
                ...buildBanners(),
                Expanded(
                  child: EncounterMap(
                    encounters: encounters,
                    onMarkerTap: (encounter) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EncounterDetailScreen(
                            encounterId: encounter.id,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );

            return TabBarView(
              children: [
                listTab,
                mapTab,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EncounterTile extends StatelessWidget {
  const _EncounterTile({required this.encounter});

  final Encounter encounter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final distance = encounter.displayDistance;
    final accent = theme.colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EncounterDetailScreen(encounterId: encounter.id),
            ),
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: encounter.unread
                  ? accent.withValues(alpha: 0.45)
                  : Colors.black.withValues(alpha: 0.06),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: encounter.unread
                    ? accent.withValues(alpha: 0.18)
                    : Colors.black.withValues(alpha: 0.03),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileAvatar(profile: encounter.profile),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            encounter.profile.displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF4C7),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _relativeTime(encounter.encounteredAt),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      encounter.message ?? '「こんにちは！」と伝えてみましょう。',
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (distance != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          encounter.proximityVerified
                              ? 'BLE\u8fd1\u63a5 約${distance.toStringAsFixed(2)}m'
                              : 'GPS\u63a8\u5b9a 約${distance.round()}m',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.black54),
                        ),
                      ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final double availableWidth = constraints.maxWidth;
                        final double rawWidth = (availableWidth - 10) / 2;
                        final double buttonWidth =
                            rawWidth.isFinite && rawWidth > 0
                                ? rawWidth
                                : availableWidth / 2;
                        final int displayLikeCount = encounter.liked
                            ? (encounter.profile.receivedLikes > 0
                                ? encounter.profile.receivedLikes
                                : 1)
                            : 0; // Hide counter until the viewer likes to avoid phantom "1" states.
                        return Row(
                          children: [
                            SizedBox(
                              width: buttonWidth,
                              child: FittedBox(
                                alignment: Alignment.centerLeft,
                                fit: BoxFit.scaleDown,
                                child: LikeButton(
                                  variant: LikeButtonVariant.chip,
                                  isLiked: encounter.liked,
                                  likeCount: displayLikeCount,
                                  onPressed: () {
                                    context
                                        .read<EncounterManager>()
                                        .toggleLike(encounter.id);
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: buttonWidth,
                              child: FittedBox(
                                alignment: Alignment.centerRight,
                                fit: BoxFit.scaleDown,
                                child: FollowButton(
                                  variant: LikeButtonVariant.chip,
                                  isFollowing: encounter.profile.following,
                                  onPressed: () {
                                    context
                                        .read<EncounterManager>()
                                        .toggleFollow(encounter.id);
                                  },
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '\u305f\u3063\u305f\u4eca';
    if (diff.inHours < 1) return '${diff.inMinutes}\u5206\u524d';
    if (diff.inHours < 24) return '${diff.inHours}\u6642\u9593\u524d';
    return '${diff.inDays}\u65e5\u524d';
  }
}

class _EmptyEncountersMessage extends StatelessWidget {
  const _EmptyEncountersMessage({required this.scanAttempted});

  final bool scanAttempted;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.sensors, size: 64, color: Color(0xFFFFC400)),
          const SizedBox(height: 16),
          Text(
            scanAttempted
                ? '\u4eca\u56de\u306f\u3059\u308c\u9055\u3044\u304c\u3042\u308a\u307e\u305b\u3093\u3067\u3057\u305f\u3002\n\u5916\u51fa\u3057\u3066\u518d\u5ea6\u30b9\u30ad\u30e3\u30f3\u3057\u3066\u307f\u307e\u3057\u3087\u3046\u3002'
                : '\u307e\u3060\u3059\u308c\u9055\u3044\u304c\u3042\u308a\u307e\u305b\u3093\u3002\u8fd1\u304f\u306e\u30d7\u30ec\u30a4\u30e4\u30fc\u3092\u63a2\u3057\u3066\u307f\u307e\u3057\u3087\u3046\u3002',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 72, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingMessage extends StatelessWidget {
  const _LoadingMessage({required this.attempted, required this.onRetry});

  final bool attempted;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            attempted
                ? '\u73fe\u5728\u521d\u671f\u5316\u4e2d\u3067\u3059...\u5909\u5316\u304c\u306a\u3044\u5834\u5408\u306f\u518d\u8a66\u884c\u3057\u3066\u304f\u3060\u3055\u3044\u3002'
                : '\u521d\u56de\u8d77\u52d5\u4e2d\u3067\u3059\u3002\u3057\u3070\u3089\u304f\u304a\u5f85\u3061\u304f\u3060\u3055\u3044\u3002',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('\u518d\u30b9\u30ad\u30e3\u30f3'),
          ),
        ],
      ),
    );
  }
}

class _BannerMessage extends StatelessWidget {
  const _BannerMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: theme.colorScheme.secondaryContainer,
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
