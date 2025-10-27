import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import 'ble_proximity_scanner.dart';
import 'streetpass_service.dart';

class BleProximityScannerImpl implements BleProximityScanner {
  BleProximityScannerImpl({FlutterBlePeripheral? peripheral})
      : _peripheral = peripheral ?? FlutterBlePeripheral(),
        _controller = StreamController<BleProximityHit>.broadcast();

  static const String _serviceUuid = '8b0c53b0-0e68-4a10-9f88-27a8fac51111';
  static const int _manufacturerId = 0x1357;

  final FlutterBlePeripheral _peripheral;
  final StreamController<BleProximityHit> _controller;
  final Uuid _uuid = const Uuid();

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  bool _started = false;
  Set<String> _targetBeaconIds = {};
  String? _localBeaconId;

  @override
  Stream<BleProximityHit> get hits => _controller.stream;

  @override
  Future<void> start({
    required String localBeaconId,
    Set<String> targetBeaconIds = const {},
  }) async {
    if (kIsWeb) {
      throw StreetPassException('BLE proximity scanning is not supported on web.');
    }
    _targetBeaconIds = targetBeaconIds.toSet();

    await _ensurePermissions();

    final beaconChanged = _localBeaconId != localBeaconId;
    if (beaconChanged) {
      await _peripheral.stop();
    }

    if (!_started) {
      await _startAdvertising(localBeaconId);
      await _startScanning();
      _started = true;
    } else if (beaconChanged) {
      await _startAdvertising(localBeaconId);
    }

    _localBeaconId = localBeaconId;
  }

  @override
  Future<void> updateTargetBeacons(Set<String> targetBeaconIds) async {
    _targetBeaconIds = targetBeaconIds.toSet();
  }

  @override
  Future<void> stop() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {
      // ignore if not scanning
    }
    await _peripheral.stop();
    _started = false;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  Future<void> _startAdvertising(String beaconId) async {
    await _peripheral.start(
      advertiseData: AdvertiseData(
        serviceUuid: _serviceUuid,
        manufacturerId: _manufacturerId,
        manufacturerData: _encodeBeacon(beaconId),
        includeDeviceName: false,
        includePowerLevel: false,
      ),
      advertiseSettings: AdvertiseSettings(
        advertiseSet: true,
        connectable: true,
        timeout: 0,
        advertiseMode: AdvertiseMode.advertiseModeLowLatency,
        txPowerLevel: AdvertiseTxPower.advertiseTxPowerHigh,
      ),
    );
  }

  Future<void> _startScanning() async {
    final serviceGuid = Guid(_serviceUuid);
    await FlutterBluePlus.startScan(
      withServices: [serviceGuid],
      continuousUpdates: true,
      androidScanMode: AndroidScanMode.lowLatency,
      androidUsesFineLocation: true,
    );
    _scanSubscription = FlutterBluePlus.scanResults.listen(_processScanResults);
  }

  void _processScanResults(List<ScanResult> results) {
    for (final result in results) {
      final data = result.advertisementData;
      final manufacturerData = data.manufacturerData[_manufacturerId];
      if (manufacturerData == null || manufacturerData.length != 16) {
        continue;
      }
      final beaconId = Uuid.unparse(manufacturerData);
      if (!_targetBeaconIds.contains(beaconId)) {
        continue;
      }
      final distance = _estimateDistance(result.rssi);
      _controller.add(
        BleProximityHit(
          beaconId: beaconId,
          rssi: result.rssi,
          distanceMeters: distance,
        ),
      );
    }
  }

  Future<void> _ensurePermissions() async {
    final permissions = <Permission>[
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ];

    final statuses = await permissions.request();

    Future<void> ensureGranted(Permission permission) async {
      var status = statuses[permission];
      if (status != null && (status.isGranted || status.isLimited)) {
        return;
      }

      // fall back to general location permission when required
      if (permission == Permission.locationWhenInUse) {
        status = await Permission.location.request();
        if (status.isGranted || status.isLimited) {
          return;
        }
      }

      if (status?.isPermanentlyDenied == true) {
        throw StreetPassException(
          'BLE\u8fd1\u63a5\u3092\u5229\u7528\u3059\u308b\u305f\u3081\u306b\u3001\u8a2d\u5b9a\u753b\u9762\u3067${_labelFor(permission)}\u3092\u6709\u52b9\u306b\u3057\u3066\u304f\u3060\u3055\u3044\u3002',
        );
      }

      if (status == null || !status.isGranted) {
        throw StreetPassException(
          '${_labelFor(permission)}\u306e\u8a31\u53ef\u304c\u5fc5\u8981\u3067\u3059\u3002\u30c0\u30a4\u30a2\u30ed\u30b0\u3067\u8a31\u53ef\u3057\u3066\u304f\u3060\u3055\u3044\u3002',
        );
      }
    }

    for (final permission in permissions) {
      await ensureGranted(permission);
    }
  }

  Uint8List _encodeBeacon(String beaconId) {
    try {
      return Uint8List.fromList(Uuid.parse(beaconId));
    } catch (_) {
      return Uint8List.fromList(Uuid.parse(_uuid.v4()));
    }
  }

  double _estimateDistance(int rssi) {
    const measuredPower = -59; // typical RSSI at 1 meter
    const pathLossExponent = 2.0;
    final ratio = (measuredPower - rssi) / (10 * pathLossExponent);
    final distance = pow(10, ratio);
    if (distance.isNaN || distance.isInfinite) {
      return 10;
    }
    return (distance as double).clamp(0.1, 10.0);
  }

  String _labelFor(Permission permission) {
    switch (permission) {
      case Permission.locationWhenInUse:
      case Permission.location:
        return '\u4f4d\u7f6e\u60c5\u5831';
      case Permission.bluetoothScan:
        return 'Bluetooth\u306e\u30b9\u30ad\u30e3\u30f3';
      case Permission.bluetoothConnect:
        return 'Bluetooth\u3068\u306e\u63a5\u7d9a';
      case Permission.bluetoothAdvertise:
        return 'Bluetooth\u306e\u5e83\u544a';
      default:
        return permission.toString();
    }
  }
}
