import 'package:flutter/foundation.dart';

import '../models/profile.dart';

class ProfileController extends ChangeNotifier {
  ProfileController({
    required Profile profile,
    required bool needsSetup,
  })  : _profile = profile,
        _needsSetup = needsSetup;

  Profile _profile;
  bool _needsSetup;

  Profile get profile => _profile;
  bool get needsSetup => _needsSetup;

  void updateProfile(Profile profile, {bool? needsSetup}) {
    _profile = profile;
    if (needsSetup != null) {
      _needsSetup = needsSetup;
    }
    notifyListeners();
  }

  void updateStats(
      {int? followersCount, int? followingCount, int? receivedLikes}) {
    final nextFollowers = followersCount ?? _profile.followersCount;
    final nextFollowing = followingCount ?? _profile.followingCount;
    final nextLikes = receivedLikes ?? _profile.receivedLikes;
    if (nextFollowers == _profile.followersCount &&
        nextFollowing == _profile.followingCount &&
        nextLikes == _profile.receivedLikes) {
      return;
    }
    _profile = _profile.copyWith(
      followersCount: nextFollowers,
      followingCount: nextFollowing,
      receivedLikes: nextLikes,
    );
    notifyListeners();
  }
}
