import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import 'api_service.dart';

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
  /// Checks whether the device is inside any branch geofence circle,
  /// or specifically inside [targetBranchId] / [targetBranchName] if provided.
  /// Can be called from any background or foreground service without a BuildContext.
  static Future<GeofenceResult> checkLocationAndGeofence({
    Position? existingPosition,
    String? targetBranchId,
    String? targetBranchName,
    List<dynamic>? customBranches,
    Map<String, dynamic>? customGeoSettings,
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
        errorMessage: 'Location permissions are permanently denied. Please enable them in device settings.',
      );
    }

    Position? position = existingPosition;
    if (position == null) {
      // 1. Instant check: Use warm cached position if fresh (< 2 mins old and accurate)
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          final age = DateTime.now().difference(lastKnown.timestamp);
          if (age.inMinutes < 2 && lastKnown.accuracy <= 45.0) {
            position = lastKnown;
            debugPrint('GeofenceUtil: Using fresh lastKnownPosition (${lastKnown.accuracy}m, ${age.inSeconds}s old)');
          }
        }
      } catch (_) {}

      // 2. If no fresh cached position, acquire assisted medium fix (instant indoor fix via WiFi/cell)
      if (position == null) {
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
            ),
          ).timeout(const Duration(milliseconds: 3500));
        } catch (e) {
          debugPrint('GeofenceUtil medium accuracy fix failed/timeout: $e');
          try {
            // 3. Fallback to any last known position before failing
            position = await Geolocator.getLastKnownPosition();
          } catch (_) {}
        }
      }
    }

    if (position == null) {
      debugPrint('GeofenceUtil: Failed to get any GPS position.');
      return const GeofenceResult(
        isInside: false,
        errorMessage: 'Failed to acquire GPS location. Please check signal and try again.',
      );
    }

    debugPrint(
      'GeofenceUtil: Got position (${position.latitude}, ${position.longitude}) with accuracy: ${position.accuracy.toStringAsFixed(1)}m',
    );

    try {
      Map<String, dynamic> data = customGeoSettings ?? {};
      if (data.isEmpty) {
        try {
          data = await ApiService.instance.fetchBranchGeoSettings();
        } catch (_) {
          final prefs = await SharedPreferences.getInstance();
          data = await ApiConfig.fetchBranchGeoSettings(prefs.getString('token') ?? '');
        }
      }

      final List<Map<String, dynamic>> allLocations = [];
      final rawLocations = data['locations'] as List?;
      if (rawLocations != null) {
        for (final loc in rawLocations) {
          if (loc is Map) allLocations.add(Map<String, dynamic>.from(loc));
        }
      }

      if (customBranches != null && customBranches.isNotEmpty) {
        for (final b in customBranches) {
          if (b is! Map) continue;
          final bId = (b['id'] ?? b['_id'])?.toString() ?? '';
          final bName = b['name']?.toString() ?? '';
          final lat = b['latitude'] ?? (b['location'] is Map ? b['location']['latitude'] : null);
          final lng = b['longitude'] ?? (b['location'] is Map ? b['location']['longitude'] : null);
          final radius = b['radius'] ?? (b['location'] is Map ? b['location']['radius'] : 100.0);
          if (lat != null && lng != null) {
            final exists = allLocations.any((loc) {
              final locB = loc['branch'];
              final locBId = (locB is Map ? (locB['id'] ?? locB['_id']) : locB)?.toString() ?? loc['branchId']?.toString();
              return locBId == bId;
            });
            if (!exists) {
              allLocations.add({
                'branch': b,
                'branchId': bId,
                'name': bName,
                'branchName': bName,
                'latitude': lat,
                'longitude': lng,
                'radius': radius,
              });
            }
          }
        }
      }

      final locations = allLocations;
      if (locations.isNotEmpty) {
        double nearestDistance = double.infinity;
        double nearestRadius = 100.0;
        String? nearestBranchName;
        String? nearestBranchId;

        // Collect all branches where the device is currently inside
        final insideBranches = <Map<String, dynamic>>[];

        for (var loc in locations) {
          final lat = loc['latitude'];
          final lng = loc['longitude'];
          final radiusStr = loc['radius'];
          final radius = (radiusStr is num) ? radiusStr.toDouble() : 100.0;
          // Indoor GPS drift tolerance:
          // Concrete roofs, metal structures, and store layout create 20-50m drift.
          // Base tolerance is 60m. If the phone's reported accuracy uncertainty is higher than 30m,
          // safely incorporate the delta (capped to 40m extra) so users inside the building are not rejected.
          final double extraAccuracy = (position.accuracy > 30.0 && position.accuracy <= 100.0)
              ? (position.accuracy - 30.0)
              : 0.0;
          final double effectiveRadius = radius + 60.0 + extraAccuracy;

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
            final branchId = (loc['branch'] is Map ? loc['branch']['id'] : loc['branch'])
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
                'GeofenceUtil: INSIDE branch "$branchName"! distance: ${distance.toStringAsFixed(1)}m <= effective: ${effectiveRadius.toStringAsFixed(1)}m (base: ${radius}m, buffer: ${(effectiveRadius - radius).toStringAsFixed(1)}m)',
              );
              insideBranches.add({
                'branchName': branchName,
                'branchId': branchId,
                'distance': distance,
                'radius': effectiveRadius,
              });
            }
          }
        }

        // If targetBranchId or targetBranchName is specified:
        if (targetBranchId != null && targetBranchId.isNotEmpty) {
          // Check if any of the inside branches matches targetBranchId or name
          final matchedInside = insideBranches.firstWhere(
            (b) {
              final bId = b['branchId']?.toString() ?? '';
              final bName = b['branchName']?.toString() ?? '';
              final idMatch = bId.isNotEmpty && bId.toLowerCase() == targetBranchId.toLowerCase();
              final nameMatch = targetBranchName != null &&
                  targetBranchName.isNotEmpty &&
                  bName.isNotEmpty &&
                  bName.toLowerCase().trim() == targetBranchName.toLowerCase().trim();
              return idMatch || nameMatch;
            },
            orElse: () => {},
          );

          if (matchedInside.isNotEmpty) {
            return GeofenceResult(
              isInside: true,
              position: position,
              branchName: matchedInside['branchName'],
              branchId: matchedInside['branchId'],
              distance: matchedInside['distance'],
              radius: matchedInside['radius'],
            );
          }

          // User is NOT inside the target branch.
          // Check if user is inside a different branch:
          if (insideBranches.isNotEmpty) {
            final actual = insideBranches.first;
            final actualName = actual['branchName'] ?? 'another branch';
            final expName = (targetBranchName != null && targetBranchName.isNotEmpty)
                ? targetBranchName
                : 'assigned branch';
            debugPrint(
              'GeofenceUtil: Inside "$actualName", but expected "$expName"',
            );
            return GeofenceResult(
              isInside: false,
              position: position,
              branchName: actual['branchName'],
              branchId: actual['branchId'],
              distance: actual['distance'],
              radius: actual['radius'],
              errorMessage:
                  'GPS mismatch: You are at "$actualName", but this login is assigned to "$expName".',
            );
          }
        } else if (insideBranches.isNotEmpty) {
          // No specific target branch required, inside at least one branch
          final first = insideBranches.first;
          return GeofenceResult(
            isInside: true,
            position: position,
            branchName: first['branchName'],
            branchId: first['branchId'],
            distance: first['distance'],
            radius: first['radius'],
          );
        }

        final nearestDisplay = (nearestBranchName != null && nearestBranchName.isNotEmpty)
            ? nearestBranchName
            : 'branch';
        debugPrint(
          'GeofenceUtil: OUTSIDE all branches. Nearest: ${nearestDistance.toStringAsFixed(1)}m (allowed: ${nearestRadius.toStringAsFixed(1)}m)',
        );
        return GeofenceResult(
          isInside: false,
          position: position,
          branchName: nearestBranchName,
          branchId: nearestBranchId,
          distance: nearestDistance,
          radius: nearestRadius,
          errorMessage:
              'Not inside any branch geofence. Nearest is $nearestDisplay (${nearestDistance.toStringAsFixed(0)}m away).',
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
    String? targetBranchId,
    String? targetBranchName,
  }) async {
    final result = await checkLocationAndGeofence(
      existingPosition: position,
      targetBranchId: targetBranchId,
      targetBranchName: targetBranchName,
    );

    if (!result.isInside && !silent && context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Not inside branch geofence area.'),
          backgroundColor: Colors.red[800],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ),
      );
    }

    return result.isInside;
  }
}
