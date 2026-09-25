import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'api_config.dart';

class GeofenceResult {
  final bool isInside;
  final Position? position;
  final String? branchName;
  final String? branchId;
  final double? distance;
  final double? radius;
  final String? errorMessage;

  const GeofenceResult({
    required this.isInside,
    this.position,
    this.branchName,
    this.branchId,
    this.distance,
    this.radius,
    this.errorMessage,
  });
}

class GeofenceUtil {
  /// Checks whether the device is inside any branch geofence circle.
  /// Can be called from any background or foreground service without a BuildContext.
  static Future<GeofenceResult> checkLocationAndGeofence({
    Position? existingPosition,
  }) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('GeofenceUtil: Location services are disabled.');
      return const GeofenceResult(
        isInside: false,
        errorMessage: 'Location services are disabled. Please enable GPS.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('GeofenceUtil: Location permissions denied.');
        return const GeofenceResult(
          isInside: false,
          errorMessage: 'Location permissions are denied.',
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('GeofenceUtil: Location permissions permanently denied.');
      return const GeofenceResult(
        isInside: false,
        errorMessage: 'Location permissions are permanently denied.',
      );
    }

    Position? position = existingPosition;
    if (position == null) {
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
          ),
        ).timeout(const Duration(seconds: 6));
      } catch (e) {
        debugPrint(
          'GeofenceUtil getCurrentPosition error: $e. Trying last known...',
        );
        try {
          position = await Geolocator.getLastKnownPosition();
        } catch (_) {}
      }
    }

    if (position == null) {
      debugPrint('GeofenceUtil: Failed to get any GPS position.');
      return const GeofenceResult(
        isInside: false,
        errorMessage: 'Failed to get current GPS location.',
      );
    }

    try {
      final data = await ApiConfig.fetchBranchGeoSettings(prefs.getString('token') ?? '');
      final locations = data['locations'] as List?;
      if (locations != null && locations.isNotEmpty) {
        double nearestDistance = double.infinity;
        double nearestRadius = 100.0;
        String? nearestBranchName;
        String? nearestBranchId;

        for (var loc in locations) {
          final lat = loc['latitude'];
          final lng = loc['longitude'];
          final radiusStr = loc['radius'];
          final radius = (radiusStr is num) ? radiusStr.toDouble() : 100.0;
          // Add 30m indoor GPS drift tolerance
          final effectiveRadius = radius + 30.0;

          if (lat != null && lng != null) {
            final double latD = (lat is num)
                ? lat.toDouble()
                : double.parse(lat.toString());
            final double lngD = (lng is num)
                ? lng.toDouble()
                : double.parse(lng.toString());

            final distance = Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              latD,
              lngD,
            );

            final branchName = loc['name'] ?? loc['branchName'] ?? '';
            final branchId =
                (loc['branch'] is Map ? loc['branch']['id'] : loc['branch'])
                    ?.toString() ??
                loc['branchId']?.toString() ??
                '';

            if (distance < nearestDistance) {
              nearestDistance = distance;
              nearestRadius = effectiveRadius;
              nearestBranchName = branchName;
              nearestBranchId = branchId;
            }

            if (distance <= effectiveRadius) {
              debugPrint(
                'GeofenceUtil: INSIDE branch "$branchName"! distance: ${distance.toStringAsFixed(1)}m <= effective: ${effectiveRadius}m',
              );
              return GeofenceResult(
                isInside: true,
                position: position,
                branchName: branchName,
                branchId: branchId,
                distance: distance,
                radius: effectiveRadius,
              );
            }
          }
        }

        debugPrint(
          'GeofenceUtil: OUTSIDE all branches. Nearest: ${nearestDistance.toStringAsFixed(1)}m (allowed: ${nearestRadius}m)',
        );
        return GeofenceResult(
          isInside: false,
          position: position,
          branchName: nearestBranchName,
          branchId: nearestBranchId,
          distance: nearestDistance,
          radius: nearestRadius,
          errorMessage:
              'Not inside any branch. Nearest is ${nearestDistance.toStringAsFixed(1)}m away.',
        );
      }
    } catch (e) {
      debugPrint('GeofenceUtil API error: $e');
      return GeofenceResult(
        isInside: false,
        position: position,
        errorMessage: 'Geofence API error: $e',
      );
    }

    return GeofenceResult(
      isInside: false,
      position: position,
      errorMessage: 'Unable to verify location against branch circles.',
    );
  }

  /// Backward-compatible check that can accept an optional BuildContext for snackbars.
  static Future<bool> isInsideAnyBranch(
    BuildContext? context, {
    bool silent = false,
    Position? position,
  }) async {
    final result = await checkLocationAndGeofence(existingPosition: position);

    if (!result.isInside && !silent && context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Not inside any branch area.'),
        ),
      );
    }

    return result.isInside;
  }
}
