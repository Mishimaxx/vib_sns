import 'dart:async';

class BleProximityHit {
  BleProximityHit({
    required this.beaconId,
    required this.rssi,
    required this.distanceMeters,
  });

  final String beaconId;
  final int rssi;
  final double distanceMeters;
}

abstract class BleProximityScanner {
  Stream<BleProximityHit> get hits;

  Future<void> start({
    required String localBeaconId,
    Set<String> targetBeaconIds = const {},
  });

  Future<void> updateTargetBeacons(Set<String> targetBeaconIds);

  Future<void> stop();

  Future<void> dispose();
}
