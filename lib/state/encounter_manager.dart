import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

import '../models/encounter.dart';
import '../models/profile.dart';
import '../services/ble_proximity_scanner.dart';
import '../services/profile_interaction_service.dart';
import '../services/streetpass_service.dart';
import 'profile_controller.dart';
import 'notification_manager.dart';

class EncounterManager extends ChangeNotifier {
  EncounterManager({
    required StreetPassService streetPassService,
    required Profile localProfile,
    BleProximityScanner? bleScanner,
    bool usesMockBackend = false,
    ProfileController? profileController,
    ProfileInteractionService? interactionService,
    NotificationManager? notificationManager,
  })  : _streetPassService = streetPassService,
        _localProfile = localProfile,
        _bleScanner = bleScanner,
        usesMockService = usesMockBackend,
        _profileController = profileController,
        _interactionService = interactionService,
        _notificationManager = notificationManager {
    _subscribeToLocalProfile();
  }

  final StreetPassService _streetPassService;
  Profile _localProfile;
  final BleProximityScanner? _bleScanner;
  final bool usesMockService;
  final ProfileController? _profileController;
  final ProfileInteractionService? _interactionService;
  final NotificationManager? _notificationManager;

  final Map<String, Encounter> _encountersByRemoteId = {};
  final Map<String, _BeaconPresence> _presenceByBeaconId = {};
  final Map<String, DateTime> _lastNotificationAt = {};
  final Map<String, DateTime> _lastVibrationAt = {};
  final Map<String, DateTime> _lastHashtagMatchAt = {};
  final Map<String, Set<String>> _remoteHashtagCache = {};
  final Map<String, _BleDistanceWindow> _bleDistanceWindows = {};

  static const Duration _presenceTimeout = Duration(seconds: 45);
  static const Duration _reencounterCooldown = Duration(minutes: 15);
  static const double _closeProximityRadiusMeters = 3;
  static const double _farProximityRadiusMeters = 10;
  static const double _bleVibrationBufferMeters = 1.5;
  static const Duration _minProximityCooldown = Duration(seconds: 5);
  static const Duration _maxProximityCooldown = Duration(seconds: 30);
  static const Duration _hashtagMatchCooldown = Duration(minutes: 1);
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
    debugPrint('[VIBE] encounter tags=${data.profile.favoriteGames}');
    final now = DateTime.now();
    final presence = _presenceByBeaconId.putIfAbsent(
      data.beaconId,
      () => _BeaconPresence(),
    );

    final existing = _encountersByRemoteId[data.remoteId];
    final isRepeatCandidate = existing != null;
    if (existing != null) {
      existing.encounteredAt = data.encounteredAt;
      existing.gpsDistanceMeters = data.gpsDistanceMeters;
      existing.message = data.message ?? existing.message;
      existing.unread = true;
      final previousProfile = existing.profile;
      existing.profile = data.profile.copyWith(
        following: previousProfile.following,
        receivedLikes: data.profile.receivedLikes,
        followersCount: data.profile.followersCount,
        followingCount: data.profile.followingCount,
      );
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
    _hydrateRemoteHashtags(data.remoteId, data.profile);

    final encounter = _encountersByRemoteId[data.remoteId];
    if (encounter != null) {
      final shouldNotify = !isRepeatCandidate ||
          _shouldNotifyRepeat(
            remoteId: data.remoteId,
            presence: presence,
            encounteredAt: encounter.encounteredAt,
            fallbackNow: now,
          );
      if (shouldNotify) {
        _notificationManager?.registerEncounter(
          profile: encounter.profile,
          encounteredAt: encounter.encounteredAt,
          encounterId: encounter.id,
          message: data.message,
          isRepeat: isRepeatCandidate,
        );
        _lastNotificationAt[data.remoteId] = now;
      }
    }
    final hasSharedHashtag = _hasSharedHashtag(data.remoteId, data.profile);
    final triggeredProximityVibration = _maybeTriggerProximityVibration(
      beaconId: data.beaconId,
      remoteId: data.remoteId,
      remoteProfile: data.profile,
      gpsDistanceMeters: data.gpsDistanceMeters,
      hasSharedHashtag: hasSharedHashtag,
    );
    if (!triggeredProximityVibration) {
      _maybeTriggerHashtagMatchFeedback(
        remoteId: data.remoteId,
        hasSharedHashtag: hasSharedHashtag,
      );
    }
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

  void _hydrateRemoteHashtags(String remoteId, Profile profile) {
    final tags = _normalizedHashtagSet(profile.favoriteGames);
    final alreadyCached = _remoteHashtagCache.containsKey(remoteId);
    _remoteHashtagCache[remoteId] = tags;
    if (tags.isEmpty && !alreadyCached) {
      unawaited(_prefetchRemoteHashtags(remoteId));
    }
  }

  Future<void> _prefetchRemoteHashtags(String remoteId) async {
    final service = _interactionService;
    if (service == null) {
      return;
    }
    try {
      final profile = await service.loadProfile(remoteId);
      if (profile == null) {
        return;
      }
      final tags = _normalizedHashtagSet(profile.favoriteGames);
      _remoteHashtagCache[remoteId] = tags;
    } catch (error) {
      debugPrint('Failed to prefetch hashtags for $remoteId: $error');
    }
  }

  void _handleBleEncounter(BleProximityHit hit) {
    _markBeaconSeen(hit.beaconId);
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
    final smoothedDistance = _recordBleDistance(hit.beaconId, hit.distanceMeters);
    matched.bleDistanceMeters = smoothedDistance;
    matched.encounteredAt = DateTime.now();
    matched.unread = true;
    debugPrint('[VIBE] ble tags=${matched.profile.favoriteGames}');
    final hasSharedHashtag = _hasSharedHashtag(matched.profile.id, matched.profile);
    final triggeredProximityVibration = _maybeTriggerProximityVibration(
      beaconId: hit.beaconId,
      remoteId: matched.profile.id,
      remoteProfile: matched.profile,
      bleDistanceMeters: smoothedDistance,
      isBleHit: true,
      hasSharedHashtag: hasSharedHashtag,
    );
    if (!triggeredProximityVibration) {
      _maybeTriggerHashtagMatchFeedback(
        remoteId: matched.profile.id,
        hasSharedHashtag: hasSharedHashtag,
      );
    }
    notifyListeners();
  }

  void _markBeaconSeen(String beaconId) {
    final presence = _presenceByBeaconId.putIfAbsent(
      beaconId,
      () => _BeaconPresence(),
    );
    presence.markSeen(_presenceTimeout);
  }

  double _recordBleDistance(String beaconId, double distance) {
    final window = _bleDistanceWindows.putIfAbsent(
      beaconId,
      () => _BleDistanceWindow(),
    );
    return window.record(distance);
  }

  bool _maybeTriggerProximityVibration({
    required String beaconId,
    required String remoteId,
    required Profile remoteProfile,
    double? gpsDistanceMeters,
    double? bleDistanceMeters,
    bool isBleHit = false,
    bool? hasSharedHashtag,
  }) {
    if (kIsWeb) {
      return false;
    }
    final sharedHashtag =
        hasSharedHashtag ?? _hasSharedHashtag(remoteId, remoteProfile);
    if (!sharedHashtag) {
      debugPrint('[VIBE] skip (no shared hashtag) remote=$remoteId');
      return false;
    }
    final distance = _resolveProximityDistance(
      gpsDistanceMeters: gpsDistanceMeters,
      bleDistanceMeters: bleDistanceMeters,
    );
    debugPrint(
        '[VIBE] shared=$sharedHashtag distance=$distance gps=$gpsDistanceMeters ble=$bleDistanceMeters isBle=$isBleHit');
    final maxDistance = isBleHit
        ? _closeProximityRadiusMeters + _bleVibrationBufferMeters
        : _farProximityRadiusMeters;
    if (distance == null || distance <= 0 || distance > maxDistance) {
      debugPrint('[VIBE] skip (distance) distance=$distance max=$maxDistance');
      return false;
    }
    final now = DateTime.now();
    final last = _lastVibrationAt[beaconId];
    final cooldown = _cooldownForDistance(distance);
    if (last != null &&
        now.difference(last) < cooldown) {
      debugPrint(
          '[VIBE] skip (cooldown) last=${now.difference(last).inSeconds}s threshold=${cooldown.inSeconds}s');
      return false;
    }
    _lastVibrationAt[beaconId] = now;
    debugPrint('[VIBE] trigger vibration');
    unawaited(_triggerProximityHaptics());
    unawaited(SystemSound.play(SystemSoundType.click));
    return true;
  }

  void _maybeTriggerHashtagMatchFeedback({
    required String remoteId,
    required bool hasSharedHashtag,
  }) {
    if (kIsWeb || !hasSharedHashtag) {
      return;
    }
    final now = DateTime.now();
    final lastTriggered = _lastHashtagMatchAt[remoteId];
    if (lastTriggered != null &&
        now.difference(lastTriggered) < _hashtagMatchCooldown) {
      debugPrint(
          '[VIBE] skip hashtag vibration (cooldown) remote=$remoteId elapsed=${now.difference(lastTriggered).inSeconds}s');
      return;
    }
    _lastHashtagMatchAt[remoteId] = now;
    debugPrint('[VIBE] trigger hashtag vibration remote=$remoteId');
    unawaited(HapticFeedback.selectionClick());
  }

  double? _resolveProximityDistance({
    double? gpsDistanceMeters,
    double? bleDistanceMeters,
  }) {
    if (bleDistanceMeters != null && bleDistanceMeters.isFinite) {
      return bleDistanceMeters;
    }
    if (gpsDistanceMeters != null && gpsDistanceMeters.isFinite) {
      return gpsDistanceMeters;
    }
    return null;
  }

  Duration _cooldownForDistance(double distance) {
    if (distance <= _closeProximityRadiusMeters) {
      return _minProximityCooldown;
    }
    if (distance >= _farProximityRadiusMeters) {
      return _maxProximityCooldown;
    }
    final ratio = (distance - _closeProximityRadiusMeters) /
        (_farProximityRadiusMeters - _closeProximityRadiusMeters);
    final minMs = _minProximityCooldown.inMilliseconds;
    final maxMs = _maxProximityCooldown.inMilliseconds;
    final interpolated = minMs + ((maxMs - minMs) * ratio);
    return Duration(milliseconds: interpolated.round());
  }

  bool _hasSharedHashtag(String remoteId, Profile remoteProfile) {
    final localTags = _normalizedHashtagSet(_localProfile.favoriteGames);
    if (localTags.isEmpty) {
      return false;
    }
    var remoteTags = _remoteHashtagCache[remoteId];
    if (remoteTags == null) {
      remoteTags = _normalizedHashtagSet(remoteProfile.favoriteGames);
      _remoteHashtagCache[remoteId] = remoteTags;
      if (remoteTags.isEmpty) {
        unawaited(_prefetchRemoteHashtags(remoteId));
      }
    }
    if (remoteTags.isEmpty) {
      return false;
    }
    for (final tag in localTags) {
      if (remoteTags.contains(tag)) {
        return true;
      }
    }
    return false;
  }

  Set<String> _normalizedHashtagSet(List<String> tags) {
    final normalized = <String>{};
    for (final tag in tags) {
      final trimmed = tag.trim();
      if (trimmed.isEmpty) continue;
      final canonical =
          trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
      if (canonical.isEmpty) continue;
      normalized.add(canonical.toLowerCase());
    }
    return normalized;
  }

  bool _shouldNotifyRepeat({
    required String remoteId,
    required _BeaconPresence presence,
    required DateTime encounteredAt,
    required DateTime fallbackNow,
  }) {
    final lastNotified = _lastNotificationAt[remoteId];
    if (!presence.hasBleContext) {
      if (lastNotified == null) {
        return true;
      }
      return fallbackNow.difference(lastNotified) >= _reencounterCooldown;
    }

    if (presence.hasExitedSince(lastNotified)) {
      return true;
    }

    if (lastNotified == null) {
      return true;
    }

    return encounteredAt.difference(lastNotified) >= _reencounterCooldown;
  }

  void _clearPresenceTracking() {
    for (final presence in _presenceByBeaconId.values) {
      presence.dispose();
    }
    _presenceByBeaconId.clear();
    _lastNotificationAt.clear();
    _lastVibrationAt.clear();
    _lastHashtagMatchAt.clear();
    _remoteHashtagCache.clear();
    for (final window in _bleDistanceWindows.values) {
      window.clear();
    }
    _bleDistanceWindows.clear();
  }

  Future<void> _triggerProximityHaptics() async {
    try {
      final supportsCustom =
          (await Vibration.hasCustomVibrationsSupport()) ?? false;
      if (supportsCustom) {
        await Vibration.vibrate(duration: 400, amplitude: 255);
        return;
      }
      final hasVibrator = (await Vibration.hasVibrator()) ?? false;
      if (hasVibrator) {
        await Vibration.vibrate(duration: 350);
        return;
      }
    } catch (error) {
      debugPrint('Vibration plugin failed: $error');
    }
    unawaited(HapticFeedback.heavyImpact());
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
    _notificationManager?.markEncounterNotificationsRead(encounterId);
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
      viewerProfile: _localProfile,
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
    _clearPresenceTracking();
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
      _clearPresenceTracking();
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

  Future<void> switchLocalProfile(Profile profile,
      {bool skipSync = false}) async {
    debugPrint(
        'EncounterManager.switchLocalProfile: switching to profile.id=${profile.id} beaconId=${profile.beaconId} skipSync=$skipSync');
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
      debugPrint(
          'EncounterManager.switchLocalProfile: local profile set to ${_localProfile.id}');
      if (!skipSync) {
        _subscribeToLocalProfile();
      }
      if (_encountersByRemoteId.isNotEmpty) {
        await _cancelInteractionSubscriptions();
        for (final remoteId in _encountersByRemoteId.keys) {
          _ensureInteractionSubscription(remoteId);
        }
      }
    }
  }
}

class _BeaconPresence {
  bool inRange = false;
  bool hasBleContext = false;
  DateTime? lastSeenAt;
  DateTime? lastExitAt;
  Timer? _exitTimer;

  void markSeen(Duration timeout) {
    hasBleContext = true;
    inRange = true;
    lastSeenAt = DateTime.now();
    _exitTimer?.cancel();
    _exitTimer = Timer(timeout, () {
      inRange = false;
      lastExitAt = DateTime.now();
    });
  }

  bool hasExitedSince(DateTime? timestamp) {
    if (lastExitAt == null) {
      return false;
    }
    if (timestamp == null) {
      return true;
    }
    return lastExitAt!.isAfter(timestamp);
  }

  void dispose() {
    _exitTimer?.cancel();
    _exitTimer = null;
  }
}

class _BleDistanceWindow {
  static const Duration _window = Duration(seconds: 6);
  final List<_BleDistanceSample> _samples = [];

  double record(double distance) {
    final now = DateTime.now();
    _samples.add(_BleDistanceSample(distance: distance, recordedAt: now));
    _samples.removeWhere(
      (sample) => now.difference(sample.recordedAt) > _window,
    );
    var minDistance = distance;
    for (final sample in _samples) {
      if (sample.distance < minDistance) {
        minDistance = sample.distance;
      }
    }
    return minDistance;
  }

  void clear() => _samples.clear();
}

class _BleDistanceSample {
  _BleDistanceSample({
    required this.distance,
    required this.recordedAt,
  });

  final double distance;
  final DateTime recordedAt;
}
