import 'package:flutter/material.dart';

import '../models/profile.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.profile,
    this.radius = 28,
  });

  final Profile profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: profile.avatarColor,
      child: Text(
        profile.displayName.characters.first,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
