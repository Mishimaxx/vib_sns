import '../models/profile.dart';

class StreetPassEncounterData {
  StreetPassEncounterData({
    required this.remoteId,
    required this.profile,
    required this.beaconId,
    required this.encounteredAt,
    required this.gpsDistanceMeters,
    this.message,
  });

  final String remoteId;
  final Profile profile;
  final String beaconId;
  final DateTime encounteredAt;
  final double gpsDistanceMeters;
  final String? message;
}

abstract class StreetPassService {
  Stream<StreetPassEncounterData> get encounterStream;

  Future<void> start(Profile localProfile);
  Future<void> stop();
  Future<void> dispose();
}

class StreetPassException implements Exception {
  StreetPassException(this.message);

  final String message;

  @override
  String toString() => 'StreetPassException: $message';
}

class StreetPassPermissionDenied extends StreetPassException {
  StreetPassPermissionDenied(super.message);
}
