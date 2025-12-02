import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:branch/categories_page.dart';
import 'package:branch/home.dart'; // ADDED
import 'package:network_info_plus/network_info_plus.dart';

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

class _IdleTimeoutWrapperState extends State<IdleTimeoutWrapper> with WidgetsBindingObserver {
  Timer? _timer;
  DateTime? _pauseTime;

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(widget.timeout, _logout);
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
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
  bool _isCheckingSession = false; // NEW: Track initial session check to prevent flash

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
        final res = await http.get(
          Uri.parse("https://admin.theblackforestcakes.com/api/users/me"),
          headers: {"Authorization": "Bearer $token"},
        );
        if (res.statusCode == 200) {
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
      setState(() => _isCheckingSession = false); // NEW: Done checking, show form if no nav
    }
  }

  // ---------------------------------------------------------
  // IP ALERT POPUP (MODIFIED TO INCLUDE BRANCH NAME)
  // ---------------------------------------------------------
  Future<void> _showIpAlert(
      String branchName,
      String deviceIp,
      String branchInfo,
      String? printerIp,
      ) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Branch Verification"),
        content: Text(
          "Branch: $branchName\nDevice IP: $deviceIp\n$branchInfo\nPrinter IP: ${printerIp ?? 'Not Set'}",
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.black,
      ),
    );
  }

  // ---------------------------------------------------------
  // LOGIN FUNCTION - USERNAME ONLY → username@bf.com (MODIFIED FOR BRANCH NAME HANDLING)
  // ---------------------------------------------------------
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final info = NetworkInfo();
    String? deviceIp = await info.getWifiIP();
    String input = _emailController.text.trim();
    String finalEmail = input.contains("@") ? input : "$input@bf.com";

    if (!finalEmail.endsWith("@bf.com")) {
      _showError("Only @bf.com domain allowed");
      setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await http.post(
        Uri.parse("https://admin.theblackforestcakes.com/api/users/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": finalEmail,
          "password": _passwordController.text,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final user = data["user"];
        final role = user["role"];

        // ✔ Allow ONLY branch users
        const allowedRoles = ["branch"];
        if (!allowedRoles.contains(role)) {
          _showError("Access denied: only branch users allowed.");
          setState(() => _isLoading = false);
          return;
        }

        dynamic branchRef = user["branch"];
        String? branchId;
        if (branchRef is Map) {
          branchId = branchRef["id"]?.toString() ?? branchRef["_id"]?.toString();
        } else {
          branchId = branchRef?.toString();
        }

        String? branchIpRange;
        String? printerIp;
        String branchName = "Unknown"; // Default if not fetched
        String branchInfo = "No IP range set"; // Default for no fixed IP
        String alertDeviceIp = deviceIp ?? "Unknown";

        // ✔ Fetch branch details if branchId exists
        if (branchId != null) {
          final bRes = await http.get(
            Uri.parse("https://admin.theblackforestcakes.com/api/branches/$branchId"),
            headers: {
              "Authorization": "Bearer ${data['token']}",
              "Content-Type": "application/json"
            },
          );
          if (bRes.statusCode == 200) {
            final branch = jsonDecode(bRes.body);
            branchName = branch["name"]?.toString().trim() ?? "Unknown"; // NEW: Fetch branch name
            branchIpRange = branch["ipAddress"]?.toString().trim();
            printerIp = branch["printerIp"]?.toString().trim();

            // ✔ Branch IP validation (only if range is set)
            if (branchIpRange != null && branchIpRange.isNotEmpty) {
              if (deviceIp == null) {
                _showError("Unable to fetch device IP for validation");
                setState(() => _isLoading = false);
                return;
              }
              if (!_isIpInRange(deviceIp, branchIpRange)) {
                _showError("IP mismatch: $deviceIp not allowed");
                setState(() => _isLoading = false);
                return;
              }
              branchInfo = "IP matched ($branchIpRange)"; // Update info for fixed IP
            }
          }
        }

        // NEW: Always show alert with branch name and status (fetches/displays branch even without fixed IP)
        await _showIpAlert(
          branchName,
          alertDeviceIp,
          branchInfo,
          printerIp,
        );

        // ✔ Save session (NEW: Save branchName)
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("token", data["token"]);
        await prefs.setString("role", role);
        await prefs.setString("email", finalEmail);
        if (branchId != null) await prefs.setString("branchId", branchId);
        await prefs.setString("branchName", branchName); // NEW: Save for later use
        if (deviceIp != null) await prefs.setString("lastLoginIp", deviceIp);
        if (printerIp != null) await prefs.setString("printerIp", printerIp);

        // ✔ NAVIGATE TO HOME PAGE AFTER LOGIN
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => IdleTimeoutWrapper(child: const HomePage()),
            ),
          );
        }
      } else {
        _showError("Invalid credentials");
      }
    } catch (e) {
      _showError("Network error: $e");
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
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: Colors.white,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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
                            ? const CircularProgressIndicator(color: Colors.black)
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        ),
      ),
    );
  }
}