import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img_lib;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'auth_service.dart';
import 'camera_page.dart';
import 'common_scaffold.dart';
import 'settings_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _profileLoading = true;
  String? _employeeName;
  String? _employeeRole;
  String? _employeeId;
  String? _employeePhotoUrl;
  String? _branchName;
  bool _isLoggingOut = false;
  bool _isProcessingPunch = false;
  String? _attendanceDocId;
  bool _hasActiveSession = false;
  List<dynamic> _rawActivities = [];

  Timer? _timer;
  Duration _workDuration = Duration.zero;
  Duration _breakDuration = Duration.zero;
  List<Map<String, dynamic>> _activities = [];

  @override
  void initState() {
    super.initState();
    _loadEmployeeData();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _openSettingsPage() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
  }

  Future<void> _loadEmployeeData() async {
    final prefs = await SharedPreferences.getInstance();
    final loginTimeMs = prefs.getInt('login_time');
    final branchId = prefs.getString('branchId');
    final token = prefs.getString('token');
    String? branchName = prefs.getString('branchName');

    if ((branchName?.trim().isEmpty ?? true) &&
        token != null &&
        token.isNotEmpty &&
        branchId != null &&
        branchId.isNotEmpty) {
      final fetchedBranchName = await _fetchBranchName(token, branchId);
      if (fetchedBranchName != null && fetchedBranchName.trim().isNotEmpty) {
        branchName = fetchedBranchName;
        await prefs.setString('branchName', fetchedBranchName);
      }
    }

    if (!mounted) return;
    setState(() {
      _employeeName =
          prefs.getString('employee_name') ?? prefs.getString('user_name');
      _employeeRole = prefs.getString('role');
      _employeeId = prefs.getString('employee_code');
      _employeePhotoUrl = prefs.getString('employee_photo_url');
      _branchName = branchName;
      _profileLoading = false;

      if (loginTimeMs != null && _workDuration == Duration.zero) {
        // We no longer calculate _workDuration from login time.
        // It will strictly rely on actual attendance session duration.
      }
    });

    await _fetchAttendance();
  }

  Future<String?> _fetchBranchName(String token, String branchId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/branches/$branchId?depth=1'),
        headers: ApiConfig.getHeaders(token),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final directName = decoded['name']?.toString();
          if (directName != null && directName.trim().isNotEmpty) {
            return directName;
          }
          final nested = decoded['doc'];
          if (nested is Map<String, dynamic>) {
            final nestedName = nested['name']?.toString();
            if (nestedName != null && nestedName.trim().isNotEmpty) {
              return nestedName;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Future<void> _fetchAttendance() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final userId = prefs.getString('user_id');

    if (token == null || userId == null) return;

    final now = DateTime.now();
    final localMidnight = DateTime(now.year, now.month, now.day);
    final queryDate = localMidnight
        .subtract(const Duration(days: 1))
        .toUtc()
        .toIso8601String();

    try {
      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/attendance?where[user][equals]=$userId&where[date][greater_than_equal]=$queryDate&sort=-date&limit=10',
        ),
        headers: ApiConfig.getHeaders(token),
      );

      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      final docs = (data is Map<String, dynamic> ? data['docs'] : null) as List?;
      if (docs == null) return;

      final allActivities = <Map<String, dynamic>>[];
      var totalWork = Duration.zero;
      var totalBreak = Duration.zero;
      var activeSessionFound = false;

      // Extract raw activities from the first doc (today's doc) to use for Punch In/Out updates.
      if (docs.isNotEmpty && docs.first is Map<String, dynamic>) {
        final firstDoc = docs.first as Map<String, dynamic>;
        final docDateStr = firstDoc['dateString']?.toString() ?? '';
        final queryDateStr = localMidnight.toIso8601String().split('T')[0];
        
        // Ensure the doc we found is actually for today
        if (docDateStr == queryDateStr || 
            (firstDoc['date']?.toString().startsWith(queryDateStr) == true)) {
          _attendanceDocId = firstDoc['id']?.toString();
          _rawActivities = (firstDoc['activities'] as List?) ?? [];
        } else {
          _attendanceDocId = null;
          _rawActivities = [];
        }
      } else {
        _attendanceDocId = null;
        _rawActivities = [];
      }

      for (final dynamic doc in docs) {
        final activities = (doc is Map<String, dynamic> ? doc['activities'] : null)
            as List?;
        if (activities == null) continue;

        for (final dynamic rawActivity in activities) {
          if (rawActivity is! Map<String, dynamic>) continue;
          final type = rawActivity['type'];
          final punchInStr = rawActivity['punchIn']?.toString();
          final punchOutStr = rawActivity['punchOut']?.toString();
          final status = rawActivity['status']?.toString();
          final durationSeconds = _toInt(rawActivity['durationSeconds']);

          if (punchInStr == null || punchInStr.isEmpty) continue;

          final punchIn = DateTime.tryParse(punchInStr)?.toLocal();
          if (punchIn == null) continue;
          final punchOut = punchOutStr != null && punchOutStr.isNotEmpty
              ? DateTime.tryParse(punchOutStr)?.toLocal()
              : null;

          final inTimeStr = DateFormat('hh:mm a').format(punchIn);
          final outTimeStr =
              punchOut != null ? DateFormat('hh:mm a').format(punchOut) : 'Active';

          if (type == 'session') {
            final duration = punchOut != null
                ? Duration(
                    seconds: durationSeconds > 0
                        ? durationSeconds
                        : punchOut.difference(punchIn).inSeconds,
                  )
                : DateTime.now().difference(punchIn);

            totalWork += duration;

            if (punchIn.isAfter(localMidnight) ||
                (punchOut != null && punchOut.isAfter(localMidnight))) {
              allActivities.add({
                'type': 'session',
                'inTime': inTimeStr,
                'outTime': outTimeStr,
                'color': Colors.white,
                'startTime': punchIn,
                'isActive': status == 'active',
              });
            }

            if (status == 'active') {
              activeSessionFound = true;
              final activeStart = punchIn;
              final pastWork = totalWork - DateTime.now().difference(activeStart);
              _timer?.cancel();
              _timer = Timer.periodic(const Duration(seconds: 1), (_) {
                if (!mounted) return;
                setState(() {
                  _workDuration = pastWork + DateTime.now().difference(activeStart);
                });
              });
            }
          } else if (type == 'break') {
            final duration = punchOut != null
                ? Duration(
                    seconds: durationSeconds > 0
                        ? durationSeconds
                        : punchOut.difference(punchIn).inSeconds,
                  )
                : Duration.zero;

            totalBreak += duration;

            if (punchIn.isAfter(localMidnight)) {
              allActivities.add({
                'type': 'break',
                'title': duration.inMinutes > 0
                    ? '${duration.inMinutes} Min Break'
                    : '${duration.inSeconds} Sec Break',
                'color': const Color(0xFFFFE0B2),
                'textColor': Colors.orange[900],
                'startTime': punchIn,
              });
            }
          }
        }
      }

      if (!activeSessionFound) {
        _timer?.cancel();
      }

      if (!mounted) return;
      setState(() {
        allActivities.sort(
          (a, b) =>
              (b['startTime'] as DateTime).compareTo(a['startTime'] as DateTime),
        );
        _activities = allActivities;
        _workDuration = totalWork;
        _breakDuration = totalBreak;
        _hasActiveSession = activeSessionFound;
      });
    } catch (_) {}
  }

  String _formatTwoDigits(int n) => n.toString().padLeft(2, '0');

  static Future<List<int>?> _compressImageIsolate(List<int> bytes) async {
    try {
      final image = img_lib.decodeImage(Uint8List.fromList(bytes));
      if (image == null) return null;

      img_lib.Image resized = image;
      if (image.width > 1280 || image.height > 1280) {
        if (image.width > image.height) {
          resized = img_lib.copyResize(image, width: 1280);
        } else {
          resized = img_lib.copyResize(image, height: 1280);
        }
      }
      return img_lib.encodeJpg(resized, quality: 70);
    } catch (_) {
      return null;
    }
  }

  Future<File> _prepareImageForUpload(File originalFile) async {
    try {
      if (!await originalFile.exists()) return originalFile;
      final length = await originalFile.length();
      if (length < 1500 * 1024) return originalFile;

      final bytes = await originalFile.readAsBytes();
      
      final compressedBytes = await compute(_compressImageIsolate, bytes);
      
      if (compressedBytes == null) return originalFile;

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/opt_selfie_$timestamp.jpg');
      await tempFile.writeAsBytes(compressedBytes);
      return tempFile;
    } catch (_) {
      return originalFile;
    }
  }

  Future<String?> _uploadMedia(File file) async {
    final uploadFile = await _prepareImageForUpload(file);
    if (!await uploadFile.exists()) return null;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return null;

    final filename = 'selfie_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final urlStr = '${ApiConfig.baseUrl}/media?prefix=attendance';

    try {
      final request = http.MultipartRequest('POST', Uri.parse(urlStr));
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['alt'] = 'Attendance Selfie';
      request.fields['prefix'] = 'attendance';

      final multipartFile = await http.MultipartFile.fromPath(
        'file',
        uploadFile.path,
        filename: filename,
        contentType: MediaType('image', 'jpeg'),
      );
      request.files.add(multipartFile);

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(body);
        final doc = data['doc'] ?? data;
        return doc['id']?.toString();
      }
    } catch (e) {
      debugPrint('Upload error: $e');
    }
    return null;
  }

  Future<void> _takePhotoAndPunchIn() async {
    if (_hasActiveSession || _isProcessingPunch) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('You are already punched in.')),
       );
       return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No camera found')),
      );
      return;
    }

    final XFile? capturedFile = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraPage(cameras: cameras, isFaceCapture: true),
      ),
    );

    if (capturedFile != null) {
      setState(() {
        _isProcessingPunch = true;
      });

      final mediaId = await _uploadMedia(File(capturedFile.path));
      if (mediaId != null) {
        await _punchIn(mediaId);
      } else {
        setState(() {
          _isProcessingPunch = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload selfie')),
        );
      }
    }
  }

  Future<void> _punchIn(String mediaId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final userId = prefs.getString('user_id');
    if (token == null || userId == null) return;

    final now = DateTime.now();
    final newActivity = {
      'type': 'session',
      'punchIn': now.toUtc().toIso8601String(),
      'status': 'active',
      'capturedImage': mediaId,
    };

    try {
      if (_attendanceDocId != null) {
        // PATCH existing
        final updatedActivities = List.from(_rawActivities)..add(newActivity);
        final url = '${ApiConfig.baseUrl}/attendance/$_attendanceDocId';
        final response = await http.patch(
          Uri.parse(url),
          headers: ApiConfig.getHeaders(token),
          body: jsonEncode({'activities': updatedActivities}),
        );
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Successfully punched in!')),
          );
          await _fetchAttendance();

        // POST to new punchin collection
        try {
          final punchInUrl = '${ApiConfig.baseUrl}/punchin';
          await http.post(
            Uri.parse(punchInUrl),
            headers: ApiConfig.getHeaders(token),
            body: jsonEncode({
              'user': userId,
              'date': now.toUtc().toIso8601String(),
              'photo': mediaId,
            }),
          );
        } catch (e) {
          debugPrint('Error creating punchin record: $e');
        }

        }
      } else {
        // POST new
        final localMidnight = DateTime(now.year, now.month, now.day);
        final dateString = DateFormat('yyyy-MM-dd').format(localMidnight);
        
        // Find employee id from current user if needed, but attendance can just have user and no employee, or we fetch employee id.
        // Actually the backend payload config creates attendance with `user`. We will just omit `employee` if we don't have it.
        final url = '${ApiConfig.baseUrl}/attendance';
        final response = await http.post(
          Uri.parse(url),
          headers: ApiConfig.getHeaders(token),
          body: jsonEncode({
            'user': userId,
            'date': localMidnight.toUtc().toIso8601String(),
            'dateString': dateString,
            'activities': [newActivity],
          }),
        );
        if (response.statusCode == 200 || response.statusCode == 201) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Successfully punched in!')),
          );
          await _fetchAttendance();

        // POST to new punchin collection
        try {
          final punchInUrl = '${ApiConfig.baseUrl}/punchin';
          await http.post(
            Uri.parse(punchInUrl),
            headers: ApiConfig.getHeaders(token),
            body: jsonEncode({
              'user': userId,
              'date': now.toUtc().toIso8601String(),
              'photo': mediaId,
            }),
          );
        } catch (e) {
          debugPrint('Error creating punchin record: $e');
        }

        }
      }
    } catch (e) {
      debugPrint('Punch In Error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingPunch = false;
        });
      }
    }
  }

  Future<void> _punchOut() async {
    if (!_hasActiveSession || _attendanceDocId == null || _isProcessingPunch) return;
    
    setState(() {
      _isProcessingPunch = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;

    try {
      final updatedActivities = List.from(_rawActivities);
      
      // Find the active session and close it
      for (var i = updatedActivities.length - 1; i >= 0; i--) {
        final activity = updatedActivities[i];
        if (activity['type'] == 'session' && activity['status'] == 'active') {
           final punchInTime = DateTime.parse(activity['punchIn']);
           final punchOutTime = DateTime.now();
           final durationSecs = punchOutTime.difference(punchInTime).inSeconds;
           
           activity['punchOut'] = punchOutTime.toUtc().toIso8601String();
           activity['status'] = 'closed';
           activity['durationSeconds'] = durationSecs;
           break;
        }
      }

      final url = '${ApiConfig.baseUrl}/attendance/$_attendanceDocId';
      final response = await http.patch(
        Uri.parse(url),
        headers: ApiConfig.getHeaders(token),
        body: jsonEncode({'activities': updatedActivities}),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully punched out!')),
        );
        await _fetchAttendance();
      }
    } catch (e) {
      debugPrint('Punch Out Error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingPunch = false;
        });
      }
    }
  }

  Future<void> _confirmLogout() async {
    if (_isLoggingOut || !mounted) return;
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Do you want to logout from this device?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true) {
      await _logout();
    }
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    setState(() {
      _isLoggingOut = true;
    });
    try {
      await AuthService.logout();
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
      } else {
        _isLoggingOut = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: 'Profile',
      pageType: PageType.profile,
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Settings',
          onPressed: _openSettingsPage,
        ),
      ],
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFFF8F9FA),
        child: _profileLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.blue))
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 40),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _takePhotoAndPunchIn,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _hasActiveSession ? Colors.green : Colors.grey[300]!,
                                width: _hasActiveSession ? 3 : 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 50,
                              backgroundColor: Colors.white,
                              backgroundImage:
                                  _employeePhotoUrl != null &&
                                      _employeePhotoUrl!.isNotEmpty
                                  ? NetworkImage(_employeePhotoUrl!)
                                  : null,
                              child: _employeePhotoUrl == null || _employeePhotoUrl!.isEmpty
                                  ? Icon(Icons.person, size: 50, color: Colors.grey[400])
                                  : null,
                            ),
                          ),
                          if (!_hasActiveSession && !_isProcessingPunch)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                              ),
                            ),
                          if (_isProcessingPunch)
                            const CircularProgressIndicator(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (_employeeId != null && _employeeId!.isNotEmpty)
                          Text(
                            'ID: $_employeeId',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        Text(
                          _employeeName ?? 'User',
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Text(
                            (_employeeRole ?? 'Role').toUpperCase(),
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_branchName != null && _branchName!.isNotEmpty)
                      Text(
                        _branchName!,
                        style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 20,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Working Hours',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _formatTwoDigits(_workDuration.inHours),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Text(
                                  ':',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                              ),
                              Text(
                                _formatTwoDigits(_workDuration.inMinutes % 60),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Text(
                                  ':',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                              ),
                              Text(
                                _formatTwoDigits(_workDuration.inSeconds % 60),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Text(
                                'Hour',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                ),
                              ),
                              Text(
                                'Min',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                ),
                              ),
                              Text(
                                'Sec',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE0B2),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withValues(alpha: 0.1),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.coffee, color: Colors.orange[800]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Total Break Time ${_formatTwoDigits(_breakDuration.inHours)}h:${_formatTwoDigits(_breakDuration.inMinutes % 60)}m',
                              style: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _hasActiveSession ? Colors.orange[800] : const Color(0xFFD32F2F),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: (_isLoggingOut || _isProcessingPunch) 
                            ? null 
                            : (_hasActiveSession ? _punchOut : _confirmLogout),
                        icon: (_isLoggingOut || _isProcessingPunch)
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Icon(
                                _hasActiveSession ? Icons.punch_clock : Icons.logout_rounded, 
                                size: 20
                              ),
                        label: Text(
                          _isProcessingPunch 
                              ? 'Processing...' 
                              : _isLoggingOut 
                                  ? 'Logging out...' 
                                  : (_hasActiveSession ? 'Punch Out' : 'Logout'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Your activity',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_activities.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text(
                            'No activity for today',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ),
                      ),
                    ..._activities.map((activity) {
                      if (activity['type'] == 'break') {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: activity['color'] as Color,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              activity['title']?.toString() ?? '',
                              style: TextStyle(
                                color:
                                    (activity['textColor'] as Color?) ??
                                    Colors.orange[900],
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        );
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[200]!),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.1),
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(12),
                                      bottomLeft: Radius.circular(12),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.login,
                                            size: 18,
                                            color: Colors.green,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Punch In',
                                            style: TextStyle(
                                              color: Colors.green[800],
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        activity['inTime']?.toString() ?? '-',
                                        style: const TextStyle(
                                          color: Colors.black87,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Container(width: 1, color: Colors.grey[300]),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: activity['isActive'] == true
                                        ? Colors.white
                                        : Colors.red.withValues(alpha: 0.08),
                                    borderRadius: const BorderRadius.only(
                                      topRight: Radius.circular(12),
                                      bottomRight: Radius.circular(12),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.logout,
                                            size: 18,
                                            color: activity['isActive'] == true
                                                ? Colors.grey
                                                : Colors.red,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Punch Out',
                                            style: TextStyle(
                                              color: activity['isActive'] == true
                                                  ? Colors.grey[600]
                                                  : Colors.red[800],
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        activity['outTime']?.toString() ?? '-',
                                        style: TextStyle(
                                          color: activity['isActive'] == true
                                              ? Colors.green[700]
                                              : Colors.red[700],
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
      ),
    );
  }
}
