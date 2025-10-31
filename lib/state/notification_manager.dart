import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/app_notification.dart';
import '../models/profile.dart';
import '../services/profile_interaction_service.dart';

class NotificationManager extends ChangeNotifier {
  NotificationManager({
    required ProfileInteractionService interactionService,
    required Profile localProfile,
  })  : _interactionService = interactionService,
        _localProfile = localProfile {
    _startSubscriptions();
  }

  final ProfileInteractionService _interactionService;
  Profile _localProfile;
  final List<AppNotification> _notifications = [];
  final Uuid _uuid = const Uuid();

  StreamSubscription<List<ProfileFollowSnapshot>>? _followersSub;
  StreamSubscription<List<ProfileLikeSnapshot>>? _likesSub;
  bool _followersInitialized = false;
  bool _likesInitialized = false;
  Set<String> _knownFollowerIds = const {};
  Set<String> _knownLikeIds = const {};

  List<AppNotification> get notifications =>
      List.unmodifiable(_notifications..sort(_sortByNewest));

  int get unreadCount =>
      _notifications.where((notification) => !notification.read).length;

  void registerEncounter({
    required Profile profile,
    required DateTime encounteredAt,
    String? encounterId,
    String? message,
    bool isRepeat = false,
  }) {
    final title = isRepeat
        ? '${profile.displayName}さんとまたすれ違いました'
        : '${profile.displayName}さんとすれ違いました';
    final body = message?.trim().isNotEmpty == true
        ? message!.trim()
        : 'プロフィールを確認してみましょう。';
    _appendNotification(
      AppNotification(
        id: _uuid.v4(),
        type: AppNotificationType.encounter,
        title: title,
        message: body,
        createdAt: encounteredAt,
        profile: profile,
        encounterId: encounterId,
      ),
    );
  }

  void markEncounterNotificationsRead(String encounterId) {
    var changed = false;
    for (final notification in _notifications) {
      if (notification.encounterId == encounterId && !notification.read) {
        notification.markRead();
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  void markNotificationRead(String notificationId) {
    for (final notification in _notifications) {
      if (notification.id == notificationId && !notification.read) {
        notification.markRead();
        notifyListeners();
        break;
      }
    }
  }

  void markAllRead() {
    var changed = false;
    for (final notification in _notifications) {
      if (!notification.read) {
        notification.markRead();
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  void updateLocalProfile(Profile profile) {
    if (profile.id == _localProfile.id) {
      _localProfile = profile;
      return;
    }
    _localProfile = profile;
    _restartSubscriptions();
  }

  Future<void> resetForProfile(Profile profile) async {
    await _followersSub?.cancel();
    await _likesSub?.cancel();
    _followersSub = null;
    _likesSub = null;
    _followersInitialized = false;
    _likesInitialized = false;
    _knownFollowerIds = const {};
    _knownLikeIds = const {};
    _notifications.clear();
    _localProfile = profile;
    _startSubscriptions();
    notifyListeners();
  }

  @override
  void dispose() {
    _followersSub?.cancel();
    _likesSub?.cancel();
    super.dispose();
  }

  void _startSubscriptions() {
    _followersSub = _interactionService
        .watchFollowers(
      targetId: _localProfile.id,
      viewerId: _localProfile.id,
    )
        .listen(
      (snapshots) => unawaited(_handleFollowers(snapshots)),
      onError: (error, stackTrace) {
        debugPrint('通知フォロワー監視に失敗: $error');
      },
    );
    _likesSub = _interactionService
        .watchLikes(
      targetId: _localProfile.id,
      viewerId: _localProfile.id,
    )
        .listen(
      (snapshots) => unawaited(_handleLikes(snapshots)),
      onError: (error, stackTrace) {
        debugPrint('通知いいね監視に失敗: $error');
      },
    );
  }

  void _restartSubscriptions() {
    _followersSub?.cancel();
    _likesSub?.cancel();
    _followersInitialized = false;
    _likesInitialized = false;
    _knownFollowerIds = const {};
    _knownLikeIds = const {};
    _startSubscriptions();
  }

  Future<void> _handleFollowers(List<ProfileFollowSnapshot> snapshots) async {
    final currentIds = snapshots.map((snapshot) => snapshot.profile.id).toSet();
    if (!_followersInitialized) {
      _knownFollowerIds = currentIds;
      _followersInitialized = true;
      return;
    }
    final newIds = currentIds.difference(_knownFollowerIds);
    for (final id in newIds) {
      final snapshot =
          snapshots.firstWhere((element) => element.profile.id == id);
      // Do not notify for actions performed by the local profile itself.
      if (snapshot.profile.id == _localProfile.id ||
          snapshot.profile.beaconId == _localProfile.beaconId) continue;
      final profile = await _resolveProfile(
        snapshot.profile,
        isFollowedByViewer: snapshot.isFollowedByViewer,
      );
      _appendNotification(
        AppNotification(
          id: _uuid.v4(),
          type: AppNotificationType.follow,
          title: '${profile.displayName}さんがあなたをフォローしました',
          message: 'フォローバックしてみましょう。',
          createdAt: snapshot.followedAt ?? DateTime.now(),
          profile: profile,
        ),
      );
    }
    _knownFollowerIds = currentIds;
  }

  Future<void> _handleLikes(List<ProfileLikeSnapshot> snapshots) async {
    final currentIds = snapshots.map((snapshot) => snapshot.profile.id).toSet();
    if (!_likesInitialized) {
      _knownLikeIds = currentIds;
      _likesInitialized = true;
      return;
    }
    final newIds = currentIds.difference(_knownLikeIds);
    for (final id in newIds) {
      final snapshot =
          snapshots.firstWhere((element) => element.profile.id == id);
      // Skip notifications when the actor is the local profile.
      if (snapshot.profile.id == _localProfile.id ||
          snapshot.profile.beaconId == _localProfile.beaconId) continue;
      final profile = await _resolveProfile(
        snapshot.profile,
        isFollowedByViewer: snapshot.isFollowedByViewer,
      );
      _appendNotification(
        AppNotification(
          id: _uuid.v4(),
          type: AppNotificationType.like,
          title: '${profile.displayName}さんがあなたにいいねしました',
          message: 'お返しにいいねやフォローをしてみませんか？',
          createdAt: snapshot.likedAt ?? DateTime.now(),
          profile: profile,
        ),
      );
    }
    _knownLikeIds = currentIds;
  }

  void _appendNotification(AppNotification notification) {
    _notifications.add(notification);
    _notifications.sort(_sortByNewest);
    notifyListeners();
  }

  Future<Profile> _resolveProfile(
    Profile profile, {
    bool? isFollowedByViewer,
  }) async {
    try {
      final fresh = await _interactionService.loadProfile(profile.id);
      if (fresh != null) {
        return fresh.copyWith(following: isFollowedByViewer ?? fresh.following);
      }
    } catch (error) {
      debugPrint('通知プロフィールの取得に失敗: $error');
    }
    return profile.copyWith(following: isFollowedByViewer ?? profile.following);
  }

  static int _sortByNewest(AppNotification a, AppNotification b) {
    return b.createdAt.compareTo(a.createdAt);
  }
}
