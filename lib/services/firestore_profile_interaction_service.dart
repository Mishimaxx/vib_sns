import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/profile.dart';
import 'profile_interaction_service.dart';

class FirestoreProfileInteractionService implements ProfileInteractionService {
  FirestoreProfileInteractionService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const _profilesCollection = 'profiles';

  final FirebaseFirestore _firestore;
  final Map<String, _ProfileWatcher> _watchers = {};
  final Map<String, _RelationshipWatcher> _relationWatchers = {};
  final Map<String, _LikesWatcher> _likeWatchers = {};
  final Map<String, _FollowingCache> _followingCaches = {};

  @override
  Future<void> bootstrapProfile(Profile profile) async {
    final profiles = _firestore.collection(_profilesCollection);
    await _firestore.runTransaction((transaction) async {
      final ref = profiles.doc(profile.id);
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) {
        // Log profile creation attempts so we can trace unexpected/profile
        // proliferation during testing. This will help identify which
        // client(s) are causing extra documents to appear in Firestore.
        debugPrint(
            'bootstrapProfile: creating profile doc id=${profile.id} beaconId=${profile.beaconId} displayName="${profile.displayName}"');
        debugPrint(StackTrace.current.toString());
      }
      final data = <String, dynamic>{
        'bio': profile.bio,
        'homeTown': profile.homeTown,
        'favoriteGames': profile.favoriteGames,
        'beaconId': profile.beaconId,
        'avatarColor': profile.avatarColor.value,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final hasAvatarImage =
          profile.avatarImageBase64?.trim().isNotEmpty ?? false;
      if (hasAvatarImage) {
        data['avatarImageBase64'] = profile.avatarImageBase64;
      } else if (snapshot.exists &&
          (snapshot.data()?['avatarImageBase64'] != null)) {
        data['avatarImageBase64'] = FieldValue.delete();
      }
      // Only write displayName if it's non-empty (avoid writing placeholder
      // defaults like empty string). This prevents creating many profiles with
      // a generic name when the user hasn't completed setup.
      if (profile.displayName.trim().isNotEmpty) {
        data['displayName'] = profile.displayName;
      }
      if (!snapshot.exists) {
        data.addAll({
          'followersCount': profile.followersCount,
          'followingCount': profile.followingCount,
          'receivedLikes': profile.receivedLikes,
        });
      }
      // Record whether we're creating a new doc or merging into an existing
      // one so we can correlate client logs with Firestore documents.
      if (!snapshot.exists) {
        debugPrint(
            'bootstrapProfile: transaction.set -> creating ${profile.id}');
      } else {
        debugPrint(
            'bootstrapProfile: transaction.set -> merging into ${profile.id}');
      }
      transaction.set(ref, data, SetOptions(merge: true));
    });
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
    late final _ProfileWatcher watcher;
    void handleEmpty() {
      final current = _watchers[key];
      if (current == watcher) {
        _watchers.remove(key);
      }
      watcher.dispose();
    }

    watcher = _ProfileWatcher(
      firestore: _firestore,
      targetId: targetId,
      viewerId: viewerId,
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
    final watcher = _RelationshipWatcher(
      firestore: _firestore,
      targetId: targetId,
      viewerId: viewerId,
      type: _RelationType.followers,
      getFollowingCache: _ensureFollowingCache,
      onEmpty: () {
        final current = _relationWatchers.remove(key);
        current?.dispose();
      },
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
    final watcher = _RelationshipWatcher(
      firestore: _firestore,
      targetId: targetId,
      viewerId: viewerId,
      type: _RelationType.following,
      getFollowingCache: _ensureFollowingCache,
      onEmpty: () {
        final current = _relationWatchers.remove(key);
        current?.dispose();
      },
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
    final watcher = _LikesWatcher(
      firestore: _firestore,
      targetId: targetId,
      viewerId: viewerId,
      getFollowingCache: _ensureFollowingCache,
      onEmpty: () {
        final current = _likeWatchers.remove(key);
        current?.dispose();
      },
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
    final profiles = _firestore.collection(_profilesCollection);
    final targetRef = profiles.doc(targetId);
    final viewerRef = profiles.doc(viewerId);
    final likeRef = targetRef.collection('likes').doc(viewerId);

    await _firestore.runTransaction((transaction) async {
      final targetSnap = await transaction.get(targetRef);
      final likeSnap = await transaction.get(likeRef);
      var likes = (targetSnap.data()?['receivedLikes'] as num?)?.toInt() ?? 0;
      Profile summaryProfile = viewerProfile;
      try {
        final viewerSnap = await transaction.get(viewerRef);
        if (viewerSnap.exists) {
          final stored = _profileFromDocument(viewerSnap, fallbackId: viewerId);
          summaryProfile = stored.copyWith(
            displayName: viewerProfile.displayName.isNotEmpty
                ? viewerProfile.displayName
                : stored.displayName,
            avatarColor: viewerProfile.avatarColor,
            avatarImageBase64: viewerProfile.avatarImageBase64,
          );
        }
      } catch (_) {
        // Ignore snapshot load failures; fall back to provided profile.
      }

      if (like && !likeSnap.exists) {
        likes += 1;
        transaction.set(likeRef, {
          'createdAt': FieldValue.serverTimestamp(),
          'profile': _profileSummary(summaryProfile),
        });
        transaction.set(
            targetRef,
            {
              'receivedLikes': likes,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
      } else if (!like && likeSnap.exists) {
        likes = max(0, likes - 1);
        transaction.delete(likeRef);
        transaction.set(
            targetRef,
            {
              'receivedLikes': likes,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
      }
    });
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
    final profiles = _firestore.collection(_profilesCollection);
    final targetRef = profiles.doc(targetId);
    final viewerRef = profiles.doc(viewerId);
    final followerRef = targetRef.collection('followers').doc(viewerId);
    final followingRef = viewerRef.collection('following').doc(targetId);

    await _firestore.runTransaction((transaction) async {
      final targetSnap = await transaction.get(targetRef);
      final viewerSnap = await transaction.get(viewerRef);
      final followerSnap = await transaction.get(followerRef);

      var followers =
          (targetSnap.data()?['followersCount'] as num?)?.toInt() ?? 0;
      var following =
          (viewerSnap.data()?['followingCount'] as num?)?.toInt() ?? 0;

      final targetProfile =
          _profileFromDocument(targetSnap, fallbackId: targetId);
      final viewerProfile =
          _profileFromDocument(viewerSnap, fallbackId: viewerId);

      if (follow && !followerSnap.exists) {
        followers += 1;
        following += 1;
        transaction.set(followerRef, {
          'createdAt': FieldValue.serverTimestamp(),
          'profile': _profileSummary(viewerProfile),
        });
        transaction.set(followingRef, {
          'createdAt': FieldValue.serverTimestamp(),
          'profile': _profileSummary(targetProfile),
        });
        transaction.set(
            targetRef,
            {
              'followersCount': followers,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
        transaction.set(
            viewerRef,
            {
              'followingCount': following,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
      } else if (!follow && followerSnap.exists) {
        followers = max(0, followers - 1);
        following = max(0, following - 1);
        transaction.delete(followerRef);
        transaction.delete(followingRef);
        transaction.set(
            targetRef,
            {
              'followersCount': followers,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
        transaction.set(
            viewerRef,
            {
              'followingCount': following,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
      }
    });
  }

  @override
  Future<List<ProfileFollowSnapshot>> loadFollowersOnce({
    required String targetId,
    required String viewerId,
  }) {
    return _fetchRelationSnapshots(
      targetId: targetId,
      viewerId: viewerId,
      type: _RelationType.followers,
    );
  }

  @override
  Future<List<ProfileFollowSnapshot>> loadFollowingOnce({
    required String targetId,
    required String viewerId,
  }) {
    return _fetchRelationSnapshots(
      targetId: targetId,
      viewerId: viewerId,
      type: _RelationType.following,
    );
  }

  Future<List<ProfileFollowSnapshot>> _fetchRelationSnapshots({
    required String targetId,
    required String viewerId,
    required _RelationType type,
  }) async {
    final profiles =
        _firestore.collection(FirestoreProfileInteractionService._profilesCollection);
    final docRef = profiles.doc(targetId);
    final collectionName =
        type == _RelationType.followers ? 'followers' : 'following';
    final query = await docRef.collection(collectionName).get();
    final entries = <_RelationEntry>[];
    for (final doc in query.docs) {
      final entry = await _buildRelationEntry(_firestore, doc);
      if (entry != null) {
        entries.add(entry);
      }
    }
    entries.sort((a, b) {
      final left = a.followedAt?.millisecondsSinceEpoch ?? 0;
      final right = b.followedAt?.millisecondsSinceEpoch ?? 0;
      return right.compareTo(left);
    });
    final viewerFollowing = await _loadViewerFollowingIds(viewerId);
    return entries
        .map(
          (entry) => ProfileFollowSnapshot(
            profile: entry.profile,
            isFollowedByViewer: viewerFollowing.contains(entry.profile.id),
            followedAt: entry.followedAt,
          ),
        )
        .toList(growable: false);
  }

  Future<Set<String>> _loadViewerFollowingIds(String viewerId) async {
    final snapshot = await _firestore
        .collection(FirestoreProfileInteractionService._profilesCollection)
        .doc(viewerId)
        .collection('following')
        .get();
    return snapshot.docs.map((doc) => doc.id).toSet();
  }

  @override
  Future<Profile?> loadProfile(String profileId) async {
    if (profileId.isEmpty) {
      return null;
    }
    try {
      final snapshot =
          await _firestore.collection(_profilesCollection).doc(profileId).get();
      if (!snapshot.exists) {
        return null;
      }
      return _profileFromDocument(snapshot, fallbackId: profileId);
    } catch (error, stackTrace) {
      debugPrint('Failed to load profile $profileId: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
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
    for (final cache in _followingCaches.values.toList()) {
      cache.dispose();
    }
    _followingCaches.clear();
  }

  String _keyFor(String targetId, String viewerId) => '$targetId|$viewerId';

  _FollowingCache _ensureFollowingCache(String viewerId) {
    final existing = _followingCaches[viewerId];
    if (existing != null) {
      return existing;
    }
    late final _FollowingCache cache;
    void handleEmpty() {
      final current = _followingCaches[viewerId];
      if (current == cache) {
        _followingCaches.remove(viewerId);
        cache.dispose();
      }
    }

    cache = _FollowingCache(
      firestore: _firestore,
      viewerId: viewerId,
      onEmpty: handleEmpty,
    );
    _followingCaches[viewerId] = cache;
    return cache;
  }
}

class _ProfileWatcher {
  _ProfileWatcher({
    required FirebaseFirestore firestore,
    required this.targetId,
    required this.viewerId,
    required VoidCallback onEmpty,
  })  : _firestore = firestore,
        _onEmpty = onEmpty {
    _controller = StreamController<ProfileInteractionSnapshot>.broadcast(
      onListen: _handleListen,
      onCancel: _handleCancel,
    );
  }

  final FirebaseFirestore _firestore;
  final String targetId;
  final String viewerId;
  final VoidCallback _onEmpty;

  late final StreamController<ProfileInteractionSnapshot> _controller;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _likeSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _followSub;
  int _listenerCount = 0;
  bool _isDisposed = false;

  int _receivedLikes = 0;
  int _followersCount = 0;
  int _followingCount = 0;
  bool _likedByViewer = false;
  bool _followedByViewer = false;
  ProfileInteractionSnapshot? _latest;

  Stream<ProfileInteractionSnapshot> get stream => _controller.stream;

  void _handleListen() {
    _listenerCount++;
    if (_listenerCount == 1) {
      _subscribe();
    }
    if (_latest != null && !_controller.isClosed) {
      scheduleMicrotask(() {
        if (!_controller.isClosed &&
            _controller.hasListener &&
            _latest != null) {
          _controller.add(_latest!);
        }
      });
    } else {
      _emitSnapshot();
    }
  }

  void _handleCancel() {
    _listenerCount = max(0, _listenerCount - 1);
    if (_listenerCount == 0) {
      _unsubscribe();
      _onEmpty();
    }
  }

  void _subscribe() {
    final docRef = _firestore
        .collection(FirestoreProfileInteractionService._profilesCollection)
        .doc(targetId);
    _profileSub = docRef.snapshots().listen(
      (snapshot) {
        final data = snapshot.data();
        _receivedLikes = (data?['receivedLikes'] as num?)?.toInt() ?? 0;
        _followersCount = (data?['followersCount'] as num?)?.toInt() ?? 0;
        _followingCount = (data?['followingCount'] as num?)?.toInt() ?? 0;
        _emitSnapshot();
      },
      onError: (error, stackTrace) {
        if (!_controller.isClosed) {
          _controller.addError(error, stackTrace);
        }
      },
    );

    if (targetId == viewerId) {
      _likedByViewer = false;
      _followedByViewer = false;
      _emitSnapshot();
      return;
    }

    _likeSub = docRef.collection('likes').doc(viewerId).snapshots().listen(
      (snapshot) {
        _likedByViewer = snapshot.exists;
        _emitSnapshot();
      },
      onError: (error, stackTrace) {
        if (!_controller.isClosed) {
          _controller.addError(error, stackTrace);
        }
      },
    );

    _followSub =
        docRef.collection('followers').doc(viewerId).snapshots().listen(
      (snapshot) {
        _followedByViewer = snapshot.exists;
        _emitSnapshot();
      },
      onError: (error, stackTrace) {
        if (!_controller.isClosed) {
          _controller.addError(error, stackTrace);
        }
      },
    );
  }

  void _emitSnapshot() {
    final snapshot = ProfileInteractionSnapshot(
      receivedLikes: _receivedLikes,
      followersCount: _followersCount,
      followingCount: _followingCount,
      isLikedByViewer: _likedByViewer,
      isFollowedByViewer: _followedByViewer,
    );
    _latest = snapshot;
    if (!_controller.isClosed && _controller.hasListener) {
      _controller.add(snapshot);
    }
  }

  void _unsubscribe() {
    unawaited(_profileSub?.cancel());
    unawaited(_likeSub?.cancel());
    unawaited(_followSub?.cancel());
    _profileSub = null;
    _likeSub = null;
    _followSub = null;
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _unsubscribe();
    unawaited(_controller.close());
  }
}

enum _RelationType { followers, following }

class _RelationshipWatcher {
  _RelationshipWatcher({
    required FirebaseFirestore firestore,
    required this.targetId,
    required this.viewerId,
    required this.type,
    required this.getFollowingCache,
    required VoidCallback onEmpty,
  })  : _firestore = firestore,
        _onEmpty = onEmpty {
    _controller = StreamController<List<ProfileFollowSnapshot>>.broadcast(
      onListen: _handleListen,
      onCancel: _handleCancel,
    );
  }

  final FirebaseFirestore _firestore;
  final String targetId;
  final String viewerId;
  final _RelationType type;
  final _FollowingCache Function(String viewerId) getFollowingCache;
  final VoidCallback _onEmpty;

  late final StreamController<List<ProfileFollowSnapshot>> _controller;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _relationSub;
  StreamSubscription<Set<String>>? _followingSub;
  _FollowingCache? _followingCache;
  int _listenerCount = 0;
  bool _isDisposed = false;
  List<_RelationEntry> _entries = const [];
  Set<String> _viewerFollowing = const {};

  Stream<List<ProfileFollowSnapshot>> get stream => _controller.stream;

  void _handleListen() {
    _listenerCount++;
    if (_listenerCount == 1) {
      _subscribe();
    }
    if (_entries.isNotEmpty && !_controller.isClosed) {
      scheduleMicrotask(_emitLatest);
    }
  }

  void _handleCancel() {
    _listenerCount = max(0, _listenerCount - 1);
    if (_listenerCount == 0) {
      _unsubscribe();
      _onEmpty();
    }
  }

  void _subscribe() {
    final profiles = _firestore
        .collection(FirestoreProfileInteractionService._profilesCollection);
    final docRef = profiles.doc(targetId);
    final collectionName =
        type == _RelationType.followers ? 'followers' : 'following';
    _relationSub =
        docRef.collection(collectionName).snapshots().listen(
      (snapshot) {
        unawaited(_rebuild(snapshot.docs));
      },
      onError: (error, stackTrace) {
        if (!_controller.isClosed) {
          _controller.addError(error, stackTrace);
        }
      },
    );

    _followingCache = getFollowingCache(viewerId);
    _viewerFollowing = _followingCache?.current ?? const {};
    _followingSub = _followingCache?.stream.listen(
      (ids) {
        _viewerFollowing = ids;
        _emitLatest();
      },
      onError: (error, stackTrace) {
        if (!_controller.isClosed) {
          _controller.addError(error, stackTrace);
        }
      },
    );
  }

  Future<void> _rebuild(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final results = <_RelationEntry>[];
    for (final doc in docs) {
      final entry = await _buildEntry(doc);
      if (entry != null) {
        results.add(entry);
      }
    }
    results.sort((a, b) {
      final left = a.followedAt?.millisecondsSinceEpoch ?? 0;
      final right = b.followedAt?.millisecondsSinceEpoch ?? 0;
      return right.compareTo(left);
    });
    _entries = results;
    _emitLatest();
  }

  Future<_RelationEntry?> _buildEntry(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return _buildRelationEntry(_firestore, doc);
  }

  void _emitLatest() {
    if (_controller.isClosed || !_controller.hasListener) {
      return;
    }
    final snapshots = _entries
        .map(
          (entry) => ProfileFollowSnapshot(
            profile: entry.profile,
            isFollowedByViewer: _viewerFollowing.contains(entry.profile.id),
            followedAt: entry.followedAt,
          ),
        )
        .toList(growable: false);
    if (!_controller.isClosed) {
      _controller.add(snapshots);
    }
  }

  void _unsubscribe() {
    unawaited(_relationSub?.cancel());
    unawaited(_followingSub?.cancel());
    _relationSub = null;
    _followingSub = null;
    _followingCache = null;
    _entries = const [];
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _unsubscribe();
    unawaited(_controller.close());
  }
}

class _RelationEntry {
  _RelationEntry({required this.profile, this.followedAt});

  final Profile profile;
  final DateTime? followedAt;
}

Future<_RelationEntry?> _buildRelationEntry(
  FirebaseFirestore firestore,
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
) async {
  final data = doc.data();
  Profile? profile;
  final profileData = data['profile'];
  if (profileData is Map<String, dynamic>) {
    profile = Profile.fromMap(Map<String, dynamic>.from(profileData));
  }
  profile ??= await _loadProfile(firestore, doc.id);
  if (profile == null) {
    return null;
  }
  final createdAt = data['createdAt'];
  DateTime? followedAt;
  if (createdAt is Timestamp) {
    followedAt = createdAt.toDate();
  }
  return _RelationEntry(profile: profile, followedAt: followedAt);
}

class _LikeEntry {
  _LikeEntry({required this.profile, this.likedAt});

  final Profile profile;
  final DateTime? likedAt;
}

class _LikesWatcher {
  _LikesWatcher({
    required FirebaseFirestore firestore,
    required this.targetId,
    required this.viewerId,
    required this.getFollowingCache,
    required VoidCallback onEmpty,
  })  : _firestore = firestore,
        _onEmpty = onEmpty {
    _controller = StreamController<List<ProfileLikeSnapshot>>.broadcast(
      onListen: _handleListen,
      onCancel: _handleCancel,
    );
  }

  final FirebaseFirestore _firestore;
  final String targetId;
  final String viewerId;
  final _FollowingCache Function(String viewerId) getFollowingCache;
  final VoidCallback _onEmpty;

  late final StreamController<List<ProfileLikeSnapshot>> _controller;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _likesSub;
  StreamSubscription<Set<String>>? _followingSub;
  _FollowingCache? _followingCache;
  int _listenerCount = 0;
  bool _isDisposed = false;
  List<_LikeEntry> _entries = const [];
  Set<String> _viewerFollowing = const {};

  Stream<List<ProfileLikeSnapshot>> get stream => _controller.stream;

  void _handleListen() {
    _listenerCount++;
    if (_listenerCount == 1) {
      _subscribe();
    }
    if (_entries.isNotEmpty && !_controller.isClosed) {
      scheduleMicrotask(_emitLatest);
    }
  }

  void _handleCancel() {
    _listenerCount = max(0, _listenerCount - 1);
    if (_listenerCount == 0) {
      _unsubscribe();
      _onEmpty();
    }
  }

  void _subscribe() {
    final profiles = _firestore
        .collection(FirestoreProfileInteractionService._profilesCollection);
    final docRef = profiles.doc(targetId);
    _likesSub = docRef
        .collection('likes')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
      (snapshot) {
        unawaited(_rebuild(snapshot.docs));
      },
      onError: (error, stackTrace) {
        if (!_controller.isClosed) {
          _controller.addError(error, stackTrace);
        }
      },
    );

    _followingCache = getFollowingCache(viewerId);
    _viewerFollowing = _followingCache?.current ?? const {};
    _followingSub = _followingCache?.stream.listen(
      (ids) {
        _viewerFollowing = ids;
        _emitLatest();
      },
      onError: (error, stackTrace) {
        if (!_controller.isClosed) {
          _controller.addError(error, stackTrace);
        }
      },
    );
  }

  Future<void> _rebuild(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final results = <_LikeEntry>[];
    for (final doc in docs) {
      final entry = await _buildEntry(doc);
      if (entry != null) {
        results.add(entry);
      }
    }
    _entries = results;
    _emitLatest();
  }

  Future<_LikeEntry?> _buildEntry(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    Profile? profile;
    final profileData = data['profile'];
    if (profileData is Map<String, dynamic>) {
      profile = Profile.fromMap(Map<String, dynamic>.from(profileData));
    }
    profile ??= await _loadProfile(_firestore, doc.id);
    if (profile == null) {
      return null;
    }
    final createdAt = data['createdAt'];
    DateTime? likedAt;
    if (createdAt is Timestamp) {
      likedAt = createdAt.toDate();
    }
    return _LikeEntry(profile: profile, likedAt: likedAt);
  }

  void _emitLatest() {
    if (_controller.isClosed || !_controller.hasListener) {
      return;
    }
    final snapshots = _entries
        .map(
          (entry) => ProfileLikeSnapshot(
            profile: entry.profile,
            isFollowedByViewer: _viewerFollowing.contains(entry.profile.id),
            likedAt: entry.likedAt,
          ),
        )
        .toList(growable: false);
    if (!_controller.isClosed) {
      _controller.add(snapshots);
    }
  }

  void _unsubscribe() {
    unawaited(_likesSub?.cancel());
    unawaited(_followingSub?.cancel());
    _likesSub = null;
    _followingSub = null;
    _followingCache = null;
    _entries = const [];
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _unsubscribe();
    unawaited(_controller.close());
  }
}

class _FollowingCache {
  _FollowingCache({
    required FirebaseFirestore firestore,
    required this.viewerId,
    required VoidCallback onEmpty,
  })  : _firestore = firestore,
        _onEmpty = onEmpty {
    _controller = StreamController<Set<String>>.broadcast(
      onListen: _handleListen,
      onCancel: _handleCancel,
    );
  }

  final FirebaseFirestore _firestore;
  final String viewerId;
  final VoidCallback _onEmpty;

  late final StreamController<Set<String>> _controller;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  int _listenerCount = 0;
  bool _isDisposed = false;
  Set<String> _current = const {};

  Stream<Set<String>> get stream => _controller.stream;
  Set<String> get current => _current;

  void _handleListen() {
    _listenerCount++;
    if (_listenerCount == 1) {
      _subscribe();
    }
    if (!_controller.isClosed && _controller.hasListener) {
      _controller.add(_current);
    }
  }

  void _handleCancel() {
    _listenerCount = max(0, _listenerCount - 1);
    if (_listenerCount == 0) {
      _unsubscribe();
      _onEmpty();
    }
  }

  void _subscribe() {
    final collection = _firestore
        .collection(FirestoreProfileInteractionService._profilesCollection)
        .doc(viewerId)
        .collection('following');
    _subscription = collection.snapshots().listen(
      (snapshot) {
        final ids = <String>{};
        for (final doc in snapshot.docs) {
          ids.add(doc.id);
        }
        _current = ids;
        if (!_controller.isClosed && _controller.hasListener) {
          _controller.add(_current);
        }
      },
      onError: (error, stackTrace) {
        if (!_controller.isClosed) {
          _controller.addError(error, stackTrace);
        }
      },
    );
  }

  void _unsubscribe() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _unsubscribe();
    unawaited(_controller.close());
  }
}

Profile _profileFromDocument(
  DocumentSnapshot<Map<String, dynamic>> snapshot, {
  required String fallbackId,
}) {
  final data = snapshot.data() ?? const <String, dynamic>{};
  final favoriteGamesRaw = data['favoriteGames'];
  final favoriteGames = favoriteGamesRaw is Iterable
      ? favoriteGamesRaw.map((e) => e.toString()).toList()
      : const <String>[];
  final map = <String, dynamic>{
    'id': snapshot.id.isNotEmpty ? snapshot.id : fallbackId,
    'displayName': data['displayName'] ?? 'Unknown',
    'beaconId': data['beaconId'] ?? snapshot.id,
    'bio': data['bio'] ?? '',
    'homeTown': data['homeTown'] ?? '',
    'favoriteGames': favoriteGames,
    'avatarColor': (data['avatarColor'] as num?)?.toInt(),
    'avatarImageBase64': data['avatarImageBase64'],
    'receivedLikes': (data['receivedLikes'] as num?)?.toInt() ?? 0,
    'followersCount': (data['followersCount'] as num?)?.toInt() ?? 0,
    'followingCount': (data['followingCount'] as num?)?.toInt() ?? 0,
  };

  return Profile.fromMap(map) ??
      Profile(
        id: fallbackId,
        beaconId: (data['beaconId'] as String?) ?? fallbackId,
        displayName: data['displayName']?.toString() ?? 'Unknown',
        bio: data['bio']?.toString() ?? '',
        homeTown: data['homeTown']?.toString() ?? '',
        favoriteGames: favoriteGames,
        avatarColor: Color(
            (data['avatarColor'] as num?)?.toInt() ?? Colors.blueAccent.value),
        avatarImageBase64: data['avatarImageBase64'] as String?,
        receivedLikes: (data['receivedLikes'] as num?)?.toInt() ?? 0,
        followersCount: (data['followersCount'] as num?)?.toInt() ?? 0,
        followingCount: (data['followingCount'] as num?)?.toInt() ?? 0,
      );
}

Map<String, dynamic> _profileSummary(Profile profile) {
  return {
    'id': profile.id,
    'displayName': profile.displayName,
    'beaconId': profile.beaconId,
    'bio': profile.bio,
    'homeTown': profile.homeTown,
    'favoriteGames': profile.favoriteGames,
    'avatarColor': profile.avatarColor.value,
    'avatarImageBase64': profile.avatarImageBase64,
    'receivedLikes': profile.receivedLikes,
    'followersCount': profile.followersCount,
    'followingCount': profile.followingCount,
  };
}

Future<Profile?> _loadProfile(
  FirebaseFirestore firestore,
  String id,
) async {
  try {
    final snapshot = await firestore
        .collection(FirestoreProfileInteractionService._profilesCollection)
        .doc(id)
        .get();
    if (!snapshot.exists) {
      return null;
    }
    return _profileFromDocument(snapshot, fallbackId: id);
  } catch (_) {
    return null;
  }
}
