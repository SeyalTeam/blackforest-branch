import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as raw_http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:branch/api_config.dart';
import 'package:branch/session_prefs.dart';
import 'package:branch/app_version.dart';
import 'package:branch/auth_service.dart';

class AuthSessionManager {
  AuthSessionManager._();

  static final AuthSessionManager instance = AuthSessionManager._();
  static const String pendingLogoutMessageKey = 'pendingLogoutMessage';
  static const String defaultSessionExpiredMessage =
      'Session expired. Please login again.';

  static const Duration _heartbeatInterval = Duration(seconds: 45);
  static const Duration _meTimeout = Duration(seconds: 8);
  static const Duration _locationTimeout = Duration(seconds: 6);
  static const Set<String> _strictGeoRoles = <String>{
    'branch',
    'waiter',
    'cashier',
    'kitchen',
    'chef',
    'manager',
  };
  static const double _geoFenceGraceMeters = 12;

  GlobalKey<NavigatorState>? _navigatorKey;
  Timer? _heartbeatTimer;
  bool _isHandlingUnauthorized = false;
  bool _isSessionCheckRunning = false;

  void attachNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  void startHeartbeat() {
    _heartbeatTimer?.cancel();
    unawaited(verifySession(force: true));
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      verifySession(force: true);
    });
  }

  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> verifySession({bool force = false}) async {
    if (_isSessionCheckRunning) return;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null || token.isEmpty) return;

    _isSessionCheckRunning = true;
    try {
      final timeout = force ? _meTimeout : const Duration(seconds: 5);
      final response = await _verifyMe(token: token, timeout: timeout);

      if (response.statusCode == 401 || response.statusCode == 403) {
        await handleUnauthorized(message: defaultSessionExpiredMessage);
        return;
      }

      await _enforceStrictGeoFenceIfNeeded(prefs);
    } catch (_) {
      // Keep current session on transient network failures.
    } finally {
      _isSessionCheckRunning = false;
    }
  }

  Future<raw_http.Response> _verifyMe({
    required String token,
    required Duration timeout,
  }) async {
    final baseUri = Uri.parse("${ApiConfig.baseUrl}/users/me?depth=5&showHiddenFields=true");
    return raw_http
        .get(baseUri, headers: {
          'Authorization': 'Bearer $token',
          'x-app-version': AppVersion.current,
        })
        .timeout(timeout);
  }

  Future<void> _enforceStrictGeoFenceIfNeeded(SharedPreferences prefs) async {
    final normalizedRole = (prefs.getString('role') ?? '').trim().toLowerCase();
    if (!_strictGeoRoles.contains(normalizedRole)) return;

    final branchLat = prefs.getDouble('branchLat');
    final branchLng = prefs.getDouble('branchLng');
    final configuredRadius = prefs.getInt('branchRadius') ?? 100;
    final branchRadius = configuredRadius <= 0 ? 100 : configuredRadius;
    if (branchLat == null || branchLng == null) return;

    final isLocationServiceEnabled =
        await Geolocator.isLocationServiceEnabled();
    if (!isLocationServiceEnabled) {
      await handleUnauthorized(
        message:
            'Session ended: location services are required while logged in.',
      );
      return;
    }

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      await handleUnauthorized(
        message:
            'Session ended: location permission is required while logged in.',
      );
      return;
    }

    Position? position;
    try {
      position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(_locationTimeout);
    } catch (_) {
      return;
    }
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      branchLat,
      branchLng,
    );
    final allowedDistance = branchRadius + _geoFenceGraceMeters;
    if (distance <= allowedDistance) return;

    await handleUnauthorized(
      message:
          'Session ended: you are outside the allowed branch location. Please login again from your branch.',
    );
  }

  Future<void> handleUnauthorized({String? message}) async {
    if (_isHandlingUnauthorized) return;
    _isHandlingUnauthorized = true;

    try {
      final resolvedMessage = (message?.trim().isNotEmpty ?? false)
          ? message!.trim()
          : defaultSessionExpiredMessage;
      stopHeartbeat();
      final prefs = await SharedPreferences.getInstance();
      await clearSessionPreservingFavorites(prefs);
      await prefs.setString(pendingLogoutMessageKey, resolvedMessage);

      final nav = _navigatorKey?.currentState ?? AuthService.navigatorKey.currentState;
      if (nav != null) {
        nav.pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } finally {
      _isHandlingUnauthorized = false;
    }
  }
}
