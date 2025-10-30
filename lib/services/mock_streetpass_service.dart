import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/profile.dart';
import 'streetpass_service.dart';

class MockStreetPassService implements StreetPassService {
  MockStreetPassService({this.seed});

  final int? seed;
  final StreamController<StreetPassEncounterData> _controller =
      StreamController.broadcast();
  Timer? _timer;
  bool _started = false;

  @override
  Stream<StreetPassEncounterData> get encounterStream => _controller.stream;

  @override
  Future<void> start(Profile localProfile) async {
    if (_started) return;
    _started = true;
    final rnd = Random(seed ?? 42);
    final sampleProfiles = _buildSampleProfiles();
    const baseLat = 35.681236;
    const baseLng = 139.767125;
    var index = 0;
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (index >= sampleProfiles.length) {
        timer.cancel();
        return;
      }
      final profile = sampleProfiles[index++];
      final offsetLat = (rnd.nextDouble() - 0.5) * 0.02;
      final offsetLng = (rnd.nextDouble() - 0.5) * 0.02;
      _controller.add(
        StreetPassEncounterData(
          remoteId: profile.id,
          profile: profile,
          beaconId: profile.beaconId,
          encounteredAt:
              DateTime.now().subtract(Duration(minutes: rnd.nextInt(120))),
          gpsDistanceMeters: rnd.nextDouble() * 90 + 10,
          message: rnd.nextBool()
              ? '\u4eca\u5ea6\u4e00\u7dd2\u306b\u904a\u3073\u307e\u3057\u3087\u3046\uff01'
              : null,
          latitude: baseLat + offsetLat,
          longitude: baseLng + offsetLng,
        ),
      );
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  List<Profile> _buildSampleProfiles() {
    final colors = [
      0xFF6C5CE7,
      0xFF00CEC9,
      0xFFFF7675,
      0xFF0984E3,
      0xFFFFB142,
      0xFF2ED573,
    ];
    final bios = [
      '\u643a\u5e2f\u6a5f\u306e\u30c9\u30c3\u30c8\u7d75\u304c\u5927\u597d\u304d\u306a\u30ec\u30c8\u30ed\u30b2\u30fc\u30de\u30fc\u3002',
      '\u30a4\u30f3\u30c7\u30a3\u30fc\u30b2\u30fc\u30e0\u304b\u3089\u5f97\u305f\u30a2\u30a4\u30c7\u30a2\u3092\u30b7\u30a7\u30a2\u3059\u308b\u306e\u304c\u65e5\u8ab2\u3002',
      'AR\u30b2\u30fc\u30e0\u306e\u30b3\u30df\u30e5\u30cb\u30c6\u30a3\u3092\u5e83\u3052\u305f\u3044\u30a8\u30f3\u30b8\u30cb\u30a2\u3002',
      '\u97f3\u697d\u30b2\u30fc\u30e0\u306e\u30b9\u30b3\u30a2\u30bf\u52e2\u3002\u5168\u56fd\u9060\u5f81\u3082\u3057\u3066\u307e\u3059\u3002',
      '\u30d3\u30b8\u30e5\u30a2\u30eb\u30ce\u30d9\u30eb\u304c\u597d\u304d\u3067\u3001\u81ea\u4f5c\u306e\u811a\u672c\u3092\u66f8\u3044\u3066\u307e\u3059\u3002',
      '\u53cb\u9054\u3068\u30dc\u30fc\u30c9\u30b2\u30fc\u30e0\u4f1a\u3092\u958b\u304f\u30de\u30eb\u30c1\u30d7\u30ec\u30a4\u30e4\u30fc\u6d3e\u3002',
    ];
    final towns = [
      '\u6771\u4eac',
      '\u6a2a\u6d5c',
      '\u540d\u53e4\u5c4b',
      '\u5927\u962a',
      '\u4ed9\u53f0',
      '\u672d\u5e4c',
    ];
    final hobbies = [
      [
        '\u30ab\u30d5\u30a7\u5de1\u308a',
        '\u30ab\u30e1\u30e9\u5199\u771f',
        '\u5916\u56f3\u9451\u8cde'
      ],
      [
        '\u62f3\u9053\u30a8\u30af\u30b5\u30b5\u30a4\u30ba',
        '\u30d4\u30a2\u30ce\u30bd\u30ed',
        '\u30e8\u30ac\u845b\u98df'
      ],
      [
        '\u9593\u53e3\u30ec\u30b7\u30d4\u63a2\u3057',
        '\u30cf\u30a4\u30ad\u30f3\u30b0',
        '\u30b2\u30fc\u30e0\u4f1a\u8a08\u753b'
      ],
      [
        '\u30b0\u30ed\u30fc\u30b5\u30af\u30b9\u65c5\u884c\u8a08\u753b',
        '\u6f14\u5287\u9451\u8cde',
        '\u30e8\u30ac\u30af\u30ec\u30d5\u30c8'
      ],
      [
        '\u4e16\u754c\u907a\u7523\u30d0\u30fc\u30c1\u30e3\u30eb\u63a2\u8a2a',
        '\u8a00\u8a9e\u5b66\u7fd2',
        '\u30da\u30a4\u30f3\u30c8\u30ec\u30b9'
      ],
      [
        '\u697d\u5668\u30bb\u30c3\u30b7\u30e7\u30f3',
        '\u304a\u6bcd\u3055\u3093\u30ac\u30fc\u30c7\u30cb\u30f3\u30b0',
        '\u8f2a\u821f\u30ec\u30fc\u30b9'
      ],
    ];

    const uuid = Uuid();
    return List.generate(6, (i) {
      return Profile(
        id: 'profile_mock_$i',
        beaconId: uuid.v4(),
        displayName: 'Mock Player ${String.fromCharCode(65 + i)}',
        bio: bios[i],
        homeTown: towns[i],
        favoriteGames: hobbies[i],
        avatarColor: Color(colors[i % colors.length]),
        receivedLikes: 10 + i * 3,
        followersCount: 50 + i * 7,
        followingCount: 12 + i,
      );
    });
  }
}
