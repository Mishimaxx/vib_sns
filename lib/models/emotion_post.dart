import 'package:flutter/material.dart';

enum EmotionType {
  happy,
  sad,
  excited,
  calm,
  surprised,
  tired,
}

extension EmotionTypeX on EmotionType {
  String get id {
    switch (this) {
      case EmotionType.happy:
        return 'happy';
      case EmotionType.sad:
        return 'sad';
      case EmotionType.excited:
        return 'excited';
      case EmotionType.calm:
        return 'calm';
      case EmotionType.surprised:
        return 'surprised';
      case EmotionType.tired:
        return 'tired';
    }
  }

  String get label {
    switch (this) {
      case EmotionType.happy:
        return 'うれしい';
      case EmotionType.sad:
        return 'かなしい';
      case EmotionType.excited:
        return 'ワクワク';
      case EmotionType.calm:
        return 'おだやか';
      case EmotionType.surprised:
        return 'びっくり';
      case EmotionType.tired:
        return 'つかれた';
    }
  }

  String get emoji {
    switch (this) {
      case EmotionType.happy:
        return '😊';
      case EmotionType.sad:
        return '😢';
      case EmotionType.excited:
        return '🤩';
      case EmotionType.calm:
        return '😌';
      case EmotionType.surprised:
        return '😮';
      case EmotionType.tired:
        return '😴';
    }
  }

  Color get color {
    switch (this) {
      case EmotionType.happy:
        return const Color(0xFFFFC857);
      case EmotionType.sad:
        return const Color(0xFF4F80FF);
      case EmotionType.excited:
        return const Color(0xFFFF6F91);
      case EmotionType.calm:
        return const Color(0xFF4DD0A1);
      case EmotionType.surprised:
        return const Color(0xFF9C6ADE);
      case EmotionType.tired:
        return const Color(0xFF9E9E9E);
    }
  }

  static EmotionType? fromId(String? id) {
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final value in EmotionType.values) {
      if (value.id == id) {
        return value;
      }
    }
    return null;
  }
}

class EmotionMapPost {
  EmotionMapPost({
    required this.id,
    required this.emotion,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.message,
    this.profileId,
  });

  final String id;
  final EmotionType emotion;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final String? message;
  final String? profileId;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'emotion': emotion.id,
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': createdAt.toIso8601String(),
      if (message != null && message!.isNotEmpty) 'message': message,
      if (profileId != null && profileId!.isNotEmpty) 'profileId': profileId,
    };
  }

  static EmotionMapPost? fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return null;
    }
    final emotion = EmotionTypeX.fromId(map['emotion'] as String?);
    final latitude = map['latitude'];
    final longitude = map['longitude'];
    final createdAtRaw = map['createdAt'] as String?;
    if (emotion == null ||
        latitude is! num ||
        longitude is! num ||
        createdAtRaw == null) {
      return null;
    }
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) {
      return null;
    }
    return EmotionMapPost(
      id: (map['id'] as String?) ?? '',
      emotion: emotion,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      createdAt: createdAt,
      message: map['message'] as String?,
      profileId: map['profileId'] as String?,
    );
  }

  String get displayMessage {
    final trimmed = message?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return emotion.label;
    }
    return trimmed;
  }
}
