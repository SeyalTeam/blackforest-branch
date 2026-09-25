import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'api_config.dart';
import 'geofence_util.dart';

class AttendanceManager {
  static final AttendanceManager instance = AttendanceManager._internal();
  AttendanceManager._internal();

  

  final StreamController<Map<String, dynamic>> _updateController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onAttendanceUpdate => _updateController.stream;

  Timer? _foregroundTimer;
  static bool _isExecuting = false;
  static DateTime? _lastActionTime;
  static int _consecutiveOutsideTicks = 0;

  /// Starts the app-wide foreground geofence watcher that runs every 15-20 seconds
  /// regardless of which page the user is viewing.
  void startForegroundWatcher() {
    _foregroundTimer?.cancel();
    _foregroundTimer = null;

    debugPrint('AttendanceManager: Starting foreground attendance watcher...');
    // Initial immediate check
    checkNow();

    // Check periodically in the foreground
    _foregroundTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      await checkAndProcessAttendance(isBackground: false);
    });
  }

  /// Stops the foreground attendance watcher (e.g. on user logout).
  void stopForegroundWatcher() {
    debugPrint('AttendanceManager: Stopping foreground attendance watcher.');
    _foregroundTimer?.cancel();
    _foregroundTimer = null;
    _consecutiveOutsideTicks = 0;
  }

  /// Immediately triggers a check and auto-punch-in / auto-punch-out evaluation.
  Future<void> checkNow() async {
    await checkAndProcessAttendance(isBackground: false);
  }

  /// Core logic executed by both the foreground manager and the background service.
  static Future<void> checkAndProcessAttendance({bool isBackground = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (_isExecuting) {
      debugPrint('AttendanceManager: Check already in progress, skipping tick.');
      return;
    }

    _isExecuting = true;
    try {
      final token = prefs.getString('token');
      final userId = prefs.getString('userId');

      if (token == null || token.isEmpty || userId == null || userId.isEmpty) {
        // User not logged in, nothing to do
        return;
      }

      // 1. Check GPS position & Geofence
      final geo = await GeofenceUtil.checkLocationAndGeofence();
      final position = geo.position;

      if (position == null) {
        debugPrint('AttendanceManager: Could not get GPS fix. Skipping attendance check.');
        return;
      }

      final isInside = geo.isInside;

      // 2. Fetch today's attendance document for this user
      final now = DateTime.now();
      final localMidnight = DateTime(now.year, now.month, now.day);
      final queryDate = localMidnight
          .subtract(const Duration(days: 1))
          .toUtc()
          .toIso8601String();
      final queryDateStr = DateFormat('yyyy-MM-dd').format(localMidnight);

      final url =
          '${ApiConfig.baseUrl}/attendance?where[user][equals]=$userId&where[date][greater_than_equal]=$queryDate&sort=-date&limit=5';

      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('AttendanceManager: Failed to fetch attendance (${response.statusCode})');
        return;
      }

      final data = jsonDecode(response.body);
      final docs = (data is Map<String, dynamic> ? data['docs'] : null) as List?;
      if (docs == null) return;

      // 3. Stale session auto-close (past days active sessions)
      for (final dynamic doc in docs) {
        if (doc is! Map<String, dynamic>) continue;
        final acts = (doc['activities'] as List?) ?? [];
        bool modified = false;

        for (final dynamic a in acts) {
          if (a is Map<String, dynamic> &&
              a['type'] == 'session' &&
              a['status'] == 'active') {
            final punchIn = DateTime.tryParse(a['punchIn']?.toString() ?? '')?.toLocal();
            if (punchIn != null && punchIn.isBefore(localMidnight)) {
              final endOfDay = DateTime(
                punchIn.year,
                punchIn.month,
                punchIn.day,
                23,
                59,
                59,
              );
              a['punchOut'] = endOfDay.toUtc().toIso8601String();
              a['status'] = 'closed';
              a['durationSeconds'] = endOfDay.difference(punchIn).inSeconds;
              a['punchOutType'] = 'auto';
              modified = true;
            }
          }
        }

        if (modified && doc['id'] != null) {
          try {
            await http.patch(
              Uri.parse('${ApiConfig.baseUrl}/attendance/${doc['id']}'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'activities': acts}),
            );
          } catch (e) {
            debugPrint('AttendanceManager: Stale session close error: $e');
          }
        }
      }

      // 4. Resolve today's document and current session state
      Map<String, dynamic>? todayDoc;
      String? docId;
      List<dynamic> rawActivities = [];

      if (docs.isNotEmpty && docs.first is Map<String, dynamic>) {
        final firstDoc = docs.first as Map<String, dynamic>;
        final docDateStr = firstDoc['dateString']?.toString() ?? '';
        if (docDateStr == queryDateStr ||
            (firstDoc['date']?.toString().startsWith(queryDateStr) == true)) {
          todayDoc = firstDoc;
          docId = firstDoc['id']?.toString();
          rawActivities = List<dynamic>.from((firstDoc['activities'] as List?) ?? []);
        }
      }

      Map<String, dynamic>? activeSession;
      bool activePhotoFound = true;
      String? latestPunchOutType;

      for (int i = rawActivities.length - 1; i >= 0; i--) {
        final a = rawActivities[i];
        if (a is Map<String, dynamic> &&
            a['type'] == 'session' &&
            a['status'] == 'active') {
          activeSession = a;
          final img = a['capturedImage'];
          activePhotoFound = img != null && img.toString().trim().isNotEmpty;
          break;
        }
      }

      if (activeSession == null) {
        // Find latest closed session punchOutType from today or previous doc
        for (final doc in docs) {
          final acts = (doc is Map ? doc['activities'] : null) as List?;
          if (acts == null) continue;
          for (int i = acts.length - 1; i >= 0; i--) {
            final a = acts[i];
            if (a is Map && a['type'] == 'session' && a['status'] == 'closed') {
              latestPunchOutType = a['punchOutType']?.toString();
              break;
            }
          }
          if (latestPunchOutType != null) break;
        }

        if (latestPunchOutType == null) {
          latestPunchOutType = prefs.getString('lastPunchOutType');
        }
      }

      debugPrint(
        'AttendanceManager tick: [bg=$isBackground] isInside=$isInside, hasActive=${activeSession != null}, hasPhoto=$activePhotoFound, lastPunchOut=$latestPunchOutType',
      );

      // ── 5. AUTO PUNCH OUT EVALUATION ──────────────────────────────────────
      if (activeSession != null) {
        if (!isInside) {
          _consecutiveOutsideTicks++;

          if (_consecutiveOutsideTicks >= 1) {
            // Punch out
            final punchInStr = activeSession['punchIn']?.toString() ?? '';
            final punchInTime = DateTime.tryParse(punchInStr)?.toLocal() ?? now;
            final durationSecs = now.difference(punchInTime).inSeconds;

            activeSession['punchOut'] = now.toUtc().toIso8601String();
            activeSession['status'] = 'closed';
            activeSession['durationSeconds'] = durationSecs > 0 ? durationSecs : 0;
            activeSession['punchOutType'] = 'auto';

            final patchUrl = '${ApiConfig.baseUrl}/attendance/$docId';
            final patchRes = await http.patch(
              Uri.parse(patchUrl),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'activities': rawActivities}),
            );

            if (patchRes.statusCode == 200) {
              debugPrint('AttendanceManager: Auto punch-out SUCCESS!');
              await prefs.setString('lastPunchOutType', 'auto');
              _consecutiveOutsideTicks = 0;

              await _showLocalNotification(
                id: 991,
                title: '🏢 Auto Punched Out',
                body: 'You left the branch area. Your work session has been automatically punched out.',
                payload: 'profile',
              );

              if (!isBackground) {
                instance._updateController.add({
                  'type': 'auto_punch_out',
                  'docId': docId,
                  'timestamp': now.toIso8601String(),
                });
              }
            } else {
              debugPrint('AttendanceManager: Auto punch-out failed on server (${patchRes.statusCode}): ${patchRes.body}');
            }
          }
        } else {
          // Inside branch
          _consecutiveOutsideTicks = 0;
        }
      }

      // ── 6. AUTO PUNCH IN EVALUATION ───────────────────────────────────────
      else {
        _consecutiveOutsideTicks = 0;
        // User rule: Auto punch-in only proceeds IF previous session ended via AUTO punch-out
        final shouldAutoPunchIn = latestPunchOutType == 'auto';

        if (shouldAutoPunchIn && isInside) {
          // Debounce to prevent rapid re-triggering
          if (_lastActionTime != null &&
              now.difference(_lastActionTime!).inSeconds < 25) {
            debugPrint('AttendanceManager: Auto punch-in debounced (recently executed).');
            return;
          }
          _lastActionTime = now;

          final newActivity = {
            'type': 'session',
            'punchIn': now.toUtc().toIso8601String(),
            'status': 'active',
            'capturedImage': null,
            'punchInType': 'auto',
            'latitude': position.latitude,
            'longitude': position.longitude,
          };

          if (docId != null) {
            final updatedActivities = List<dynamic>.from(rawActivities)..add(newActivity);
            final patchUrl = '${ApiConfig.baseUrl}/attendance/$docId';
            final patchRes = await http.patch(
              Uri.parse(patchUrl),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'activities': updatedActivities}),
            );

            if (patchRes.statusCode == 200) {
              debugPrint('AttendanceManager: Auto punch-in SUCCESS (patched)!');
              await prefs.remove('lastPunchOutType');

              await _showLocalNotification(
                id: 992,
                title: '⚡ Auto Punched In',
                body: 'You arrived at the branch! Session started. Tap here to add your selfie.',
                payload: 'auto_punch_in',
              );

              if (!isBackground) {
                instance._updateController.add({
                  'type': 'auto_punch_in',
                  'docId': docId,
                  'timestamp': now.toIso8601String(),
                });
              }
            } else {
              debugPrint('AttendanceManager: Auto punch-in PATCH failed (${patchRes.statusCode}): ${patchRes.body}');
            }
          } else {
            // Create new today document
            final postUrl = '${ApiConfig.baseUrl}/attendance';
            final postRes = await http.post(
              Uri.parse(postUrl),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'user': userId,
                'date': localMidnight.toUtc().toIso8601String(),
                'dateString': queryDateStr,
                'activities': [newActivity],
              }),
            );

            if (postRes.statusCode == 200 || postRes.statusCode == 201) {
              debugPrint('AttendanceManager: Auto punch-in SUCCESS (posted new doc)!');
              await prefs.remove('lastPunchOutType');

              await _showLocalNotification(
                id: 992,
                title: '⚡ Auto Punched In',
                body: 'You arrived at the branch! Session started. Tap here to add your selfie.',
                payload: 'auto_punch_in',
              );

              if (!isBackground) {
                instance._updateController.add({
                  'type': 'auto_punch_in',
                  'timestamp': now.toIso8601String(),
                });
              }
            } else {
              debugPrint('AttendanceManager: Auto punch-in POST failed (${postRes.statusCode}): ${postRes.body}');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('AttendanceManager error: $e');
    } finally {
      _isExecuting = false;
    }
  }

  static Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      final notificationsPlugin = FlutterLocalNotificationsPlugin();

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'auto_attendance_channel',
        'Auto Attendance Alerts',
        description: 'Notifications for automatic punch-in and punch-out based on geofence',
        importance: Importance.max,
      );

      await notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'auto_attendance_channel',
        'Auto Attendance Alerts',
        channelDescription: 'Notifications for automatic punch-in and punch-out based on geofence',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'Attendance Alert',
        icon: '@mipmap/launcher_icon',
      );

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await notificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: platformDetails,
        payload: payload,
      );
    } catch (e) {
      debugPrint('AttendanceManager notification error: $e');
    }
  }
}
