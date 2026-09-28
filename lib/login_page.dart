import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'auth_service.dart';
import 'home.dart';

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
//  BRANCH LOGIN PAGE (Same Authentication System as Tracker)
// ---------------------------------------------------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _branchController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
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

  Future<void> _checkExistingSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const storage = FlutterSecureStorage();
      final token = (await storage.read(key: 'token')) ?? prefs.getString('token');

      if (token != null && token.isNotEmpty) {
        // Validate token by fetching user profile
        final res = await http.get(
          Uri.parse('https://dev1-blacforest.vseyal.com/api/users/me'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
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
    await _fetchDynamicRanges();
    await _fetchIp();
  }

  Future<void> _fetchDynamicRanges() async {
    try {
      final res = await http.get(
        Uri.parse('https://dev1-blacforest.vseyal.com/api/branches?limit=1000'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['docs'] as List?;
        if (docs != null) {
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
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      // Ensure Private IP is fetched if available
      if (_privateIp == null) {
        await _fetchIp();
      }

      try {
        final rawInput = _branchController.text.trim();
        final emailToUse = rawInput.contains('@') ? rawInput : '$rawInput@bf.com';

        var res = await http.post(
          Uri.parse('https://dev1-blacforest.vseyal.com/api/users/login'),
          headers: {
            'Content-Type': 'application/json',
            'x-private-ip': _privateIp ?? '',
          },
          body: jsonEncode({
            'email': emailToUse,
            'password': _passwordController.text,
            'privateIp': _privateIp,
          }),
        );

        // Fallback: If @bf.com failed and input had no @, try sending rawInput directly
        if (res.statusCode != 200 && !rawInput.contains('@')) {
          final fallbackRes = await http.post(
            Uri.parse('https://dev1-blacforest.vseyal.com/api/users/login'),
            headers: {
              'Content-Type': 'application/json',
              'x-private-ip': _privateIp ?? '',
            },
            body: jsonEncode({
              'email': rawInput,
              'password': _passwordController.text,
              'privateIp': _privateIp,
            }),
          );
          if (fallbackRes.statusCode == 200) {
            res = fallbackRes;
          }
        }

        if (!mounted) {
          setState(() => _isLoading = false);
          return;
        }

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final token = data['token'];
          final user = data['user'] ?? {};

          setState(() => _isLoading = false);

          // Fetch full profile to populate nested fields like employee, branch, kitchen
          Map<String, dynamic> fullUser = user;
          try {
            final profile = await ApiService.instance.fetchUserProfile();
            if (profile.isNotEmpty) fullUser = profile;
          } catch (e) {
            debugPrint('Failed to fetch full profile: $e');
          }

          final userRole = fullUser['role']?.toString().toLowerCase() ?? '';
          final userName = fullUser['name']?.toString() ?? fullUser['username']?.toString() ?? '';
          final userId = (fullUser['id'] ?? fullUser['_id'])?.toString() ?? '';

          debugPrint('Login success. Role: $userRole, Name: $userName, ID: $userId');

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
          final branchObj = fullUser['branch'];
          String branchId = '';
          String branchName = '';
          if (branchObj is Map) {
            branchId = (branchObj['id'] ?? branchObj['_id'])?.toString() ?? '';
            branchName = branchObj['name']?.toString() ?? '';
          } else if (branchObj is String) {
            branchId = branchObj;
          }

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

          // Save to FlutterSecureStorage
          const storage = FlutterSecureStorage();
          await storage.write(key: 'isLoggedIn', value: 'true');
          await storage.write(key: 'token', value: token);
          await storage.write(key: 'userId', value: userId);
          await storage.write(key: 'userRole', value: userRole);
          await storage.write(key: 'userName', value: userName);
          await storage.write(key: 'userIsKitchen', value: isKitchen.toString());
          await storage.write(key: 'userIsStock', value: isStock.toString());
          if (branchId.isNotEmpty) await storage.write(key: 'userBranchId', value: branchId);

          // Save to SharedPreferences for full compatibility with existing branch modules
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
          await prefs.setInt('login_time', DateTime.now().millisecondsSinceEpoch);
          if (branchId.isNotEmpty) {
            await prefs.setString('branchId', branchId);
            await prefs.setString('branch', branchId);
          }
          if (branchName.isNotEmpty) {
            await prefs.setString('branchName', branchName);
          }
          if (photoUrl != null && photoUrl.isNotEmpty) {
            await prefs.setString('employee_photo_url', photoUrl);
          }

          // Extract manager companies if manager
          if (userRole == 'manager') {
            final rawCompanies = fullUser['manager_companies'];
            final companyIds = <String>[];
            if (rawCompanies is List) {
              for (final c in rawCompanies) {
                final id = (c is Map ? (c['id'] ?? c['_id']) : c)?.toString() ?? '';
                if (id.isNotEmpty) companyIds.add(id);
              }
            }
            await storage.write(key: 'managerCompanyIds', value: companyIds.join(','));
            await prefs.setString('managerCompanyIds', companyIds.join(','));
          }

          // Kitchen specifics
          if (isKitchen) {
            final kitchenObj = fullUser['kitchen'];
            String kitchenId = '';
            List<String> categories = [];

            if (kitchenObj is Map) {
              kitchenId = (kitchenObj['id'] ?? kitchenObj['_id'])?.toString() ?? '';
            } else if (kitchenObj is String) {
              kitchenId = kitchenObj;
            }

            if (kitchenId.isNotEmpty) {
              try {
                final kitchenDetails = await ApiService.instance.fetchKitchenDetails(kitchenId);
                final cats = (kitchenDetails['categories'] as List?) ?? [];
                for (var c in cats) {
                  final cId = (c is Map ? (c['id'] ?? c['_id']) : c)?.toString() ?? '';
                  if (cId.isNotEmpty) categories.add(cId);
                }
              } catch (_) {}
            }

            await storage.write(key: 'userKitchenId', value: kitchenId);
            await storage.write(key: 'userKitchenCategoryIds', value: categories.join(','));
          }

          // Fetch Branch Details (IP, Lat, Lng, Radius, Printer IP)
          if (branchId.isNotEmpty) {
            try {
              final bRes = await http.get(
                Uri.parse('https://dev1-blacforest.vseyal.com/api/branches/$branchId'),
                headers: {'Authorization': 'Bearer $token'},
              ).timeout(const Duration(seconds: 4));
              if (bRes.statusCode == 200) {
                final bData = jsonDecode(bRes.body);
                final bIp = bData['ipAddress']?.toString().trim();
                final pIp = bData['printerIp']?.toString().trim();
                if (bIp != null && bIp.isNotEmpty) await prefs.setString('branchIp', bIp);
                if (pIp != null && pIp.isNotEmpty) await prefs.setString('printerIp', pIp);

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
          String errorMessage = 'Login Failed: ${res.statusCode}. Check credentials.';
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: const Color(0xFF1A202C),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red[800],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
  }

  @override
  void dispose() {
    _branchController.dispose();
    _passwordController.dispose();
    super.dispose();
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
              colors: [Color(0xFF1C0908), Color(0xFF4A1A12), Color(0xFF7A2D1C)],
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
                          child: Icon(Icons.cake_rounded, color: Colors.white, size: 44),
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
                      'Sign in with your username and password',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ),
                  const SizedBox(height: 32),

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
                          controller: _branchController,
                          decoration: InputDecoration(
                            labelText: 'Username',
                            hintText: 'Enter username or email',
                            prefixIcon: const Icon(Icons.person_outline_rounded),
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
                        const SizedBox(height: 18),

                        // Password Field
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: 'Enter your password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
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
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter password';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),

                        // Submit Button
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E170F),
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
                                : const Text(
                                    'Login',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                            color: _isIpAuthorized ? Colors.green[700] : Colors.red[700],
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Private IP',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                ),
                                Text(
                                  _privateIp!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'monospace',
                                    color: _isIpAuthorized ? Colors.green[800] : Colors.red[800],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                                color: _isIpAuthorized ? Colors.green[800] : Colors.red[800],
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
