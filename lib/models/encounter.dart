import 'profile.dart';

class Encounter {
  Encounter({
    required this.id,
    required this.profile,
    required this.encounteredAt,
    required this.beaconId,
    this.message,
    this.unread = true,
    this.liked = false,
    this.gpsDistanceMeters,
    this.bleDistanceMeters,
    this.latitude,
    this.longitude,
  });

  final String id;
  Profile profile;
  final String beaconId;
  DateTime encounteredAt;
  String? message;
  double? gpsDistanceMeters;
  double? bleDistanceMeters;
  double? latitude;
  double? longitude;
  bool unread;
  bool liked;

  double? get displayDistance => bleDistanceMeters ?? gpsDistanceMeters;
  bool get proximityVerified => bleDistanceMeters != null;

  void markRead() {
    unread = false;
  }

  void toggleLiked() {
    liked = !liked;
  }
}
