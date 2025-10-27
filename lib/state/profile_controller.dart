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
}
