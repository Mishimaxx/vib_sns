import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
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

const Map<String, List<String>> _botMemosByEmotion = {
  'happy': [
    '散歩中に犬に会えた！',
    'カフェのケーキが最高だった',
    '久しぶりに友達と会えた',
    '良い天気で気分いい',
    '素敵な場所を見つけた',
    '今日はいい日だ',
  ],
  'sad': [
    '雨降ってきちゃった',
    '電車乗り過ごした...',
    '財布忘れて取りに戻った',
    'なんだか寂しい気分',
    '疲れたなぁ',
    '気分が沈む',
  ],
};

const double _memoMinInnerWidth = 40;
const double _memoMaxInnerWidth = 360;
const double _memoWidthStep = 18;

const _BotStaticSpot _tokyoDomeSpot = _BotStaticSpot(
  id: 'tokyo_dome',
  center: LatLng(35.705639, 139.751891),
  radiusMeters: 400,
  count: 30,
);

const _BotStaticSpot _tokyoBigSightSpot = _BotStaticSpot(
  id: 'tokyo_big_sight',
  center: LatLng(35.6298, 139.7976),
  radiusMeters: 400,
  count: 30,
);

const List<_BotStaticSpot> _botStaticSpots = [
  _tokyoDomeSpot,
  _tokyoBigSightSpot,
];

class _EmotionMapState extends State<EmotionMap> {
  final MapController _mapController = MapController();
  final Random _random = Random();
  bool _mapReady = false;
  bool _isLocating = false;
  bool _isPosting = false;
  bool _centeredOnUserOnce = false;
  LatLng? _userLocation;
  String _lastPostSignature = '';
  StreamSubscription<MapEvent>? _mapEventSub;
  double _currentZoom = 14;
  List<EmotionMapPost> _botPosts = const [];
  Timer? _botMemoTimer;
  Set<String> _visibleBotMemoIds = <String>{};

  @override
  void initState() {
    super.initState();
    _mapEventSub = _mapController.mapEventStream.listen((event) {
      final zoom = event.camera.zoom;
      if (zoom.isNaN) return;
      if ((zoom - _currentZoom).abs() < 0.01) return;
      if (mounted) {
        setState(() {
          _currentZoom = zoom;
        });
      } else {
        _currentZoom = zoom;
      }
    });
    _botMemoTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _rotateBotMemoVisibility(),
    );
  }

  @override
  void dispose() {
    _mapEventSub?.cancel();
    _botMemoTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<EmotionMapManager>();
    final posts = manager.posts;
    final userLocation = _userLocation;

    final markers = posts
        .map((post) => _buildEmotionMarker(context, post, isBot: false))
        .toList(growable: true)
      ..addAll(
        _botPosts.map(
          (post) => _buildEmotionMarker(context, post, isBot: true),
        ),
      );
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

  Marker _buildEmotionMarker(
    BuildContext context,
    EmotionMapPost post, {
    required bool isBot,
  }) {
    final emotion = post.emotion;
    const baseWidth = 40.0;
    final scale = _markerScaleForZoom(_currentZoom);
    final visualScale = scale.clamp(0.75, 1.0);
    final labelStyle = TextStyle(
      fontSize: 11 * visualScale,
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
    final showMemo = !isBot || _visibleBotMemoIds.contains(post.id);
    const memoSpacing = 4.0;
    const memoPaddingV = 4.0;
    const memoPaddingH = 10.0;
    // スタンプが動かないように、常にメモレイアウトを計算
    final memoLayout = _resolveMemoBubbleLayout(
      text: post.displayMessage,
      style: labelStyle,
      spacing: memoSpacing * scale,
      paddingVertical: memoPaddingV * scale,
      paddingHorizontal: memoPaddingH * scale,
      minInnerWidth: _memoMinInnerWidth * scale,
      maxInnerWidth: _memoMaxInnerWidth * scale,
      widthStep: _memoWidthStep * scale,
    );
    const circlePadding = 11.0;
    const emojiSize = 18.0;
    const spacing = memoSpacing;
    final circleHeight = (circlePadding * 2 + emojiSize) * scale;
    // 常にメモがある時の幅と高さを確保（メモの表示/非表示に関わらず）
    final width = max(baseWidth * scale, memoLayout.outerWidth);
    // memoLayout.height + SizedBoxのspacing + circleHeight + 余裕
    final height = memoLayout.height + (spacing * scale) + circleHeight + (20 * scale);

    // 円マーカーの中心を地図座標に固定
    final circleCenterFromBottom = (circlePadding + emojiSize / 2) * scale;
    final alignmentY = 1.0 - 2.0 * circleCenterFromBottom / height;

    return Marker(
      point: LatLng(post.latitude, post.longitude),
      width: width,
      height: height,
      alignment: Alignment(0, alignmentY),
      child: GestureDetector(
        onTap: () => _showPostDetails(post, canDelete: !isBot),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (showMemo) ...[
              Container(
                padding: EdgeInsets.symmetric(
                  vertical: memoPaddingV * scale,
                  horizontal: memoPaddingH * scale,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12 * scale),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 6 * scale,
                      offset: Offset(0, 2 * scale),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: memoLayout.innerWidth,
                  child: Text(
                    post.displayMessage,
                    softWrap: true,
                    maxLines: 2,
                    overflow: TextOverflow.fade,
                    style: labelStyle,
                  ),
                ),
              ),
              SizedBox(height: spacing * scale),
            ],
            Container(
              decoration: BoxDecoration(
                color: emotion.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 10 * scale,
                    offset: Offset(0, 4 * scale),
                  ),
                ],
              ),
              padding: EdgeInsets.all(circlePadding * scale),
              child: Text(
                emotion.emoji,
                style: TextStyle(fontSize: emojiSize * scale),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Marker _buildUserMarker(LatLng position) {
    const baseSize = 40.0;
    final scale = _markerScaleForZoom(_currentZoom);
    final size = baseSize * scale;
    final borderWidth = 2 * scale.clamp(0.7, 1.0);
    return Marker(
      point: position,
      width: size,
      height: size,
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1E88E5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1E88E5).withValues(alpha: 0.35),
              blurRadius: 16 * scale,
              spreadRadius: 1,
            ),
          ],
          border: Border.all(
            color: Colors.white,
            width: borderWidth,
          ),
        ),
        child: Icon(
          Icons.person_pin_circle,
          color: Colors.white,
          size: 20 * scale.clamp(0.7, 1.0),
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
      _generateBotPostsAround(latLng);
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
    if (points.isNotEmpty) {
      _generateBotPostsAround(points.first);
    }
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

  Future<void> _showPostDetails(EmotionMapPost post,
      {required bool canDelete}) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return _EmotionPostDetailSheet(
          post: post,
          canDelete: canDelete,
          onDelete: canDelete
              ? () {
                  context.read<EmotionMapManager>().removePost(post.id);
                  Navigator.of(context).pop();
                  _showSnack('投稿を削除しました。');
                }
              : null,
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

  String _randomBotMemo(EmotionType emotion) {
    final memos = _botMemosByEmotion[emotion.id];
    if (memos == null || memos.isEmpty) {
      return '${emotion.label}な気分';
    }
    return memos[_random.nextInt(memos.length)];
  }

  void _rotateBotMemoVisibility() {
    if (_botPosts.isEmpty) {
      _updateVisibleMemoIds(<String>{});
      return;
    }
    final targetCount = max(1, (_botPosts.length / 3).round());
    final shuffled = List<EmotionMapPost>.from(_botPosts)..shuffle(_random);
    final nextIds =
        shuffled.take(targetCount).map((post) => post.id).toSet();
    _updateVisibleMemoIds(nextIds);
  }

  void _updateVisibleMemoIds(Set<String> nextIds) {
    if (setEquals(nextIds, _visibleBotMemoIds)) {
      return;
    }
    if (mounted) {
      setState(() {
        _visibleBotMemoIds = nextIds;
      });
    } else {
      _visibleBotMemoIds = nextIds;
    }
  }

  double _markerScaleForZoom(double zoom) {
    const minZoom = 10.0;
    const maxZoom = 18.0;
    const minScale = 0.55;
    const maxScale = 1.0;
    final clampedZoom = zoom.clamp(minZoom, maxZoom);
    final t = (clampedZoom - minZoom) / (maxZoom - minZoom);
    return minScale + (maxScale - minScale) * t;
  }

  _MemoBubbleLayout _resolveMemoBubbleLayout({
    required String text,
    required TextStyle style,
    required double spacing,
    required double paddingVertical,
    required double paddingHorizontal,
    required double minInnerWidth,
    required double maxInnerWidth,
    required double widthStep,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    );
    double innerWidth = minInnerWidth;
    while (true) {
      painter.layout(maxWidth: innerWidth);
      if (!painter.didExceedMaxLines || innerWidth >= maxInnerWidth) {
        final outerWidth = innerWidth + paddingHorizontal * 2;
        final height = spacing + paddingVertical * 2 + painter.height;
        return _MemoBubbleLayout(
          outerWidth: outerWidth,
          innerWidth: innerWidth,
          height: height,
        );
      }
      innerWidth = min(innerWidth + widthStep, maxInnerWidth);
    }
  }

  void _generateBotPostsAround(LatLng origin, {bool force = false}) {
    // Bot投稿は一度生成したら固定（再生成しない）
    if (!force && _botPosts.isNotEmpty) {
      return;
    }
    const botCount = 15;
    const radiusMeters = 2000.0;
    const minSeparationMeters = 120.0;
    final bots = <EmotionMapPost>[];
    final now = DateTime.now();
    var attempts = 0;
    while (bots.length < botCount && attempts < botCount * 20) {
      attempts++;
      final distance = sqrt(_random.nextDouble()) * radiusMeters;
      final bearing = _random.nextDouble() * 2 * pi;
      final position = _offsetBy(origin, distance, bearing);
      final hasNearbyBot = bots.any(
        (existing) =>
            _distanceMeters(
              LatLng(existing.latitude, existing.longitude),
              position,
            ) <
            minSeparationMeters,
      );
      if (hasNearbyBot) {
        continue;
      }
      // 利用可能な感情は「うれしい」と「かなしい」の2種類のみ
      const availableEmotions = [EmotionType.happy, EmotionType.sad];
      final emotion = availableEmotions[_random.nextInt(availableEmotions.length)];
      final ageMinutes = _random.nextInt(6 * 60); // within last 6 hours
      final post = EmotionMapPost(
        id:
            'bot_${now.microsecondsSinceEpoch}_${bots.length}_${_random.nextInt(1 << 16)}',
        emotion: emotion,
        latitude: position.latitude,
        longitude: position.longitude,
        createdAt: now.subtract(Duration(minutes: ageMinutes)),
        message: _randomBotMemo(emotion),
      );
      bots.add(post);
    }
    for (final spot in _botStaticSpots) {
      _populateStaticSpotBots(
        bots: bots,
        spot: spot,
        now: now,
      );
    }
    if (mounted) {
      setState(() {
        _botPosts = bots;
      });
    } else {
      _botPosts = bots;
    }
    _rotateBotMemoVisibility();
  }

  double _distanceMeters(LatLng a, LatLng b) {
    const earthRadius = 6378137.0;
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLon = _degToRad(b.longitude - a.longitude);
    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);
    final h = pow(sin(dLat / 2), 2) +
        cos(lat1) * cos(lat2) * pow(sin(dLon / 2), 2);
    final c = 2 * atan2(sqrt(h), sqrt(1 - h));
    return earthRadius * c;
  }

  LatLng _offsetBy(LatLng origin, double distanceMeters, double bearing) {
    const earthRadius = 6378137.0;
    final latRad = _degToRad(origin.latitude);
    final lonRad = _degToRad(origin.longitude);
    final angular = distanceMeters / earthRadius;
    final nextLat = asin(sin(latRad) * cos(angular) +
        cos(latRad) * sin(angular) * cos(bearing));
    final nextLon = lonRad +
        atan2(
            sin(bearing) * sin(angular) * cos(latRad),
            cos(angular) - sin(latRad) * sin(nextLat));
    return LatLng(_radToDeg(nextLat), _radToDeg(nextLon));
  }

  double _degToRad(double value) => value * pi / 180;
  double _radToDeg(double value) => value * 180 / pi;

  void _populateStaticSpotBots({
    required List<EmotionMapPost> bots,
    required _BotStaticSpot spot,
    required DateTime now,
  }) {
    var generated = 0;
    var attempts = 0;
    while (generated < spot.count && attempts < spot.count * 20) {
      attempts++;
      final distance = sqrt(_random.nextDouble()) * spot.radiusMeters;
      final bearing = _random.nextDouble() * 2 * pi;
      final position = _offsetBy(spot.center, distance, bearing);
      final hasNearby = bots.any(
        (existing) =>
            _distanceMeters(
              LatLng(existing.latitude, existing.longitude),
              position,
            ) <
            40,
      );
      if (hasNearby) continue;
      final emotion =
          _random.nextDouble() < 0.95 ? EmotionType.happy : EmotionType.sad;
      final ageMinutes = _random.nextInt(6 * 60);
      bots.add(
        EmotionMapPost(
          id:
              'bot_static_${spot.id}_${generated}_${now.microsecondsSinceEpoch}_${_random.nextInt(1 << 16)}',
          emotion: emotion,
          latitude: position.latitude,
          longitude: position.longitude,
          createdAt: now.subtract(Duration(minutes: ageMinutes)),
          message: _randomBotMemo(emotion),
        ),
      );
      generated++;
    }
  }
}

class _MemoBubbleLayout {
  const _MemoBubbleLayout({
    required this.outerWidth,
    required this.innerWidth,
    required this.height,
  });

  final double outerWidth;
  final double innerWidth;
  final double height;
}

class _BotStaticSpot {
  const _BotStaticSpot({
    required this.id,
    required this.center,
    required this.radiusMeters,
    required this.count,
  });

  final String id;
  final LatLng center;
  final double radiusMeters;
  final int count;
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
                      children: const [EmotionType.happy, EmotionType.sad].map((emotion) {
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
                      maxLength: 60,
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
    required this.canDelete,
    this.onDelete,
  });

  final EmotionMapPost post;
  final bool canDelete;
  final VoidCallback? onDelete;

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
                if (canDelete)
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
