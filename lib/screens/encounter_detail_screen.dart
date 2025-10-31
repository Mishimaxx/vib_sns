import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/encounter.dart';
import '../models/profile.dart';
import '../state/encounter_manager.dart';
import '../state/profile_controller.dart';
import '../widgets/like_button.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_info_tile.dart';
import '../widgets/profile_stats_row.dart';
import 'profile_follow_list_sheet.dart';
import 'profile_view_screen.dart';

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
    final viewerId = context.read<ProfileController>().profile.id;
    final double? gpsDistance = encounter.gpsDistanceMeters;
    final double? bleDistance = encounter.bleDistanceMeters;
    final bio = _displayOrPlaceholder(profile.bio);
    final homeTown = _displayOrPlaceholder(profile.homeTown);
    final hobbies = _hobbiesOrPlaceholder(profile.favoriteGames);
    final encounterTime = _formattedDate(encounter.encounteredAt);
    final distanceSummary = _distanceSummary(gpsDistance, bleDistance);
    final message = encounter.message?.trim();

    return SafeArea(
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
                        ProfileAvatar(
                          profile: profile,
                          radius: 38,
                          showBorder: false,
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
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
                                '\u3059\u308c\u9055\u3044\u65e5\u6642: $encounterTime',
                                style: theme.textTheme.bodyMedium,
                              ),
                              if (homeTown != '\u672a\u767b\u9332') ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.place_outlined, size: 20),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        homeTown,
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (distanceSummary != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  distanceSummary,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    ProfileStatsRow(
                      profile: profile,
                      onFollowersTap: () => _openRelationsSheet(
                        context,
                        profile,
                        viewerId,
                        ProfileFollowSheetMode.followers,
                      ),
                      onFollowingTap: () => _openRelationsSheet(
                        context,
                        profile,
                        viewerId,
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
                    if (message != null && message.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        '\u3059\u308c\u9055\u3044\u30e1\u30c3\u30bb\u30fc\u30b8',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4C7),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          message,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ],
                ),
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

String? _distanceSummary(double? gpsDistance, double? bleDistance) {
  final parts = <String>[];
  if (gpsDistance != null) {
    parts.add('GPS\u63a8\u5b9a \u7d04${gpsDistance.round()}m');
  }
  if (bleDistance != null) {
    parts.add('BLE\u8fd1\u63a5 \u7d04${bleDistance.toStringAsFixed(2)}m');
  }
  if (parts.isEmpty) {
    return null;
  }
  return parts.join(' / ');
}

void _openRelationsSheet(
  BuildContext context,
  Profile profile,
  String viewerId,
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
        viewerId: viewerId,
        mode: mode,
        onProfileTap: (selectedProfile) {
          if (selectedProfile.id == profile.id) {
            return;
          }
          navigator.push(
            MaterialPageRoute(
              builder: (_) => ProfileViewScreen(
                profileId: selectedProfile.id,
                initialProfile: selectedProfile,
              ),
            ),
          );
        },
      );
    },
  );
}
