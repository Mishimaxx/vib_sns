import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:image_picker/image_picker.dart';

import 'download_qr_screen.dart';
import 'encounter_list_screen.dart';
import 'notifications_screen.dart';
import '../services/streetpass_service.dart';
import '../state/encounter_manager.dart';
import '../state/local_profile_loader.dart';
import '../state/notification_manager.dart';
import '../state/profile_controller.dart';
import '../state/timeline_manager.dart';
import 'profile_edit_screen.dart';
import '../models/profile.dart';
import '../models/encounter.dart';
import '../models/timeline_post.dart';
import '../widgets/profile_info_tile.dart';
import '../widgets/profile_stats_row.dart';
import 'profile_follow_list_sheet.dart';
import 'profile_view_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 1;
  bool _autoStartAttempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoStartStreetPass();
    });
  }

  final List<Widget> _pages = const [
    _TimelineScreen(),
    EncounterListScreen(),
    NotificationsScreen(),
    _ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final unreadCount = context.watch<NotificationManager>().unreadCount;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _pages[_currentIndex],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '\u30db\u30fc\u30e0',
          ),
          const NavigationDestination(
            icon: Icon(Icons.radio),
            selectedIcon: Icon(Icons.radio_button_checked),
            label: '\u3059\u308c\u9055\u3044',
          ),
          NavigationDestination(
            icon: _buildNotificationIcon(unreadCount, selected: false),
            selectedIcon: _buildNotificationIcon(unreadCount, selected: true),
            label: '\u901a\u77e5',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '\u30d7\u30ed\u30d5\u30a3\u30fc\u30eb',
          ),
        ],
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
      ),
    );
  }

  static Widget _buildNotificationIcon(int unreadCount,
      {required bool selected}) {
    final icon =
        Icon(selected ? Icons.notifications : Icons.notifications_none);
    if (unreadCount <= 0) {
      return icon;
    }
    final displayLabel = unreadCount > 99 ? '99+' : '$unreadCount';
    return Badge(
      label: Text(displayLabel),
      child: icon,
    );
  }

  Future<void> _autoStartStreetPass() async {
    if (_autoStartAttempted || !mounted) return;
    _autoStartAttempted = true;
    final manager = context.read<EncounterManager>();
    if (manager.isRunning) return;
    try {
      await manager.start();
    } on StreetPassException catch (error) {
      if (!mounted) return;
      _showStreetPassSnack(error.message);
    } catch (_) {
      if (!mounted) return;
      _showStreetPassSnack(
          '\u3059\u308c\u9055\u3044\u901a\u4fe1\u306e\u8d77\u52d5\u306b\u5931\u6557\u3057\u307e\u3057\u305f\u3002\u8a2d\u5b9a\u3092\u78ba\u8a8d\u3057\u3066\u304f\u3060\u3055\u3044\u3002');
    }
  }

  void _showStreetPassSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TimelineScreen extends StatelessWidget {
  const _TimelineScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _HomePalette.fromTheme(theme);
    final encounterManager = context.watch<EncounterManager>();
    final timelineManager = context.watch<TimelineManager>();
    final metrics = _computeMetrics(encounterManager);
    final feedItems =
        _buildFeedItems(timelineManager.posts, encounterManager.encounters);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: const Text('🏠 \u30db\u30fc\u30e0'),
        backgroundColor: palette.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: '\u30c0\u30a6\u30f3\u30ed\u30fc\u30c9QR\u3092\u8868\u793a',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DownloadQrScreen()),
              );
            },
            icon: const Icon(Icons.qr_code_2),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              children: [
                _HighlightsSection(
                  palette: palette,
                  metrics: metrics,
                ),
                const SizedBox(height: 28),
                _TimelineComposer(timelineManager: timelineManager),
                const SizedBox(height: 24),
                if (feedItems.isEmpty)
                  const _EmptyTimelineMessage()
                else
                  for (final item in feedItems)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: item.post != null
                          ? _UserPostCard(
                              post: item.post!,
                              timelineManager: timelineManager,
                            )
                          : _EncounterPostCard(
                              encounter: item.encounter!,
                            ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

List<_TimelineFeedItem> _buildFeedItems(
  List<TimelinePost> posts,
  List<Encounter> encounters,
) {
  final items = <_TimelineFeedItem>[
    for (final post in posts) _TimelineFeedItem(post: post),
    for (final encounter in encounters) _TimelineFeedItem(encounter: encounter),
  ];
  items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return items;
}

class _TimelineFeedItem {
  _TimelineFeedItem({this.post, this.encounter})
      : assert(post != null || encounter != null),
        timestamp = post?.createdAt ?? encounter!.encounteredAt;

  final TimelinePost? post;
  final Encounter? encounter;
  final DateTime timestamp;
}

_HomeMetrics _computeMetrics(EncounterManager manager) {
  final encounters = manager.encounters;
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final todaysEncounters = encounters
      .where((encounter) => encounter.encounteredAt.isAfter(todayStart))
      .length;

  final occurrences = <String, int>{};
  for (final encounter in encounters) {
    final key = encounter.profile.id;
    if (key.isEmpty) continue;
    occurrences.update(key, (value) => value + 1, ifAbsent: () => 1);
  }
  final reencounters = occurrences.values.where((count) => count > 1).length;

  final resonance = encounters.where((encounter) => encounter.liked).length;

  return _HomeMetrics(
    todaysEncounters: todaysEncounters,
    reencounters: reencounters,
    resonance: resonance,
  );
}

class _HomeMetrics {
  const _HomeMetrics({
    required this.todaysEncounters,
    required this.reencounters,
    required this.resonance,
  });

  final int todaysEncounters;
  final int reencounters;
  final int resonance;
}

class _HomePalette {
  _HomePalette({
    required this.background,
    required this.onSurface,
    required this.primaryAccent,
    required this.secondaryAccent,
    required this.tertiaryAccent,
  });

  final Color background;
  final Color onSurface;
  final Color primaryAccent;
  final Color secondaryAccent;
  final Color tertiaryAccent;

  factory _HomePalette.fromTheme(ThemeData theme) {
    final scheme = theme.colorScheme;
    return _HomePalette(
      background: Color.alphaBlend(
          scheme.primary.withValues(alpha: 0.02), scheme.surface),
      onSurface: scheme.onSurface,
      primaryAccent: scheme.primary,
      secondaryAccent: scheme.secondary,
      tertiaryAccent: scheme.tertiary,
    );
  }
}

class _HighlightsSection extends StatelessWidget {
  const _HighlightsSection({
    required this.palette,
    required this.metrics,
  });

  final _HomePalette palette;
  final _HomeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tiles = <Widget>[
      _HighlightTile(
        label: '\u3059\u308c\u9055\u3044\u4eba\u6570',
        value: '${metrics.todaysEncounters}\u4eba',
        accent: palette.primaryAccent,
        textColor: palette.onSurface,
      ),
      _HighlightTile(
        label: '\u518d\u4f1a',
        value: '${metrics.reencounters}\u4eba',
        accent: palette.secondaryAccent,
        textColor: palette.onSurface,
      ),
      _HighlightTile(
        label: '\u5171\u9cf4\u6570',
        value: metrics.resonance.toString(),
        accent: palette.tertiaryAccent,
        textColor: palette.onSurface,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '\u4eca\u65e5\u306e\u30cf\u30a4\u30e9\u30a4\u30c8',
          style: theme.textTheme.titleMedium?.copyWith(
            letterSpacing: 1.1,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth =
                constraints.maxWidth <= 0 ? 320.0 : constraints.maxWidth;
            final columns = availableWidth >= 640
                ? 3
                : availableWidth >= 420
                    ? 2
                    : 1;
            const spacing = 12.0;
            final itemWidth = columns == 1
                ? availableWidth
                : (availableWidth - (columns - 1) * spacing) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final tile in tiles)
                  SizedBox(
                    width: itemWidth,
                    child: tile,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _HighlightTile extends StatelessWidget {
  const _HighlightTile({
    required this.label,
    required this.value,
    required this.accent,
    required this.textColor,
  });

  final String label;
  final String value;
  final Color accent;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: accent,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineComposer extends StatefulWidget {
  const _TimelineComposer({required this.timelineManager});

  final TimelineManager timelineManager;

  @override
  State<_TimelineComposer> createState() => _TimelineComposerState();
}

class _TimelineComposerState extends State<_TimelineComposer> {
  final TextEditingController _controller = TextEditingController();
  Uint8List? _imageBytes;
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1440,
      );
      if (picked == null) {
        return;
      }
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _imageBytes = bytes);
    } catch (_) {
      if (!mounted) return;
      _showSnack(
          '\u753b\u50cf\u3092\u8aad\u307f\u8fbc\u3081\u307e\u305b\u3093\u3067\u3057\u305f\u3002');
    }
  }

  Future<void> _submit() async {
    final caption = _controller.text.trim();
    final hasImage = _imageBytes != null && _imageBytes!.isNotEmpty;
    if (caption.isEmpty && !hasImage) {
      _showSnack(
          '\u30c6\u30ad\u30b9\u30c8\u304b\u753b\u50cf\u3092\u8ffd\u52a0\u3057\u3066\u304f\u3060\u3055\u3044\u3002');
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.timelineManager.addPost(
        caption: caption,
        imageBytes: _imageBytes,
      );
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _imageBytes = null;
      });
      FocusScope.of(context).unfocus();
      _showSnack('\u6295\u7a3f\u3057\u307e\u3057\u305f\u3002');
    } catch (_) {
      if (!mounted) return;
      _showSnack(
          '\u6295\u7a3f\u306b\u5931\u6557\u3057\u307e\u3057\u305f\u3002');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _removeImage() {
    setState(() => _imageBytes = null);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '\u4eca\u306e\u77ac\u9593\u3092\u30b7\u30a7\u30a2',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText:
                    '\u4eca\u306e\u6c17\u6301\u3061\u3084\u3082\u3088\u3044\u3092\u5171\u6709...',
                border: OutlineInputBorder(),
              ),
            ),
            if (_imageBytes != null) ...[
              const SizedBox(height: 12),
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(
                      _imageBytes!,
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: IconButton.filled(
                      onPressed: _removeImage,
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _submitting ? null : _pickImage,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('\u753b\u50cf\u3092\u3048\u3089\u3076'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('\u30b7\u30a7\u30a2'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UserPostCard extends StatelessWidget {
  const _UserPostCard({
    required this.post,
    required this.timelineManager,
  });

  final TimelinePost post;
  final TimelineManager timelineManager;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageBytes = post.decodeImage();
    final likeLabel = post.likeCount > 0
        ? '${post.likeCount}\u4ef6\u306e\u3044\u3044\u306d'
        : '\u307e\u3060\u3044\u3044\u306d\u306f\u3042\u308a\u307e\u305b\u3093';
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TimelineCardHeader(
            title: post.authorName,
            subtitle: _relativeTime(post.createdAt),
            color: post.authorColor,
          ),
          if (imageBytes != null) _TimelineImage(bytes: imageBytes),
          if (post.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Text(
                post.caption,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          _TimelineActions(
            isLiked: post.isLiked,
            likeLabel: likeLabel,
            onLike: () => timelineManager.toggleLike(post.id),
          ),
        ],
      ),
    );
  }
}

class _EncounterPostCard extends StatelessWidget {
  const _EncounterPostCard({required this.encounter});

  final Encounter encounter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = encounter.profile;
    final caption = (encounter.message?.trim().isNotEmpty ?? false)
        ? encounter.message!.trim()
        : '${profile.displayName}\u3068\u306e\u65b0\u3057\u3044\u51fa\u4f1a\u3092\u8a18\u9332\u3057\u307e\u3057\u305f\u3002';
    final distance = encounter.displayDistance;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TimelineCardHeader(
            title: profile.displayName,
            subtitle: _relativeTime(encounter.encounteredAt),
            color: profile.avatarColor,
          ),
          _EncounterImage(profile: profile),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  caption,
                  style: theme.textTheme.bodyLarge,
                ),
                if (distance != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '\u63a8\u5b9a\u8ddd\u96e2: ${distance.toStringAsFixed(1)}m',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          _TimelineActions(
            isLiked: encounter.liked,
            likeLabel: encounter.liked
                ? '\u3044\u3044\u306d\u3057\u307e\u3057\u305f'
                : '\u3059\u308c\u9055\u3044\u306b\u3044\u3044\u306d',
            onLike: () =>
                context.read<EncounterManager>().toggleLike(encounter.id),
          ),
        ],
      ),
    );
  }
}

class _TimelineCardHeader extends StatelessWidget {
  const _TimelineCardHeader({
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmedTitle = title.trim().isEmpty ? '\u533f\u540d' : title.trim();
    final initial = trimmedTitle.characters.first.toUpperCase();
    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: color,
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      title: Text(
        trimmedTitle,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}

class _TimelineActions extends StatelessWidget {
  const _TimelineActions({
    required this.isLiked,
    required this.likeLabel,
    required this.onLike,
  });

  final bool isLiked;
  final String likeLabel;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onLike,
            icon: Icon(
              isLiked ? Icons.favorite : Icons.favorite_border,
              color: isLiked
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              likeLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineImage extends StatelessWidget {
  const _TimelineImage({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Image.memory(
        bytes,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(
            Icons.image_not_supported_outlined,
            size: 48,
            color: Colors.black38,
          ),
        ),
      ),
    );
  }
}

class _EncounterImage extends StatelessWidget {
  const _EncounterImage({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final accent = profile.avatarColor;
    final details = profile.favoriteGames.isNotEmpty
        ? profile.favoriteGames.first
        : profile.homeTown;
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: 0.9),
              accent.withValues(alpha: 0.6),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.center,
              child: Icon(
                Icons.people_alt_rounded,
                size: 72,
                color: Colors.white.withValues(alpha: 0.88),
              ),
            ),
            Positioned(
              left: 20,
              bottom: 20,
              right: 20,
              child: Text(
                details.isEmpty
                    ? '\u65b0\u3057\u3044\u3059\u308c\u9055\u3044\u3092\u8a18\u9332'
                    : details,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTimelineMessage extends StatelessWidget {
  const _EmptyTimelineMessage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            '\u307e\u3060\u30bf\u30a4\u30e0\u30e9\u30a4\u30f3\u306b\u306f\u6295\u7a3f\u304c\u3042\u308a\u307e\u305b\u3093\u3002\n\u6700\u521d\u306e\u77ac\u9593\u3092\u30b7\u30a7\u30a2\u3057\u3066\u307f\u307e\u3057\u3087\u3046\uff01',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
        ],
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

class _ProfileScreen extends StatefulWidget {
  const _ProfileScreen();

  @override
  State<_ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<_ProfileScreen> {
  bool _loggingOut = false;

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    final controller = context.read<ProfileController>();
    final manager = context.read<EncounterManager>();
    final notificationManager = context.read<NotificationManager>();
    try {
      // If the user is authenticated, call the server-side function to
      // delete their profile and related server-side data before clearing
      // local state. We catch and continue on error to avoid blocking logout.
      final user = FirebaseAuth.instance.currentUser;
      var serverDeleted = false;
      if (user != null) {
        try {
          debugPrint(
              'HomeShell._logout: calling deleteUserProfile for profileId=${controller.profile.id} beaconId=${controller.profile.beaconId}');
          final callable =
              FirebaseFunctions.instance.httpsCallable('deleteUserProfile');
          final result = await callable.call(<String, dynamic>{
            'profileId': controller.profile.id,
            'beaconId': controller.profile.beaconId,
          });
          debugPrint(
              'HomeShell._logout: deleteUserProfile result=${result.data}');
          serverDeleted = true;
        } catch (e, st) {
          debugPrint('deleteUserProfile failed: $e');
          debugPrintStack(stackTrace: st);
        }
      }

      // Sign out from Firebase Auth.
      debugPrint('HomeShell._logout: signing out FirebaseAuth');
      await FirebaseAuth.instance.signOut();

      if (serverDeleted) {
        // Wipe local identity only if server-side deletion succeeded. This
        // prevents generating a fresh device id/profile when the server
        // couldn't delete the old one (which was causing profile proliferation).
        debugPrint(
            'HomeShell._logout: resetting local profile with wipeIdentity=true');
        await LocalProfileLoader.resetLocalProfile(wipeIdentity: true);
        final refreshed = await LocalProfileLoader.loadOrCreate();
        debugPrint(
            'HomeShell._logout: new local profile id=${refreshed.id} beaconId=${refreshed.beaconId}');
        // Do not bootstrap profile on logout and avoid re-subscribing to server
        // stats so that follower/following/likes counts are reset locally.
        await manager.switchLocalProfile(refreshed, skipSync: true);
        await notificationManager.resetForProfile(refreshed);
        // Reset UI-visible stats to zero on logout.
        controller.updateStats(
            followersCount: 0, followingCount: 0, receivedLikes: 0);
        controller.updateProfile(refreshed, needsSetup: true);
      } else {
        // Server deletion failed or wasn't attempted (no auth). Keep the local
        // identity to avoid creating a new profile doc on next start. Still
        // clear local UI-visible stats and reset managers to a neutral state.
        debugPrint(
            'HomeShell._logout: server deletion failed or not attempted; keeping local identity to avoid creating extra profiles');
        final currentLocal = controller.profile;
        await manager.switchLocalProfile(currentLocal, skipSync: true);
        await notificationManager.resetForProfile(currentLocal);
        controller.updateStats(
            followersCount: 0, followingCount: 0, receivedLikes: 0);
        controller.updateProfile(currentLocal, needsSetup: true);
      }
    } finally {
      if (mounted) {
        setState(() => _loggingOut = false);
      }
    }
  }

  void _openRelationsSheet(
    Profile profile,
    ProfileFollowSheetMode mode,
  ) {
    final navigator = Navigator.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return ProfileFollowListSheet(
          targetId: profile.id,
          viewerId: profile.id,
          mode: mode,
          onProfileTap: (remoteProfile) {
            navigator.push(
              MaterialPageRoute(
                builder: (_) => ProfileViewScreen(
                  profileId: remoteProfile.id,
                  initialProfile: remoteProfile,
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = context.watch<ProfileController>().profile;
    final bio = _displayOrPlaceholder(profile.bio);
    final homeTown = _displayOrPlaceholder(profile.homeTown);
    final hobbies = _hobbiesOrPlaceholder(profile.favoriteGames);
    return Scaffold(
      appBar: AppBar(
        title: const Text('\u30d7\u30ed\u30d5\u30a3\u30fc\u30eb'),
        actions: [
          IconButton(
            tooltip: '\u7de8\u96c6',
            onPressed: () async {
              final controller = context.read<ProfileController>();
              final messenger = ScaffoldMessenger.of(context);
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) =>
                      ProfileEditScreen(profile: controller.profile),
                ),
              );
              if (!mounted) return;
              if (result == true) {
                messenger.showSnackBar(
                  const SnackBar(
                      content: Text(
                          '\u30d7\u30ed\u30d5\u30a3\u30fc\u30eb\u3092\u66f4\u65b0\u3057\u307e\u3057\u305f\u3002')),
                );
              }
            },
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF4C7),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Icon(Icons.person, size: 42),
                          ),
                          const SizedBox(width: 18),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.displayName,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '\u30b5\u30de\u30ea\u30fc\u3092\u7de8\u96c6\u3057\u3066\n\u3042\u306a\u305f\u3089\u3057\u3055\u3092\u5c4a\u3051\u307e\u3057\u3087\u3046\u3002',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          )
                        ],
                      ),
                      const SizedBox(height: 24),
                      ProfileStatsRow(
                        profile: profile,
                        onFollowersTap: () => _openRelationsSheet(
                          profile,
                          ProfileFollowSheetMode.followers,
                        ),
                        onFollowingTap: () => _openRelationsSheet(
                          profile,
                          ProfileFollowSheetMode.following,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        '\u30b9\u30c6\u30fc\u30bf\u30b9',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      ProfileInfoTile(
                        icon: Icons.mood,
                        title: '\u4e00\u8a00\u30b3\u30e1\u30f3\u30c8',
                        value: bio,
                      ),
                      ProfileInfoTile(
                        icon: Icons.place_outlined,
                        title: '\u6d3b\u52d5\u30a8\u30ea\u30a2',
                        value: homeTown,
                      ),
                      ProfileInfoTile(
                        icon: Icons.palette_outlined,
                        title: '\u8da3\u5473',
                        value: hobbies,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _loggingOut ? null : _logout,
                icon: const Icon(Icons.logout),
                label: _loggingOut
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('\u30ed\u30b0\u30a2\u30a6\u30c8'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _displayOrPlaceholder(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == '\u672a\u767b\u9332') {
    return '\u672a\u767b\u9332';
  }
  return trimmed;
}

String _hobbiesOrPlaceholder(List<String> hobbies) {
  if (hobbies.isEmpty) {
    return '\u672a\u767b\u9332';
  }
  return hobbies.join(', ');
}
