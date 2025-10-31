import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_notification.dart';
import '../state/notification_manager.dart';
import 'encounter_detail_screen.dart';
import 'profile_view_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<NotificationManager>();
    final notifications = manager.notifications;
    final hasUnread = manager.unreadCount > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('\u901a\u77e5'),
        actions: [
          IconButton(
            tooltip: '\u5168\u4ef6\u3092\u65e2\u8aad\u306b\u3059\u308b',
            onPressed: hasUnread ? manager.markAllRead : null,
            icon: const Icon(Icons.done_all),
          ),
        ],
      ),
      body: notifications.isEmpty
          ? const _EmptyNotificationsView()
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              itemCount: notifications.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final notification = notifications[index];
                return _NotificationTile(notification: notification);
              },
            ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnread = !notification.read;
    final surface = theme.colorScheme.surface;
    final tileColor =
        isUnread ? theme.colorScheme.primary.withValues(alpha: 0.08) : surface;

    return Material(
      color: tileColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _handleTap(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _NotificationIcon(notification: notification),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight:
                                  isUnread ? FontWeight.w700 : FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _relativeTime(notification.createdAt),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      notification.message,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleTap(BuildContext context) {
    final manager = context.read<NotificationManager>();
    switch (notification.type) {
      case AppNotificationType.encounter:
        if (notification.encounterId != null) {
          manager.markEncounterNotificationsRead(notification.encounterId!);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EncounterDetailScreen(
                encounterId: notification.encounterId!,
              ),
            ),
          );
        } else {
          manager.markNotificationRead(notification.id);
        }
        break;
      case AppNotificationType.like:
      case AppNotificationType.follow:
        manager.markNotificationRead(notification.id);
        if (notification.profile != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProfileViewScreen(
                profileId: notification.profile!.id,
                initialProfile: notification.profile!,
              ),
            ),
          );
        }
        break;
    }
  }
}

class _NotificationIcon extends StatelessWidget {
  const _NotificationIcon({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = notification.iconColor(theme);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        notification.icon,
        color: iconColor,
      ),
    );
  }
}

class _EmptyNotificationsView extends StatelessWidget {
  const _EmptyNotificationsView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notifications_none,
                size: 72, color: Color(0xFFFFC400)),
            const SizedBox(height: 18),
            Text(
              '\u307e\u3060\u901a\u77e5\u304c\u3042\u308a\u307e\u305b\u3093\u3002\n\u3059\u308c\u9055\u3044\u3084\u30a4\u30f3\u30bf\u30fc\u30af\u30b7\u30e7\u30f3\u3092\u307e\u3064\u308a\u307e\u3057\u3087\u3046\u3002',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return '\u305f\u3063\u305f\u4eca';
  if (diff.inHours < 1) return '${diff.inMinutes}\u5206\u524d';
  if (diff.inHours < 24) return '${diff.inHours}\u6642\u9593\u524d';
  return '${diff.inDays}\u65e5\u524d';
}
