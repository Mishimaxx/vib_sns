import 'dart:async';
import 'dart:math';

import 'ble_proximity_scanner.dart';

class MockBleProximityScanner implements BleProximityScanner {
  MockBleProximityScanner({int? seed}) : _random = Random(seed);

  final Random _random;
  final StreamController<BleProximityHit> _controller = StreamController.broadcast();

  Timer? _timer;
  Set<String> _targets = {};
  bool _started = false;

  @override
  Stream<BleProximityHit> get hits => _controller.stream;

  @override
  Future<void> start({
    required String localBeaconId,
    Set<String> targetBeaconIds = const {},
  }) async {
    _targets = targetBeaconIds.toSet();
    _started = true;
    _timer ??= Timer.periodic(const Duration(seconds: 7), (_) => _emitHits());
  }

  @override
  Future<void> updateTargetBeacons(Set<String> targetBeaconIds) async {
    _targets = targetBeaconIds.toSet();
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  void _emitHits() {
    if (!_started || _targets.isEmpty) {
      return;
    }
    for (final beaconId in _targets) {
      final distance = (_random.nextDouble() * 1.5) + 0.2;
      final rssi = -35 - _random.nextInt(15);
      _controller.add(
        BleProximityHit(
          beaconId: beaconId,
          rssi: rssi,
          distanceMeters: double.parse(distance.toStringAsFixed(2)),
        ),
      );
    }
  }
}
