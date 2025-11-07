import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/emotion_post.dart';
import 'profile_controller.dart';

class EmotionMapManager extends ChangeNotifier {
  EmotionMapManager({required ProfileController profileController})
      : _profileController = profileController {
    _profileController.addListener(_handleProfileChanged);
    _activeProfileId = _profileController.profile.id;
    unawaited(_loadPostsForProfile(_activeProfileId!));
  }

  static const _storageKey = 'emotion_map_posts_v1';

  final ProfileController _profileController;
  final List<EmotionMapPost> _posts = [];
  String? _activeProfileId;
  bool _isLoaded = false;

  List<EmotionMapPost> get posts => List.unmodifiable(_posts);
  bool get isLoaded => _isLoaded;

  Future<void> addPost({
    required EmotionType emotion,
    required double latitude,
    required double longitude,
    String? message,
  }) async {
    final profileId = _activeProfileId;
    if (profileId == null) {
      return;
    }
    final trimmedMessage = message?.trim();
    final post = EmotionMapPost(
      id: const Uuid().v4(),
      emotion: emotion,
      latitude: latitude,
      longitude: longitude,
      createdAt: DateTime.now(),
      message: trimmedMessage?.isEmpty ?? true ? null : trimmedMessage,
    );
    _posts.insert(0, post);
    await _persist();
    notifyListeners();
  }

  Future<void> removePost(String postId) async {
    final index = _posts.indexWhere((element) => element.id == postId);
    if (index == -1) {
      return;
    }
    _posts.removeAt(index);
    await _persist();
    notifyListeners();
  }

  void _handleProfileChanged() {
    final nextProfileId = _profileController.profile.id;
    if (_activeProfileId == nextProfileId) {
      notifyListeners();
      return;
    }
    _activeProfileId = nextProfileId;
    unawaited(_loadPostsForProfile(nextProfileId));
  }

  Future<void> _loadPostsForProfile(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final stored =
        prefs.getStringList('${_storageKey}_$profileId') ?? const <String>[];
    final loaded = <EmotionMapPost>[];
    for (final entry in stored) {
      try {
        final map = jsonDecode(entry) as Map<String, dynamic>;
        final post = EmotionMapPost.fromMap(map);
        if (post != null && post.id.isNotEmpty) {
          loaded.add(post);
        }
      } catch (_) {
        // Ignore malformed entries.
      }
    }
    loaded.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _posts
      ..clear()
      ..addAll(loaded);
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final profileId = _activeProfileId;
    if (profileId == null) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final serialized =
        _posts.map((post) => jsonEncode(post.toMap())).toList(growable: false);
    await prefs.setStringList('${_storageKey}_$profileId', serialized);
  }

  @override
  void dispose() {
    _profileController.removeListener(_handleProfileChanged);
    super.dispose();
  }
}
