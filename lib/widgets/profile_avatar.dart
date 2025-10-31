import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/profile.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.profile,
    this.radius = 28,
    this.showBorder = true,
  });

  static final Map<String, Uint8List> _imageCache = <String, Uint8List>{};

  final Profile profile;
  final double radius;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final imageBase64 = profile.avatarImageBase64?.trim();
    MemoryImage? imageProvider;
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      final cached = _imageCache[imageBase64];
      if (cached != null) {
        imageProvider = MemoryImage(cached);
      } else {
        try {
          final bytes = base64Decode(imageBase64);
          if (bytes.isNotEmpty) {
            _imageCache[imageBase64] = bytes;
            imageProvider = MemoryImage(bytes);
          }
        } catch (_) {
          imageProvider = null;
        }
      }
    }
    final displayName = profile.displayName.trim();
    final fallback = profile.id.trim();
    String initial;
    if (displayName.isNotEmpty) {
      initial = displayName.characters.first;
    } else if (fallback.isNotEmpty) {
      initial = fallback.characters.first;
    } else {
      initial = '?';
    }
    final hasImage = imageProvider != null;
    final backgroundColor =
        hasImage && !showBorder ? Colors.transparent : profile.avatarColor;
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      foregroundImage: imageProvider,
      child: hasImage
          ? null
          : Text(
              initial,
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * 0.9,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }
}
