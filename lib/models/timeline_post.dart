import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class TimelinePost {
  TimelinePost({
    required this.id,
    required this.authorName,
    required this.authorColorValue,
    required this.caption,
    required this.createdAt,
    this.imageBase64,
    this.likeCount = 0,
    this.isLiked = false,
  });

  final String id;
  final String authorName;
  final int authorColorValue;
  final String caption;
  final DateTime createdAt;
  final String? imageBase64;
  int likeCount;
  bool isLiked;
  Uint8List? _cachedImageBytes;
  String? _cachedImageKey;

  Color get authorColor => Color(authorColorValue);

  Uint8List? decodeImage() {
    if (imageBase64 == null || imageBase64!.isEmpty) {
      return null;
    }
    if (_cachedImageBytes != null && _cachedImageKey == imageBase64) {
      return _cachedImageBytes;
    }
    try {
      final decoded = base64Decode(imageBase64!);
      _cachedImageBytes = decoded;
      _cachedImageKey = imageBase64;
      return decoded;
    } catch (_) {
      _cachedImageBytes = null;
      _cachedImageKey = null;
      return null;
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'authorName': authorName,
        'authorColorValue': authorColorValue,
        'caption': caption,
        'createdAt': createdAt.toIso8601String(),
        'imageBase64': imageBase64,
        'likeCount': likeCount,
        'isLiked': isLiked,
      };

  static TimelinePost? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    try {
      final createdRaw = map['createdAt'] as String?;
      final createdAt = DateTime.tryParse(createdRaw ?? '') ?? DateTime.now();
      final id = map['id'] as String? ?? '';
      if (id.isEmpty) {
        return null;
      }
      final authorName = map['authorName'] as String? ?? '';
      final authorColor =
          (map['authorColorValue'] as num?)?.toInt() ?? 0xFF9E9E9E;
      final caption = map['caption'] as String? ?? '';
      final likeCount = (map['likeCount'] as num?)?.toInt() ?? 0;
      final isLiked = map['isLiked'] as bool? ?? false;
      final imageBase64 = map['imageBase64'] as String?;
      return TimelinePost(
        id: id,
        authorName: authorName,
        authorColorValue: authorColor,
        caption: caption,
        createdAt: createdAt,
        imageBase64: imageBase64,
        likeCount: likeCount,
        isLiked: isLiked,
      );
    } catch (_) {
      return null;
    }
  }
}
