import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/timeline_post.dart';
import 'profile_controller.dart';

class TimelineManager extends ChangeNotifier {
  TimelineManager({required ProfileController profileController})
      : _profileController = profileController {
    _profileController.addListener(_handleProfileChanged);
    _loadPosts();
  }

  static const _storageKey = 'timeline_posts_v1';

  final ProfileController _profileController;
  final List<TimelinePost> _posts = [];
  bool _isLoaded = false;

  List<TimelinePost> get posts => List.unmodifiable(_posts);
  bool get isLoaded => _isLoaded;

  ProfileController get profileController => _profileController;

  Future<void> addPost({
    required String caption,
    Uint8List? imageBytes,
  }) async {
    final profile = _profileController.profile;
    final encodedImage = imageBytes != null && imageBytes.isNotEmpty
        ? base64Encode(imageBytes)
        : null;
    final post = TimelinePost(
      id: const Uuid().v4(),
      authorName: profile.displayName.isEmpty
          ? '\u3042\u306a\u305f'
          : profile.displayName,
      authorColorValue: profile.avatarColor.toARGB32(),
      caption: caption.trim(),
      createdAt: DateTime.now(),
      imageBase64: encodedImage,
      likeCount: 0,
      isLiked: false,
    );
    _posts.insert(0, post);
    await _persist();
    notifyListeners();
  }

  Future<void> toggleLike(String postId) async {
    final index = _posts.indexWhere((post) => post.id == postId);
    if (index == -1) {
      return;
    }
    final post = _posts[index];
    if (post.isLiked) {
      post.isLiked = false;
      if (post.likeCount > 0) {
        post.likeCount -= 1;
      }
    } else {
      post.isLiked = true;
      post.likeCount += 1;
    }
    await _persist();
    notifyListeners();
  }

  @override
  void dispose() {
    _profileController.removeListener(_handleProfileChanged);
    super.dispose();
  }

  void _handleProfileChanged() {
    notifyListeners();
  }

  Future<void> _loadPosts() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_storageKey) ?? const <String>[];
    final loaded = <TimelinePost>[];
    for (final entry in stored) {
      try {
        final map = jsonDecode(entry) as Map<String, dynamic>;
        final post = TimelinePost.fromMap(map);
        if (post != null) {
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
    final prefs = await SharedPreferences.getInstance();
    final serialized =
        _posts.map((post) => jsonEncode(post.toMap())).toList(growable: false);
    await prefs.setStringList(_storageKey, serialized);
  }
}
