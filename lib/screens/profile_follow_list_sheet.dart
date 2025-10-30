import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../services/profile_interaction_service.dart';
import '../widgets/like_button.dart';
import '../widgets/profile_avatar.dart';

enum ProfileFollowSheetMode { followers, following }

class ProfileFollowListSheet extends StatefulWidget {
  const ProfileFollowListSheet({
    super.key,
    required this.targetId,
    required this.viewerId,
    required this.mode,
    this.onProfileTap,
  });

  final String targetId;
  final String viewerId;
  final ProfileFollowSheetMode mode;
  final ValueChanged<Profile>? onProfileTap;

  @override
  State<ProfileFollowListSheet> createState() => _ProfileFollowListSheetState();
}

class _ProfileFollowListSheetState extends State<ProfileFollowListSheet> {
  final Set<String> _pending = <String>{};

  @override
  Widget build(BuildContext context) {
    final service = context.read<ProfileInteractionService>();
    final stream = widget.mode == ProfileFollowSheetMode.followers
        ? service.watchFollowers(
            targetId: widget.targetId,
            viewerId: widget.viewerId,
          )
        : service.watchFollowing(
            targetId: widget.targetId,
            viewerId: widget.viewerId,
          );

    final title =
        widget.mode == ProfileFollowSheetMode.followers ? 'フォロワー' : 'フォロー';

    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: StreamBuilder<List<ProfileFollowSnapshot>>(
          stream: stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return SizedBox(
                height: 240,
                child: Center(
                  child: Text('一覧の読み込みに失敗しました。再度お試しください。'),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final items = snapshot.data ?? const <ProfileFollowSnapshot>[];
            if (items.isEmpty) {
              final emptyMessage =
                  widget.mode == ProfileFollowSheetMode.followers
                      ? 'まだフォロワーはいません。'
                      : 'まだフォロー中のプレイヤーはいません。';
              return SizedBox(
                height: 220,
                child: Column(
                  children: [
                    _SheetHeader(title: title, count: 0),
                    const Divider(height: 1),
                    Expanded(
                      child: Center(
                        child: Text(emptyMessage),
                      ),
                    ),
                  ],
                ),
              );
            }
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.65,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SheetHeader(title: title, count: items.length),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = items[index];
                        return _ProfileFollowTile(
                          snapshot: entry,
                          viewerId: widget.viewerId,
                          isBusy: _pending.contains(entry.profile.id),
                          onFollowToggle: () => _toggleFollow(entry),
                          onProfileTap: widget.onProfileTap,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _toggleFollow(ProfileFollowSnapshot snapshot) async {
    final profileId = snapshot.profile.id;
    if (_pending.contains(profileId) || profileId == widget.viewerId) {
      return;
    }
    setState(() => _pending.add(profileId));
    final service = context.read<ProfileInteractionService>();
    final shouldFollow = !snapshot.isFollowedByViewer;
    try {
      await service.setFollow(
        targetId: profileId,
        viewerId: widget.viewerId,
        follow: shouldFollow,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('フォロー状態の更新に失敗しました: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _pending.remove(profileId));
      }
    }
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text('$count件', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ProfileFollowTile extends StatelessWidget {
  const _ProfileFollowTile({
    required this.snapshot,
    required this.viewerId,
    required this.isBusy,
    required this.onFollowToggle,
    required this.onProfileTap,
  });

  final ProfileFollowSnapshot snapshot;
  final String viewerId;
  final bool isBusy;
  final VoidCallback onFollowToggle;
  final ValueChanged<Profile>? onProfileTap;

  @override
  Widget build(BuildContext context) {
    final profile = snapshot.profile;
    final isSelf = profile.id == viewerId;
    final bio = profile.bio.trim().isEmpty ? '自己紹介はまだありません。' : profile.bio;
    final trailing = isSelf
        ? null
        : IgnorePointer(
            ignoring: isBusy,
            child: Opacity(
              opacity: isBusy ? 0.5 : 1,
              child: FollowButton(
                isFollowing: snapshot.isFollowedByViewer,
                onPressed: onFollowToggle,
                variant: LikeButtonVariant.chip,
              ),
            ),
          );

    return ListTile(
      leading: ProfileAvatar(profile: profile, radius: 24),
      title: Text(profile.displayName),
      subtitle: Text(
        bio,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
      onTap: () {
        final handler = onProfileTap;
        if (handler != null) {
          Navigator.of(context).pop();
          handler(profile);
        }
      },
    );
  }
}
