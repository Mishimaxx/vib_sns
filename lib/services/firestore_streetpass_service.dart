import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/profile.dart';
import 'streetpass_service.dart';

class FirestoreStreetPassService implements StreetPassService {
  FirestoreStreetPassService({
    FirebaseFirestore? firestore,
    GeolocatorPlatform? geolocator,
    SharedPreferences? sharedPreferences,
    Duration? presenceTimeout,
    double? detectionRadiusMeters,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _geolocator = geolocator ?? GeolocatorPlatform.instance,
        _sharedPreferences = sharedPreferences,
        _presenceTimeout = presenceTimeout ?? const Duration(minutes: 10),
        _detectionRadiusMeters = detectionRadiusMeters ?? 5000,
        _encounterController =
            StreamController<StreetPassEncounterData>.broadcast();

  static const prefsDeviceIdKey = 'streetpass_device_id';
  static const _presenceCollection = 'streetpass_presences';

  final FirebaseFirestore _firestore;
  final GeolocatorPlatform _geolocator;
  SharedPreferences? _sharedPreferences;
  final Duration _presenceTimeout;
  final double _detectionRadiusMeters;
  final StreamController<StreetPassEncounterData> _encounterController;

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _presenceSubscription;
  Profile? _localProfile;
  String? _deviceId;
  bool _started = false;
  Timer? _pollTimer;
  Position? _lastPosition;
  DateTime? _lastPositionUpdatedAt;

  final Map<String, DateTime> _lastEncounterByProfile = {};

  @override
  Stream<StreetPassEncounterData> get encounterStream =>
      _encounterController.stream;

  @override
  Future<void> start(Profile localProfile) async {
    if (_started) return;
    _localProfile = localProfile;
    _deviceId = await _ensureDeviceId();
    await _ensurePermission();

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_ensureRecentPosition().then((position) {
        if (position != null) {
          return _scanNearby(position);
        }
        return null;
      }));
    });
    _started = true;
    _subscribePresence();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 5,
    );
    _positionSubscription = _geolocator
        .getPositionStream(locationSettings: locationSettings)
        .listen(
      (position) async {
        try {
          await _handlePosition(position);
        } catch (error, stackTrace) {
          _encounterController.addError(error, stackTrace);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _encounterController.addError(error, stackTrace);
      },
    );

    unawaited(_publishInitialPresence().catchError((error, stackTrace) {
      _encounterController.addError(
          error, stackTrace as StackTrace? ?? StackTrace.current);
    }));
  }

  @override
  Future<void> stop() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    await _presenceSubscription?.cancel();
    _presenceSubscription = null;
    _started = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _markPresenceInactive();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _encounterController.close();
  }

  Future<void> _handlePosition(Position position) async {
    _lastPosition = position;
    _lastPositionUpdatedAt = DateTime.now();
    await _updatePresence(position);
    await _scanNearby(position);
  }

  Future<void> _updatePresence(Position position) async {
    final profile = _localProfile;
    final deviceId = _deviceId;
    if (profile == null || deviceId == null) {
      return;
    }
    final profileMap = profile.toMap()..['id'] = deviceId;
    await _firestore.collection(_presenceCollection).doc(deviceId).set(
      {
        'profile': profileMap,
        'lat': position.latitude,
        'lng': position.longitude,
        'lastUpdatedMs': DateTime.now().toUtc().millisecondsSinceEpoch,
        'active': true,
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _scanNearby(Position position) async {
    final deviceId = _deviceId;
    if (deviceId == null) return;
    final cutoffMs = DateTime.now()
        .toUtc()
        .subtract(_presenceTimeout)
        .millisecondsSinceEpoch;

    final query = await _firestore
        .collection(_presenceCollection)
        .where('lastUpdatedMs', isGreaterThan: cutoffMs)
        .get();

    _processDocuments(query.docs, position);
  }

  void _processDocuments(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Position position,
  ) {
    final deviceId = _deviceId;
    if (deviceId == null) {
      return;
    }
    for (final doc in docs) {
      if (doc.id == deviceId) {
        continue;
      }
      final data = doc.data();
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      final profileDataRaw = data['profile'];

      if (profileDataRaw is! Map<String, dynamic>) {
        continue;
      }

      final profileData = Map<String, dynamic>.from(profileDataRaw);
      profileData.putIfAbsent('id', () => doc.id);

      double distance = 0;
      if (lat != null && lng != null) {
        distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          lat,
          lng,
        );
        if (distance > _detectionRadiusMeters) {
          continue;
        }
      }

      final profile = Profile.fromMap(profileData);
      if (profile == null) continue;

      final lastTime = _lastEncounterByProfile[doc.id];
      final now = DateTime.now();
      if (lastTime != null &&
          now.difference(lastTime) < const Duration(seconds: 30)) {
        continue;
      }
      _lastEncounterByProfile[doc.id] = now;

      _encounterController.add(
        StreetPassEncounterData(
          remoteId: doc.id,
          profile: profile,
          beaconId: profile.beaconId,
          encounteredAt: now,
          gpsDistanceMeters: distance,
          message: data['message'] as String?,
          latitude: lat,
          longitude: lng,
        ),
      );
    }
  }

  void _subscribePresence() {
    _presenceSubscription?.cancel();
    _presenceSubscription =
        _firestore.collection(_presenceCollection).snapshots().listen(
      (snapshot) {
        unawaited(_ensureRecentPosition().then((position) {
          if (position == null) return;
          _processDocuments(snapshot.docs, position);
        }));
      },
      onError: (error, stackTrace) {
        _encounterController.addError(error, stackTrace);
      },
    );
  }

  Future<void> _ensurePermission() async {
    var permission = await _geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      throw StreetPassPermissionDenied(
          '\u4f4d\u7f6e\u60c5\u5831\u3078\u306e\u30a2\u30af\u30bb\u30b9\u304c\u8a31\u53ef\u3055\u308c\u3066\u3044\u307e\u305b\u3093\u3002');
    }

    final serviceEnabled = await _geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw StreetPassException(
          '\u4f4d\u7f6e\u60c5\u5831\u30b5\u30fc\u30d3\u30b9\u304c\u7121\u52b9\u3067\u3059\u3002\u30c7\u30d0\u30a4\u30b9\u306e\u8a2d\u5b9a\u3092\u78ba\u8a8d\u3057\u3066\u304f\u3060\u3055\u3044\u3002');
    }
  }

  Future<String> _ensureDeviceId() async {
    _sharedPreferences ??= await SharedPreferences.getInstance();
    final prefs = _sharedPreferences!;
    final existing = prefs.getString(prefsDeviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final newId = const Uuid().v4();
    await prefs.setString(prefsDeviceIdKey, newId);
    return newId;
  }

  Future<void> _publishInitialPresence() async {
    final position = await _ensureRecentPosition(forceRefresh: true);
    if (position == null) {
      throw StreetPassException(
        '\u4f4d\u7f6e\u60c5\u5831\u304c\u53d6\u5f97\u3067\u304d\u307e\u305b\u3093\u3067\u3057\u305f\u3002GPS\u3092\u6709\u52b9\u306b\u3057\u3066\u518d\u8d77\u52d5\u3057\u3066\u304f\u3060\u3055\u3044\u3002',
      );
    }
    await _updatePresence(position);
    await _scanNearby(position);
  }

  Future<void> _markPresenceInactive() async {
    final deviceId = _deviceId;
    if (deviceId == null) {
      return;
    }
    try {
      await _firestore.collection(_presenceCollection).doc(deviceId).delete();
    } catch (error) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Failed to remove presence: $error');
      }
    }
  }

  Future<Position?> _ensureRecentPosition({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh) {
      final last = _lastPosition;
      final updatedAt = _lastPositionUpdatedAt;
      if (last != null &&
          updatedAt != null &&
          now.difference(updatedAt) < const Duration(seconds: 10)) {
        return last;
      }
    }

    try {
      final lastKnown = await _geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        _lastPosition = lastKnown;
        _lastPositionUpdatedAt = now;
        return lastKnown;
      }
    } catch (error, stackTrace) {
      _encounterController.addError(error, stackTrace);
    }

    try {
      final current = await _geolocator.getCurrentPosition();
      _lastPosition = current;
      _lastPositionUpdatedAt = now;
      return current;
    } catch (error, stackTrace) {
      _encounterController.addError(error, stackTrace);
      return _lastPosition;
    }
  }
}
