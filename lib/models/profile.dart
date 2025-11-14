import 'package:flutter/material.dart';

import '../utils/color_extensions.dart';

class Profile {
  Profile({
    required this.id,
    required this.beaconId,
    required this.displayName,
    required this.bio,
    required this.homeTown,
    required List<String> favoriteGames,
    required this.avatarColor,
    this.avatarImageBase64,
    this.following = false,
    this.receivedLikes = 0,
    this.followersCount = 0,
    this.followingCount = 0,
  }) : favoriteGames = sanitizeHashtags(favoriteGames);

  static const int maxHashtagCount = 10;
  static const int maxHashtagLength = 32;

  final String id;
  final String beaconId;
  final String displayName;
  final String bio;
  final String homeTown;
  final List<String> favoriteGames;
  final Color avatarColor;
  final String? avatarImageBase64;
  bool following;
  int receivedLikes;
  int followersCount;
  int followingCount;

  void toggleFollow() {
    following = !following;
  }

  void like() {
    receivedLikes++;
  }

  Profile copyWith({
    String? id,
    String? beaconId,
    String? displayName,
    String? bio,
    String? homeTown,
    List<String>? favoriteGames,
    Color? avatarColor,
    String? avatarImageBase64,
    bool clearAvatarImage = false,
    bool? following,
    int? receivedLikes,
    int? followersCount,
    int? followingCount,
  }) {
    return Profile(
      id: id ?? this.id,
      beaconId: beaconId ?? this.beaconId,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      homeTown: homeTown ?? this.homeTown,
      favoriteGames: favoriteGames != null
          ? sanitizeHashtags(favoriteGames)
          : List<String>.from(this.favoriteGames),
      avatarColor: avatarColor ?? this.avatarColor,
      avatarImageBase64: clearAvatarImage
          ? null
          : (avatarImageBase64 ?? this.avatarImageBase64),
      following: following ?? this.following,
      receivedLikes: receivedLikes ?? this.receivedLikes,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'displayName': displayName,
      'beaconId': beaconId,
      'bio': bio,
      'homeTown': homeTown,
      'favoriteGames': favoriteGames,
      'avatarColor': avatarColor.toARGB32(),
      'avatarImageBase64': avatarImageBase64,
      'following': following,
      'receivedLikes': receivedLikes,
      'followersCount': followersCount,
      'followingCount': followingCount,
    };
  }

  static Profile? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    try {
      final favoriteGamesRaw = map['favoriteGames'];
      final favoriteGames = favoriteGamesRaw is Iterable
          ? favoriteGamesRaw.map((e) => e.toString()).toList()
          : <String>[];
      return Profile(
        id: map['id']?.toString() ?? '',
        displayName: map['displayName']?.toString() ?? 'Unknown',
        beaconId: map['beaconId']?.toString() ?? map['id']?.toString() ?? '',
        bio: map['bio']?.toString() ?? '',
        homeTown: map['homeTown']?.toString() ?? '',
        favoriteGames: favoriteGames,
        avatarColor: Color((map['avatarColor'] as num?)?.toInt() ??
            Colors.blueAccent.toARGB32()),
        avatarImageBase64: map['avatarImageBase64'] as String?,
        following: map['following'] as bool? ?? false,
        receivedLikes: (map['receivedLikes'] as num?)?.toInt() ?? 0,
        followersCount: (map['followersCount'] as num?)?.toInt() ?? 0,
        followingCount: (map['followingCount'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
  static List<String> sanitizeHashtags(Iterable<String> values) {
    final sanitized = <String>[];
    final seen = <String>{};
    for (final raw in values) {
      final normalized = normalizeHashtag(raw);
      if (normalized == null) continue;
      final key = _canonicalKey(normalized);
      if (seen.contains(key)) continue;
      sanitized.add(normalized);
      seen.add(key);
      if (sanitized.length >= maxHashtagCount) {
        break;
      }
    }
    return List<String>.unmodifiable(sanitized);
  }

  static String? normalizeHashtag(String? raw) {
    if (raw == null) return null;
    var value = raw.trim();
    if (value.isEmpty) return null;
    value = value.replaceAll(RegExp(r'\s+'), '');
    if (value.isEmpty) return null;
    if (!value.startsWith('#')) {
      value = '#$value';
    }
    if (value == '#') return null;
    if (value.length > maxHashtagLength) {
      value = value.substring(0, maxHashtagLength);
    }
    return value;
  }

  static String _canonicalKey(String tag) {
    final trimmed = tag.startsWith('#') ? tag.substring(1) : tag;
    return trimmed.toLowerCase();
  }
}
