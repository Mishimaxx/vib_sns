import '../models/profile.dart';

class ProfileInteractionSnapshot {
  ProfileInteractionSnapshot({
    required this.receivedLikes,
    required this.followersCount,
    required this.followingCount,
    required this.isLikedByViewer,
    required this.isFollowedByViewer,
  });

  final int receivedLikes;
  final int followersCount;
  final int followingCount;
  final bool isLikedByViewer;
  final bool isFollowedByViewer;
}

class ProfileFollowSnapshot {
  ProfileFollowSnapshot({
    required this.profile,
    required this.isFollowedByViewer,
    this.followedAt,
  });

  final Profile profile;
  final bool isFollowedByViewer;
  final DateTime? followedAt;
}

class ProfileLikeSnapshot {
  ProfileLikeSnapshot({
    required this.profile,
    required this.isFollowedByViewer,
    this.likedAt,
  });

  final Profile profile;
  final bool isFollowedByViewer;
  final DateTime? likedAt;
}

abstract class ProfileInteractionService {
  Future<void> bootstrapProfile(Profile profile);

  Stream<ProfileInteractionSnapshot> watchProfile({
    required String targetId,
    required String viewerId,
  });

  Stream<List<ProfileFollowSnapshot>> watchFollowers({
    required String targetId,
    required String viewerId,
  });

  Stream<List<ProfileFollowSnapshot>> watchFollowing({
    required String targetId,
    required String viewerId,
  });

  Stream<List<ProfileLikeSnapshot>> watchLikes({
    required String targetId,
    required String viewerId,
  });

  Future<void> setLike({
    required String targetId,
    required Profile viewerProfile,
    required bool like,
  });

  Future<void> setFollow({
    required String targetId,
    required String viewerId,
    required bool follow,
  });

  Future<Profile?> loadProfile(String profileId);

  Future<void> dispose();
}
