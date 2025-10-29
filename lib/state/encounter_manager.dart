import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/encounter.dart';
import '../models/profile.dart';
import '../services/ble_proximity_scanner.dart';
import '../services/streetpass_service.dart';

class EncounterManager extends ChangeNotifier {
  EncounterManager({
    required StreetPassService streetPassService,
    required Profile localProfile,
    BleProximityScanner? bleScanner,
    bool usesMockBackend = false,
  })  : _streetPassService = streetPassService,
        _localProfile = localProfile,
        _bleScanner = bleScanner,
        usesMockService = usesMockBackend;

  final StreetPassService _streetPassService;
  Profile _localProfile;
  final BleProximityScanner? _bleScanner;
  final bool usesMockService;

  final Map<String, Encounter> _encountersByRemoteId = {};
  final Set<String> _targetBeaconIds = {};
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
    notifyListeners();
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
    encounter.toggleLiked();
    if (encounter.liked) {
      encounter.profile.like();
    } else {
      encounter.profile.receivedLikes =
          (encounter.profile.receivedLikes - 1).clamp(0, 999);
    }
    notifyListeners();
  }

  void toggleFollow(String encounterId) {
    final encounter = findById(encounterId);
    if (encounter == null) return;
    encounter.profile.toggleFollow();
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _bleSubscription?.cancel();
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
    }
  }
}
