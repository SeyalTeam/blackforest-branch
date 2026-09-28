import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';

class AttendanceCalendarPage extends StatefulWidget {
  const AttendanceCalendarPage({super.key});

  @override
  State<AttendanceCalendarPage> createState() => _AttendanceCalendarPageState();
}

class _AttendanceCalendarPageState extends State<AttendanceCalendarPage> {
  DateTime _currentMonth = DateTime.now();
  DateTime _selectedDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  Map<String, Map<String, dynamic>> _attendanceMap = {};
  bool _isLoading = true;

  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _fetchMonthlyAttendance();
  }

  Future<void> _fetchMonthlyAttendance() async {
    setState(() => _isLoading = true);
    try {
      final monthStr = DateFormat('yyyy-MM').format(_currentMonth);

      // We need the current user ID to filter (or query directly)
      final userId = await _storage.read(key: 'userId');
      final token = await _storage.read(key: 'token');

      // Query the attendance collection directly (fetch latest 100 for this user)
      final url = Uri.parse(
        '${ApiService.baseUrl}/attendance?where[user][equals]=$userId&sort=-date&limit=100',
      );

      final res = await http.get(
        url,
        headers: {if (token != null) 'Authorization': 'Bearer $token'},
      );

      final newMap = <String, Map<String, dynamic>>{};
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final docs = data['docs'] as List?;
        if (docs != null) {
          for (final doc in docs) {
            final ds = doc['dateString'] as String?;
            if (ds != null) {
              newMap[ds] = doc as Map<String, dynamic>;
            }
          }
        }
      } else {
        debugPrint('Failed to load attendance: ${res.statusCode}');
      }

      if (mounted) {
        setState(() {
          _attendanceMap = newMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching monthly attendance: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
    _fetchMonthlyAttendance();
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    });
    _fetchMonthlyAttendance();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Calendar',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 4),
                    ],
                  ),
                  child: const Icon(
                    Icons.calendar_month,
                    color: Colors.blue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(Icons.list, color: Colors.grey, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildMonthSelector(),
                  const SizedBox(height: 16),
                  _buildCalendarGrid(),
                  const SizedBox(height: 24),
                  _buildLegend(),
                  const SizedBox(height: 24),
                  _buildPendingRegularization(),
                  const SizedBox(height: 24),
                  _buildSelectedDateActivity(),
                ],
              ),
            ),
    );
  }

  Widget _buildMonthSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: _previousMonth,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chevron_left, color: Colors.blue),
          ),
        ),
        Text(
          DateFormat('MMMM yyyy').format(_currentMonth),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        GestureDetector(
          onTap: _nextMonth,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chevron_right, color: Colors.blue),
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarGrid() {
    final daysInMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month + 1,
      0,
    ).day;
    final firstDayWeekday = DateTime(
      _currentMonth.year,
      _currentMonth.month,
      1,
    ).weekday; // 1=Mon, 7=Sun
    final startingOffset = firstDayWeekday % 7; // Map so Sun=0, Mon=1, etc.

    final totalCells = ((daysInMonth + startingOffset) / 7).ceil() * 7;

    return Container(
      padding: const EdgeInsets.all(16),
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
      ),
      child: Column(
        children: [
          // Weekday headers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                .map(
                  (day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          // Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: totalCells,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.85,
            ),
            itemBuilder: (context, index) {
              if (index < startingOffset ||
                  index >= startingOffset + daysInMonth) {
                return const SizedBox.shrink();
              }
              final day = index - startingOffset + 1;
              final date = DateTime(
                _currentMonth.year,
                _currentMonth.month,
                day,
              );
              return _buildDayCell(date);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell(DateTime date) {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final isToday = dateStr == DateFormat('yyyy-MM-dd').format(DateTime.now());

    final attendance = _attendanceMap[dateStr];

    // Status Logic
    bool isPresent = attendance != null;
    bool isHalfDay = attendance?['dayType'] == 'half_day';
    bool isLate = attendance?['isLate'] == true;
    final now = DateTime.now();
    bool isAbsent =
        !isPresent && date.isBefore(DateTime(now.year, now.month, now.day));
    bool isSunday = date.weekday == 7;

    // Colors based on image
    Color bgColor = const Color(0xFFF0F2F5); // default future or empty
    Color textColor = Colors.grey[600]!;
    Border? border;

    if (isToday) {
      border = Border.all(color: Colors.blue, width: 2);
    }

    if (isPresent) {
      if (isHalfDay) {
        bgColor = const Color(0xFFFFF3E0); // light orange
        textColor = Colors.orange[900]!;
      } else {
        bgColor = const Color(0xFFE8F5E9); // light green
        textColor = Colors.green[800]!;
      }
    } else if (isSunday && date.isBefore(DateTime.now())) {
      bgColor = Colors.grey[200]!;
      textColor = Colors.grey[700]!;
    } else if (isAbsent) {
      bgColor = const Color(0xFFFFEBEE); // light red
      textColor = Colors.red[800]!;
    }

    final isSelected =
        dateStr == DateFormat('yyyy-MM-dd').format(_selectedDate);
    if (isSelected) {
      border = Border.all(color: Colors.black87, width: 2);
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedDate = date;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: border,
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                '${date.day}',
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            if (isHalfDay)
              const Positioned(
                bottom: 4,
                left: 4,
                child: Icon(
                  Icons.access_time_filled,
                  color: Colors.orange,
                  size: 10,
                ),
              ),
            if (isLate)
              const Positioned(
                bottom: 4,
                right: 4,
                child: Icon(
                  Icons.running_with_errors,
                  color: Colors.redAccent,
                  size: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: [
        _buildLegendItem('Today', Colors.blue, isOutline: true),
        _buildLegendItem('Present', Colors.green),
        _buildLegendItem('Absent', Colors.red),
        _buildLegendItem('On leave', Colors.purple),
        _buildLegendItem(
          'Half Day',
          Colors.orange,
          icon: Icons.access_time_filled,
        ),
        _buildLegendItem('Week Off', Colors.blueGrey),
        _buildLegendItem('Holiday', Colors.teal),
        _buildLegendItem(
          'Late',
          Colors.redAccent,
          icon: Icons.running_with_errors,
        ),
        _buildLegendItem(
          'Punch Error',
          Colors.orange,
          icon: Icons.warning_rounded,
        ),
      ],
    );
  }

  Widget _buildLegendItem(
    String label,
    Color color, {
    bool isOutline = false,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, color: color, size: 14)
          else if (isOutline)
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
            )
          else
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[800],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _processActivitiesForDate(List rawActivities) {
    final List<Map<String, dynamic>> allActivities = [];

    for (final rawActivity in rawActivities) {
      if (rawActivity['type'] != 'session') continue;

      final punchInStr = rawActivity['punchIn'];
      if (punchInStr == null) continue;

      final punchIn = DateTime.parse(punchInStr.toString()).toLocal();
      final punchOutStr = rawActivity['punchOut'];
      final status = rawActivity['status']?.toString();
      final breakDurationSeconds =
          (rawActivity['breakDurationSeconds'] as num?)?.toInt() ?? 0;

      final inTimeStr = DateFormat('hh:mm a').format(punchIn);
      String outTimeStr = '-';
      if (punchOutStr != null) {
        final punchOut = DateTime.parse(punchOutStr.toString()).toLocal();
        outTimeStr = DateFormat('hh:mm a').format(punchOut);
      }

      if (breakDurationSeconds > 0) {
        final breakDur = Duration(seconds: breakDurationSeconds);
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

      allActivities.add({
        'type': 'session',
        'inTime': inTimeStr,
        'outTime': outTimeStr,
        'color': Colors.white,
        'startTime': punchIn,
        'isActive': status == 'active',
      });
    }

    allActivities.sort((a, b) {
      final tA = a['startTime'] as DateTime;
      final tB = b['startTime'] as DateTime;
      return tB.compareTo(tA);
    });

    return allActivities;
  }

  Widget _buildSelectedDateActivity() {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final isToday = dateStr == DateFormat('yyyy-MM-dd').format(DateTime.now());
    final title = isToday
        ? 'Today\'s Activity'
        : '${DateFormat('MMM d, yyyy').format(_selectedDate)} Activity';

    final attendance = _attendanceMap[dateStr];
    final rawActivities = (attendance?['activities'] as List?) ?? [];
    final activities = _processActivitiesForDate(rawActivities);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.history, color: Colors.black87),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (activities.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Center(
              child: Text(
                isToday
                    ? 'No activity for today yet'
                    : 'No activity on this date',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ...activities.map((activity) {
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
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildPendingRegularization() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.calendar_today_outlined, color: Colors.black87),
            SizedBox(width: 8),
            Text(
              'Pending Regularization',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Empty state for now
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: const Center(
            child: Text(
              'No pending items',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }
}
