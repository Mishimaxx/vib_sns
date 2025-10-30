import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/encounter.dart';
import '../models/profile.dart';
import '../services/ble_proximity_scanner.dart';
import '../services/profile_interaction_service.dart';
import '../services/streetpass_service.dart';
import 'profile_controller.dart';

class EncounterManager extends ChangeNotifier {
  EncounterManager({
    required StreetPassService streetPassService,
    required Profile localProfile,
    BleProximityScanner? bleScanner,
    bool usesMockBackend = false,
    ProfileController? profileController,
    ProfileInteractionService? interactionService,
  })  : _streetPassService = streetPassService,
        _localProfile = localProfile,
        _bleScanner = bleScanner,
        usesMockService = usesMockBackend,
        _profileController = profileController,
        _interactionService = interactionService {
    _subscribeToLocalProfile();
  }

  final StreetPassService _streetPassService;
  Profile _localProfile;
  final BleProximityScanner? _bleScanner;
  final bool usesMockService;
  final ProfileController? _profileController;
  final ProfileInteractionService? _interactionService;

  final Map<String, Encounter> _encountersByRemoteId = {};
  final Set<String> _targetBeaconIds = {};
  final Map<String, StreamSubscription<ProfileInteractionSnapshot>>
      _interactionSubscriptions = {};
  StreamSubscription<ProfileInteractionSnapshot>? _localStatsSubscription;
  StreamSubscription<StreetPassEncounterData>? _subscription;
  StreamSubscription<BleProximityHit>? _bleSubscription;
  bool _isRunning = false;
  String? _errorMessage;
  Future<void>? _resetFuture;

  bool get isRunning => _isRunning;
  String? get errorMessage => _errorMessage;

  List<Encounter> get encounters {
    final list = _encountersByRemoteId.values.toList()
      ..sort((a, b) => b.encounteredAt.compareTo(a.encounteredAt));
    return List.unmodifiable(list);
  }

  void _subscribeToLocalProfile() {
    final service = _interactionService;
    if (service == null) {
      return;
    }
    _localStatsSubscription?.cancel();
    _localStatsSubscription = service
        .watchProfile(targetId: _localProfile.id, viewerId: _localProfile.id)
        .listen(
      (snapshot) {
        final updatedProfile = _localProfile.copyWith(
          followersCount: snapshot.followersCount,
          followingCount: snapshot.followingCount,
          receivedLikes: snapshot.receivedLikes,
        );
        _localProfile = updatedProfile;
        _profileController?.updateStats(
          followersCount: snapshot.followersCount,
          followingCount: snapshot.followingCount,
          receivedLikes: snapshot.receivedLikes,
        );
      },
      onError: (error, stackTrace) {
        debugPrint('Failed to sync local profile stats: $error');
      },
    );
  }

  Future<void> start() async {
    if (_isRunning) return;
    _errorMessage = null;
    try {
      await _streetPassService.start(_localProfile);
      _subscription = _streetPassService.encounterStream.listen(
        _handleEncounter,
        onError: (error, stackTrace) {
          _errorMessage =
              error is StreetPassException ? error.message : error.toString();
          notifyListeners();
        },
      );
      _isRunning = true;
      final bleScanner = _bleScanner;
      if (bleScanner != null) {
        await bleScanner.start(
          localBeaconId: _localProfile.beaconId,
          targetBeaconIds: _targetBeaconIds,
        );
        _bleSubscription = bleScanner.hits.listen(
          _handleBleEncounter,
          onError: (error, stackTrace) {
            _errorMessage = error.toString();
            notifyListeners();
          },
        );
      }
    } catch (error) {
      _errorMessage =
          error is StreetPassException ? error.message : error.toString();
      notifyListeners();
      rethrow;
    }
  }

  void _handleEncounter(StreetPassEncounterData data) {
    final existing = _encountersByRemoteId[data.remoteId];
    if (existing != null) {
      existing.encounteredAt = data.encounteredAt;
      existing.gpsDistanceMeters = data.gpsDistanceMeters;
      existing.message = data.message ?? existing.message;
      existing.unread = true;
      existing.profile.receivedLikes = data.profile.receivedLikes;
      existing.profile.followersCount = data.profile.followersCount;
      existing.profile.followingCount = data.profile.followingCount;
      if (data.latitude != null) {
        existing.latitude = data.latitude;
      }
      if (data.longitude != null) {
        existing.longitude = data.longitude;
      }
    } else {
      _encountersByRemoteId[data.remoteId] = Encounter(
        id: 'encounter_${data.remoteId}',
        profile: data.profile,
        encounteredAt: data.encounteredAt,
        beaconId: data.beaconId,
        message: data.message,
        gpsDistanceMeters: data.gpsDistanceMeters,
        latitude: data.latitude,
        longitude: data.longitude,
      );
    }
    if (_targetBeaconIds.add(data.beaconId)) {
      _bleScanner?.updateTargetBeacons(_targetBeaconIds);
    }
    _ensureInteractionSubscription(data.remoteId);
    notifyListeners();
  }

  void _ensureInteractionSubscription(String remoteId) {
    final service = _interactionService;
    if (service == null || remoteId == _localProfile.id) {
      return;
    }
    if (_interactionSubscriptions.containsKey(remoteId)) {
      return;
    }
    final subscription = service
        .watchProfile(targetId: remoteId, viewerId: _localProfile.id)
        .listen(
      (snapshot) {
        final encounter = _encountersByRemoteId[remoteId];
        if (encounter == null) {
          return;
        }
        var updated = false;
        final profile = encounter.profile;
        if (profile.receivedLikes != snapshot.receivedLikes) {
          profile.receivedLikes = snapshot.receivedLikes;
          updated = true;
        }
        if (profile.followersCount != snapshot.followersCount) {
          profile.followersCount = snapshot.followersCount;
          updated = true;
        }
        if (profile.followingCount != snapshot.followingCount) {
          profile.followingCount = snapshot.followingCount;
          updated = true;
        }
        if (profile.following != snapshot.isFollowedByViewer) {
          profile.following = snapshot.isFollowedByViewer;
          updated = true;
        }
        if (encounter.liked != snapshot.isLikedByViewer) {
          encounter.liked = snapshot.isLikedByViewer;
          updated = true;
        }
        if (updated) {
          notifyListeners();
        }
      },
      onError: (error, stackTrace) {
        debugPrint('Failed to watch profile $remoteId: $error');
      },
    );
    _interactionSubscriptions[remoteId] = subscription;
  }

  void _handleBleEncounter(BleProximityHit hit) {
    Encounter? matched;
    for (final encounter in _encountersByRemoteId.values) {
      if (encounter.beaconId == hit.beaconId) {
        matched = encounter;
        break;
      }
    }
    if (matched == null) {
      return;
    }
    matched.bleDistanceMeters = hit.distanceMeters;
    matched.encounteredAt = DateTime.now();
    matched.unread = true;
    notifyListeners();
  }

  Future<void> _cancelInteractionSubscriptions() async {
    if (_interactionSubscriptions.isEmpty) {
      return;
    }
    final futures = _interactionSubscriptions.values
        .map((subscription) => subscription.cancel())
        .toList(growable: false);
    _interactionSubscriptions.clear();
    await Future.wait(futures, eagerError: false);
  }

  Encounter? findById(String id) {
    for (final encounter in _encountersByRemoteId.values) {
      if (encounter.id == id) {
        return encounter;
      }
    }
    return null;
  }

  void markSeen(String encounterId) {
    final encounter = findById(encounterId);
    if (encounter == null) return;
    if (encounter.unread) {
      encounter.markRead();
      notifyListeners();
    }
  }

  void toggleLike(String encounterId) {
    final encounter = findById(encounterId);
    if (encounter == null) return;
    final service = _interactionService;
    if (service == null) {
      encounter.toggleLiked();
      if (encounter.liked) {
        encounter.profile.like();
      } else {
        encounter.profile.receivedLikes =
            (encounter.profile.receivedLikes - 1).clamp(0, 999);
      }
      notifyListeners();
      return;
    }

    final wasLiked = encounter.liked;
    final nextLiked = !wasLiked;
    final previousCount = encounter.profile.receivedLikes;
    final adjusted = (previousCount + (nextLiked ? 1 : -1)).clamp(0, 999999);

    encounter.liked = nextLiked;
    encounter.profile.receivedLikes = adjusted;
    notifyListeners();

    unawaited(service
        .setLike(
      targetId: encounter.profile.id,
      viewerId: _localProfile.id,
      like: nextLiked,
    )
        .catchError((error, stackTrace) {
      debugPrint('Failed to update like: $error');
      encounter.liked = wasLiked;
      encounter.profile.receivedLikes = previousCount;
      notifyListeners();
    }));
  }

  void toggleFollow(String encounterId) {
    final encounter = findById(encounterId);
    if (encounter == null) return;
    final service = _interactionService;
    if (service == null) {
      encounter.profile.toggleFollow();
      final delta = encounter.profile.following ? 1 : -1;
      encounter.profile.followersCount =
          (encounter.profile.followersCount + delta).clamp(0, 999999);
      final updatedFollowing =
          (_localProfile.followingCount + delta).clamp(0, 999999);
      _localProfile = _localProfile.copyWith(followingCount: updatedFollowing);
      _profileController?.updateStats(followingCount: updatedFollowing);
      notifyListeners();
      return;
    }

    final wasFollowing = encounter.profile.following;
    final nextFollowing = !wasFollowing;
    final previousRemoteFollowers = encounter.profile.followersCount;
    final previousLocalFollowing = _localProfile.followingCount;

    encounter.profile.following = nextFollowing;
    encounter.profile.followersCount =
        (previousRemoteFollowers + (nextFollowing ? 1 : -1)).clamp(0, 999999);

    final updatedFollowing =
        (previousLocalFollowing + (nextFollowing ? 1 : -1)).clamp(0, 999999);
    _localProfile = _localProfile.copyWith(followingCount: updatedFollowing);
    _profileController?.updateStats(followingCount: updatedFollowing);
    notifyListeners();

    unawaited(service
        .setFollow(
      targetId: encounter.profile.id,
      viewerId: _localProfile.id,
      follow: nextFollowing,
    )
        .catchError((error, stackTrace) {
      debugPrint('Failed to update follow: $error');
      encounter.profile.following = wasFollowing;
      encounter.profile.followersCount = previousRemoteFollowers;
      _localProfile =
          _localProfile.copyWith(followingCount: previousLocalFollowing);
      _profileController?.updateStats(followingCount: previousLocalFollowing);
      notifyListeners();
    }));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _bleSubscription?.cancel();
    for (final subscription in _interactionSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    _interactionSubscriptions.clear();
    final localStatsSub = _localStatsSubscription;
    _localStatsSubscription = null;
    if (localStatsSub != null) {
      unawaited(localStatsSub.cancel());
    }
    unawaited(_bleScanner?.stop());
    unawaited(_bleScanner?.dispose());
    unawaited(_streetPassService.stop());
    unawaited(_streetPassService.dispose());
    super.dispose();
  }

  Future<void> reset() {
    _resetFuture ??= _performReset();
    return _resetFuture!;
  }

  Future<void> _performReset() async {
    try {
      await _cancelInteractionSubscriptions();
      _encountersByRemoteId.clear();
      _targetBeaconIds.clear();
      await _subscription?.cancel();
      _subscription = null;
      await _bleSubscription?.cancel();
      _bleSubscription = null;
      await _bleScanner?.stop();
      await _streetPassService.stop();
      _isRunning = false;
      notifyListeners();
    } finally {
      _resetFuture = null;
    }
  }

  Future<void> switchLocalProfile(Profile profile) async {
    try {
      await reset().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      debugPrint(
          'Encounter reset timed out while switching profile; continuing.');
    } catch (error, stackTrace) {
      debugPrint(
          'Failed to reset before switching profile: $error\n$stackTrace');
    } finally {
      _localProfile = profile;
      _subscribeToLocalProfile();
      if (_encountersByRemoteId.isNotEmpty) {
        await _cancelInteractionSubscriptions();
        for (final remoteId in _encountersByRemoteId.keys) {
          _ensureInteractionSubscription(remoteId);
        }
      }
    }
  }
}
