import 'package:flutter/material.dart';

class Profile {
  Profile({
    required this.id,
    required this.beaconId,
    required this.displayName,
    required this.bio,
    required this.homeTown,
    required this.favoriteGames,
    required this.avatarColor,
    this.following = false,
    this.receivedLikes = 0,
  });

  final String id;
  final String beaconId;
  final String displayName;
  final String bio;
  final String homeTown;
  final List<String> favoriteGames;
  final Color avatarColor;
  bool following;
  int receivedLikes;

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
    bool? following,
    int? receivedLikes,
  }) {
    return Profile(
      id: id ?? this.id,
      beaconId: beaconId ?? this.beaconId,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      homeTown: homeTown ?? this.homeTown,
      favoriteGames: favoriteGames != null
          ? List<String>.from(favoriteGames)
          : List<String>.from(this.favoriteGames),
      avatarColor: avatarColor ?? this.avatarColor,
      following: following ?? this.following,
      receivedLikes: receivedLikes ?? this.receivedLikes,
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
      'following': following,
      'receivedLikes': receivedLikes,
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
        following: map['following'] as bool? ?? false,
        receivedLikes: (map['receivedLikes'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}
