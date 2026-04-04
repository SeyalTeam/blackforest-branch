import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:branch/api_config.dart';
import 'package:branch/home.dart'; // ADDED
import 'package:branch/auth_service.dart'; // ADDED
import 'package:network_info_plus/network_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';

// ---------------------------------------------------------
// IDLE TIMEOUT WRAPPER (UNCHANGED)
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
  _IdleTimeoutWrapperState createState() => _IdleTimeoutWrapperState();
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

// ---------------------------------------------------------
// PREMIUM LOGIN PAGE + USERNAME-ONLY LOGIN
// ---------------------------------------------------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(); // username only
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isCheckingSession =
      false; // NEW: Track initial session check to prevent flash

  @override
  void initState() {
    super.initState();
    _isCheckingSession = true; // NEW: Start with checking state
    _checkExistingSession();
  }

  // ---------------------------------------------------------
  // CHECK EXISTING SESSION
  // ---------------------------------------------------------
  Future<void> _checkExistingSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");

    if (token != null) {
      try {
        final res = await http
            .get(
              Uri.parse(
                "${ApiConfig.baseUrl}/users/me?depth=5&showHiddenFields=true",
              ),
              headers: ApiConfig.getHeaders(token),
            )
            .timeout(const Duration(seconds: 12));

        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          final user = body is Map<String, dynamic>
              ? (body['user'] ?? body)
              : null;

          if (user is Map<String, dynamic>) {
            if (_isForceLoggedOutUser(user)) {
              await prefs.clear();
              if (mounted) {
                _showError(
                  "Your session was ended by admin. Please login again.",
                );
                setState(() => _isCheckingSession = false);
              }
              return;
            }

            if (_isLoginBlockedUser(user)) {
              await prefs.clear();
              if (mounted) {
                _showError(
                  "Login blocked by superadmin. Please contact administrator.",
                );
                setState(() => _isCheckingSession = false);
              }
              return;
            }

            final role = user['role']?.toString();
            if (role != null && role.isNotEmpty) {
              await prefs.setString('role', role);
            }

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

            final name = user['name'] ?? user['username'];
            if (name != null) {
              final normalizedName = name.toString();
              await prefs.setString('user_name', normalizedName);
              await prefs.setString('username', normalizedName);
            }

            dynamic branchRef = user["branch"];
            String? branchId;
            String? branchName;
            if (branchRef is Map) {
              branchId =
                  branchRef["id"]?.toString() ??
                  branchRef["_id"]?.toString() ??
                  branchRef[r'$oid']?.toString();
              branchName = branchRef["name"]?.toString();
            } else {
              branchId = branchRef?.toString();
            }
            if (branchId != null && branchId.isNotEmpty) {
              await prefs.setString('branchId', branchId);
            }
            if (branchName != null && branchName.isNotEmpty) {
              await prefs.setString('branchName', branchName);
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

      await prefs.clear();
    }

    if (mounted) {
      setState(() => _isCheckingSession = false);
    }
  }

  // ---------------------------------------------------------
  // IP / CONNECTION ALERT POPUP
  // ---------------------------------------------------------
  Future<void> _showIpAlert(
    String connectionType,
    String deviceIp,
    String branchInfo,
    String? printerIp,
  ) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Verification Success"),
        content: Text(
          "Internet: $connectionType\nDevice IP: $deviceIp\n$branchInfo\nPrinter IP: ${printerIp ?? 'Not Set'}",
        ),
        actions: [
          TextButton(
            child: const Text("OK"),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // HELPER FUNCTIONS
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

  void _showError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.black));
  }

  bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' ||
          normalized == '1' ||
          normalized == 'yes' ||
          normalized == 'y' ||
          normalized == 'on';
    }
    return false;
  }

  bool _isLoginBlockedUser(dynamic user) {
    if (user is! Map) return false;
    return _toBool(user['loginBlocked']) || _toBool(user['loginblocked']);
  }

  bool _isForceLoggedOutUser(dynamic user) {
    if (user is! Map) return false;
    const forceLogoutKeys = [
      'forceLogoutAllDevices',
      'forceLogout',
      'forcelogout',
      'forceLogoutAll',
      'forcelogot',
    ];
    for (final key in forceLogoutKeys) {
      if (_toBool(user[key])) return true;
    }
    return false;
  }

  Future<bool> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showError('Location services are disabled.');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showError('Location permissions are denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showError(
        'Location permissions are permanently denied. Please enable in settings.',
      );
      return false;
    }

    return true;
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

  // ---------------------------------------------------------
  // LOGIN FUNCTION - USERNAME ONLY → username@bf.com (MODIFIED FOR BRANCH NAME HANDLING)
  // ---------------------------------------------------------
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final info = NetworkInfo();
    String? deviceIp = await info.getWifiIP();

    final connectivityResults = await Connectivity().checkConnectivity();
    bool isWifi = connectivityResults.contains(ConnectivityResult.wifi);
    bool isMobile = connectivityResults.contains(ConnectivityResult.mobile);
    if (!isWifi && !isMobile && deviceIp != null) {
      isWifi = true;
    }

    String input = _emailController.text.trim();
    String finalEmail = input.contains("@") ? input : "$input@bf.com";

    if (!finalEmail.endsWith("@bf.com")) {
      _showError("Only @bf.com domain allowed");
      setState(() => _isLoading = false);
      return;
    }

    final deviceId = await _getDeviceId();

    if (!await _checkLocationPermission()) {
      setState(() => _isLoading = false);
      return;
    }

    late final Position currentPos;
    try {
      currentPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (e) {
      _showError("Unable to verify location: $e");
      setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await http.post(
        Uri.parse("${ApiConfig.baseUrl}/users/login"),
        headers: {
          ...ApiConfig.getHeaders(null),
          "x-device-id": deviceId,
          if (deviceIp != null) "x-private-ip": deviceIp,
          "x-latitude": currentPos.latitude.toString(),
          "x-longitude": currentPos.longitude.toString(),
        },
        body: jsonEncode({
          "email": finalEmail,
          "password": _passwordController.text,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final user = data["user"];
        final role = user["role"];

        if (_isForceLoggedOutUser(user)) {
          _showError("Your session was ended by admin. Please try again.");
          setState(() => _isLoading = false);
          return;
        }

        if (_isLoginBlockedUser(user)) {
          _showError(
            "Login blocked by superadmin. Please contact administrator.",
          );
          setState(() => _isLoading = false);
          return;
        }

        const allowedRoles = ["branch", "kitchen", "cashier", "waiter"];
        if (!allowedRoles.contains(role)) {
          _showError("Access denied: only branch-related users allowed.");
          setState(() => _isLoading = false);
          return;
        }

        dynamic branchRef = user["branch"];
        String? branchId;
        String? branchName;
        if (branchRef is Map) {
          branchId =
              branchRef["id"]?.toString() ??
              branchRef["_id"]?.toString() ??
              branchRef[r'$oid']?.toString();
          branchName = branchRef["name"]?.toString();
        } else {
          branchId = branchRef?.toString();
        }

        if (branchId == null && role == "waiter") {
          try {
            final gRes = await http.get(
              Uri.parse("${ApiConfig.baseUrl}/globals/branch-geo-settings"),
              headers: ApiConfig.getHeaders(data['token']),
            );

            if (gRes.statusCode == 200) {
              final settings = jsonDecode(gRes.body);
              final locations = settings['locations'] as List?;
              if (locations != null) {
                if (deviceIp != null) {
                  final dynamic ipMatchLoc = locations.firstWhere((loc) {
                    final locIp = loc['ipAddress']?.toString().trim();
                    return locIp != null &&
                        locIp.isNotEmpty &&
                        _isIpInRange(deviceIp, locIp);
                  }, orElse: () => null);

                  if (ipMatchLoc != null) {
                    final locBranch = ipMatchLoc['branch'];
                    if (locBranch is Map) {
                      branchId =
                          (locBranch['id'] ??
                                  locBranch['_id'] ??
                                  locBranch[r'$oid'])
                              ?.toString();
                      branchName = locBranch['name']?.toString();
                    } else {
                      branchId = locBranch?.toString();
                    }
                  }
                }

                if (branchId == null) {
                  final dynamic geoMatchLoc = locations.firstWhere((loc) {
                    final lat2 = loc['latitude'] != null
                        ? (loc['latitude'] as num).toDouble()
                        : null;
                    final lng2 = loc['longitude'] != null
                        ? (loc['longitude'] as num).toDouble()
                        : null;
                    final radius = loc['radius'] != null
                        ? (loc['radius'] as num).toInt()
                        : 100;

                    if (lat2 != null && lng2 != null) {
                      final dist = Geolocator.distanceBetween(
                        currentPos.latitude,
                        currentPos.longitude,
                        lat2,
                        lng2,
                      );
                      return dist <= radius;
                    }
                    return false;
                  }, orElse: () => null);

                  if (geoMatchLoc != null) {
                    final locBranch = geoMatchLoc['branch'];
                    if (locBranch is Map) {
                      branchId =
                          (locBranch['id'] ??
                                  locBranch['_id'] ??
                                  locBranch[r'$oid'])
                              ?.toString();
                      branchName = locBranch['name']?.toString();
                    } else {
                      branchId = locBranch?.toString();
                    }
                  }
                }
              }
            }
          } catch (_) {}
        }

        String? branchIpRange;
        String? printerIp;
        double? branchLat;
        double? branchLng;
        int? branchRadius;

        if (branchId == null || branchId.isEmpty) {
          _showError("Access Denied: Unable to identify branch");
          setState(() => _isLoading = false);
          return;
        }

        try {
          final gRes = await http.get(
            Uri.parse("${ApiConfig.baseUrl}/globals/branch-geo-settings"),
            headers: ApiConfig.getHeaders(data['token']),
          );
          if (gRes.statusCode == 200) {
            final settings = jsonDecode(gRes.body);
            final locations = settings['locations'] as List?;
            if (locations != null) {
              final dynamic branchConfig = locations.firstWhere((loc) {
                final locBranch = loc['branch'];
                String? locBranchId;
                if (locBranch is Map) {
                  locBranchId =
                      locBranch['id']?.toString() ??
                      locBranch['_id']?.toString() ??
                      locBranch[r'$oid']?.toString();
                } else {
                  locBranchId = locBranch?.toString();
                }
                return locBranchId == branchId;
              }, orElse: () => null);

              if (branchConfig != null) {
                branchIpRange = branchConfig['ipAddress']?.toString().trim();
                printerIp = branchConfig['printerIp']?.toString().trim();
                branchLat = (branchConfig['latitude'] as num?)?.toDouble();
                branchLng = (branchConfig['longitude'] as num?)?.toDouble();
                branchRadius = (branchConfig['radius'] as num?)?.toInt();

                final configBranch = branchConfig['branch'];
                if ((branchName?.trim().isEmpty ?? true) &&
                    configBranch is Map) {
                  branchName = configBranch['name']?.toString();
                }
                if (branchName?.trim().isEmpty ?? true) {
                  branchName =
                      branchConfig['branchName']?.toString() ??
                      branchConfig['name']?.toString();
                }

                final configPrefs = await SharedPreferences.getInstance();
                if (branchLat != null) {
                  await configPrefs.setDouble('branchLat', branchLat);
                }
                if (branchLng != null) {
                  await configPrefs.setDouble('branchLng', branchLng);
                }
                if (branchRadius != null) {
                  await configPrefs.setInt('branchRadius', branchRadius);
                }
              }
            }
          }
        } catch (_) {}

        final shouldFetchBranchDetails =
            branchIpRange == null ||
            branchIpRange.isEmpty ||
            (branchName?.trim().isEmpty ?? true);
        if (shouldFetchBranchDetails) {
          final bRes = await http.get(
            Uri.parse("${ApiConfig.baseUrl}/branches/$branchId"),
            headers: ApiConfig.getHeaders(data['token']),
          );

          if (bRes.statusCode == 200) {
            final branch = jsonDecode(bRes.body);
            if (branchIpRange == null || branchIpRange.isEmpty) {
              branchIpRange = branch["ipAddress"]?.toString().trim();
            }
            if (printerIp == null || printerIp.isEmpty) {
              printerIp = branch["printerIp"]?.toString().trim();
            }
            final fetchedBranchName = branch["name"]?.toString();
            if (fetchedBranchName != null &&
                fetchedBranchName.trim().isNotEmpty) {
              branchName = fetchedBranchName;
            }
          }
        }

        final locationPrefs = await SharedPreferences.getInstance();
        branchLat ??= locationPrefs.getDouble('branchLat');
        branchLng ??= locationPrefs.getDouble('branchLng');
        branchRadius ??= locationPrefs.getInt('branchRadius');
        final hasIpRule = branchIpRange != null && branchIpRange.isNotEmpty;
        final hasGeoRule =
            branchLat != null &&
            branchLng != null &&
            branchRadius != null &&
            branchRadius > 0;

        final bool ipMatched =
            hasIpRule &&
            deviceIp != null &&
            _isIpInRange(deviceIp, branchIpRange);

        double? distance;
        bool geoMatched = false;
        if (hasGeoRule) {
          distance = Geolocator.distanceBetween(
            currentPos.latitude,
            currentPos.longitude,
            branchLat,
            branchLng,
          );
          geoMatched = distance <= branchRadius;
        }

        if (!ipMatched && !geoMatched) {
          String reason = "Access Denied: Branch verification failed";
          if (hasGeoRule && distance != null) {
            reason =
                "Access Denied: You are ${distance.toStringAsFixed(0)}m away from branch";
          } else if (hasIpRule) {
            reason = "Access Denied: Outside Branch IP Range";
          } else if (!hasGeoRule && !hasIpRule) {
            reason = "Access Denied: Branch IP/Location rules not configured";
          }
          _showError(reason);
          setState(() => _isLoading = false);
          return;
        }

        final String connectionType = ipMatched && geoMatched
            ? (isWifi ? "WiFi (IP + GPS Match)" : "Mobile (IP + GPS Match)")
            : ipMatched
            ? (isWifi ? "WiFi (IP Match)" : "Mobile (IP Match)")
            : (isWifi ? "WiFi (GPS Match)" : "Mobile (GPS Match)");

        final String branchInfo = distance != null
            ? (ipMatched
                  ? "IP matched • Distance: ${distance.toStringAsFixed(1)}m"
                  : "Distance: ${distance.toStringAsFixed(1)}m")
            : "IP matched";

        await _showIpAlert(
          connectionType,
          deviceIp ?? "Unknown",
          branchInfo,
          printerIp,
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("token", data["token"]);
        await prefs.setString("role", role);
        await prefs.setString("email", finalEmail);
        await prefs.setString("branchId", branchId);
        if (branchName != null && branchName.isNotEmpty) {
          await prefs.setString("branchName", branchName);
        }
        if (deviceIp != null) {
          await prefs.setString("lastLoginIp", deviceIp);
        }
        if (printerIp != null) await prefs.setString("printerIp", printerIp);
        if (user['id'] != null) {
          await prefs.setString("user_id", user['id'].toString());
        }

        final name = user['name'] ?? user['username'];
        if (name != null) {
          final normalizedName = name.toString();
          await prefs.setString('user_name', normalizedName);
          await prefs.setString('username', normalizedName);
        }

        await prefs.setInt('login_time', DateTime.now().millisecondsSinceEpoch);

        final emp = user['employee'];
        if (emp != null) {
          if (emp is Map) {
            final empId =
                emp['id']?.toString() ??
                emp['_id']?.toString() ??
                emp[r'$oid']?.toString();
            if (empId != null) {
              await prefs.setString('employee_id', empId);
            }

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
          } else {
            await prefs.setString('employee_id', emp.toString());
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
      } else {
        String errMsg = "Invalid credentials";
        try {
          final data = jsonDecode(response.body);
          if (data["errors"] != null &&
              data["errors"] is List &&
              data["errors"].isNotEmpty) {
            errMsg = data["errors"][0]["message"] ?? errMsg;
          } else if (data["message"] != null) {
            errMsg = data["message"];
          }
        } catch (_) {}
        _showError(errMsg);
      }
    } catch (_) {
      _showError("Network error: Check your internet");
    }

    if (mounted) setState(() => _isLoading = false);
  }

  // ---------------------------------------------------------
  // PREMIUM UI (UNCHANGED)
  // ---------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    // NEW: Show loading spinner while checking session to avoid flash
    if (_isCheckingSession) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.black, Color(0xFF1E1E1E)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      );
    }

    // Original UI when not checking
    return Scaffold(
      body: Stack(
        children: [
          // BG gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.black, Color(0xFF1E1E1E)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 380,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.45),
                    blurRadius: 22,
                    spreadRadius: 5,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Welcome Team",
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Login to Continue",
                      style: TextStyle(fontSize: 18, color: Colors.white70),
                    ),
                    const SizedBox(height: 30),
                    // USERNAME FIELD
                    _premiumInput(
                      controller: _emailController,
                      hint: "Username",
                      icon: Icons.person,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return "Enter username";
                        }
                        if (v.contains("@") && !v.endsWith("@bf.com")) {
                          return "Only @bf.com email allowed";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 15),
                    // PASSWORD FIELD
                    _premiumInput(
                      controller: _passwordController,
                      hint: "Password",
                      icon: Icons.lock,
                      obscure: _obscurePassword,
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.white,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                      validator: (v) => v!.isEmpty ? "Enter password" : null,
                    ),
                    const SizedBox(height: 25),
                    // LOGIN BUTTON
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          elevation: 10,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.black,
                              )
                            : const Text(
                                "Login",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // INPUT WIDGET
  Widget _premiumInput({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    FormFieldValidator<String>? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white30),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        validator: validator,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.white),
          suffixIcon: suffix,
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white60),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 15,
          ),
        ),
      ),
    );
  }
}
