import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as raw_http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import 'package:branch/api_server_prefs.dart';
import 'package:branch/app_version.dart';
import 'package:branch/auth_flags.dart';
import 'package:branch/auth_session_manager.dart';
import 'package:branch/session_prefs.dart';
import 'package:branch/home.dart';
import 'package:branch/auth_service.dart';
import 'package:branch/cart_provider.dart';

// ---------------------------------------------------------
//  IDLE TIMEOUT WRAPPER (UNCHANGED)
// ---------------------------------------------------------
class IdleTimeoutWrapper extends StatefulWidget {
  final Widget child;
  final Duration timeout;

  const IdleTimeoutWrapper({
    super.key,
    required this.child,
    this.timeout = const Duration(hours: 6),
  });

  @override
  State<IdleTimeoutWrapper> createState() => _IdleTimeoutWrapperState();
}

class _IdleTimeoutWrapperState extends State<IdleTimeoutWrapper>
    with WidgetsBindingObserver {
  Timer? _timer;
  DateTime? _pauseTime;

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(widget.timeout, _logout);
  }

  Future<void> _logout() async {
    await AuthService.logout();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused) {
      _timer?.cancel();
      _pauseTime = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_pauseTime != null) {
        final diff = DateTime.now().difference(_pauseTime!);
        if (diff > widget.timeout) {
          _logout();
        } else {
          _startTimer();
        }
        _pauseTime = null;
      } else {
        _startTimer();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _startTimer(),
      onPointerMove: (_) => _startTimer(),
      onPointerUp: (_) => _startTimer(),
      child: widget.child,
    );
  }
}

class _BranchGeoFence {
  final double latitude;
  final double longitude;
  final int radiusMeters;

  const _BranchGeoFence({
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });
}

// ---------------------------------------------------------
//  PREMIUM LOGIN PAGE + USERNAME-ONLY LOGIN
// ---------------------------------------------------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const String _appVersion = '2.0.0+1';
  static const Duration _loginRequestTimeout = Duration(seconds: 20);
  static const int _loginTimeoutRetryCount = 2;
  static const Set<String> _staffRoles = <String>{
    'waiter',
    'cashier',
    'supervisor',
    'branch',
    'kitchen',
    'delivery',
    'driver',
    'chef',
    'manager',
  };
  static const String _waiterDefaultPassword = '12345';

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(); // username input
  final _branchPinController = TextEditingController();
  final List<TextEditingController> _branchPinDigitControllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _branchPinFocusNodes = List.generate(
    4,
    (_) => FocusNode(),
  );
  final RegExp _branchPinPattern = RegExp(r'^\d{4}$');

  bool _isLoading = false;
  bool _showBranchPinRetryHint = false;
  String? _pinRetryEmail;
  bool _forcePinOnNextLogin = false;
  bool _isCheckingSession = false;

  String get _apiHostActive => apiHostPrimary;

  @override
  void initState() {
    super.initState();
    _isCheckingSession = true;
    _checkExistingSession();
    _showPendingLogoutMessageIfAny();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _branchPinController.dispose();
    for (final controller in _branchPinDigitControllers) {
      controller.dispose();
    }
    for (final focusNode in _branchPinFocusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------
  //  CHECK EXISTING SESSION
  // ---------------------------------------------------------
  Future<void> _checkExistingSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");

    if (token != null) {
      try {
        final res = await raw_http
            .get(
              Uri.parse(
                "https://$_apiHostActive/api/users/me?depth=5&showHiddenFields=true",
              ),
              headers: {"Authorization": "Bearer $token"},
            )
            .timeout(const Duration(seconds: 12));

        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          final user = body is Map<String, dynamic>
              ? (body['user'] ?? body)
              : null;
          if (user is Map<String, dynamic>) {
            if (isForceLoggedOutUser(user)) {
              await clearSessionPreservingFavorites(prefs);
              if (mounted) {
                _showError(
                  "Your session was ended by admin. Please login again.",
                );
                setState(() => _isCheckingSession = false);
              }
              return;
            }

            if (isLoginBlockedUser(user)) {
              await clearSessionPreservingFavorites(prefs);
              if (mounted) {
                _showError(
                  "Login blocked by superadmin. Please contact administrator.",
                );
                setState(() => _isCheckingSession = false);
              }
              return;
            }

            // Store user-level name as a secondary identifier
            final name = user['name'] ?? user['username'];
            if (name != null) {
              await prefs.setString('user_name', name.toString());
            }

            // Ensure login timestamp exists for current session
            if (prefs.getInt('login_time') == null) {
              await prefs.setInt(
                'login_time',
                DateTime.now().millisecondsSinceEpoch,
              );
            }

            final userId =
                user['id']?.toString() ??
                user['_id']?.toString() ??
                user[r'$oid']?.toString();
            if (userId != null && userId.isNotEmpty) {
              await prefs.setString('user_id', userId);
            }

            final role = user['role']?.toString();
            if (role != null && role.isNotEmpty) {
              await prefs.setString('role', role);
            }

            // Extract Branch ID and Name
            dynamic branchRef = user["branch"];
            String? branchId;
            String? branchName;
            if (branchRef is Map) {
              branchId =
                  (branchRef["id"] ?? branchRef["_id"] ?? branchRef["\$oid"])
                      ?.toString();
              branchName = branchRef["name"]?.toString();
            } else {
              branchId = branchRef?.toString();
            }
            if (branchId != null) {
              await prefs.setString('branchId', branchId);
              if (branchName != null) {
                await prefs.setString('branchName', branchName);
              }
            }

            final emp = user['employee'];
            if (emp is Map<String, dynamic>) {
              final empId =
                  emp['id']?.toString() ??
                  emp['_id']?.toString() ??
                  emp[r'$oid']?.toString();
              if (empId != null && empId.isNotEmpty) {
                await prefs.setString('employee_id', empId);
              }

              // Strictly prioritize name from employee collection
              final empName = emp['name']?.toString();
              if (empName != null && empName.isNotEmpty) {
                await prefs.setString('employee_name', empName);
              }

              final empCode =
                  emp['employeeId']?.toString() ??
                  emp['employeeID']?.toString() ??
                  emp['empId']?.toString();
              if (empCode != null && empCode.isNotEmpty) {
                await prefs.setString('employee_code', empCode);
              }
            }
          }

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => IdleTimeoutWrapper(child: const HomePage()),
              ),
            );
          }
          return;
        }
      } catch (_) {}

      await clearSessionPreservingFavorites(prefs);
    }
    if (mounted) {
      setState(() => _isCheckingSession = false);
    }
  }

  // ---------------------------------------------------------
  //  IP ALERT POPUP
  // ---------------------------------------------------------
  Future<void> _showIpAlert(
    String connectionType,
    String deviceIp,
    String branchInfo,
    String? printerIp,
  ) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Verified: $connectionType • $branchInfo",
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------------------------------------------------------
  //  HELPER FUNCTIONS
  // ---------------------------------------------------------
  int _ipToInt(String ip) {
    final p = ip.split('.').map(int.parse).toList();
    return p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3];
  }

  bool _isIpInRange(String deviceIp, String range) {
    final parts = range.split("-");
    if (parts.length != 2) return false;

    final start = _ipToInt(parts[0].trim());
    final end = _ipToInt(parts[1].trim());
    final dev = _ipToInt(deviceIp);

    return dev >= start && dev <= end;
  }

  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('deviceId');
    if (deviceId == null) {
      final random = Random();
      deviceId =
          'dev_${DateTime.now().millisecondsSinceEpoch}_${random.nextInt(999999)}';
      await prefs.setString('deviceId', deviceId);
    }
    return deviceId;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF1A202C),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _showPendingLogoutMessageIfAny() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs
        .getString(AuthSessionManager.pendingLogoutMessageKey)
        ?.trim();
    if (pending == null || pending.isEmpty) return;
    await prefs.remove(AuthSessionManager.pendingLogoutMessageKey);
    if (!mounted) return;

    setState(() {
      _showBranchPinRetryHint = true;
      _forcePinOnNextLogin = true;
      _pinRetryEmail = null;
      _setBranchPinValue('');
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showError(pending);
      _branchPinFocusNodes.first.requestFocus();
    });
  }

  Future<Position?> _tryGetCurrentPositionQuick({
    bool requestPermission = false,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) return lastKnown;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  Future<Position?> _requireLocationForLogin() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError("Enable location services to login.");
        unawaited(Geolocator.openLocationSettings());
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _showError("Location permission is required to login.");
        return null;
      }

      if (permission == LocationPermission.deniedForever) {
        _showError(
          "Location permission is permanently denied. Enable it in app settings.",
        );
        unawaited(Geolocator.openAppSettings());
        return null;
      }

      final pos = await _tryGetCurrentPositionQuick(
        requestPermission: false,
        timeout: const Duration(seconds: 3),
      );
      if (pos == null) {
        _showError("Unable to fetch current location. Please try again.");
      }
      return pos;
    } catch (_) {
      _showError("Unable to verify location. Please try again.");
      return null;
    }
  }

  Future<void> _refreshBranchMetadataInBackground({
    required String token,
    required String branchId,
    String? fallbackBranchName,
  }) async {
    final normalizedToken = token.trim();
    final normalizedBranchId = branchId.trim();
    if (normalizedToken.isEmpty || normalizedBranchId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    String? branchName = fallbackBranchName?.trim();

    try {
      final gRes = await raw_http
          .get(
            Uri.parse(
              "https://$_apiHostActive/api/globals/branch-geo-settings",
            ),
            headers: {
              "Authorization": "Bearer $normalizedToken",
              "Content-Type": "application/json",
            },
          )
          .timeout(const Duration(seconds: 5));

      if (gRes.statusCode == 200) {
        final settings = jsonDecode(gRes.body);
        final locations = settings['locations'] as List?;
        if (locations != null) {
          final branchConfig = locations.firstWhere((loc) {
            final locBranch = loc['branch'];
            String? locBranchId;
            if (locBranch is Map) {
              locBranchId =
                  locBranch['id']?.toString() ??
                  locBranch['_id']?.toString() ??
                  locBranch['\$oid']?.toString();
            } else {
              locBranchId = locBranch?.toString();
            }
            return locBranchId == normalizedBranchId;
          }, orElse: () => null);

          if (branchConfig != null) {
            final branchIpRange = branchConfig['ipAddress']?.toString().trim();
            final printerIp = branchConfig['printerIp']?.toString().trim();
            if (branchIpRange != null && branchIpRange.isNotEmpty) {
              await prefs.setString('branchIp', branchIpRange);
            }
            if (printerIp != null && printerIp.isNotEmpty) {
              await prefs.setString('printerIp', printerIp);
            }

            final configuredLat = _toDoubleOrNull(branchConfig['latitude']);
            final configuredLng = _toDoubleOrNull(branchConfig['longitude']);
            final configuredRadius = _toIntOrNull(branchConfig['radius']);
            if (configuredLat != null && configuredLng != null) {
              await prefs.setDouble('branchLat', configuredLat);
              await prefs.setDouble('branchLng', configuredLng);
              await prefs.setInt('branchRadius', configuredRadius ?? 100);
            }

            final configBranch = branchConfig['branch'];
            if (branchName?.isEmpty ?? true) {
              if (configBranch is Map) {
                branchName = configBranch['name']?.toString().trim();
              }
            }
            if (branchName?.isEmpty ?? true) {
              branchName =
                  branchConfig['branchName']?.toString().trim() ??
                  branchConfig['name']?.toString().trim();
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Background branch global refresh skipped: $e");
    }

    try {
      final bRes = await raw_http
          .get(
            Uri.parse(
              "https://$_apiHostActive/api/branches/$normalizedBranchId",
            ),
            headers: {
              "Authorization": "Bearer $normalizedToken",
              "Content-Type": "application/json",
            },
          )
          .timeout(const Duration(seconds: 5));

      if (bRes.statusCode == 200) {
        final branch = jsonDecode(bRes.body);
        final branchIp = branch['ipAddress']?.toString().trim();
        final printerIp = branch['printerIp']?.toString().trim();
        if (branchIp != null && branchIp.isNotEmpty) {
          await prefs.setString('branchIp', branchIp);
        }
        if (printerIp != null && printerIp.isNotEmpty) {
          await prefs.setString('printerIp', printerIp);
        }
        final fallbackLat =
            _toDoubleOrNull(branch['latitude']) ??
            _toDoubleOrNull(branch['lat']);
        final fallbackLng =
            _toDoubleOrNull(branch['longitude']) ??
            _toDoubleOrNull(branch['lng']);
        final fallbackRadius = _toIntOrNull(branch['radius']);
        if (fallbackLat != null && fallbackLng != null) {
          await prefs.setDouble('branchLat', fallbackLat);
          await prefs.setDouble('branchLng', fallbackLng);
          await prefs.setInt('branchRadius', fallbackRadius ?? 100);
        }

        final fetchedBranchName = branch['name']?.toString().trim();
        if (fetchedBranchName != null && fetchedBranchName.isNotEmpty) {
          branchName = fetchedBranchName;
        }
      }
    } catch (e) {
      debugPrint("Background branch detail refresh skipped: $e");
    }

    if (branchName != null && branchName.isNotEmpty) {
      await prefs.setString('branchName', branchName);
    }
  }

  bool _requiresStrictGeoFence(String normalizedRole) {
    return normalizedRole == 'branch' ||
        normalizedRole == 'waiter' ||
        normalizedRole == 'cashier' ||
        normalizedRole == 'kitchen' ||
        normalizedRole == 'chef' ||
        normalizedRole == 'manager';
  }

  String? _extractRelationshipId(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is num) return value.toString();
    if (value is Map) {
      final idValue = value['id'] ?? value['_id'] ?? value['\$oid'];
      final fromId = _extractRelationshipId(idValue);
      if (fromId != null && fromId.isNotEmpty) return fromId;
    }
    return null;
  }

  _BranchGeoFence? _geoFenceFromValues({
    required dynamic latitude,
    required dynamic longitude,
    required dynamic radius,
  }) {
    final lat = _toDoubleOrNull(latitude);
    final lng = _toDoubleOrNull(longitude);
    if (lat == null || lng == null) return null;
    final parsedRadius = _toIntOrNull(radius) ?? 100;
    final safeRadius = parsedRadius <= 0 ? 100 : parsedRadius;
    return _BranchGeoFence(
      latitude: lat,
      longitude: lng,
      radiusMeters: safeRadius,
    );
  }

  Future<_BranchGeoFence?> _loadBranchGeoFence({
    required String token,
    required String branchId,
    required SharedPreferences prefs,
  }) async {
    final normalizedToken = token.trim();
    final normalizedBranchId = branchId.trim();
    if (normalizedToken.isEmpty || normalizedBranchId.isEmpty) return null;

    Future<void> cacheGeoFence(_BranchGeoFence geo) async {
      await prefs.setDouble('branchLat', geo.latitude);
      await prefs.setDouble('branchLng', geo.longitude);
      await prefs.setInt('branchRadius', geo.radiusMeters);
    }

    try {
      final gRes = await raw_http
          .get(
            Uri.parse(
              "https://$_apiHostActive/api/globals/branch-geo-settings",
            ),
            headers: {
              "Authorization": "Bearer $normalizedToken",
              "Content-Type": "application/json",
            },
          )
          .timeout(const Duration(seconds: 4));

      if (gRes.statusCode == 200) {
        final decoded = jsonDecode(gRes.body);
        List? locations;
        if (decoded is Map) {
          if (decoded['locations'] is List) {
            locations = decoded['locations'] as List;
          } else if (decoded['doc'] is Map &&
              (decoded['doc'] as Map)['locations'] is List) {
            locations = (decoded['doc'] as Map)['locations'] as List;
          }
        }
        if (locations != null) {
          for (final loc in locations) {
            if (loc is! Map) continue;
            final locBranchId = _extractRelationshipId(loc['branch']);
            if (locBranchId != normalizedBranchId) continue;
            final geo = _geoFenceFromValues(
              latitude: loc['latitude'],
              longitude: loc['longitude'],
              radius: loc['radius'],
            );
            if (geo != null) {
              await cacheGeoFence(geo);
              return geo;
            }
            break;
          }
        }
      }
    } catch (e) {
      debugPrint("Geo fence global fetch skipped: $e");
    }

    try {
      final bRes = await raw_http
          .get(
            Uri.parse(
              "https://$_apiHostActive/api/branches/$normalizedBranchId",
            ),
            headers: {
              "Authorization": "Bearer $normalizedToken",
              "Content-Type": "application/json",
            },
          )
          .timeout(const Duration(seconds: 4));

      if (bRes.statusCode == 200) {
        final decoded = jsonDecode(bRes.body);
        Map? branch;
        if (decoded is Map) {
          if (decoded['doc'] is Map) {
            branch = decoded['doc'] as Map;
          } else if (decoded['docs'] is List &&
              (decoded['docs'] as List).isNotEmpty &&
              (decoded['docs'] as List).first is Map) {
            branch = (decoded['docs'] as List).first as Map;
          } else {
            branch = decoded;
          }
        }

        if (branch != null) {
          final geo = _geoFenceFromValues(
            latitude: branch['latitude'] ?? branch['lat'],
            longitude: branch['longitude'] ?? branch['lng'],
            radius: branch['radius'],
          );
          if (geo != null) {
            await cacheGeoFence(geo);
            return geo;
          }
        }
      }
    } catch (e) {
      debugPrint("Geo fence branch fetch skipped: $e");
    }

    final cachedBranchId = prefs.getString('branchId')?.trim();
    if (cachedBranchId == normalizedBranchId) {
      final cachedGeo = _geoFenceFromValues(
        latitude: prefs.getDouble('branchLat'),
        longitude: prefs.getDouble('branchLng'),
        radius: prefs.getInt('branchRadius'),
      );
      if (cachedGeo != null) return cachedGeo;
    }

    return null;
  }

  String _normalizeRetryEmail(String rawInput) {
    final input = rawInput.trim().toLowerCase();
    if (input.isEmpty) return '';
    return input.contains("@") ? input : "$input@bf.com";
  }

  String _extractLoginErrorMessage(
    raw_http.Response response, {
    String fallback = "Invalid credentials",
  }) {
    var errMsg = fallback;
    try {
      final data = jsonDecode(response.body);
      if (data is Map) {
        if (data["errors"] is List && (data["errors"] as List).isNotEmpty) {
          final firstError = (data["errors"] as List).first;
          if (firstError is Map &&
              firstError["message"] != null &&
              firstError["message"].toString().trim().isNotEmpty) {
            errMsg = firstError["message"].toString();
          }
        } else if (data["message"] != null &&
            data["message"].toString().trim().isNotEmpty) {
          errMsg = data["message"].toString();
        }
      }
    } catch (_) {}
    return errMsg;
  }

  bool _isBranchPinFailureError(String message) {
    final normalized = message.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return normalized.contains('branch pin is required') ||
        normalized.contains('send x-branch-pin') ||
        normalized.contains('branch pin must be exactly 4 digits') ||
        normalized.contains('branch pin does not match your assigned branch') ||
        normalized.contains('invalid branch pin') ||
        normalized.contains('branch login pin is not configured correctly');
  }

  bool _isWifiGpsPinValidationError(String message) {
    final normalized = message.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    const keywords = <String>[
      'wifi',
      'wi-fi',
      'gps',
      'location',
      'geo',
      'radius',
      'ip',
      'network',
      'branch pin',
      'branch login pin',
      'outside branch',
    ];
    return keywords.any(normalized.contains);
  }

  bool _isGenericServerFailureMessage(String message) {
    final normalized = message.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return normalized == 'something went wrong.' ||
        normalized == 'something went wrong' ||
        normalized == 'internal server error' ||
        normalized == 'server error';
  }

  String _maskPinForLog(String pin) {
    if (pin.isEmpty) return pin;
    final visibleChars = pin.length >= 2 ? 2 : 1;
    final visible = pin.substring(0, visibleChars);
    final maskedLength = (pin.length - visibleChars).clamp(0, pin.length);
    return '$visible${'*' * maskedLength}';
  }

  Map<String, String> _maskedLoginHeadersForLog(Map<String, String> headers) {
    final sanitized = Map<String, String>.from(headers);
    final pinHeader = sanitized['x-branch-pin'];
    if (pinHeader != null) {
      sanitized['x-branch-pin'] = _maskPinForLog(pinHeader);
    }
    final legacyPinHeader = sanitized['x-branch-code'];
    if (legacyPinHeader != null) {
      sanitized['x-branch-code'] = _maskPinForLog(legacyPinHeader);
    }
    return sanitized;
  }

  void _handleUsernameInputChanged(String value) {
    if (_forcePinOnNextLogin) return;
    if (_pinRetryEmail == null) return;
    final normalized = _normalizeRetryEmail(value);
    if (_pinRetryEmail == normalized) return;
    if (!mounted) return;
    setState(() {
      _pinRetryEmail = null;
      _showBranchPinRetryHint = false;
    });
  }

  Future<String?> _resolveBranchNameForSession({
    required String token,
    required String branchId,
    required SharedPreferences prefs,
  }) async {
    final normalizedBranchId = branchId.trim();
    if (normalizedBranchId.isEmpty) return null;

    final cachedBranchId = prefs.getString('branchId')?.trim();
    final cachedBranchName = prefs.getString('branchName')?.trim();
    if (cachedBranchId == normalizedBranchId &&
        cachedBranchName != null &&
        cachedBranchName.isNotEmpty) {
      return cachedBranchName;
    }

    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      return (cachedBranchName?.isNotEmpty ?? false) ? cachedBranchName : null;
    }

    try {
      final response = await raw_http
          .get(
            Uri.parse(
              "https://$_apiHostActive/api/branches/$normalizedBranchId",
            ),
            headers: {
              "Authorization": "Bearer $normalizedToken",
              "Content-Type": "application/json",
            },
          )
          .timeout(const Duration(seconds: 2));

      if (response.statusCode != 200) {
        return (cachedBranchName?.isNotEmpty ?? false)
            ? cachedBranchName
            : null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return (cachedBranchName?.isNotEmpty ?? false)
            ? cachedBranchName
            : null;
      }

      String? resolvedName = decoded['name']?.toString().trim();
      if (resolvedName == null || resolvedName.isEmpty) {
        final doc = decoded['doc'];
        if (doc is Map) {
          resolvedName = doc['name']?.toString().trim();
        }
      }
      if ((resolvedName == null || resolvedName.isEmpty) &&
          decoded['docs'] is List) {
        final docs = decoded['docs'] as List;
        if (docs.isNotEmpty && docs.first is Map) {
          resolvedName = (docs.first as Map)['name']?.toString().trim();
        }
      }

      if (resolvedName != null && resolvedName.isNotEmpty) {
        return resolvedName;
      }
    } catch (e) {
      debugPrint("Branch name lookup skipped: $e");
    }

    return (cachedBranchName?.isNotEmpty ?? false) ? cachedBranchName : null;
  }

  String _currentBranchPin() =>
      _branchPinDigitControllers.map((controller) => controller.text).join();

  void _syncBranchPinController() {
    final pin = _currentBranchPin();
    _branchPinController.value = _branchPinController.value.copyWith(
      text: pin,
      selection: TextSelection.collapsed(offset: pin.length),
      composing: TextRange.empty,
    );
  }

  void _setBranchPinValue(String pin) {
    final sanitized = pin.replaceAll(RegExp(r'[^0-9]'), '');
    for (var i = 0; i < _branchPinDigitControllers.length; i++) {
      final nextChar = i < sanitized.length ? sanitized[i] : '';
      _branchPinDigitControllers[i].text = nextChar;
    }
    _syncBranchPinController();
  }

  void _handleBranchPinDigitChanged(int index, String value) {
    final sanitized = value.replaceAll(RegExp(r'[^0-9]'), '');
    final digit = sanitized.isEmpty ? '' : sanitized[sanitized.length - 1];
    if (_branchPinDigitControllers[index].text != digit) {
      _branchPinDigitControllers[index].value = TextEditingValue(
        text: digit,
        selection: TextSelection.collapsed(offset: digit.length),
      );
    }

    if (digit.isNotEmpty && index < _branchPinFocusNodes.length - 1) {
      _branchPinFocusNodes[index + 1].requestFocus();
    }

    _syncBranchPinController();

    if (mounted &&
        _currentBranchPin().length == _branchPinDigitControllers.length) {
      FocusScope.of(context).unfocus();
    }

    if (_showBranchPinRetryHint && _currentBranchPin().isNotEmpty && mounted) {
      setState(() => _showBranchPinRetryHint = false);
    }
  }

  KeyEventResult _handleBranchPinKeyEvent(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.backspace &&
        key != LogicalKeyboardKey.delete) {
      return KeyEventResult.ignored;
    }

    final currentController = _branchPinDigitControllers[index];
    final currentText = currentController.text;
    if (currentText.isNotEmpty) {
      // Let TextFormField handle deletion from current box.
      return KeyEventResult.ignored;
    }

    if (index == 0) return KeyEventResult.handled;

    final previousIndex = index - 1;
    final previousController = _branchPinDigitControllers[previousIndex];
    if (previousController.text.isNotEmpty) {
      previousController.clear();
      _syncBranchPinController();
    }
    _branchPinFocusNodes[previousIndex].requestFocus();
    return KeyEventResult.handled;
  }

  double? _toDoubleOrNull(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  int? _toIntOrNull(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) {
      final trimmed = value.trim();
      return int.tryParse(trimmed) ?? double.tryParse(trimmed)?.toInt();
    }
    return null;
  }

  // ---------------------------------------------------------
  //  LOGIN FUNCTION - USERNAME ONLY -> username@bf.com
  // ---------------------------------------------------------
  Future<void> _login() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    if (!_formKey.currentState!.validate()) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final enteredBranchPin = _currentBranchPin().trim();
    if (enteredBranchPin.isEmpty) {
      _showError("Branch PIN is required");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _branchPinFocusNodes.first.requestFocus();
      });
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (!_branchPinPattern.hasMatch(enteredBranchPin)) {
      _showError("Branch PIN must be exactly 4 digits");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _branchPinFocusNodes.first.requestFocus();
      });
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    const resolvedPassword = _waiterDefaultPassword;
    final String branchPin = enteredBranchPin;

    // USERNAME / EMAIL PROCESSING
    String input = _emailController.text.trim();

    // If user typed only username → convert
    String finalEmail = input.contains("@") ? input : "$input@bf.com";

    // Enforce domain
    if (!finalEmail.endsWith("@bf.com")) {
      _showError("Only @bf.com domain allowed");
      setState(() => _isLoading = false);
      return;
    }

    final normalizedRetryEmail = _normalizeRetryEmail(finalEmail);

    setState(() => _showBranchPinRetryHint = false);

    final deviceIpFuture = NetworkInfo().getWifiIP().timeout(
      const Duration(seconds: 2),
      onTimeout: () => null,
    );
    final deviceIdFuture = _getDeviceId();
    final currentPosFuture = _requireLocationForLogin();
    final meta = await Future.wait<dynamic>([
      deviceIpFuture,
      deviceIdFuture,
      currentPosFuture,
    ]);
    final String? deviceIp = meta[0] as String?;
    final String deviceId = meta[1] as String;
    final Position? currentPos = meta[2] as Position?;
    if (currentPos == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final requestHeaders = <String, String>{
      "Content-Type": "application/json",
      "x-device-id": deviceId,
      "x-branch-pin": branchPin,
      "x-branch-code": branchPin,
      if (deviceIp != null) "x-private-ip": deviceIp,
      "x-latitude": currentPos.latitude.toString(),
      "x-longitude": currentPos.longitude.toString(),
      "x-app-version": AppVersion.current,
    };
    final requestBody = <String, dynamic>{
      "email": finalEmail,
      "password": resolvedPassword,
      "branchPin": branchPin,
    };

    Future<raw_http.Response> sendLoginRequest() async {
      await ensureApiHostRoutingReady();

      bool shouldTryNextHostForCredentialFailure(raw_http.Response response) {
        return response.statusCode == 401 || response.statusCode == 403;
      }

      final primaryLoginUri = Uri.parse(
        "https://$_apiHostActive/api/users/login",
      );
      final activeLoginUri = withActiveApiHost(primaryLoginUri);
      final loginUris = <Uri>[];
      final seen = <String>{};

      loginUris.add(activeLoginUri);
      seen.add(activeLoginUri.toString());

      for (final host in getApiHostCandidates(preferredHost: _apiHostActive)) {
        final candidate = primaryLoginUri.replace(host: host);
        final key = candidate.toString();
        if (seen.contains(key)) continue;
        seen.add(key);
        loginUris.add(candidate);
      }

      TimeoutException? lastTimeout;
      SocketException? lastSocketException;
      Object? lastError;
      raw_http.Response? lastCredentialFailureResponse;

      for (final loginUri in loginUris) {
        for (var attempt = 0; attempt <= _loginTimeoutRetryCount; attempt++) {
          try {
            if (attempt > 0 || loginUri != loginUris.first) {
              debugPrint(
                "Retrying login request: host=${loginUri.host}, attempt=${attempt + 1}",
              );
            }
            final response = await raw_http
                .post(
                  loginUri,
                  headers: requestHeaders,
                  body: jsonEncode(requestBody),
                )
                .timeout(_loginRequestTimeout);

            if (response.statusCode == 200) {
              return response;
            }

            final hasMoreHosts = loginUri != loginUris.last;
            if (hasMoreHosts &&
                shouldTryNextHostForCredentialFailure(response)) {
              lastCredentialFailureResponse = response;
              debugPrint(
                "Login credential check failed on host=${loginUri.host}; trying next host candidate.",
              );
              break;
            }

            return response;
          } on TimeoutException catch (e) {
            lastTimeout = e;
            lastError = e;
            if (attempt >= _loginTimeoutRetryCount) break;
          } on SocketException catch (e) {
            lastSocketException = e;
            lastError = e;
            if (attempt >= _loginTimeoutRetryCount) break;
          }
        }
      }

      if (lastCredentialFailureResponse != null) {
        return lastCredentialFailureResponse;
      }
      if (lastTimeout != null) {
        throw TimeoutException(
          "Login request timed out for hosts: "
          "${loginUris.map((uri) => uri.host).join(', ')}",
          _loginRequestTimeout,
        );
      }
      if (lastSocketException != null) {
        throw lastSocketException;
      }
      throw lastError ?? Exception("Login request failed unexpectedly");
    }

    try {
      final response = await sendLoginRequest();

      if (response.statusCode == 200) {
        dynamic data;
        try {
          data = jsonDecode(response.body);
        } catch (e) {
          debugPrint("JSON Decode Error: $e\nBody: ${response.body}");
          _showError(
            "Server returned invalid data. Please check your connection.",
          );
          setState(() => _isLoading = false);
          return;
        }

        final token = data["token"]?.toString() ?? "";
        final user = data["user"];
        final role = user["role"]?.toString() ?? "";
        final normalizedRole = role.trim().toLowerCase();

        // Pre-extract company ID for faster navigation after login
        String? companyId;
        if (normalizedRole == 'company' && user['company'] != null) {
          final comp = user['company'];
          companyId = comp is Map
              ? (comp['id'] ?? comp['_id'] ?? comp[r'$oid'])?.toString()
              : comp.toString();
        } else if ((normalizedRole == 'branch' || normalizedRole == 'waiter' || normalizedRole == 'cashier' || normalizedRole == 'chef' || normalizedRole == 'manager' || normalizedRole == 'supervisor') &&
            user['branch'] != null &&
            user['branch'] is Map &&
            user['branch']['company'] != null) {
          final comp = user['branch']['company'];
          companyId = comp is Map
              ? (comp['id'] ?? comp['_id'] ?? comp[r'$oid'])?.toString()
              : comp.toString();
        }

        if (isForceLoggedOutUser(user)) {
          _showError("Your session was ended by admin. Please try again.");
          setState(() => _isLoading = false);
          return;
        }

        if (isLoginBlockedUser(user)) {
          _showError(
            "Login blocked by superadmin. Please contact administrator.",
          );
          setState(() => _isLoading = false);
          return;
        }
        // Allowed roles
        if (!_staffRoles.contains(normalizedRole)) {
          _showError("Access denied: only branch-related users allowed.");
          setState(() => _isLoading = false);
          return;
        }

        dynamic branchRef =
            user["branch"] ??
            user["activeBranch"] ??
            user["selectedBranch"] ??
            user["loginBranch"] ??
            data["branch"] ??
            data["activeBranch"] ??
            data["selectedBranch"] ??
            data["loginBranch"];
        String? branchId;
        String? branchName;
        if (branchRef is Map) {
          branchId =
              branchRef["id"]?.toString() ??
              branchRef["_id"]?.toString() ??
              (branchRef["\$oid"]?.toString());
          if (branchId == null && branchRef.containsKey("\$oid")) {
            branchId = branchRef["\$oid"]?.toString();
          }
          branchName = branchRef["name"]?.toString();
        } else {
          branchId = branchRef?.toString();
        }
        branchId ??=
            _extractRelationshipId(user["branchId"]) ??
            _extractRelationshipId(user["activeBranchId"]) ??
            _extractRelationshipId(user["selectedBranchId"]) ??
            _extractRelationshipId(user["loginBranchId"]) ??
            _extractRelationshipId(data["branchId"]) ??
            _extractRelationshipId(data["activeBranchId"]) ??
            _extractRelationshipId(data["selectedBranchId"]) ??
            _extractRelationshipId(data["loginBranchId"]);
        branchName ??=
            user["branchName"]?.toString() ??
            user["activeBranchName"]?.toString() ??
            user["selectedBranchName"]?.toString() ??
            user["loginBranchName"]?.toString() ??
            data["branchName"]?.toString() ??
            data["activeBranchName"]?.toString() ??
            data["selectedBranchName"]?.toString() ??
            data["loginBranchName"]?.toString();
        if (branchName?.trim().isEmpty ?? true) {
          branchName = null;
        } else {
          branchName = branchName!.trim();
        }

        final prefs = await SharedPreferences.getInstance();
        if (branchId?.trim().isEmpty ?? true) {
          final cachedBranchId = prefs.getString('branchId')?.trim();
          final cachedBranchName = prefs.getString('branchName')?.trim();
          if (cachedBranchId != null && cachedBranchId.isNotEmpty) {
            branchId = cachedBranchId;
            if ((branchName == null || branchName.isEmpty) &&
                cachedBranchName != null &&
                cachedBranchName.isNotEmpty) {
              branchName = cachedBranchName;
            }
            debugPrint(
              "Login response missing branch id; using cached branch $branchId",
            );
          }
        }
        if (branchId?.trim().isEmpty ?? true) {
          _showError(
            "Branch could not be identified for this login. Please contact admin.",
          );
          setState(() => _isLoading = false);
          return;
        }

        if ((branchName == null || branchName.isEmpty) &&
            branchId != null &&
            branchId.isNotEmpty) {
          branchName = await _resolveBranchNameForSession(
            token: token,
            branchId: branchId,
            prefs: prefs,
          );
        }
        branchName ??= branchId;

        if (_requiresStrictGeoFence(normalizedRole) &&
            branchId != null &&
            branchId.isNotEmpty) {
          final geoFence = await _loadBranchGeoFence(
            token: token,
            branchId: branchId,
            prefs: prefs,
          );
          if (geoFence != null) {
            final distanceMeters = Geolocator.distanceBetween(
              currentPos.latitude,
              currentPos.longitude,
              geoFence.latitude,
              geoFence.longitude,
            );
            if (distanceMeters > geoFence.radiusMeters) {
              _showError(
                "Login denied: You are outside branch range (${distanceMeters.toStringAsFixed(0)}m / ${geoFence.radiusMeters}m).",
              );
              debugPrint(
                "Login denied by strict geofence: role=$normalizedRole, "
                "branchId=$branchId, "
                "distanceMeters=${distanceMeters.toStringAsFixed(2)}, "
                "allowedMeters=${geoFence.radiusMeters}",
              );
              if (mounted) setState(() => _isLoading = false);
              return;
            }
          } else {
            debugPrint(
              "Strict geofence check skipped: no coordinates configured for branchId=$branchId",
            );
          }
        }

        _pinRetryEmail = null;
        _forcePinOnNextLogin = false;

        String? branchIpRange = prefs.getString('branchIp')?.trim();
        if (branchIpRange?.isEmpty ?? true) branchIpRange = null;
        String? printerIp = prefs.getString('printerIp')?.trim();
        if (printerIp?.isEmpty ?? true) printerIp = null;

        if (branchId != null && branchId.isNotEmpty) {
          if (deviceIp != null && branchIpRange != null) {
            final isIpMatch = _isIpInRange(deviceIp, branchIpRange);
            if (isIpMatch) {
              _showIpAlert("WiFi/IP", deviceIp, "Branch IP matched", printerIp);
            }
          }

          unawaited(
            _refreshBranchMetadataInBackground(
              token: data['token']?.toString() ?? '',
              branchId: branchId,
              fallbackBranchName: branchName,
            ),
          );
        }

        // Save the minimum session keys before navigation.
        if (mounted) {
          final cartProvider = Provider.of<CartProvider>(
            context,
            listen: false,
          );
          cartProvider.clearData();
          cartProvider.setBranchId(branchId);
        }
        await Future.wait<bool>([
          prefs.setString("token", token),
          prefs.setString("role", role),
          prefs.setString("email", finalEmail),
          if (branchId != null) prefs.setString("branchId", branchId),
          if (branchName != null) prefs.setString("branchName", branchName),
          if (companyId != null) prefs.setString("company_id", companyId),
        ]);

        final backgroundWrites = <Future<bool>>[
          if (branchIpRange != null) prefs.setString("branchIp", branchIpRange),
          if (deviceIp != null) prefs.setString("lastLoginIp", deviceIp),
          if (printerIp != null) prefs.setString("printerIp", printerIp),
          prefs.setInt('login_time', DateTime.now().millisecondsSinceEpoch),
        ];

        if (user['id'] != null) {
          backgroundWrites.add(
            prefs.setString("user_id", user['id'].toString()),
          );
        }

        // Store user-level name as a secondary identifier.
        final name = user['name'] ?? user['username'];
        if (name != null) {
          backgroundWrites.add(prefs.setString('user_name', name.toString()));
        }

        // Store employee relation info if present.
        final emp = user['employee'];
        if (emp != null) {
          if (emp is Map) {
            final empId =
                emp['id']?.toString() ??
                emp['_id']?.toString() ??
                emp[r'$oid']?.toString();
            if (empId != null) {
              backgroundWrites.add(prefs.setString('employee_id', empId));
            }
            final empName = emp['name']?.toString();
            if (empName != null && empName.isNotEmpty) {
              backgroundWrites.add(prefs.setString('employee_name', empName));
            }
            final empCode =
                emp['employeeId']?.toString() ??
                emp['employeeID']?.toString() ??
                emp['empId']?.toString();
            if (empCode != null && empCode.isNotEmpty) {
              backgroundWrites.add(prefs.setString('employee_code', empCode));
            }
          } else {
            backgroundWrites.add(
              prefs.setString('employee_id', emp.toString()),
            );
          }
        }
        unawaited(Future.wait<bool>(backgroundWrites));

        if (!mounted) return;
        AuthSessionManager.instance.startHeartbeat();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => IdleTimeoutWrapper(
              child: const HomePage(),
            ),
          ),
        );
      } else {
        final errMsg = _extractLoginErrorMessage(response);
        final isBranchPinError = _isBranchPinFailureError(errMsg);
        final isWifiGpsPinValidationError = _isWifiGpsPinValidationError(
          errMsg,
        );
        final shouldSuggestPinRetryForGenericServerError =
            response.statusCode >= 500 &&
            branchPin.isEmpty &&
            _isGenericServerFailureMessage(errMsg);
        final uiErrorMessage = shouldSuggestPinRetryForGenericServerError
            ? "Location sent. Enter your 4-digit Branch PIN and try again."
            : (!isBranchPinError && isWifiGpsPinValidationError)
            ? "Login failed due to WiFi/GPS/PIN validation."
            : errMsg;
        debugPrint(
          "Login request headers (masked): ${jsonEncode(_maskedLoginHeadersForLog(requestHeaders))}",
        );
        debugPrint(
          "Login failed: status=${response.statusCode}, "
          "pinSent=true, "
          "gpsSent=true, "
          "error=$errMsg, "
          "responseBody=${response.body}",
        );

        if (isBranchPinError ||
            isWifiGpsPinValidationError ||
            shouldSuggestPinRetryForGenericServerError ||
            _forcePinOnNextLogin) {
          if (mounted) {
            setState(() {
              _showBranchPinRetryHint = true;
              _pinRetryEmail = normalizedRetryEmail;
            });
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _branchPinFocusNodes.first.requestFocus();
          });
        } else if (!_forcePinOnNextLogin &&
            _pinRetryEmail == normalizedRetryEmail &&
            mounted) {
          setState(() {
            _pinRetryEmail = null;
            _showBranchPinRetryHint = false;
          });
        }
        _showError(uiErrorMessage);
      }
    } on TimeoutException catch (e) {
      _showError(
        "Login request timed out. Please check network and try again.",
      );
      debugPrint(
        "Login timeout: host=${_apiHostActive.trim()}, timeoutSeconds=${_loginRequestTimeout.inSeconds}, error=$e",
      );
      debugPrint(
        "Login request headers (masked): ${jsonEncode(_maskedLoginHeadersForLog(requestHeaders))}",
      );
    } on SocketException catch (e) {
      _showError("Network error: unable to reach server.");
      debugPrint("Login socket error: host=${_apiHostActive.trim()}, error=$e");
      debugPrint(
        "Login request headers (masked): ${jsonEncode(_maskedLoginHeadersForLog(requestHeaders))}",
      );
    } catch (e) {
      _showError("Network error: $e");
      debugPrint(
        "Login request headers (masked): ${jsonEncode(_maskedLoginHeadersForLog(requestHeaders))}",
      );
      debugPrint("Login exception: $e");
    }

    if (mounted) setState(() => _isLoading = false);
  }

  // ---------------------------------------------------------
  //  PREMIUM UI
  // ---------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_isCheckingSession) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1C0908), Color(0xFF4A1A12), Color(0xFF7A2D1C)],
              stops: [0, 0.55, 1],
            ),
          ),
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1C0908), Color(0xFF4A1A12), Color(0xFF7A2D1C)],
            stops: [0, 0.55, 1],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -110,
              left: -60,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF6D365).withValues(alpha: 0.2),
                ),
              ),
            ),
            Positioned(
              bottom: -120,
              right: -80,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFA07A).withValues(alpha: 0.16),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.95, end: 1),
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutCubic,
                      builder: (context, scale, child) {
                        return Transform.scale(scale: scale, child: child);
                      },
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFF8EFE6,
                          ).withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.62),
                            width: 1.4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.22),
                              blurRadius: 30,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'BLACKFOREST CAKES',
                                style: TextStyle(
                                  color: Color(0xFF6A2A1A),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.6,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Branch Login',
                                style: TextStyle(
                                  color: Color(0xFF2E170F),
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Sign in with your username. Location must be enabled. Enter your 4-digit branch PIN.',
                                style: TextStyle(
                                  color: Color(0xFF7B5A49),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Container(
                                  height: 110,
                                  width: double.infinity,
                                  color: const Color(0xFF2D0A0A),
                                  child: Image.asset(
                                    'assets/logo.png',
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Center(
                                        child: Text(
                                          'BLACKFOREST CAKES',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              _premiumInput(
                                controller: _emailController,
                                hint: "Enter your username ...",
                                icon: Icons.person_outline,
                                onChanged: _handleUsernameInputChanged,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return "Enter username";
                                  }

                                  if (v.contains("@") &&
                                      !v.endsWith("@bf.com")) {
                                    return "Only @bf.com domain allowed";
                                  }

                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              _branchPinBoxesInput(),
                              if (_showBranchPinRetryHint)
                                Container(
                                  margin: const EdgeInsets.only(top: 10),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFFFFF1E7,
                                    ).withValues(alpha: 0.92),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFEAB089),
                                      width: 1,
                                    ),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        color: Color(0xFF9A4A23),
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          "Enter your 4-digit branch PIN.",
                                          style: TextStyle(
                                            color: Color(0xFF9A4A23),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 22),
                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: ElevatedButton(
                                  onPressed: () {
                                    if (_isLoading) return;
                                    _login();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2D0A0A),
                                    foregroundColor: Colors.white,
                                    shadowColor: const Color(
                                      0xFF2D0A0A,
                                    ).withValues(alpha: 0.45),
                                    elevation: 8,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 180),
                                    child: _isLoading
                                        ? const Row(
                                            key: ValueKey('login-loading'),
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2.2,
                                                      color: Colors.white,
                                                    ),
                                              ),
                                              SizedBox(width: 10),
                                              Text(
                                                "SIGNING IN...",
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 1.0,
                                                ),
                                              ),
                                            ],
                                          )
                                        : const Text(
                                            key: ValueKey('login-idle'),
                                            "CONTINUE",
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.1,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Center(
                                child: Text(
                                  'Version $_appVersion',
                                  style: const TextStyle(
                                    color: Color(0xFF8A6B59),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _branchPinBoxesInput({Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.pin_outlined, color: Color(0xFF7B513A), size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                "Branch PIN (Required, 4 digits)",
                style: TextStyle(
                  color: Color(0xFF553325),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        const Text(
          "Mandatory for branch/waiter/cashier login",
          style: TextStyle(
            color: Color(0xFF8A6B59),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            const preferredSize = 60.0;
            const minSize = 44.0;
            const preferredGap = 10.0;
            final availableWidth = constraints.maxWidth;

            final computedSize =
                (availableWidth - (preferredGap * 3)) /
                _branchPinDigitControllers.length;
            final boxSize =
                (computedSize.isFinite ? computedSize : preferredSize)
                    .clamp(minSize, preferredSize)
                    .toDouble();

            final computedGap =
                (availableWidth -
                    (boxSize * _branchPinDigitControllers.length)) /
                (_branchPinDigitControllers.length - 1);
            final gap = (computedGap.isFinite ? computedGap : preferredGap)
                .clamp(6.0, preferredGap)
                .toDouble();

            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_branchPinDigitControllers.length, (
                index,
              ) {
                return Padding(
                  padding: EdgeInsets.only(
                    right: index == _branchPinDigitControllers.length - 1
                        ? 0
                        : gap,
                  ),
                  child: _branchPinDigitBox(index, size: boxSize),
                );
              }),
            );
          },
        ),
      ],
    );
  }

  Widget _branchPinDigitBox(int index, {required double size}) {
    return SizedBox(
      width: size,
      height: size,
      child: Focus(
        onKeyEvent: (node, event) => _handleBranchPinKeyEvent(index, event),
        child: TextFormField(
          controller: _branchPinDigitControllers[index],
          focusNode: _branchPinFocusNodes[index],
          keyboardType: TextInputType.number,
          textInputAction: index == _branchPinDigitControllers.length - 1
              ? TextInputAction.done
              : TextInputAction.next,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF3D2217),
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(1),
          ],
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: const Color(0xFFFDF8F2),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(
                color: Color(0xFFD8C3B4),
                width: 1.4,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(
                color: Color(0xFF7A2D1C),
                width: 2.2,
              ),
            ),
          ),
          onChanged: (value) => _handleBranchPinDigitChanged(index, value),
        ),
      ),
    );
  }

  // INPUT FIELD WIDGET
  Widget _premiumInput({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    FormFieldValidator<String>? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFDF8F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD8C3B4), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        validator: validator,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        style: const TextStyle(
          color: Color(0xFF4E3022),
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: const Color(0xFF8A6B59)),
          suffixIcon: suffix,
          hintText: hint,
          hintStyle: const TextStyle(
            color: Color(0xFFB19888),
            fontWeight: FontWeight.w500,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}
