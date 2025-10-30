import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../services/profile_interaction_service.dart';
import '../state/profile_controller.dart';
import '../widgets/like_button.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_info_tile.dart';
import '../widgets/profile_stats_row.dart';
import 'profile_follow_list_sheet.dart';

class ProfileViewScreen extends StatefulWidget {
  const ProfileViewScreen({
    super.key,
    required this.profileId,
    required this.initialProfile,
  });

  final String profileId;
  final Profile initialProfile;

  @override
  State<ProfileViewScreen> createState() => _ProfileViewScreenState();
}

class _ProfileViewScreenState extends State<ProfileViewScreen> {
  late Profile _profile = widget.initialProfile;
  late String _viewerId;
  ProfileInteractionSnapshot? _latestSnapshot;
  StreamSubscription<ProfileInteractionSnapshot>? _subscription;
  bool _isProcessingFollow = false;
  bool _isLoadingDetails = false;

  @override
  void initState() {
    super.initState();
    _viewerId = context.read<ProfileController>().profile.id;
    _profile = widget.initialProfile;
    _subscribeToStats();
    _loadDetails();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoadingDetails = true);
    final service = context.read<ProfileInteractionService>();
    try {
      final fresh = await service.loadProfile(widget.profileId);
      if (!mounted) return;
      if (fresh != null) {
        _profile = _mergeProfileDetails(fresh);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingDetails = false);
      }
    }
  }

  void _subscribeToStats() {
    final service = context.read<ProfileInteractionService>();
    _subscription = service
        .watchProfile(targetId: widget.profileId, viewerId: _viewerId)
        .listen(
      (snapshot) {
        _latestSnapshot = snapshot;
        if (!mounted) return;
        setState(() {
          _profile = _profile.copyWith(
            followersCount: snapshot.followersCount,
            followingCount: snapshot.followingCount,
            receivedLikes: snapshot.receivedLikes,
            following: snapshot.isFollowedByViewer,
          );
        });
      },
      onError: (error, stackTrace) {
        debugPrint('Failed to watch profile ${widget.profileId}: $error');
      },
    );
  }

  Profile _mergeProfileDetails(Profile fresh) {
    final snapshot = _latestSnapshot;
    return fresh.copyWith(
      followersCount: snapshot?.followersCount ?? fresh.followersCount,
      followingCount: snapshot?.followingCount ?? fresh.followingCount,
      receivedLikes: snapshot?.receivedLikes ?? fresh.receivedLikes,
      following: snapshot?.isFollowedByViewer ?? _profile.following,
    );
  }

  Future<void> _toggleFollow() async {
    if (_isProcessingFollow || widget.profileId == _viewerId) {
      return;
    }
    final service = context.read<ProfileInteractionService>();
    final shouldFollow = !_profile.following;
    setState(() {
      _isProcessingFollow = true;
      final delta = shouldFollow ? 1 : -1;
      _profile = _profile.copyWith(
        following: shouldFollow,
        followersCount: (_profile.followersCount + delta).clamp(0, 999999),
      );
    });
    try {
      await service.setFollow(
        targetId: widget.profileId,
        viewerId: _viewerId,
        follow: shouldFollow,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        final snapshot = _latestSnapshot;
        final fallbackCount =
            (_profile.followersCount + (shouldFollow ? -1 : 1))
                .clamp(0, 999999);
        _profile = _profile.copyWith(
          following: snapshot?.isFollowedByViewer ?? !shouldFollow,
          followersCount: snapshot?.followersCount ?? fallbackCount,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('フォロー状態の更新に失敗しました: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessingFollow = false);
      }
    }
  }

  void _showFollowSheet(ProfileFollowSheetMode mode) {
    final navigator = Navigator.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return ProfileFollowListSheet(
          targetId: widget.profileId,
          viewerId: _viewerId,
          mode: mode,
          onProfileTap: (profile) {
            if (profile.id == widget.profileId) {
              return;
            }
            navigator.push(
              MaterialPageRoute(
                builder: (_) => ProfileViewScreen(
                  profileId: profile.id,
                  initialProfile: profile,
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
    final bio = _displayOrPlaceholder(_profile.bio);
    final homeTown = _displayOrPlaceholder(_profile.homeTown);
    final hobbies = _hobbiesOrPlaceholder(_profile.favoriteGames);
    final isSelf = widget.profileId == _viewerId;

    return Scaffold(
      appBar: AppBar(
        title: Text(_profile.displayName),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            if (_isLoadingDetails) const LinearProgressIndicator(minHeight: 2),
            Padding(
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
                              ProfileAvatar(profile: _profile, radius: 38),
                              const SizedBox(width: 18),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _profile.displayName,
                                      style:
                                          theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      bio == '未登録' ? '自己紹介はまだありません。' : bio,
                                      style: theme.textTheme.bodyMedium,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          ProfileStatsRow(
                            profile: _profile,
                            onFollowersTap: () => _showFollowSheet(
                                ProfileFollowSheetMode.followers),
                            onFollowingTap: () => _showFollowSheet(
                                ProfileFollowSheetMode.following),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'ステータス',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 10),
                          ProfileInfoTile(
                            icon: Icons.mood,
                            title: '一言コメント',
                            value: bio,
                          ),
                          ProfileInfoTile(
                            icon: Icons.place_outlined,
                            title: '活動エリア',
                            value: homeTown,
                          ),
                          ProfileInfoTile(
                            icon: Icons.palette_outlined,
                            title: '趣味',
                            value: hobbies,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!isSelf) ...[
                    const SizedBox(height: 16),
                    IgnorePointer(
                      ignoring: _isProcessingFollow,
                      child: Opacity(
                        opacity: _isProcessingFollow ? 0.7 : 1,
                        child: FollowButton(
                          isFollowing: _profile.following,
                          onPressed: _toggleFollow,
                          variant: LikeButtonVariant.hero,
                          maxWidth: double.infinity,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _displayOrPlaceholder(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == '未登録') {
    return '未登録';
  }
  return trimmed;
}

String _hobbiesOrPlaceholder(List<String> hobbies) {
  if (hobbies.isEmpty) {
    return '未登録';
  }
  return hobbies.join(', ');
}
