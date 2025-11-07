import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/emotion_post.dart';
import '../state/emotion_map_manager.dart';

class EmotionMap extends StatefulWidget {
  const EmotionMap({super.key});

  @override
  State<EmotionMap> createState() => _EmotionMapState();
}

const LatLng _defaultCenter = LatLng(35.681236, 139.767125);

class _EmotionMapState extends State<EmotionMap> {
  final MapController _mapController = MapController();
  bool _mapReady = false;
  bool _isLocating = false;
  bool _isPosting = false;
  bool _centeredOnUserOnce = false;
  LatLng? _userLocation;
  String _lastPostSignature = '';

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<EmotionMapManager>();
    final posts = manager.posts;
    final userLocation = _userLocation;

    final markers = posts
        .map((post) => _buildEmotionMarker(context, post))
        .toList(growable: true);
    if (userLocation != null) {
      markers.add(_buildUserMarker(userLocation));
    }
    final showMarkers = markers.isNotEmpty;

    if (_mapReady) {
      final signature = _signatureForPosts(posts);
      if (signature != _lastPostSignature) {
        _lastPostSignature = signature;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _mapReady) {
            _fitToContent(posts);
          }
        });
      }
    } else {
      _lastPostSignature = _signatureForPosts(posts);
    }

    final initialCenter = userLocation ??
        (posts.isNotEmpty
            ? LatLng(posts.first.latitude, posts.first.longitude)
            : _defaultCenter);
    final initialZoom = userLocation != null
        ? 16.0
        : posts.isNotEmpty
            ? 14.5
            : 12.0;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: initialZoom,
            onMapReady: () {
              _mapReady = true;
              _fitToContent(posts);
              _locateUser(initial: true);
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.vib_sns',
            ),
            if (showMarkers) MarkerLayer(markers: markers),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.small(
                heroTag: 'emotionMap_locate',
                onPressed:
                    _isLocating ? null : () => _locateUser(initial: false),
                child: _isLocating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
              ),
              const SizedBox(height: 12),
              FloatingActionButton.extended(
                heroTag: 'emotionMap_add',
                onPressed: _isPosting ? null : _openAddEmotionSheet,
                icon: const Icon(Icons.mood),
                label: _isPosting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('気持ちを投稿'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Marker _buildEmotionMarker(BuildContext context, EmotionMapPost post) {
    final emotion = post.emotion;
    return Marker(
      point: LatLng(post.latitude, post.longitude),
      width: 60,
      height: 110,
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: () => _showPostDetails(post),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: emotion.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(14),
              child: Text(
                emotion.emoji,
                style: const TextStyle(fontSize: 22),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                post.emotion.label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Marker _buildUserMarker(LatLng position) {
    return Marker(
      point: position,
      width: 56,
      height: 56,
      alignment: Alignment.center,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1E88E5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1E88E5).withValues(alpha: 0.4),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
          border: Border.all(
            color: Colors.white,
            width: 3,
          ),
        ),
        child: const Icon(
          Icons.person_pin_circle,
          color: Colors.white,
        ),
      ),
    );
  }

  Future<void> _openAddEmotionSheet() async {
    if (_isPosting) return;
    final location = await _locateUser(
      initial: false,
      moveCamera: false,
      showPromptOnError: true,
    );
    if (!mounted) return;
    if (location == null) {
      _showSnack('現在地を取得してから投稿してください。');
      return;
    }
    final result = await showModalBottomSheet<_EmotionFormResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _EmotionPostSheet(),
    );
    if (!mounted) return;
    if (result == null) {
      return;
    }
    setState(() => _isPosting = true);
    final emotionManager = context.read<EmotionMapManager>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await emotionManager.addPost(
        emotion: result.emotion,
        latitude: location.latitude,
        longitude: location.longitude,
        message: result.message,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('気持ちを投稿しました。')),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('投稿に失敗しました。もう一度お試しください。')),
      );
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  Future<LatLng?> _locateUser({
    required bool initial,
    bool moveCamera = true,
    bool showPromptOnError = false,
  }) async {
    if (!_mapReady) return _userLocation;
    if (_isLocating) {
      return _userLocation;
    }
    if (initial && _centeredOnUserOnce) {
      return _userLocation;
    }
    if (mounted) {
      setState(() {
        _isLocating = true;
      });
    }
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (showPromptOnError || !initial) {
          _showSnack('位置情報へのアクセスを許可してください。');
        }
        return null;
      }
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (showPromptOnError || !initial) {
          _showSnack('位置サービスを有効にしてください。');
        }
        return null;
      }
      final position = await Geolocator.getCurrentPosition();
      final latLng = LatLng(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _userLocation = latLng;
        });
      }
      if (moveCamera) {
        final currentZoom = _mapController.camera.zoom;
        final targetZoom =
            currentZoom.isNaN || currentZoom < 15 ? 16.0 : currentZoom;
        _mapController.move(latLng, targetZoom);
      }
      if (initial) {
        _centeredOnUserOnce = true;
      }
      return latLng;
    } catch (_) {
      if (showPromptOnError || !initial) {
        _showSnack('現在地を取得できませんでした。');
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  void _fitToContent(List<EmotionMapPost> posts) {
    if (!_mapReady) return;
    final points = <LatLng>[
      if (_userLocation != null) _userLocation!,
      ...posts.map((post) => LatLng(post.latitude, post.longitude)),
    ];
    if (points.isEmpty) {
      _mapController.move(_defaultCenter, 12);
      return;
    }
    if (points.length == 1) {
      _mapController.move(points.first, 15);
      return;
    }
    if (_pointsCollapsed(points)) {
      _mapController.move(points.first, 16);
      return;
    }
    final bounds = LatLngBounds.fromPoints(points);
    final cameraFit = CameraFit.bounds(
      bounds: bounds,
      padding: const EdgeInsets.all(80),
    );
    _mapController.fitCamera(cameraFit);
  }

  bool _pointsCollapsed(List<LatLng> points) {
    if (points.isEmpty) return true;
    final first = points.first;
    for (final point in points.skip(1)) {
      if ((point.latitude - first.latitude).abs() > 1e-5 ||
          (point.longitude - first.longitude).abs() > 1e-5) {
        return false;
      }
    }
    return true;
  }

  Future<void> _showPostDetails(EmotionMapPost post) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return _EmotionPostDetailSheet(
          post: post,
          onDelete: () {
            context.read<EmotionMapManager>().removePost(post.id);
            Navigator.of(context).pop();
            _showSnack('投稿を削除しました。');
          },
        );
      },
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _signatureForPosts(List<EmotionMapPost> posts) {
    if (posts.isEmpty) {
      return '';
    }
    return posts.map((post) => post.id).join('|');
  }
}

class _EmotionFormResult {
  _EmotionFormResult({required this.emotion, this.message});

  final EmotionType emotion;
  final String? message;
}

class _EmotionPostSheet extends StatefulWidget {
  const _EmotionPostSheet();

  @override
  State<_EmotionPostSheet> createState() => _EmotionPostSheetState();
}

class _EmotionPostSheetState extends State<_EmotionPostSheet> {
  final TextEditingController _controller = TextEditingController();
  EmotionType? _selectedEmotion = EmotionType.happy;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight == double.infinity
                      ? 0
                      : constraints.maxHeight,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '気持ちを投稿',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: EmotionType.values.map((emotion) {
                        final selected = _selectedEmotion == emotion;
                        return ChoiceChip(
                          label: Text('${emotion.emoji} ${emotion.label}'),
                          selected: selected,
                          onSelected: (_) {
                            setState(() => _selectedEmotion = emotion);
                          },
                        );
                      }).toList(growable: false),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _controller,
                      maxLength: 120,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'ひとことメモ（任意）',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _selectedEmotion == null
                                ? null
                                : () {
                                    final trimmed = _controller.text.trim();
                                    final message =
                                        trimmed.isEmpty ? null : trimmed;
                                    Navigator.of(context).pop(
                                      _EmotionFormResult(
                                        emotion: _selectedEmotion!,
                                        message: message,
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.send),
                            label: const Text('投稿する'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmotionPostDetailSheet extends StatelessWidget {
  const _EmotionPostDetailSheet({
    required this.post,
    required this.onDelete,
  });

  final EmotionMapPost post;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emotion = post.emotion;
    final formattedTime = _formatTimestamp(post.createdAt);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: emotion.color,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    emotion.emoji,
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      emotion.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formattedTime,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey.shade600),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '削除',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              post.displayMessage,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime time) {
    final local = time.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final date =
        '${local.year}/${twoDigits(local.month)}/${twoDigits(local.day)}';
    final clock =
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}:${twoDigits(local.second)}';
    return '$date $clock';
  }
}
