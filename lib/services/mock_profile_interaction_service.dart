import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/profile.dart';
import 'profile_interaction_service.dart';

class MockProfileInteractionService implements ProfileInteractionService {
  final Map<String, _MockProfileState> _profiles = {};
  final Map<String, _MockWatcher> _watchers = {};
  final Map<String, _MockRelationWatcher> _relationWatchers = {};
  final Map<String, _MockLikeWatcher> _likeWatchers = {};

  @override
  Future<void> bootstrapProfile(Profile profile) async {
    final state = _profiles.putIfAbsent(
      profile.id,
      () => _MockProfileState(),
    );
    state.beaconId = profile.beaconId;
    state.displayName = profile.displayName;
    state.bio = profile.bio;
    state.homeTown = profile.homeTown;
    state.favoriteGames = List<String>.from(profile.favoriteGames);
    state.avatarColorValue = profile.avatarColor.value;
    state.avatarImageBase64 = profile.avatarImageBase64;
    state.followersCount = profile.followersCount;
    state.followingCount = profile.followingCount;
    state.receivedLikes = profile.receivedLikes;
  }

  @override
  Stream<ProfileInteractionSnapshot> watchProfile({
    required String targetId,
    required String viewerId,
  }) {
    final key = _keyFor(targetId, viewerId);
    final existing = _watchers[key];
    if (existing != null) {
      return existing.stream;
    }

    late final _MockWatcher watcher;
    void handleEmpty() {
      final current = _watchers[key];
      if (current == watcher) {
        _watchers.remove(key);
      }
      watcher.dispose();
    }

    watcher = _MockWatcher(
      targetId: targetId,
      viewerId: viewerId,
      stateLookup: _getProfileState,
      onEmpty: handleEmpty,
    );
    _watchers[key] = watcher;
    return watcher.stream;
  }

  @override
  Stream<List<ProfileFollowSnapshot>> watchFollowers({
    required String targetId,
    required String viewerId,
  }) {
    final key = 'followers|$targetId|$viewerId';
    final existing = _relationWatchers[key];
    if (existing != null) {
      return existing.stream;
    }

    late final _MockRelationWatcher watcher;
    void handleEmpty() {
      final current = _relationWatchers[key];
      if (current == watcher) {
        _relationWatchers.remove(key);
      }
      watcher.dispose();
    }

    watcher = _MockRelationWatcher(
      targetId: targetId,
      viewerId: viewerId,
      type: _MockRelationType.followers,
      stateLookup: _getProfileState,
      onEmpty: handleEmpty,
    );
    _relationWatchers[key] = watcher;
    return watcher.stream;
  }

  @override
  Stream<List<ProfileFollowSnapshot>> watchFollowing({
    required String targetId,
    required String viewerId,
  }) {
    final key = 'following|$targetId|$viewerId';
    final existing = _relationWatchers[key];
    if (existing != null) {
      return existing.stream;
    }

    late final _MockRelationWatcher watcher;
    void handleEmpty() {
      final current = _relationWatchers[key];
      if (current == watcher) {
        _relationWatchers.remove(key);
      }
      watcher.dispose();
    }

    watcher = _MockRelationWatcher(
      targetId: targetId,
      viewerId: viewerId,
      type: _MockRelationType.following,
      stateLookup: _getProfileState,
      onEmpty: handleEmpty,
    );
    _relationWatchers[key] = watcher;
    return watcher.stream;
  }

  @override
  Stream<List<ProfileLikeSnapshot>> watchLikes({
    required String targetId,
    required String viewerId,
  }) {
    final key = 'likes|$targetId|$viewerId';
    final existing = _likeWatchers[key];
    if (existing != null) {
      return existing.stream;
    }

    late final _MockLikeWatcher watcher;
    void handleEmpty() {
      final current = _likeWatchers[key];
      if (current == watcher) {
        _likeWatchers.remove(key);
      }
      watcher.dispose();
    }

    watcher = _MockLikeWatcher(
      targetId: targetId,
      viewerId: viewerId,
      stateLookup: _getProfileState,
      onEmpty: handleEmpty,
    );
    _likeWatchers[key] = watcher;
    return watcher.stream;
  }

  @override
  Future<void> setLike({
    required String targetId,
    required Profile viewerProfile,
    required bool like,
  }) async {
    final viewerId = viewerProfile.id;
    if (targetId.isEmpty || viewerId.isEmpty || targetId == viewerId) {
      return;
    }
    final target = _getProfileState(targetId);
    final likedBefore = target.likedBy.containsKey(viewerId);

    if (like && !likedBefore) {
      target.likedBy[viewerId] = DateTime.now();
      target.receivedLikes += 1;
    } else if (!like && likedBefore) {
      target.likedBy.remove(viewerId);
      target.receivedLikes = max(0, target.receivedLikes - 1);
    }

    _notifyWatchers(targetId);
    _notifyLikeWatchers(targetId);
    _notifyLikeWatchers(viewerId);
  }

  @override
  Future<void> setFollow({
    required String targetId,
    required String viewerId,
    required bool follow,
  }) async {
    if (targetId.isEmpty || viewerId.isEmpty || targetId == viewerId) {
      return;
    }
    final target = _getProfileState(targetId);
    final viewer = _getProfileState(viewerId);
    final alreadyFollowing = target.followedBy.containsKey(viewerId);

    if (follow && !alreadyFollowing) {
      final now = DateTime.now();
      target.followedBy[viewerId] = now;
      target.followersCount = target.followedBy.length;
      viewer.following[targetId] = now;
      viewer.followingCount = viewer.following.length;
    } else if (!follow && alreadyFollowing) {
      target.followedBy.remove(viewerId);
      target.followersCount = target.followedBy.length;
      viewer.following.remove(targetId);
      viewer.followingCount = viewer.following.length;
    }

    _notifyWatchers(targetId);
    _notifyWatchers(viewerId);
    _notifyRelationWatchers(targetId);
    _notifyRelationWatchers(viewerId);
    _notifyLikeWatchers(targetId);
    _notifyLikeWatchers(viewerId);
  }

  @override
  Future<List<ProfileFollowSnapshot>> loadFollowersOnce({
    required String targetId,
    required String viewerId,
  }) async {
    return _buildRelationSnapshots(
      targetId: targetId,
      viewerId: viewerId,
      type: _MockRelationType.followers,
    );
  }

  @override
  Future<List<ProfileFollowSnapshot>> loadFollowingOnce({
    required String targetId,
    required String viewerId,
  }) async {
    return _buildRelationSnapshots(
      targetId: targetId,
      viewerId: viewerId,
      type: _MockRelationType.following,
    );
  }

  Future<List<ProfileFollowSnapshot>> _buildRelationSnapshots({
    required String targetId,
    required String viewerId,
    required _MockRelationType type,
  }) async {
    final targetState = _getProfileState(targetId);
    final viewerState = _getProfileState(viewerId);
    final viewerFollowing = viewerState.following.keys.toSet();
    final source = type == _MockRelationType.followers
        ? targetState.followedBy.entries
        : targetState.following.entries;
    final sorted = source.toList()..sort((a, b) => b.value.compareTo(a.value));
    final snapshots = <ProfileFollowSnapshot>[];
    for (final entry in sorted) {
      final profileId = entry.key;
      final otherState = _getProfileState(profileId);
      final profile = _profileFromState(profileId, otherState);
      snapshots.add(
        ProfileFollowSnapshot(
          profile: profile,
          isFollowedByViewer: viewerFollowing.contains(profileId),
          followedAt: entry.value,
        ),
      );
    }
    return snapshots;
  }

  @override
  Future<Profile?> loadProfile(String profileId) async {
    if (profileId.isEmpty) {
      return null;
    }
    final state = _getProfileState(profileId);
    if (state.displayName.isEmpty) {
      return null;
    }
    return _profileFromState(profileId, state);
  }

  @override
  Future<void> dispose() async {
    for (final watcher in _watchers.values.toList()) {
      watcher.dispose();
    }
    _watchers.clear();
    for (final watcher in _relationWatchers.values.toList()) {
      watcher.dispose();
    }
    _relationWatchers.clear();
    for (final watcher in _likeWatchers.values.toList()) {
      watcher.dispose();
    }
    _likeWatchers.clear();
    _profiles.clear();
  }

  _MockProfileState _getProfileState(String id) {
    return _profiles.putIfAbsent(id, () => _MockProfileState());
  }

  void _notifyWatchers(String targetId) {
    final entries = _watchers.entries
        .where((entry) => entry.value.targetId == targetId)
        .toList(growable: false);
    for (final entry in entries) {
      entry.value.emit();
    }
  }

  void _notifyRelationWatchers(String targetId) {
    final entries = _relationWatchers.entries
        .where((entry) => entry.value.targetId == targetId)
        .toList(growable: false);
    for (final entry in entries) {
      entry.value.emit();
    }
  }

  void _notifyLikeWatchers(String targetId) {
    final entries = _likeWatchers.entries
        .where((entry) => entry.value.targetId == targetId)
        .toList(growable: false);
    for (final entry in entries) {
      entry.value.emit();
    }
  }

  String _keyFor(String targetId, String viewerId) => '$targetId|$viewerId';
}

class _MockWatcher {
  _MockWatcher({
    required this.targetId,
    required this.viewerId,
    required _MockProfileState Function(String id) stateLookup,
    required VoidCallback onEmpty,
  })  : _stateLookup = stateLookup,
        _onEmpty = onEmpty {
    _controller = StreamController<ProfileInteractionSnapshot>.broadcast(
      onListen: _handleListen,
      onCancel: _handleCancel,
    );
  }

  final String targetId;
  final String viewerId;
  final _MockProfileState Function(String id) _stateLookup;
  final VoidCallback _onEmpty;

  late final StreamController<ProfileInteractionSnapshot> _controller;
  int _listenerCount = 0;
  bool _isDisposed = false;

  Stream<ProfileInteractionSnapshot> get stream => _controller.stream;

  void emit() {
    final target = _stateLookup(targetId);
    final snapshot = ProfileInteractionSnapshot(
      receivedLikes: target.receivedLikes,
      followersCount: target.followersCount,
      followingCount: target.followingCount,
      isLikedByViewer:
          viewerId == targetId ? false : target.likedBy.containsKey(viewerId),
      isFollowedByViewer: viewerId == targetId
          ? false
          : target.followedBy.containsKey(viewerId),
    );
    if (!_controller.isClosed && _controller.hasListener) {
      _controller.add(snapshot);
    }
  }

  void _handleListen() {
    _listenerCount++;
    emit();
  }

  void _handleCancel() {
    _listenerCount = max(0, _listenerCount - 1);
    if (_listenerCount == 0) {
      _onEmpty();
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    unawaited(_controller.close());
  }
}

enum _MockRelationType { followers, following }

class _MockRelationWatcher {
  _MockRelationWatcher({
    required this.targetId,
    required this.viewerId,
    required this.type,
    required _MockProfileState Function(String id) stateLookup,
    required VoidCallback onEmpty,
  })  : _stateLookup = stateLookup,
        _onEmpty = onEmpty {
    _controller = StreamController<List<ProfileFollowSnapshot>>.broadcast(
      onListen: _handleListen,
      onCancel: _handleCancel,
    );
  }

  final String targetId;
  final String viewerId;
  final _MockRelationType type;
  final _MockProfileState Function(String id) _stateLookup;
  final VoidCallback _onEmpty;

  late final StreamController<List<ProfileFollowSnapshot>> _controller;
  int _listenerCount = 0;
  bool _isDisposed = false;

  Stream<List<ProfileFollowSnapshot>> get stream => _controller.stream;

  void emit() {
    if (_controller.isClosed || !_controller.hasListener) {
      return;
    }
    final targetState = _stateLookup(targetId);
    final viewerState = _stateLookup(viewerId);
    final viewerFollowing = viewerState.following.keys.toSet();
    final source = type == _MockRelationType.followers
        ? targetState.followedBy.entries
        : targetState.following.entries;

    final sorted = source.toList()..sort((a, b) => b.value.compareTo(a.value));

    final snapshots = <ProfileFollowSnapshot>[];
    for (final entry in sorted) {
      final profileId = entry.key;
      final otherState = _stateLookup(profileId);
      final profile = _profileFromState(profileId, otherState);
      final isFollowed = viewerFollowing.contains(profileId);
      snapshots.add(
        ProfileFollowSnapshot(
          profile: profile,
          isFollowedByViewer: isFollowed,
          followedAt: entry.value,
        ),
      );
    }
    _controller.add(snapshots);
  }

  void _handleListen() {
    _listenerCount++;
    emit();
  }

  void _handleCancel() {
    _listenerCount = max(0, _listenerCount - 1);
    if (_listenerCount == 0) {
      _onEmpty();
    }
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    unawaited(_controller.close());
  }
}

class _MockLikeWatcher {
  _MockLikeWatcher({
    required this.targetId,
    required this.viewerId,
    required _MockProfileState Function(String id) stateLookup,
    required VoidCallback onEmpty,
  })  : _stateLookup = stateLookup,
        _onEmpty = onEmpty {
    _controller = StreamController<List<ProfileLikeSnapshot>>.broadcast(
      onListen: _handleListen,
      onCancel: _handleCancel,
    );
  }

  final String targetId;
  final String viewerId;
  final _MockProfileState Function(String id) _stateLookup;
  final VoidCallback _onEmpty;

  late final StreamController<List<ProfileLikeSnapshot>> _controller;
  int _listenerCount = 0;
  bool _isDisposed = false;

  Stream<List<ProfileLikeSnapshot>> get stream => _controller.stream;

  void emit() {
    if (_controller.isClosed || !_controller.hasListener) {
      return;
    }
    final targetState = _stateLookup(targetId);
    final viewerState = _stateLookup(viewerId);
    final viewerFollowing = viewerState.following.keys.toSet();
    final entries = targetState.likedBy.entries.toList()
      ..sort((a, b) {
        final left = a.value;
        final right = b.value;
        if (left == null && right == null) {
          return 0;
        }
        if (left == null) {
          return 1;
        }
        if (right == null) {
          return -1;
        }
        return right.compareTo(left);
      });
    final snapshots = <ProfileLikeSnapshot>[];
    for (final entry in entries) {
      final profileId = entry.key;
      final state = _stateLookup(profileId);
      final profile = _profileFromState(profileId, state);
      snapshots.add(
        ProfileLikeSnapshot(
          profile: profile,
          isFollowedByViewer: viewerFollowing.contains(profileId),
          likedAt: entry.value,
        ),
      );
    }
    _controller.add(snapshots);
  }

  void _handleListen() {
    _listenerCount++;
    emit();
  }

  void _handleCancel() {
    _listenerCount = max(0, _listenerCount - 1);
    if (_listenerCount == 0) {
      _onEmpty();
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    unawaited(_controller.close());
  }
}

class _MockProfileState {
  _MockProfileState();

  String beaconId = '';
  String displayName = '';
  String bio = '';
  String homeTown = '';
  List<String> favoriteGames = const [];
  int avatarColorValue = 0;
  String? avatarImageBase64;
  int followersCount = 0;
  int followingCount = 0;
  int receivedLikes = 0;
  final Map<String, DateTime> likedBy = <String, DateTime>{};
  final Map<String, DateTime> followedBy = <String, DateTime>{};
  final Map<String, DateTime> following = <String, DateTime>{};
}

Profile _profileFromState(String id, _MockProfileState state) {
  return Profile(
    id: id,
    beaconId: state.beaconId.isNotEmpty ? state.beaconId : id,
    displayName: state.displayName,
    bio: state.bio,
    homeTown: state.homeTown,
    favoriteGames: List<String>.from(state.favoriteGames),
    avatarColor: Color(state.avatarColorValue),
    avatarImageBase64: state.avatarImageBase64,
    receivedLikes: state.receivedLikes,
    followersCount: state.followersCount,
    followingCount: state.followingCount,
  );
}
