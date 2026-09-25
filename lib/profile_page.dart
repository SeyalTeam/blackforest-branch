import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img_lib;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'api_config.dart';
import 'camera_page.dart';
import 'login_page.dart';
import 'geofence_util.dart';
import 'notification_service.dart';
import 'attendance_manager.dart';
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
  List<String> _managerCompanyNames = [];
  String? _employeeId;
  String? _employeePhotoUrl;
  String? _branchName;
  String? _employeePhone;
  bool _isLoggingOut = false;
  bool _isProcessingPunch = false;
  String? _attendanceDocId;
  bool _hasActiveSession = false;
  bool _activeSessionHasPhoto = true;
  String? _lastPunchOutType;
  File? _capturedPunchInPhoto;
  List<dynamic> _rawActivities = [];

  Timer? _timer;
  Timer? _geofenceTimer; // polls GPS every 60s while session is active
  bool _autoPunchOutFired = false; // prevents double-fire on same geofence exit
  bool _autoPunchInFired = false;
  StreamSubscription<String?>? _notificationSubscription;
  StreamSubscription<Map<String, dynamic>>? _attendanceManagerSub;
  Duration _workDuration = Duration.zero;
  Duration _breakDuration = Duration.zero;
  List<Map<String, dynamic>> _activities = [];
  String? _dayType; // 'full_day' | 'half_day' | null

  @override
  void initState() {
    super.initState();
    _loadEmployeeData();
    _notificationSubscription = NotificationService().onNotificationClick
        .listen((payload) {
          if (payload == 'auto_punch_in') {
            if (_hasActiveSession && !_activeSessionHasPhoto) {
              _attachSelfieToActiveSession();
            } else {
              _autoCaptureAndPunchIn();
            }
          }
        });
    _attendanceManagerSub = AttendanceManager.instance.onAttendanceUpdate
        .listen((event) {
          debugPrint('ProfilePage: received attendance update: $event');
          if (mounted) {
            _fetchAttendance();
          }
        });
    AttendanceManager.instance.checkNow();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _geofenceTimer?.cancel();
    _notificationSubscription?.cancel();
    _attendanceManagerSub?.cancel();
    super.dispose();
  }

  Future<void> _loadEmployeeData() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final cachedName = prefs.getString('userName');
      final cachedRole = prefs.getString('userRole');

      if (mounted) {
        setState(() {
          _employeeName = cachedName;
          _employeeRole = cachedRole;
        });
      }

      await _fetchEmployeeProfile();
      await _fetchAttendance();
    } catch (e) {
      debugPrint('Error loading employee data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _profileLoading = false;
        });
      }
    }
  }

  String _resolveApiAssetUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return value;
    if (value.startsWith('data:image/')) return value;

    final sanitized = value.replaceAll(' ', '%20');
    final normalizedInput = sanitized.startsWith('//')
        ? 'https:$sanitized'
        : sanitized;

    if (normalizedInput.startsWith('http://') ||
        normalizedInput.startsWith('https://')) {
      return normalizedInput;
    }

    final relative = normalizedInput.startsWith('/')
        ? normalizedInput
        : '/$normalizedInput';

    return 'https://dev1-blacforest.vseyal.com$relative';
  }

  Future<void> _fetchEmployeeProfile() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final profile = await ApiConfig.fetchUserProfile(
        prefs.getString('token') ?? '',
      );
      if (profile.isNotEmpty) {
        final user = profile['user'] ?? profile;
        final employee = user['employee'] ?? {};
        final branch = user['branch'] ?? {};

        final name = user['name']?.toString() ?? employee['name']?.toString();
        final role = user['role']?.toString();
        final code = employee['employeeId']?.toString();
        final phone = employee['phoneNumber']?.toString();
        final bName = branch['name']?.toString();

        final photo = employee['photo'];
        String? photoUrl;
        if (photo is Map) {
          photoUrl =
              photo['thumbnailURL']?.toString() ??
              photo['thumbnailUrl']?.toString() ??
              photo['url']?.toString();
        } else if (photo is String) {
          photoUrl = photo;
        }

        String? resolvedUrl;
        if (photoUrl != null && photoUrl.isNotEmpty) {
          resolvedUrl = _resolveApiAssetUrl(photoUrl);
        }

        List<String> companyNames = [];
        if (role == 'manager') {
          final rawCompanies = user['manager_companies'];
          if (rawCompanies is List) {
            for (final c in rawCompanies) {
              if (c is Map && c['name'] != null) {
                companyNames.add(c['name'].toString());
              }
            }
          }
        }

        if (mounted) {
          setState(() {
            if (name != null) _employeeName = name;
            if (role != null) _employeeRole = role;
            if (code != null) _employeeId = code;
            if (phone != null) _employeePhone = phone;
            if (bName != null) _branchName = bName;
            if (resolvedUrl != null) _employeePhotoUrl = resolvedUrl;
            if (companyNames.isNotEmpty) _managerCompanyNames = companyNames;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching employee profile: $e');
    }
  }

  Future<void> _fetchAttendance() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final userId = prefs.getString('userId');

    if (token == null || userId == null) return;

    final now = DateTime.now();
    final localMidnight = DateTime(now.year, now.month, now.day);
    final queryDate = localMidnight
        .subtract(const Duration(days: 1))
        .toUtc()
        .toIso8601String();

    try {
      final url =
          '${ApiConfig.baseUrl}/attendance?where[user][equals]=$userId&where[date][greater_than_equal]=$queryDate&sort=-date&limit=10';
      final response = await http.get(
        Uri.parse(url),
        headers: token.isNotEmpty ? {'Authorization': 'Bearer $token'} : {},
      );

      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      final docs =
          (data is Map<String, dynamic> ? data['docs'] : null) as List?;
      if (docs == null) return;

      final allActivities = <Map<String, dynamic>>[];
      var totalWork = Duration.zero;
      var totalBreak = Duration.zero;
      var activeSessionFound = false;
      var activePhotoFound = true;
      String? latestPunchOutType;
      DateTime? latestPunchOutTime;

      if (docs.isNotEmpty && docs.first is Map<String, dynamic>) {
        final firstDoc = docs.first as Map<String, dynamic>;
        final docDateStr = firstDoc['dateString']?.toString() ?? '';
        final queryDateStr = localMidnight.toIso8601String().split('T')[0];

        if (docDateStr == queryDateStr ||
            (firstDoc['date']?.toString().startsWith(queryDateStr) == true)) {
          _attendanceDocId = firstDoc['id']?.toString();
          _rawActivities = (firstDoc['activities'] as List?) ?? [];
          _dayType = firstDoc['dayType']?.toString();
        } else {
          _attendanceDocId = null;
          _rawActivities = [];
          _dayType = null;
        }
      } else {
        _attendanceDocId = null;
        _rawActivities = [];
      }

      for (final dynamic doc in docs) {
        final activities =
            (doc is Map<String, dynamic> ? doc['activities'] : null) as List?;
        if (activities == null) continue;

        for (final dynamic rawActivity in activities) {
          if (rawActivity is! Map<String, dynamic>) continue;
          final type = rawActivity['type'];
          final punchInStr = rawActivity['punchIn']?.toString();
          final punchOutStr = rawActivity['punchOut']?.toString();
          final status = rawActivity['status']?.toString();
          final durationSeconds = _toInt(rawActivity['durationSeconds']);
          final breakDurationSeconds = _toInt(
            rawActivity['breakDurationSeconds'],
          );

          if (punchInStr == null || punchInStr.isEmpty) continue;

          final punchIn = DateTime.tryParse(punchInStr)?.toLocal();
          final punchOut = punchOutStr != null
              ? DateTime.tryParse(punchOutStr)?.toLocal()
              : null;

          if (punchIn == null) continue;

          final inTimeStr = DateFormat('hh:mm a').format(punchIn);
          final outTimeStr = punchOut != null
              ? DateFormat('hh:mm a').format(punchOut)
              : 'Active';

          if (type == 'session') {
            // ── Stale active session guard (FIRST — before any accumulation) ──
            // If active but punchIn was before today's midnight, the employee
            // forgot to punch out. Auto-close it on the server and skip it
            // entirely so it never inflates today's work timer.
            if (status == 'active' && punchIn.isBefore(localMidnight)) {
              final endOfDay = DateTime(
                punchIn.year,
                punchIn.month,
                punchIn.day,
                23,
                59,
                59,
              );
              final durationSecs = endOfDay.difference(punchIn).inSeconds;

              final ownerDoc = docs.firstWhere((d) {
                final acts = (d is Map ? d['activities'] : null) as List?;
                return acts?.any(
                      (a) =>
                          a is Map &&
                          a['punchIn']?.toString() == punchInStr &&
                          a['status'] == 'active',
                    ) ??
                    false;
              }, orElse: () => null);

              if (ownerDoc != null) {
                final ownerDocId = ownerDoc['id']?.toString();
                final ownerActivities = List<dynamic>.from(
                  (ownerDoc['activities'] as List?) ?? [],
                );
                for (final a in ownerActivities) {
                  if (a is Map &&
                      a['punchIn']?.toString() == punchInStr &&
                      a['status'] == 'active') {
                    a['punchOut'] = endOfDay.toUtc().toIso8601String();
                    a['status'] = 'closed';
                    a['durationSeconds'] = durationSecs > 0 ? durationSecs : 0;
                    a['punchOutType'] = 'auto';
                    break;
                  }
                }
                final storedToken = token;
                if (ownerDocId != null &&
                    storedToken != null &&
                    storedToken.isNotEmpty) {
                  http
                      .patch(
                        Uri.parse(
                          '${ApiConfig.baseUrl}/attendance/$ownerDocId',
                        ),
                        headers: {
                          'Authorization': 'Bearer $storedToken',
                          'Content-Type': 'application/json',
                        },
                        body: jsonEncode({'activities': ownerActivities}),
                      )
                      .then((_) {
                        if (mounted) _fetchAttendance();
                      })
                      .catchError((e) {
                        debugPrint('Stale session auto-close error: $e');
                      });
                }
              }
              // Skip entirely — don't add to totalWork, don't show in UI
              continue;
            }

            // ── Only count today's sessions toward the work timer ─────────
            if (punchOut != null) {
              if (latestPunchOutTime == null ||
                  punchOut.isAfter(latestPunchOutTime)) {
                latestPunchOutTime = punchOut;
                latestPunchOutType = rawActivity['punchOutType']?.toString();
              }
            }

            final isToday =
                punchIn.isAfter(localMidnight) ||
                (punchOut != null && punchOut.isAfter(localMidnight));

            final duration = punchOut != null
                ? Duration(
                    seconds: durationSeconds > 0
                        ? durationSeconds
                        : punchOut.difference(punchIn).inSeconds,
                  )
                : DateTime.now().difference(punchIn);

            if (isToday) {
              totalWork += duration;
            }

            // Add break card before this session if breakDurationSeconds is stored
            if (breakDurationSeconds > 0 && punchIn.isAfter(localMidnight)) {
              final breakDur = Duration(seconds: breakDurationSeconds);
              totalBreak += breakDur;
              allActivities.add({
                'type': 'break',
                'title': breakDur.inHours > 0
                    ? '${breakDur.inHours}h ${breakDur.inMinutes % 60}m Break'
                    : breakDur.inMinutes > 0
                    ? '${breakDur.inMinutes} Min Break'
                    : '${breakDur.inSeconds} Sec Break',
                'color': const Color(0xFFFFE0B2),
                'textColor': Colors.orange[900],
                'startTime': punchIn.subtract(
                  Duration(seconds: breakDurationSeconds),
                ),
              });
            }

            if (isToday) {
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
              // Normal active session for today — start the live ticker
              activeSessionFound = true;
              final capturedImg = rawActivity['capturedImage'];
              activePhotoFound =
                  capturedImg != null &&
                  capturedImg.toString().trim().isNotEmpty;
              final activeStart = punchIn;
              final pastWork =
                  totalWork - DateTime.now().difference(activeStart);
              _timer?.cancel();
              _timer = Timer.periodic(const Duration(seconds: 1), (_) {
                if (!mounted) return;
                setState(() {
                  _workDuration =
                      pastWork + DateTime.now().difference(activeStart);
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
          (a, b) => (b['startTime'] as DateTime).compareTo(
            a['startTime'] as DateTime,
          ),
        );
        _activities = allActivities;
        _workDuration = totalWork;
        _breakDuration = totalBreak;
        _hasActiveSession = activeSessionFound;
        _activeSessionHasPhoto = activePhotoFound;
        _lastPunchOutType = latestPunchOutType;
        // dayType is only meaningful after midnight for a COMPLETED past day.
        // Never show half/full day badge for today's ongoing session.
        final todayStr = DateFormat('yyyy-MM-dd').format(localMidnight);
        final docDateStr2 = docs.isNotEmpty && docs.first is Map
            ? (docs.first as Map)['dateString']?.toString() ?? ''
            : '';
        final isToday = docDateStr2 == todayStr;
        if (!isToday && allActivities.isNotEmpty) {
          // Past date: all sessions closed = full day, any open session = half day
          _dayType = activeSessionFound ? 'half_day' : 'full_day';
        } else {
          _dayType = null; // Today: no judgement yet
        }
      });

      // Start or stop the geofence watcher based on session state
      if (activeSessionFound) {
        _autoPunchOutFired =
            false; // reset so a fresh punch-out can trigger auto punch-out
      } else {
        _autoPunchInFired =
            false; // reset so auto punch-in is enabled whenever not in a session
        _autoPunchOutFired = false;
      }
      _startGeofenceWatcher();
    } catch (e) {
      debugPrint('Error fetching attendance: $e');
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
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
    final prefs = await SharedPreferences.getInstance();
    final uploadFile = await _prepareImageForUpload(file);
    if (!await uploadFile.exists()) return null;

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
      debugPrint(
        'DEBUG: Selfie upload response status: ${response.statusCode}, body: $body',
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(body);
        final doc = data['doc'] ?? data;
        return doc['id']?.toString();
      } else {
        debugPrint(
          'DEBUG: Selfie upload failed. Status: ${response.statusCode}, Body: $body',
        );
      }
    } catch (e) {
      debugPrint('Upload error: $e');
    }
    return null;
  }

  Future<void> _capturePhoto() async {
    if (_hasActiveSession || _isProcessingPunch) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are already punched in.')),
      );
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No camera found')));
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
        _capturedPunchInPhoto = File(capturedFile.path);
      });
      await _submitPunchIn(isAuto: true);
    }
  }

  Future<void> _submitPunchIn({bool isAuto = false}) async {
    if (_capturedPunchInPhoto == null ||
        _hasActiveSession ||
        _isProcessingPunch)
      return;

    setState(() {
      _isProcessingPunch = true;
    });

    // GPS Geofence Check
    final isInside = await GeofenceUtil.isInsideAnyBranch(context);
    if (!isInside && mounted) {
      setState(() => _isProcessingPunch = false);
      return; // Block punch in if not inside branch circle
    }

    try {
      final mediaId = await _uploadMedia(_capturedPunchInPhoto!);
      if (mediaId != null) {
        await _punchIn(mediaId, isAuto: isAuto);
        if (mounted) {
          setState(() {
            _capturedPunchInPhoto = null;
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload selfie.')),
          );
        }
      }
    } catch (e) {
      debugPrint('Submit Punch In Error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingPunch = false;
        });
      }
    }
  }

  Future<void> _punchIn(String mediaId, {bool isAuto = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final userId = prefs.getString('userId');
    if (token == null || userId == null) return;

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('PunchIn location error: $e');
    }

    final now = DateTime.now();
    final newActivity = {
      'type': 'session',
      'punchIn': now.toUtc().toIso8601String(),
      'status': 'active',
      'capturedImage': mediaId,
      'punchInType': isAuto ? 'auto' : 'manual',
      if (position != null) 'latitude': position.latitude,
      if (position != null) 'longitude': position.longitude,
    };

    try {
      if (_attendanceDocId != null) {
        final updatedActivities = List.from(_rawActivities)..add(newActivity);
        final url = '${ApiConfig.baseUrl}/attendance/$_attendanceDocId';
        final response = await http.patch(
          Uri.parse(url),
          headers: token.isNotEmpty
              ? {
                  'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json',
                }
              : {},
          body: jsonEncode({'activities': updatedActivities}),
        );
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Successfully punched in!')),
          );
          await _fetchEmployeeProfile();
          await _fetchAttendance();
          _lastPunchOutType = null;
          await prefs.remove('lastPunchOutType');
        }
      } else {
        final localMidnight = DateTime(now.year, now.month, now.day);
        final dateString = DateFormat('yyyy-MM-dd').format(localMidnight);

        final url = '${ApiConfig.baseUrl}/attendance';
        final response = await http.post(
          Uri.parse(url),
          headers: token.isNotEmpty
              ? {
                  'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json',
                }
              : {},
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
          await _fetchEmployeeProfile();
          await _fetchAttendance();
          _lastPunchOutType = null;
          await prefs.remove('lastPunchOutType');
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

  // ── Geofence watcher ────────────────────────────────────────────────────────

  /// Starts a 60-second periodic GPS check. If the employee is outside every
  /// branch geofence while a session is active, auto punch-out fires once.
  void _startGeofenceWatcher() {
    _geofenceTimer?.cancel();
    _geofenceTimer = null;

    // Check IMMEDIATELY on start / refresh
    _checkGeofence();

    _geofenceTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      await _checkGeofence();
    });
  }

  Future<void> _checkGeofence() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || _isProcessingPunch) return;
    await AttendanceManager.instance.checkNow();
  }

  Future<void> _autoPunchInWithoutSelfie() async {
    final prefs = await SharedPreferences.getInstance();
    if (_hasActiveSession || _isProcessingPunch) return;

    setState(() {
      _isProcessingPunch = true;
    });

    final token = prefs.getString('token');
    final userId = prefs.getString('userId');
    if (token == null || userId == null) {
      setState(() => _isProcessingPunch = false);
      return;
    }

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('AutoPunchIn location error: $e');
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (_) {}
    }

    final now = DateTime.now();
    final newActivity = {
      'type': 'session',
      'punchIn': now.toUtc().toIso8601String(),
      'status': 'active',
      'capturedImage': null,
      'punchInType': 'auto',
      if (position != null) 'latitude': position.latitude,
      if (position != null) 'longitude': position.longitude,
    };

    try {
      if (_attendanceDocId != null) {
        final updatedActivities = List.from(_rawActivities)..add(newActivity);
        final url = '${ApiConfig.baseUrl}/attendance/$_attendanceDocId';
        final response = await http.patch(
          Uri.parse(url),
          headers: token.isNotEmpty
              ? {
                  'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json',
                }
              : {},
          body: jsonEncode({'activities': updatedActivities}),
        );
        debugPrint(
          'AutoPunchIn PATCH response: ${response.statusCode} -> ${response.body}',
        );
        if (response.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.bolt, color: Colors.amber),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Auto punched in! Please add your selfie photo.',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.blue[800],
                duration: const Duration(seconds: 5),
              ),
            );
          }
          await _fetchEmployeeProfile();
          await _fetchAttendance();
          _lastPunchOutType = null;
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Auto punch-in rejected by server (${response.statusCode}): ${response.body}',
                ),
                backgroundColor: Colors.red[800],
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      } else {
        final localMidnight = DateTime(now.year, now.month, now.day);
        final dateString = DateFormat('yyyy-MM-dd').format(localMidnight);

        final url = '${ApiConfig.baseUrl}/attendance';
        final response = await http.post(
          Uri.parse(url),
          headers: token.isNotEmpty
              ? {
                  'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json',
                }
              : {},
          body: jsonEncode({
            'user': userId,
            'date': localMidnight.toUtc().toIso8601String(),
            'dateString': dateString,
            'activities': [newActivity],
          }),
        );
        debugPrint(
          'AutoPunchIn POST response: ${response.statusCode} -> ${response.body}',
        );
        if (response.statusCode == 200 || response.statusCode == 201) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.bolt, color: Colors.amber),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Auto punched in! Please add your selfie photo.',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.blue[800],
                duration: const Duration(seconds: 5),
              ),
            );
          }
          await _fetchEmployeeProfile();
          await _fetchAttendance();
          _lastPunchOutType = null;
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Auto punch-in rejected by server (${response.statusCode}): ${response.body}',
                ),
                backgroundColor: Colors.red[800],
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Auto punch in error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingPunch = false;
        });
      }
    }
  }

  Future<void> _attachSelfieToActiveSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (_isProcessingPunch) return;

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No camera found')));
      return;
    }

    final XFile? capturedFile = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraPage(cameras: cameras, isFaceCapture: true),
      ),
    );

    if (capturedFile == null) return;

    final photoFile = File(capturedFile.path);
    setState(() {
      _capturedPunchInPhoto = photoFile;
      _isProcessingPunch = true;
    });

    try {
      final mediaId = await _uploadMedia(photoFile);
      if (mediaId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload selfie photo.')),
          );
        }
        return;
      }

      final token = prefs.getString('token');
      if (token == null || _attendanceDocId == null) return;

      final updatedActivities = List.from(_rawActivities);
      for (var i = updatedActivities.length - 1; i >= 0; i--) {
        final activity = updatedActivities[i];
        if (activity is Map &&
            activity['type'] == 'session' &&
            activity['status'] == 'active') {
          activity['capturedImage'] = mediaId;
          break;
        }
      }

      final url = '${ApiConfig.baseUrl}/attendance/$_attendanceDocId';
      final response = await http.patch(
        Uri.parse(url),
        headers: token.isNotEmpty
            ? {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              }
            : {},
        body: jsonEncode({'activities': updatedActivities}),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Selfie attached successfully! You can now punch out when done.',
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        }
        await _fetchAttendance();
        AttendanceManager.instance.checkNow();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to update attendance: ${response.statusCode}',
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error attaching selfie: $e');
    } finally {
      if (mounted) {
        setState(() => _isProcessingPunch = false);
      }
    }
  }

  Future<void> _autoCaptureAndPunchIn() async {
    if (_hasActiveSession || _isProcessingPunch) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.location_on, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Inside branch! Please take a selfie to complete punch-in.',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green[700],
          duration: const Duration(seconds: 4),
        ),
      );
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      _autoPunchInFired = false;
      return;
    }

    if (!mounted) return;
    final XFile? capturedFile = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraPage(cameras: cameras, isFaceCapture: true),
      ),
    );

    if (capturedFile != null) {
      setState(() {
        _capturedPunchInPhoto = File(capturedFile.path);
      });
      await _submitPunchIn(isAuto: true);
    } else {
      // User cancelled camera without taking photo: allow re-trigger
      _autoPunchInFired = false;
    }
  }

  void _stopGeofenceWatcher() {
    _geofenceTimer?.cancel();
    _geofenceTimer = null;
  }

  /// Identical to _punchOut() but stamps punchOutType:'auto' and shows a
  /// different banner explaining the reason.
  Future<void> _autoPunchOut() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_hasActiveSession || _attendanceDocId == null || _isProcessingPunch)
      return;

    setState(() => _isProcessingPunch = true);

    final token = prefs.getString('token');
    if (token == null) {
      setState(() => _isProcessingPunch = false);
      return;
    }

    try {
      final updatedActivities = List.from(_rawActivities);

      for (var i = updatedActivities.length - 1; i >= 0; i--) {
        final activity = updatedActivities[i];
        if (activity['type'] == 'session' && activity['status'] == 'active') {
          final punchInTime = DateTime.parse(activity['punchIn']);
          final punchOutTime = DateTime.now();
          final durationSecs = punchOutTime.difference(punchInTime).inSeconds;

          activity['punchOut'] = punchOutTime.toUtc().toIso8601String();
          activity['status'] = 'closed';
          activity['durationSeconds'] = durationSecs;
          activity['punchOutType'] =
              'auto'; // ← marks this as geofence-triggered
          break;
        }
      }

      final url = '${ApiConfig.baseUrl}/attendance/$_attendanceDocId';
      final response = await http.patch(
        Uri.parse(url),
        headers: token.isNotEmpty
            ? {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              }
            : {},
        body: jsonEncode({'activities': updatedActivities}),
      );

      if (response.statusCode == 200) {
        _lastPunchOutType = 'auto';
        _autoPunchInFired = false;
        _stopGeofenceWatcher();
        await _fetchEmployeeProfile();
        await _fetchAttendance();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.location_off, color: Colors.white),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Auto punched out — you left the branch area.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.orange[800],
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Auto Punch Out Error: $e');
      _autoPunchOutFired = false; // allow retry on next tick if network failed
    } finally {
      if (mounted) setState(() => _isProcessingPunch = false);
    }
  }

  // ── Manual Punch Out ────────────────────────────────────────────────────────

  Future<void> _punchOut() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_hasActiveSession || _attendanceDocId == null || _isProcessingPunch)
      return;

    if (!_activeSessionHasPhoto) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Text('Photo Required'),
            ],
          ),
          content: const Text(
            'You cannot punch out yet! Please add your selfie photo to complete today\'s attendance first.',
            style: TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _attachSelfieToActiveSession();
              },
              icon: const Icon(Icons.camera_alt, size: 18),
              label: const Text('Add Photo Now'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      _isProcessingPunch = true;
    });

    final token = prefs.getString('token');
    if (token == null) return;

    try {
      final updatedActivities = List.from(_rawActivities);

      for (var i = updatedActivities.length - 1; i >= 0; i--) {
        final activity = updatedActivities[i];
        if (activity['type'] == 'session' && activity['status'] == 'active') {
          final punchInTime = DateTime.parse(activity['punchIn']);
          final punchOutTime = DateTime.now();
          final durationSecs = punchOutTime.difference(punchInTime).inSeconds;

          activity['punchOut'] = punchOutTime.toUtc().toIso8601String();
          activity['status'] = 'closed';
          activity['durationSeconds'] = durationSecs;
          activity['punchOutType'] = 'manual'; // ← employee tapped the button
          break;
        }
      }

      final url = '${ApiConfig.baseUrl}/attendance/$_attendanceDocId';
      final response = await http.patch(
        Uri.parse(url),
        headers: token.isNotEmpty
            ? {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              }
            : {},
        body: jsonEncode({'activities': updatedActivities}),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully punched out!')),
        );
        await _fetchEmployeeProfile();
        await _fetchAttendance();
        _autoPunchInFired = false;
        _lastPunchOutType = 'manual';
        await prefs.setString('lastPunchOutType', 'manual');
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
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isLoggingOut = true;
    });

    try {
      AttendanceManager.instance.stopForegroundWatcher();
      await prefs.clear();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('Logout Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logout failed. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFFF8F9FA),
        child: _profileLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.blue))
            : RefreshIndicator(
                onRefresh: () async {
                  await _fetchEmployeeProfile();
                  await _fetchAttendance();
                  _autoPunchInFired = false;
                  await _checkGeofence();
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 40),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _hasActiveSession
                            ? (!_activeSessionHasPhoto
                                  ? _attachSelfieToActiveSession
                                  : null)
                            : _capturePhoto,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _hasActiveSession
                                      ? (_activeSessionHasPhoto
                                            ? Colors.green
                                            : Colors.red)
                                      : Colors.grey[300]!,
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
                                backgroundImage: _capturedPunchInPhoto != null
                                    ? FileImage(_capturedPunchInPhoto!)
                                          as ImageProvider
                                    : (_employeePhotoUrl != null &&
                                              _employeePhotoUrl!.isNotEmpty
                                          ? NetworkImage(_employeePhotoUrl!)
                                          : null),
                                child:
                                    _capturedPunchInPhoto == null &&
                                        (_employeePhotoUrl == null ||
                                            _employeePhotoUrl!.isEmpty)
                                    ? Icon(
                                        Icons.person,
                                        size: 50,
                                        color: Colors.grey[400],
                                      )
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
                                  child: const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            if (_hasActiveSession && !_activeSessionHasPhoto)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.add_a_photo,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_hasActiveSession && !_activeSessionHasPhoto) ...[
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: _attachSelfieToActiveSession,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFEBEE),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.redAccent,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Selfie Required for Punch-In',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Tap here to add selfie. Punch-out is blocked until added.',
                                        style: TextStyle(
                                          color: Colors.black87,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.camera_alt,
                                  color: Colors.red,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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
                      if (_employeeRole == 'manager' &&
                          _managerCompanyNames.isNotEmpty)
                        Text(
                          _managerCompanyNames.join(' • '),
                          style: const TextStyle(
                            color: Colors.blue,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        )
                      else if (_branchName != null && _branchName!.isNotEmpty)
                        Text(
                          _branchName!,
                          style: const TextStyle(
                            color: Colors.blue,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                      const SizedBox(height: 16),
                      if (!_hasActiveSession) ...[
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE3F2FD),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF90CAF9)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF1976D2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.my_location,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _lastPunchOutType == 'auto'
                                          ? 'Auto Punch-In Ready (Auto Punched Out)'
                                          : 'Punched Out (Manual)',
                                      style: const TextStyle(
                                        color: Color(0xFF0D47A1),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      _lastPunchOutType == 'auto'
                                          ? 'Will auto punch-in when you enter branch'
                                          : 'Manual punch out active. Use camera to punch in.',
                                      style: const TextStyle(
                                        color: Color(0xFF1565C0),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1976D2),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: _isProcessingPunch
                                    ? null
                                    : () => _checkGeofence(),
                                child: _isProcessingPunch
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text(
                                        'Check Now',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
                                _buildTimeBox(
                                  _formatTwoDigits(_workDuration.inHours),
                                  'Hour',
                                ),
                                const Text(
                                  ':',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                                _buildTimeBox(
                                  _formatTwoDigits(
                                    _workDuration.inMinutes % 60,
                                  ),
                                  'Min',
                                ),
                                const Text(
                                  ':',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                                _buildTimeBox(
                                  _formatTwoDigits(
                                    _workDuration.inSeconds % 60,
                                  ),
                                  'Sec',
                                ),
                              ],
                            ),
                            if (_dayType != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _dayType == 'full_day'
                                      ? Colors.green.withValues(alpha: 0.25)
                                      : Colors.orange.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                    color: _dayType == 'full_day'
                                        ? Colors.greenAccent
                                        : Colors.orangeAccent,
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _dayType == 'full_day'
                                          ? Icons.check_circle_rounded
                                          : Icons.warning_amber_rounded,
                                      color: _dayType == 'full_day'
                                          ? Colors.greenAccent
                                          : Colors.orangeAccent,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _dayType == 'full_day'
                                          ? 'Full Day'
                                          : 'Half Day',
                                      style: TextStyle(
                                        color: _dayType == 'full_day'
                                            ? Colors.greenAccent
                                            : Colors.orangeAccent,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      if (!_hasActiveSession &&
                          _capturedPunchInPhoto != null) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _isProcessingPunch
                                ? null
                                : () => _submitPunchIn(isAuto: false),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: _isProcessingPunch
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.login, size: 20),
                            label: Text(
                              _isProcessingPunch
                                  ? 'Punching in...'
                                  : 'Punch In',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (_breakDuration > Duration.zero) ...[
                        SizedBox(
                          height: 52,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE0B2),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.orange.withValues(alpha: 0.15),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: Colors.orange[800],
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.coffee,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Text(
                                  'Total Break  ',
                                  style: TextStyle(
                                    color: Colors.orange[900],
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${_formatTwoDigits(_breakDuration.inHours)}h : ${_formatTwoDigits(_breakDuration.inMinutes % 60)}m',
                                  style: TextStyle(
                                    color: Colors.orange[900],
                                    fontWeight: FontWeight.w900,
                                    fontSize: 22,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _hasActiveSession
                                ? Colors.orange[800]
                                : const Color(0xFFD32F2F),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: (_isLoggingOut || _isProcessingPunch)
                              ? null
                              : (_hasActiveSession
                                    ? _punchOut
                                    : _confirmLogout),
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
                                  _hasActiveSession
                                      ? Icons.punch_clock
                                      : Icons.logout_rounded,
                                  size: 20,
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
                      GestureDetector(
                        onTap: () => _showActivitiesBottomSheet(context),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.history,
                                  color: Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Your Activity',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'View your punch-in and break history',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios,
                                color: Colors.grey[400],
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  void _showActivitiesBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Color(0xFFF8F9FA),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 20),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Your Activity',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  children: [
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                              color:
                                                  activity['isActive'] == true
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
            ],
          ),
        );
      },
    );
  }

  Widget _buildTimeBox(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
      ],
    );
  }
}
