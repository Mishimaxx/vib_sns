import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/encounter.dart';

class EncounterMap extends StatefulWidget {
  const EncounterMap({
    super.key,
    required this.encounters,
    this.onMarkerTap,
  });

  final List<Encounter> encounters;
  final ValueChanged<Encounter>? onMarkerTap;

  @override
  State<EncounterMap> createState() => _EncounterMapState();
}

const LatLng _defaultCenter = LatLng(35.681236, 139.767125);
const double _maxDisplayRadiusMeters = 100;

class _EncounterMapState extends State<EncounterMap> {
  final MapController _mapController = MapController();
  bool _mapReady = false;
  bool _isLocating = false;
  bool _centeredOnUserOnce = false;
  LatLng? _userLocation;

  @override
  void didUpdateWidget(covariant EncounterMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_mapReady && widget.encounters != oldWidget.encounters) {
      _fitToMarkers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final markers = _buildMarkers(context);
    final hasMarkers = markers.isNotEmpty;
    final userLocation = _userLocation;
    final combinedMarkers = <Marker>[
      ...markers,
      if (userLocation != null) _buildUserMarker(context, userLocation),
    ];
    final showMarkers = combinedMarkers.isNotEmpty;
    final initialCenter =
        userLocation ?? (hasMarkers ? markers.first.point : _defaultCenter);
    final initialZoom =
        userLocation != null ? 16.0 : (hasMarkers ? 15.0 : 13.0);
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: initialZoom,
            onMapReady: () {
              _mapReady = true;
              _fitToMarkers();
              _centerOnUser(initial: true);
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.vib_sns',
            ),
            if (showMarkers) MarkerLayer(markers: combinedMarkers),
          ],
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.small(
            heroTag: null,
            onPressed: _isLocating ? null : _centerOnUser,
            child: _isLocating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }

  List<Marker> _buildMarkers(BuildContext context) {
    final theme = Theme.of(context);
    final nearbyEncounters = widget.encounters.where((encounter) {
      final latitude = encounter.latitude;
      final longitude = encounter.longitude;
      if (latitude == null || longitude == null) {
        return false;
      }
      final distance = encounter.displayDistance;
      if (distance != null && distance > _maxDisplayRadiusMeters) {
        return false;
      }
      return true;
    }).toList();
    if (nearbyEncounters.isEmpty) {
      return const [];
    }
    return nearbyEncounters.map((encounter) {
      final latLng = LatLng(encounter.latitude!, encounter.longitude!);
      return Marker(
        point: latLng,
        width: 60,
        height: 60,
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () => widget.onMarkerTap?.call(encounter),
          child: Tooltip(
            message: encounter.profile.displayName,
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.85),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(10),
              child: const Icon(
                Icons.person_pin_circle,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  void _fitToMarkers() {
    final positions = widget.encounters
        .where((encounter) =>
            encounter.latitude != null && encounter.longitude != null)
        .map((encounter) => LatLng(encounter.latitude!, encounter.longitude!))
        .toList();
    if (positions.isEmpty) {
      _mapController.move(_defaultCenter, 13);
      return;
    }
    if (positions.length == 1) {
      _mapController.move(positions.first, 15);
      return;
    }
    final bounds = LatLngBounds.fromPoints(positions);
    final cameraFit = CameraFit.bounds(
      bounds: bounds,
      padding: const EdgeInsets.all(80),
    );
    _mapController.fitCamera(
      cameraFit,
    );
  }

  Future<void> _centerOnUser({bool initial = false}) async {
    if (!_mapReady) return;
    if (_isLocating) return;
    if (initial && _centeredOnUserOnce) return;
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
        if (!initial) {
          _showSnack(
              '\u4f4d\u7f6e\u60c5\u5831\u3078\u306e\u30a2\u30af\u30bb\u30b9\u3092\u8a31\u53ef\u3057\u3066\u304f\u3060\u3055\u3044\u3002');
        }
        return;
      }
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!initial) {
          _showSnack(
              '\u4f4d\u7f6e\u30b5\u30fc\u30d3\u30b9\u3092\u6709\u52b9\u306b\u3057\u3066\u304f\u3060\u3055\u3044\u3002');
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      final latLng = LatLng(position.latitude, position.longitude);
      final currentZoom = _mapController.camera.zoom;
      final targetZoom =
          currentZoom.isNaN || currentZoom < 15 ? 16.0 : currentZoom;
      if (mounted) {
        setState(() {
          _userLocation = latLng;
        });
      }
      _mapController.move(latLng, targetZoom);
      if (initial) {
        _centeredOnUserOnce = true;
      }
    } catch (error) {
      if (!initial) {
        _showSnack(
            '\u73fe\u5728\u5730\u3092\u53d6\u5f97\u3067\u304d\u307e\u305b\u3093\u3067\u3057\u305f\u3002');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  Marker _buildUserMarker(BuildContext context, LatLng position) {
    final theme = Theme.of(context);
    return Marker(
      point: position,
      width: 56,
      height: 56,
      alignment: Alignment.center,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primary,
              theme.colorScheme.primary.withValues(alpha: 0.55),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.35),
              blurRadius: 18,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.primary,
                width: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
