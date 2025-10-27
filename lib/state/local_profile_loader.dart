import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/profile.dart';
import '../services/firestore_streetpass_service.dart';

class LocalProfileLoader {
  static const _displayNameKey = 'local_display_name';
  static const _bioKey = 'local_bio';
  static const _homeTownKey = 'local_home_town';
  static const _favoriteGamesKey = 'local_favorite_games';
  static const _avatarColorKey = 'local_avatar_color';
  static const _beaconIdKey = 'local_beacon_id';

  static Future<Profile> loadOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = await _ensureDeviceId(prefs);
    final beaconId = await _ensureBeaconId(prefs);

    final displayName = prefs.getString(_displayNameKey) ?? '\u3042\u306a\u305f';
    final bio = prefs.getString(_bioKey) ?? '\u30d7\u30ed\u30d5\u30a3\u30fc\u30eb\u3092\u7de8\u96c6\u3057\u3066\u81ea\u5df1\u7d39\u4ecb\u3092\u8ffd\u52a0\u3057\u307e\u3057\u3087\u3046\u3002';
    final homeTown = prefs.getString(_homeTownKey) ?? '\u672a\u8a2d\u5b9a';
    final favoriteGames = prefs.getStringList(_favoriteGamesKey) ??
        ['Splatoon 3', 'Mario Kart 8 Deluxe', 'Animal Crossing'];
    final avatarColorValue = prefs.getInt(_avatarColorKey) ?? _randomAccentColorValue();

    return Profile(
      id: deviceId,
      beaconId: beaconId,
      displayName: displayName,
      bio: bio,
      homeTown: homeTown,
      favoriteGames: favoriteGames,
      avatarColor: Color(avatarColorValue),
      receivedLikes: 0,
    );
  }

  static Future<String> _ensureDeviceId(SharedPreferences prefs) async {
    final existing = prefs.getString(FirestoreStreetPassService.prefsDeviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final newId = const Uuid().v4();
    await prefs.setString(FirestoreStreetPassService.prefsDeviceIdKey, newId);
    return newId;
  }

  static Future<String> _ensureBeaconId(SharedPreferences prefs) async {
    final existing = prefs.getString(_beaconIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final newId = const Uuid().v4();
    await prefs.setString(_beaconIdKey, newId);
    return newId;
  }

  static int _randomAccentColorValue() {
    const palette = [
      0xFF1E88E5,
      0xFF8E24AA,
      0xFF43A047,
      0xFFF4511E,
      0xFF3949AB,
      0xFF00897B,
    ];
    final rnd = Random();
    return palette[rnd.nextInt(palette.length)];
  }

  static Future<void> saveDisplayName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, name.trim());
  }

  static Future<bool> hasDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_displayNameKey);
    return stored != null && stored.trim().isNotEmpty;
  }

  static Future<void> resetDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_displayNameKey);
  }
}
