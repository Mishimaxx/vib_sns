import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/encounter.dart';
import '../state/encounter_manager.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/like_button.dart';

class EncounterDetailScreen extends StatefulWidget {
  const EncounterDetailScreen({super.key, required this.encounterId});

  final String encounterId;

  @override
  State<EncounterDetailScreen> createState() => _EncounterDetailScreenState();
}

class _EncounterDetailScreenState extends State<EncounterDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<EncounterManager>().markSeen(widget.encounterId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EncounterManager>(
      builder: (context, manager, _) {
        final encounter = manager.findById(widget.encounterId);
        if (encounter == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(
                child: Text(
                    '\u3053\u306e\u3059\u308c\u9055\u3044\u306f\u898b\u3064\u304b\u308a\u307e\u305b\u3093\u3067\u3057\u305f\u3002')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(encounter.profile.displayName),
            actions: [
              IconButton(
                icon: Icon(
                    encounter.liked ? Icons.favorite : Icons.favorite_border),
                color: encounter.liked ? Colors.pinkAccent : null,
                onPressed: () => manager.toggleLike(encounter.id),
                tooltip: '\u3044\u3044\u306d',
              ),
            ],
          ),
          body: _EncounterDetailBody(
            encounter: encounter,
            onLikePressed: () => manager.toggleLike(encounter.id),
            onFollowPressed: () => manager.toggleFollow(encounter.id),
          ),
        );
      },
    );
  }
}

class _EncounterDetailBody extends StatelessWidget {
  const _EncounterDetailBody({
    required this.encounter,
    required this.onLikePressed,
    required this.onFollowPressed,
  });

  final Encounter encounter;
  final VoidCallback onLikePressed;
  final VoidCallback onFollowPressed;

  @override
  Widget build(BuildContext context) {
    final profile = encounter.profile;
    final theme = Theme.of(context);
    final double? gpsDistance = encounter.gpsDistanceMeters;
    final double? bleDistance = encounter.bleDistanceMeters;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 88),
        child: ListView(
          children: [
            Row(
              children: [
                ProfileAvatar(profile: profile, radius: 48),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.displayName,
                          style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.place_outlined, size: 20),
                          const SizedBox(width: 4),
                          Text(profile.homeTown,
                              style: theme.textTheme.bodyMedium),
                        ],
                      ),
                      if (gpsDistance != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.map_outlined, size: 20),
                            const SizedBox(width: 4),
                            Text(
                              'GPS\u63a8\u5b9a \u7d04${gpsDistance.round()}m',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ],
                      if (bleDistance != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.bluetooth_connected, size: 20),
                            const SizedBox(width: 4),
                            Text(
                              'BLE\u8fd1\u63a5 \u7d04${bleDistance.toStringAsFixed(2)}m',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        '\u3059\u308c\u9055\u3063\u305f\u65e5\u6642: ${_formattedDate(encounter.encounteredAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _Section(
              title: '\u81ea\u5df1\u7d39\u4ecb',
              child: Text(profile.bio, style: theme.textTheme.bodyLarge),
            ),
            _Section(
              title: '\u8da3\u5473',
              child: profile.favoriteGames.isEmpty
                  ? Text('\u672a\u767b\u9332', style: theme.textTheme.bodyLarge)
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: profile.favoriteGames
                          .map(
                            (game) => Chip(
                              label: Text(game),
                              avatar:
                                  const Icon(Icons.palette_outlined, size: 18),
                            ),
                          )
                          .toList(),
                    ),
            ),
            if (encounter.message != null)
              _Section(
                title: '\u3059\u308c\u9055\u3044\u30e1\u30c3\u30bb\u30fc\u30b8',
                child: Card(
                  color: const Color(0xFFFFF4C7),
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      encounter.message!,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ),
              ),
            _Section(
              title: '\u30a2\u30af\u30c6\u30a3\u30d3\u30c6\u30a3',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _StatBadge(
                    icon: Icons.favorite,
                    value: encounter.profile.receivedLikes,
                    label: '\u3082\u3089\u3063\u305f\u3044\u3044\u306d',
                  ),
                  _StatBadge(
                    icon: Icons.people_alt,
                    value: encounter.profile.following ? 1 : 0,
                    label: '\u30d5\u30a9\u30ed\u30fc\u4e2d',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final double width = constraints.maxWidth;
                final bool compact = width < 360;
                final double maxHeight = compact ? 58 : 68;
                return Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: maxHeight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: LikeButton(
                            variant: LikeButtonVariant.hero,
                            isLiked: encounter.liked,
                            likeCount: encounter.profile.receivedLikes,
                            onPressed: onLikePressed,
                            maxHeight: maxHeight,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: SizedBox(
                        height: maxHeight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: FollowButton(
                            variant: LikeButtonVariant.hero,
                            isFollowing: encounter.profile.following,
                            onPressed: onFollowPressed,
                            maxHeight: maxHeight,
                          ),
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
    );
  }

  String _formattedDate(DateTime time) {
    return '${time.year}/${time.month.toString().padLeft(2, '0')}/${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(icon, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 8),
        Text(
          value.toString(),
          style:
              theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
