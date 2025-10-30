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
  static const _followersCountKey = 'local_followers_count';
  static const _followingCountKey = 'local_following_count';

  static Future<Profile> loadOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = await _ensureDeviceId(prefs);
    final beaconId = await _ensureBeaconId(prefs);

    final displayName =
        prefs.getString(_displayNameKey) ?? '\u3042\u306a\u305f';
    final bio = prefs.getString(_bioKey) ?? '\u672a\u767b\u9332';
    final homeTown = prefs.getString(_homeTownKey) ?? '\u672a\u767b\u9332';
    final favoriteGames =
        (prefs.getStringList(_favoriteGamesKey) ?? const <String>[])
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false);
    final avatarColorValue =
        prefs.getInt(_avatarColorKey) ?? _randomAccentColorValue();
    final followersCount = prefs.getInt(_followersCountKey) ?? 0;
    final followingCount = prefs.getInt(_followingCountKey) ?? 0;

    return Profile(
      id: deviceId,
      beaconId: beaconId,
      displayName: displayName,
      bio: bio,
      homeTown: homeTown,
      favoriteGames: favoriteGames,
      avatarColor: Color(avatarColorValue),
      receivedLikes: 0,
      followersCount: followersCount,
      followingCount: followingCount,
    );
  }

  static Future<String> _ensureDeviceId(SharedPreferences prefs) async {
    final existing =
        prefs.getString(FirestoreStreetPassService.prefsDeviceIdKey);
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

  static Future<Profile> updateLocalProfile({
    String? displayName,
    String? bio,
    String? homeTown,
    List<String>? favoriteGames,
    Color? avatarColor,
    int? followersCount,
    int? followingCount,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    Future<void> writeString(String key, String? value) async {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, trimmed);
      }
    }

    if (displayName != null) {
      await writeString(_displayNameKey, displayName);
    }
    if (bio != null) {
      await writeString(_bioKey, bio);
    }
    if (homeTown != null) {
      await writeString(_homeTownKey, homeTown);
    }
    if (favoriteGames != null) {
      final sanitized = favoriteGames
          .map((game) => game.trim())
          .where((game) => game.isNotEmpty)
          .toList(growable: false);
      if (sanitized.isEmpty) {
        await prefs.remove(_favoriteGamesKey);
      } else {
        await prefs.setStringList(_favoriteGamesKey, sanitized);
      }
    }
    if (avatarColor != null) {
      await prefs.setInt(_avatarColorKey, avatarColor.toARGB32());
    }
    if (followersCount != null) {
      await prefs.setInt(_followersCountKey, followersCount);
    }
    if (followingCount != null) {
      await prefs.setInt(_followingCountKey, followingCount);
    }
    return loadOrCreate();
  }

  static Future<bool> hasDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_displayNameKey);
    return stored != null && stored.trim().isNotEmpty;
  }

  static Future<void> resetDisplayName() async {
    await resetLocalProfile();
  }

  static Future<void> resetLocalProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_displayNameKey);
    await prefs.remove(_bioKey);
    await prefs.remove(_homeTownKey);
    await prefs.remove(_favoriteGamesKey);
    await prefs.remove(_avatarColorKey);
    await prefs.remove(_followersCountKey);
    await prefs.remove(_followingCountKey);
  }
}
