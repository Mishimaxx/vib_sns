import 'package:flutter/material.dart';

import '../models/profile.dart';

class ProfileStatsRow extends StatelessWidget {
  const ProfileStatsRow({
    super.key,
    required this.profile,
    this.onFollowersTap,
    this.onFollowingTap,
  });

  final Profile profile;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: ProfileStatBadge(
              icon: Icons.people_alt,
              label: '\u30d5\u30a9\u30ed\u30ef\u30fc',
              value: profile.followersCount,
              accentColor: theme.colorScheme.primary,
              onTap: onFollowersTap,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ProfileStatBadge(
              icon: Icons.person_add_alt_1,
              label: '\u30d5\u30a9\u30ed\u30fc',
              value: profile.followingCount,
              accentColor: theme.colorScheme.secondary,
              onTap: onFollowingTap,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ProfileStatBadge(
              icon: Icons.favorite,
              label: '\u3082\u3089\u3063\u305f\u3044\u3044\u306d',
              value: profile.receivedLikes,
              accentColor: const Color(0xFFFF5F8F),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileStatBadge extends StatelessWidget {
  const ProfileStatBadge({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(20);
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: accentColor,
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(height: 10),
          Text(
            value.toString(),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return content;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: content,
      ),
    );
  }
}
