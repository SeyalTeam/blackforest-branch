import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:branch/app_http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'auth_service.dart';
import 'home.dart';
import 'package:geolocator/geolocator.dart';
import 'geofence_util.dart';
import 'geo_settings_manager.dart';

// ---------------------------------------------------------
//  IDLE TIMEOUT WRAPPER
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

// ---------------------------------------------------------
//  BRANCH LOGIN PAGE (Branch PIN Based Authentication)
// ---------------------------------------------------------
enum PinLocationStatus {
  idle,
  checking,
  verifiedInside,
  outsideBranch,
  invalidPin,
  gpsError,
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _branchPinController = TextEditingController();
  final List<TextEditingController> _branchPinDigitControllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _branchPinFocusNodes = List.generate(
    4,
    (_) => FocusNode(),
  );
  final RegExp _branchPinPattern = RegExp(r'^\d{4}$');

  PinLocationStatus _pinLocationStatus = PinLocationStatus.idle;
  String? _pinLocationMessage;
  Map<String, dynamic>? _matchedBranchForPin;
  double? _pinBranchDistance;
  String? _pinBranchName;
  int _locationCheckRequestId = 0;
  List<dynamic> _cachedBranchesList = [];
  Map<String, dynamic> _cachedGeoSettings = {};

  final TextEditingController _passwordController = TextEditingController();
  bool _useCustomPassword = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isCheckingSession = true;
  String? _privateIp;
  bool _isIpAuthorized = true;
  List<String> _dynamicAllowedRanges = [];

  static const List<String> _allowedIpRanges = [
    '157.51.21.130-157.51.21.250',
    '157.51.32.24-157.51.32.78',
  ];

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
    _initializeAuth();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _branchPinController.dispose();
    for (final c in _branchPinDigitControllers) {
      c.dispose();
    }
    for (final f in _branchPinFocusNodes) {
      f.dispose();
    }
    _passwordController.dispose();
    super.dispose();
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
    if (sanitized.length > 1) {
      // User pasted full PIN
      _setBranchPinValue(sanitized);
      final targetIndex = (sanitized.length - 1).clamp(0, 3);
      _branchPinFocusNodes[targetIndex].requestFocus();
      if (_currentBranchPin().length == 4) {
        if (mounted) {
          FocusScope.of(context).unfocus();
        }
        _checkBranchPinLocation();
      }
      return;
    }

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

    final pin = _currentBranchPin();
    if (pin.length == 4) {
      if (mounted) {
        FocusScope.of(context).unfocus();
      }
      _checkBranchPinLocation();
    } else {
      if (_pinLocationStatus != PinLocationStatus.idle) {
        setState(() {
          _pinLocationStatus = PinLocationStatus.idle;
          _pinLocationMessage = null;
          _matchedBranchForPin = null;
          _pinBranchDistance = null;
          _pinBranchName = null;
        });
      }
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
      return KeyEventResult.ignored;
    }

    if (index == 0) return KeyEventResult.handled;

    final previousIndex = index - 1;
    final previousController = _branchPinDigitControllers[previousIndex];
    if (previousController.text.isNotEmpty) {
      previousController.clear();
      _syncBranchPinController();
      if (_pinLocationStatus != PinLocationStatus.idle) {
        setState(() {
          _pinLocationStatus = PinLocationStatus.idle;
          _pinLocationMessage = null;
          _matchedBranchForPin = null;
          _pinBranchDistance = null;
          _pinBranchName = null;
        });
      }
    }
    _branchPinFocusNodes[previousIndex].requestFocus();
    return KeyEventResult.handled;
  }

  Map<String, dynamic>? _findBranchInList(List<dynamic> list, String pin) {
    for (final b in list) {
      if (b is! Map) continue;
      final bPin = (b['pin'] ??
              b['branchPin'] ??
              b['loginPin'] ??
              b['code'] ??
              b['branchCode'] ??
              b['pincode'])
          ?.toString()
          .trim();
      if (bPin != null && bPin.isNotEmpty && bPin == pin) {
        return Map<String, dynamic>.from(b);
      }
    }
    return null;
  }

  Map<String, dynamic>? _findBranchInGeoSettings(
    Map<String, dynamic> geo,
    String pin,
  ) {
    final locations = geo['locations'] as List?;
    if (locations == null) return null;
    for (final loc in locations) {
      if (loc is! Map) continue;
      final b = loc['branch'];
      final locPin = (loc['pin'] ??
              loc['branchPin'] ??
              (b is Map ? (b['pin'] ?? b['branchPin'] ?? b['code']) : null))
          ?.toString()
          .trim();
      if (locPin != null && locPin.isNotEmpty && locPin == pin) {
        final bId = (b is Map ? (b['id'] ?? b['_id']) : b)?.toString() ??
            loc['branchId']?.toString() ??
            '';
        final bName = (b is Map ? b['name'] : null)?.toString() ??
            loc['name']?.toString() ??
            loc['branchName']?.toString() ??
            '';
        return {
          'id': bId,
          '_id': bId,
          'name': bName,
          'latitude': loc['latitude'],
          'longitude': loc['longitude'],
          'radius': loc['radius'],
        };
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _resolveBranchByPin(String pin) async {
    if (pin.isEmpty) return null;

    // 1. Check in cached branches list
    var match = _findBranchInList(_cachedBranchesList, pin);
    if (match != null) return match;

    // 2. Fetch fresh work-gps endpoint (returns branches with branchPin)
    try {
      final gpsRes = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/work-gps'),
        headers: {
          ...ApiConfig.getHeaders(null),
          http.skipUnauthorizedLogoutHeaderName: 'true',
        },
      );
      if (gpsRes.statusCode == 200) {
        final gpsData = jsonDecode(gpsRes.body);
        final branches = gpsData['branches'] as List?;
        if (branches != null && branches.isNotEmpty) {
          _cachedBranchesList = branches;
          match = _findBranchInList(branches, pin);
          if (match != null) {
            return match;
          }
        }
      }
    } catch (_) {}

    // 3. Check in cached geo settings
    match = _findBranchInGeoSettings(_cachedGeoSettings, pin);
    if (match != null) return match;

    // 4. Fetch geo settings (Cached)
    try {
      _cachedGeoSettings = await GeoSettingsManager.getSettings();
      if (_cachedGeoSettings.isNotEmpty) {
        match = _findBranchInGeoSettings(_cachedGeoSettings, pin);
        if (match != null) return match;
      }
    } catch (_) {}

    // 5. Fallback: Check /branches?limit=1000
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/branches?limit=1000'),
        headers: {
          ...ApiConfig.getHeaders(null),
          http.skipUnauthorizedLogoutHeaderName: 'true',
        },
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = (data['docs'] as List?) ?? [];
        if (docs.isNotEmpty) {
          match = _findBranchInList(docs, pin);
          if (match != null) return match;
        }
      }
    } catch (_) {}

    return null;
  }

  Future<void> _checkBranchPinLocation({bool forceGpsRefresh = false}) async {
    final pin = _currentBranchPin().trim();
    if (pin.length != 4 || !_branchPinPattern.hasMatch(pin)) {
      if (_pinLocationStatus != PinLocationStatus.idle) {
        setState(() {
          _pinLocationStatus = PinLocationStatus.idle;
          _pinLocationMessage = null;
          _matchedBranchForPin = null;
          _pinBranchDistance = null;
          _pinBranchName = null;
        });
      }
      return;
    }

    final int requestId = ++_locationCheckRequestId;

    setState(() {
      _pinLocationStatus = PinLocationStatus.checking;
      _pinLocationMessage = 'Checking GPS branch location...';
    });

    try {
      final branch = await _resolveBranchByPin(pin);
      if (requestId != _locationCheckRequestId || !mounted) return;

      // If branch PIN does not match any branch in the system, it is invalid!
      if (branch == null) {
        setState(() {
          _pinLocationStatus = PinLocationStatus.invalidPin;
          _pinBranchName = null;
          _matchedBranchForPin = null;
          _pinBranchDistance = null;
          _pinLocationMessage =
              'Invalid Branch PIN ($pin). No branch found with this PIN.';
        });
        return;
      }

      final bId = (branch['id'] ?? branch['_id'])?.toString() ?? '';
      final bName = branch['name']?.toString() ?? 'Branch';

      _pinBranchName = bName;
      _matchedBranchForPin = branch;

      // Check GPS location against the target branch that owns this PIN
      final geoResult = await GeofenceUtil.checkLocationAndGeofence(
        targetBranchId: bId.isNotEmpty ? bId : null,
        targetBranchName: bName.isNotEmpty ? bName : null,
        customBranches: _cachedBranchesList,
        customGeoSettings: _cachedGeoSettings,
      );

      if (requestId != _locationCheckRequestId || !mounted) return;

      if (geoResult.isInside) {
        setState(() {
          _pinLocationStatus = PinLocationStatus.verifiedInside;
          _pinBranchName = bName;
          _pinLocationMessage = 'You are inside $bName';
          _pinBranchDistance = geoResult.distance;
        });
      } else {
        final err = geoResult.errorMessage ?? '';
        final isGpsErr = err.toLowerCase().contains('permission') ||
            err.toLowerCase().contains('service') ||
            err.toLowerCase().contains('failed to acquire') ||
            err.toLowerCase().contains('disabled');

        setState(() {
          _pinLocationStatus = isGpsErr
              ? PinLocationStatus.gpsError
              : PinLocationStatus.outsideBranch;
          _pinBranchName = bName;
          _pinLocationMessage = isGpsErr
              ? err
              : (geoResult.errorMessage ??
                  'You are not inside $bName. Login is only allowed inside the branch.');
          _pinBranchDistance = geoResult.distance;
        });
      }
    } catch (e) {
      if (requestId != _locationCheckRequestId || !mounted) return;
      setState(() {
        _pinLocationStatus = PinLocationStatus.gpsError;
        _pinLocationMessage = 'GPS check failed: $e';
      });
    }
  }

  Future<void> _checkExistingSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const storage = FlutterSecureStorage();
      final token =
          (await storage.read(key: 'token')) ?? prefs.getString('token');

      if (token != null && token.isNotEmpty) {
        // Validate token by fetching user profile
        final res = await http
            .get(
              Uri.parse('${ApiConfig.baseUrl}/users/me'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final user = data['user'] ?? data;
          final role = (user['role'] ??
                  prefs.getString('userRole') ??
                  prefs.getString('role'))
              ?.toString()
              .toLowerCase() ??
              '';

          // Strictly allow only cashier and branch roles (plus admin/superadmin)
          final isAllowedRole = role == 'cashier' ||
              role == 'branch' ||
              role == 'admin' ||
              role == 'superadmin';

          if (!isAllowedRole) {
            debugPrint(
              'Existing session has unauthorized role ($role) for Branch App. Logging out.',
            );
            await AuthService.logout();
            return;
          }

          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => IdleTimeoutWrapper(child: const HomePage()),
              ),
            );
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Existing session check error: $e');
    } finally {
      if (mounted) {
        setState(() => _isCheckingSession = false);
      }
    }
  }

  Future<void> _initializeAuth() async {
    await Future.wait([
      _preloadBranchesAndPins(),
      _fetchDynamicRanges(),
      _fetchIp(),
      _preloadGeoSettings(),
    ]);
  }

  Future<void> _preloadBranchesAndPins() async {
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/work-gps'),
        headers: {
          ...ApiConfig.getHeaders(null),
          http.skipUnauthorizedLogoutHeaderName: 'true',
        },
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final branches = data['branches'] as List?;
        if (branches != null && branches.isNotEmpty) {
          _cachedBranchesList = branches;
        }
      }
    } catch (e) {
      debugPrint('Preload work-gps error: $e');
    }
  }

  Future<void> _preloadGeoSettings() async {
    try {
      final data = await GeoSettingsManager.getSettings();
      if (data.isNotEmpty) {
        _cachedGeoSettings = data;
      }
    } catch (e) {
      debugPrint('Preload geo settings error: $e');
    }
  }

  Future<void> _fetchDynamicRanges() async {
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/branches?limit=1000'),
        headers: {
          ...ApiConfig.getHeaders(null),
          http.skipUnauthorizedLogoutHeaderName: 'true',
        },
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['docs'] as List?;
        if (docs != null) {
          if (_cachedBranchesList.isEmpty) {
            _cachedBranchesList = docs;
          }
          final ranges = docs
              .map((d) => d['ipAddress']?.toString().trim() ?? '')
              .where((ip) => ip.isNotEmpty)
              .toList();
          if (mounted) {
            setState(() {
              _dynamicAllowedRanges = ranges;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch dynamic ranges: $e');
    }
  }

  int _ipToLong(String ip) {
    try {
      List<int> parts = ip.split('.').map(int.parse).toList();
      return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
    } catch (e) {
      return 0;
    }
  }

  bool _checkIpInRange(String ip, String range) {
    if (!range.contains('-')) return ip == range.trim();

    List<String> parts = range.split('-').map((e) => e.trim()).toList();
    if (parts.length != 2) return false;

    int ipLong = _ipToLong(ip);
    int startLong = _ipToLong(parts[0]);
    int endLong = _ipToLong(parts[1]);

    if (ipLong == 0 || startLong == 0 || endLong == 0) return false;

    return ipLong >= startLong && ipLong <= endLong;
  }

  bool _isPrivateIpAuthorized(String? private) {
    final allRanges = [..._allowedIpRanges, ..._dynamicAllowedRanges];
    for (final range in allRanges) {
      if (private != null && _checkIpInRange(private, range)) return true;
    }
    return false;
  }

  Future<void> _fetchIp() async {
    String? private;

    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      if (interfaces.isNotEmpty) {
        for (var interface in interfaces) {
          for (var addr in interface.addresses) {
            final ip = addr.address;
            if (ip.startsWith('192.168.') ||
                ip.startsWith('10.') ||
                ip.startsWith('172.16.') ||
                ip.startsWith('192.0.')) {
              private = ip;
              break;
            }
            private ??= ip;
          }
          if (private != null) break;
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch Private IP: $e');
    }

    if (mounted) {
      setState(() {
        _privateIp = private;
        _isIpAuthorized = _isPrivateIpAuthorized(private);
      });
    }
  }

  void _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final branchPin = _currentBranchPin().trim();
    if (!_useCustomPassword &&
        (branchPin.isEmpty || !_branchPinPattern.hasMatch(branchPin))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Branch PIN is required (must be exactly 4 digits)',
          ),
          backgroundColor: const Color(0xFF1A202C),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      if (_branchPinFocusNodes.isNotEmpty) {
        _branchPinFocusNodes.first.requestFocus();
      }
      return;
    }

    // STRICT GEOFENCE VERIFICATION: User must be physically inside branch to log in!
    if (branchPin.isNotEmpty) {
      if (_pinLocationStatus == PinLocationStatus.checking) {
        setState(() => _isLoading = true);
        for (var i = 0; i < 30; i++) {
          if (_pinLocationStatus != PinLocationStatus.checking) break;
          await Future.delayed(const Duration(milliseconds: 200));
        }
        if (mounted) setState(() => _isLoading = false);
      }

      if (_pinLocationStatus != PinLocationStatus.verifiedInside) {
        setState(() => _isLoading = true);
        await _checkBranchPinLocation(forceGpsRefresh: true);
        if (mounted) setState(() => _isLoading = false);
      }

      if (_pinLocationStatus != PinLocationStatus.verifiedInside) {
        String title;
        String msg;
        switch (_pinLocationStatus) {
          case PinLocationStatus.outsideBranch:
            title = 'Outside Branch';
            msg = _pinLocationMessage ??
                'You are not physically inside ${_pinBranchName ?? 'the branch'}. Login is only allowed inside the branch.';
            break;
          case PinLocationStatus.invalidPin:
            title = 'Invalid Branch PIN';
            msg = _pinLocationMessage ??
                'No branch found matching PIN $branchPin. Please enter a valid 4-digit PIN.';
            break;
          case PinLocationStatus.gpsError:
            title = 'GPS Location Required';
            msg = _pinLocationMessage ??
                'Could not verify location. Please enable GPS and try again.';
            break;
          default:
            title = 'Location Verification Required';
            msg = _pinLocationMessage ??
                'Please verify your branch GPS location before logging in.';
            break;
        }

        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  const Icon(Icons.location_off_rounded, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: Text(msg),
              actions: [
                if (_pinLocationStatus == PinLocationStatus.outsideBranch ||
                    _pinLocationStatus == PinLocationStatus.gpsError)
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _checkBranchPinLocation(forceGpsRefresh: true);
                    },
                    child: const Text('Retry GPS'),
                  ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E170F),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    // Ensure Private IP is fetched if available
    if (_privateIp == null) {
      await _fetchIp();
    }

    // Quick GPS capture to send with login request headers (non-blocking 2s timeout)
    Position? loginPosition;
    try {
      loginPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(const Duration(seconds: 2));
    } catch (_) {
      try {
        loginPosition = await Geolocator.getLastKnownPosition();
      } catch (_) {}
    }

    try {
      final rawInput = _usernameController.text.trim();
      final emailToUse =
          rawInput.contains('@') ? rawInput : '$rawInput@bf.com';
      final passwordToUse = _useCustomPassword && _passwordController.text.isNotEmpty
          ? _passwordController.text
          : '12345';

      final headers = {
        'Content-Type': 'application/json',
        'x-private-ip': _privateIp ?? '',
        'x-branch-pin': branchPin,
        'x-branch-code': branchPin,
        if (loginPosition != null) ...{
          'x-latitude': loginPosition.latitude.toString(),
          'x-longitude': loginPosition.longitude.toString(),
          'x-accuracy': loginPosition.accuracy.toString(),
        },
      };

      var res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/users/login'),
        headers: headers,
        body: jsonEncode({
          'email': emailToUse,
          'password': passwordToUse,
          'branchPin': branchPin,
          'privateIp': _privateIp,
        }),
      );

      // Fallback 1: If @bf.com failed and input had no @, try sending rawInput directly
      if (res.statusCode != 200 && !rawInput.contains('@')) {
        final fallbackRes = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/users/login'),
          headers: headers,
          body: jsonEncode({
            'email': rawInput,
            'password': passwordToUse,
            'branchPin': branchPin,
            'privateIp': _privateIp,
          }),
        );
        if (fallbackRes.statusCode == 200) {
          res = fallbackRes;
        }
      }

      // Fallback 2: If default 12345 failed, try branchPin as password
      if (res.statusCode != 200 && passwordToUse == '12345' && branchPin.isNotEmpty) {
        final pinPassRes = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/users/login'),
          headers: headers,
          body: jsonEncode({
            'email': emailToUse,
            'password': branchPin,
            'branchPin': branchPin,
            'privateIp': _privateIp,
          }),
        );
        if (pinPassRes.statusCode == 200) {
          res = pinPassRes;
        }
      }

      if (!mounted) {
        setState(() => _isLoading = false);
        return;
      }

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final token = data['token']?.toString() ?? '';
        final user = data['user'] ?? {};

        // Fetch full profile to populate nested fields like employee, branch, kitchen
        Map<String, dynamic> fullUser = user is Map<String, dynamic> ? user : {};
        if (token.isNotEmpty) {
          try {
            final profileRes = await http.get(
              Uri.parse('${ApiConfig.baseUrl}/users/me?depth=2'),
              headers: {'Authorization': 'Bearer $token'},
            );
            if (profileRes.statusCode == 200) {
              final pData = jsonDecode(profileRes.body);
              if (pData is Map && pData['user'] is Map) {
                fullUser = Map<String, dynamic>.from(pData['user']);
              }
            }
          } catch (e) {
            debugPrint('Failed to fetch full profile: $e');
          }
        }

        final userRole = fullUser['role']?.toString().toLowerCase() ?? '';
        final userName =
            fullUser['name']?.toString() ??
            fullUser['username']?.toString() ??
            '';
        final userId =
            (fullUser['id'] ?? fullUser['_id'])?.toString() ?? '';

        debugPrint(
          'Login success. Role: $userRole, Name: $userName, ID: $userId',
        );

        // -----------------------------------------------------------------
        // ROLE RESTRICTION: Branch app is restricted to cashier and branch logins only
        // -----------------------------------------------------------------
        final isAllowedRole = userRole == 'cashier' ||
            userRole == 'branch' ||
            userRole == 'admin' ||
            userRole == 'superadmin';

        if (!isAllowedRole) {
          setState(() => _isLoading = false);
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, color: Colors.red),
                    SizedBox(width: 8),
                    Text(
                      'Access Denied',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                content: Text(
                  'This Branch App is restricted to Cashier and Branch logins only. Your role ($userRole) is not authorized.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      'OK',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          }
          return;
        }

        final isKitchen = fullUser['isKitchen'] is bool
            ? fullUser['isKitchen'] as bool
            : (fullUser['isKitchen'] == true || userRole == 'kitchen');
        final isStock = fullUser['isStock'] is bool
            ? fullUser['isStock'] as bool
            : (fullUser['isStock'] == true ||
                userRole == 'chef' ||
                userRole == 'supervisor' ||
                userRole == 'manager' ||
                userRole == 'driver' ||
                userRole == 'factory');

        // Extract Branch ID and Name
        final branchObj = fullUser['branch'] ?? data['branch'];
        String branchId = '';
        String branchName = '';
        if (branchObj is Map) {
          branchId = (branchObj['id'] ?? branchObj['_id'])?.toString() ?? '';
          branchName = branchObj['name']?.toString() ?? '';
        } else if (branchObj is String) {
          branchId = branchObj;
        }

        // PIN-authoritative branch assignment: The branch verified by PIN is the authoritative branch
        Map<String, dynamic>? matchedBranch = _matchedBranchForPin;
        if (matchedBranch != null) {
          final mId = (matchedBranch['id'] ?? matchedBranch['_id'])?.toString() ?? '';
          final mName = matchedBranch['name']?.toString() ?? '';
          if (mId.isNotEmpty) {
            branchId = mId;
          }
          if (mName.isNotEmpty) {
            branchName = mName;
          }
        }

        // GPS Location Verification: User MUST be physically inside the branch corresponding to the PIN
        final bool isExemptRole =
            userRole == 'watcher' || userRole == 'superadmin' || userRole == 'admin';
        if (!isExemptRole) {
          try {
            final geoResult = await GeofenceUtil.checkLocationAndGeofence(
              existingPosition:
                  (loginPosition != null && loginPosition.accuracy <= 100.0)
                      ? loginPosition
                      : null,
              targetBranchId: branchId.isNotEmpty ? branchId : null,
              targetBranchName: branchName.isNotEmpty ? branchName : null,
              customBranches: _cachedBranchesList,
              customGeoSettings: _cachedGeoSettings,
            );

            if (!geoResult.isInside) {
              if (mounted) {
                final targetDisplay =
                    branchName.isNotEmpty ? branchName : 'Branch (PIN $branchPin)';
                final errorMsg = geoResult.errorMessage ??
                    'You are not physically inside $targetDisplay. Login is blocked.';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.location_off, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            errorMsg,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: const Color(0xFFC62828),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    duration: const Duration(seconds: 5),
                  ),
                );
                setState(() => _isLoading = false);
              }
              return;
            }

            debugPrint(
              'GPS verified: User is physically inside $branchName ($branchId). Login allowed.',
            );
          } catch (e) {
            debugPrint('GPS branch verification error: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Could not verify branch GPS location: $e. Please enable GPS and try again.',
                  ),
                  backgroundColor: const Color(0xFFC62828),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  duration: const Duration(seconds: 4),
                ),
              );
              setState(() => _isLoading = false);
            }
            return;
          }
        }

        setState(() => _isLoading = false);

        // Extract Photo URL
        String? photoUrl;
        final empObj = fullUser['employee'];
        if (empObj is Map && empObj['photo'] != null) {
          final p = empObj['photo'];
          if (p is Map) {
            photoUrl = p['url']?.toString() ?? p['thumbnailURL']?.toString();
          } else if (p is String) {
            photoUrl = p;
          }
        }

        // Save to FlutterSecureStorage now that geofence is strictly verified
        const storage = FlutterSecureStorage();
        await storage.write(key: 'isLoggedIn', value: 'true');
        await storage.write(key: 'token', value: token);
        await storage.write(key: 'userId', value: userId);
        await storage.write(key: 'userRole', value: userRole);
        await storage.write(key: 'userName', value: userName);
        await storage.write(key: 'userIsKitchen', value: isKitchen.toString());
        await storage.write(key: 'userIsStock', value: isStock.toString());
        if (branchPin.isNotEmpty) {
          await storage.write(key: 'branchPin', value: branchPin);
        }
        if (branchId.isNotEmpty) {
          await storage.write(key: 'userBranchId', value: branchId);
          await storage.write(key: 'userBranchName', value: branchName);
          await storage.write(key: 'isBranchLocked', value: 'true');
          await storage.write(key: 'lockedBranchId', value: branchId);
          await storage.write(key: 'lockedBranchName', value: branchName);
        }
        await storage.delete(key: 'userKitchenName');
        await storage.delete(key: 'userKitchenId');

        // Save to SharedPreferences for compatibility with existing branch modules
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', token);
        await prefs.setString('userId', userId);
        await prefs.setString('user_id', userId);
        await prefs.setString('employee_id', userId);
        await prefs.setString('role', userRole);
        await prefs.setString('userRole', userRole);
        await prefs.setString('userName', userName);
        await prefs.setString('user_name', userName);
        await prefs.setString('employee_name', userName);
        await prefs.setInt(
          'login_time',
          DateTime.now().millisecondsSinceEpoch,
        );
        if (branchPin.isNotEmpty) {
          await prefs.setString('branchPin', branchPin);
        }
        if (branchId.isNotEmpty) {
          await prefs.setString('branchId', branchId);
          await prefs.setString('branch', branchId);
          await prefs.setString('userBranchId', branchId);
          await prefs.setBool('isBranchLocked', true);
          await prefs.setString('lockedBranchId', branchId);
          await prefs.setString('lockedBranchName', branchName);
        }
        if (branchName.isNotEmpty) {
          await prefs.setString('branchName', branchName);
          await prefs.setString('userBranchName', branchName);
          await prefs.setString('lastGpsBranchName', branchName);
        }
        if (photoUrl != null && photoUrl.isNotEmpty) {
          await prefs.setString('employee_photo_url', photoUrl);
        }

        // Fetch Branch Details (IP, Lat, Lng, Radius, Printer IP)
        if (branchId.isNotEmpty) {
          try {
            final bRes = await http
                .get(
                  Uri.parse('${ApiConfig.baseUrl}/branches/$branchId'),
                  headers: {'Authorization': 'Bearer $token'},
                )
                .timeout(const Duration(seconds: 4));
            if (bRes.statusCode == 200) {
              final bData = jsonDecode(bRes.body);
              final comp = bData['company'];
              final compId = comp is Map
                  ? (comp['id'] ?? comp['_id'])?.toString()
                  : comp?.toString();
              if (compId != null && compId.isNotEmpty) {
                await prefs.setString('company_id', compId);
                if (comp is Map && comp['name'] != null) {
                  await prefs.setString('company_name', comp['name'].toString());
                }
              }
              final bIp = bData['ipAddress']?.toString().trim();
              final pIp = bData['printerIp']?.toString().trim();
              if (bIp != null && bIp.isNotEmpty) {
                await prefs.setString('branchIp', bIp);
              }
              if (pIp != null && pIp.isNotEmpty) {
                await prefs.setString('printerIp', pIp);
              }

              final lat = double.tryParse(bData['latitude']?.toString() ?? '');
              final lng = double.tryParse(bData['longitude']?.toString() ?? '');
              final radius = int.tryParse(bData['radius']?.toString() ?? '');
              if (lat != null && lng != null) {
                await prefs.setDouble('branchLat', lat);
                await prefs.setDouble('branchLng', lng);
                await prefs.setInt('branchRadius', radius ?? 100);
              }
            }
          } catch (_) {}
        }

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => IdleTimeoutWrapper(child: const HomePage()),
          ),
        );
      } else {
        // Login Failed
        String errorMessage =
            'Login Failed: ${res.statusCode}. Check credentials.';
        try {
          final errorData = jsonDecode(res.body);
          if (errorData is Map) {
            if (errorData['errors'] != null &&
                errorData['errors'] is List &&
                (errorData['errors'] as List).isNotEmpty) {
              final firstErr = errorData['errors'][0];
              if (firstErr is Map && firstErr['message'] != null) {
                errorMessage = firstErr['message'].toString();
              } else if (firstErr is String) {
                errorMessage = firstErr;
              }
            } else if (errorData['message'] != null) {
              errorMessage = errorData['message'].toString();
            } else if (errorData['error'] != null) {
              errorMessage = errorData['error'].toString();
            }
          }
        } catch (_) {}

        if (mounted) {
          if (res.statusCode == 403) {
            String dialogMessage = errorMessage
                .replaceAll(
                  RegExp(
                    r'\.?\s*Please provide a valid App Key\.?',
                    caseSensitive: false,
                  ),
                  '',
                )
                .trim();
            if (dialogMessage.isEmpty) {
              dialogMessage =
                  'Login is restricted to authorized Blackforest applications.';
            }
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, color: Colors.red),
                    SizedBox(width: 8),
                    Text(
                      'Access Denied',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                content: Text(dialogMessage),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      'OK',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: const Color(0xFF1A202C),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red[800],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildBranchPinLocationStatus() {
    if (_pinLocationStatus == PinLocationStatus.idle) {
      return const SizedBox.shrink();
    }

    Color bgColor;
    Color borderColor;
    Color textColor;
    IconData icon;
    String title;
    String? subtitle = _pinLocationMessage;
    bool showRetry = false;

    switch (_pinLocationStatus) {
      case PinLocationStatus.checking:
        bgColor = const Color(0xFFEFF6FF);
        borderColor = const Color(0xFFBFDBFE);
        textColor = const Color(0xFF1E40AF);
        icon = Icons.location_searching_rounded;
        title = 'Checking GPS Location...';
        subtitle = 'Verifying you are physically inside the branch';
        break;

      case PinLocationStatus.verifiedInside:
        bgColor = const Color(0xFFF0FDF4);
        borderColor = const Color(0xFFBBF7D0);
        textColor = const Color(0xFF15803D);
        icon = Icons.check_circle_rounded;
        title = 'Location Verified: ${_pinBranchName ?? 'Inside Branch'}';
        final distStr = _pinBranchDistance != null
            ? ' • ${_pinBranchDistance!.toStringAsFixed(0)}m away'
            : '';
        subtitle = 'You are inside the branch boundary$distStr. Login allowed.';
        break;

      case PinLocationStatus.outsideBranch:
        bgColor = const Color(0xFFFEF2F2);
        borderColor = const Color(0xFFFECACA);
        textColor = const Color(0xFFB91C1C);
        icon = Icons.location_off_rounded;
        title = 'Not Inside Branch: ${_pinBranchName ?? 'Branch'}';
        subtitle = _pinLocationMessage ??
            'You are outside the branch area. You must be physically inside the branch to log in.';
        showRetry = true;
        break;

      case PinLocationStatus.invalidPin:
        bgColor = const Color(0xFFFFFBEB);
        borderColor = const Color(0xFFFDE68A);
        textColor = const Color(0xFFB45309);
        icon = Icons.error_outline_rounded;
        title = 'Invalid Branch PIN';
        subtitle =
            _pinLocationMessage ?? 'No branch found matching this 4-digit PIN.';
        break;

      case PinLocationStatus.gpsError:
        bgColor = const Color(0xFFFEF2F2);
        borderColor = const Color(0xFFFECACA);
        textColor = const Color(0xFFB91C1C);
        icon = Icons.gps_off_rounded;
        title = 'GPS Location Required';
        subtitle =
            _pinLocationMessage ?? 'Could not verify location. Please enable GPS.';
        showRetry = true;
        break;

      case PinLocationStatus.idle:
        return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_pinLocationStatus == PinLocationStatus.checking)
            const Padding(
              padding: EdgeInsets.only(top: 2, right: 10),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1E40AF)),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 10, top: 2),
              child: Icon(icon, color: textColor, size: 20),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.85),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
                if (showRetry) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _checkBranchPinLocation(forceGpsRefresh: true),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: textColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh_rounded, size: 14, color: textColor),
                          const SizedBox(width: 4),
                          Text(
                            'Retry GPS Check',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingSession) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1C0908),
                Color(0xFF4A1A12),
                Color(0xFF7A2D1C),
              ],
            ),
          ),
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo & Brand Header
                  Center(
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D0A0A),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(
                            Icons.cake_rounded,
                            color: Colors.white,
                            size: 44,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Center(
                    child: Text(
                      'BLACKFOREST CAKES',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                        color: Color(0xFF8B2500),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Center(
                    child: Text(
                      'Branch Login',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E170F),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Sign in with your username and branch PIN',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Form Container
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Username Field
                        TextFormField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: 'Username',
                            hintText: 'Enter username or email',
                            prefixIcon:
                                const Icon(Icons.person_outline_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF9FAFB),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter username';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        // Branch PIN Section Header
                        Row(
                          children: [
                            const Icon(
                              Icons.pin_outlined,
                              color: Color(0xFF8B2500),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Branch PIN',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2E170F),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '4 Digits',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // 4-Digit PIN Boxes
                        LayoutBuilder(
                          builder: (context, constraints) {
                            const preferredSize = 58.0;
                            const minSize = 44.0;
                            const preferredGap = 12.0;
                            final availableWidth = constraints.maxWidth;

                            final computedSize =
                                (availableWidth - (preferredGap * 3)) / 4;
                            final boxSize = (computedSize.isFinite
                                    ? computedSize
                                    : preferredSize)
                                .clamp(minSize, preferredSize)
                                .toDouble();

                            final computedGap =
                                (availableWidth - (boxSize * 4)) / 3;
                            final gap = (computedGap.isFinite
                                    ? computedGap
                                    : preferredGap)
                                .clamp(6.0, preferredGap)
                                .toDouble();

                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(4, (index) {
                                return Padding(
                                  padding: EdgeInsets.only(
                                    right: index == 3 ? 0 : gap,
                                  ),
                                  child: SizedBox(
                                    width: boxSize,
                                    height: boxSize,
                                    child: Focus(
                                      onKeyEvent: (node, event) =>
                                          _handleBranchPinKeyEvent(index, event),
                                      child: TextFormField(
                                        controller:
                                            _branchPinDigitControllers[index],
                                        focusNode: _branchPinFocusNodes[index],
                                        keyboardType: TextInputType.number,
                                        textInputAction: index == 3
                                            ? TextInputAction.done
                                            : TextInputAction.next,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Color(0xFF2E170F),
                                          fontWeight: FontWeight.bold,
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
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            borderSide: const BorderSide(
                                              color: Color(0xFFD8C3B4),
                                              width: 1.4,
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            borderSide: const BorderSide(
                                              color: Color(0xFF8B2500),
                                              width: 2.0,
                                            ),
                                          ),
                                        ),
                                        onChanged: (value) =>
                                            _handleBranchPinDigitChanged(
                                          index,
                                          value,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            );
                          },
                        ),
                        _buildBranchPinLocationStatus(),
                        const SizedBox(height: 12),

                        // Optional Custom Password toggle
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _useCustomPassword = !_useCustomPassword;
                                });
                              },
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(50, 30),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                _useCustomPassword
                                    ? 'Login with PIN only'
                                    : 'Use password instead',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF8B2500),
                                ),
                              ),
                            ),
                          ],
                        ),

                        if (_useCustomPassword) ...[
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              hintText: 'Enter your password',
                              prefixIcon:
                                  const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: Colors.grey[600],
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF9FAFB),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),

                        // Submit Button
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: (_pinLocationStatus ==
                                          PinLocationStatus.outsideBranch ||
                                      _pinLocationStatus ==
                                          PinLocationStatus.invalidPin)
                                  ? const Color(0xFF8B2500)
                                  : const Color(0xFF2E170F),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Colors.white,
                                    ),
                                  )
                                : FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_pinLocationStatus ==
                                            PinLocationStatus.verifiedInside) ...[
                                          const Icon(
                                            Icons.check_circle_rounded,
                                            size: 18,
                                            color: Color(0xFF86EFAC),
                                          ),
                                          const SizedBox(width: 8),
                                        ] else if (_pinLocationStatus ==
                                            PinLocationStatus.outsideBranch) ...[
                                          const Icon(
                                            Icons.location_off_rounded,
                                            size: 18,
                                            color: Colors.white70,
                                          ),
                                          const SizedBox(width: 8),
                                        ] else if (_pinLocationStatus ==
                                            PinLocationStatus.invalidPin) ...[
                                          const Icon(
                                            Icons.error_outline_rounded,
                                            size: 18,
                                            color: Colors.white70,
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Text(
                                          _pinLocationStatus ==
                                                  PinLocationStatus.outsideBranch
                                              ? 'Outside Branch - Cannot Login'
                                              : (_pinLocationStatus ==
                                                      PinLocationStatus.invalidPin
                                                  ? 'Invalid PIN - Cannot Login'
                                                  : 'Login'),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Network Information Card
                  if (_privateIp != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _isIpAuthorized
                              ? Colors.green.withValues(alpha: 0.3)
                              : Colors.red.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lan_rounded,
                            size: 20,
                            color: _isIpAuthorized
                                ? Colors.green[700]
                                : Colors.red[700],
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Private IP',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                Text(
                                  _privateIp!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'monospace',
                                    color: _isIpAuthorized
                                        ? Colors.green[800]
                                        : Colors.red[800],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _isIpAuthorized
                                  ? Colors.green.withValues(alpha: 0.12)
                                  : Colors.red.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _isIpAuthorized ? 'Authorized' : 'Unauthorized',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _isIpAuthorized
                                    ? Colors.green[800]
                                    : Colors.red[800],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
