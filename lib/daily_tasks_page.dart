import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';

class DailyTasksPage extends StatefulWidget {
  const DailyTasksPage({super.key});

  @override
  State<DailyTasksPage> createState() => _DailyTasksPageState();
}

class _DailyTasksPageState extends State<DailyTasksPage> {
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = true;
  List<Map<String, dynamic>> _tasks = [];
  final Set<String> _togglingTaskIds = {};
  String _filter = 'all'; // 'all' | 'pending' | 'completed'
  String _frequencyFilter = 'all'; // 'all' | 'daily' | 'weekly' | 'monthly' | 'hourly'

  @override
  void initState() {
    super.initState();
    _fetchTasks();
  }

  Future<void> _fetchTasks() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.instance.fetchMyDailyTasks();
      if (res['success'] == true && res['tasks'] is List) {
        if (mounted) {
          setState(() {
            _tasks = List<Map<String, dynamic>>.from(
              (res['tasks'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
            );
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading daily tasks: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load tasks: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleTaskAction(Map<String, dynamic> task) {
    final taskId = task['id']?.toString() ?? '';
    final isCompleted = task['completed'] == true;
    final requiresPhoto = task['requiresPhoto'] == true;

    if (isCompleted) {
      // Confirm unmark if task is completed
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Mark as Incomplete?'),
          content: Text('Are you sure you want to mark "${task['title']}" as not completed?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _toggleTask(taskId, isCompleted);
              },
              child: const Text('Unmark', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    } else {
      // Completing task: check if photo proof required
      if (requiresPhoto) {
        _showPhotoProofSheet(task);
      } else {
        _toggleTask(taskId, isCompleted);
      }
    }
  }

  Future<void> _toggleTask(String taskId, bool currentCompleted) async {
    if (_togglingTaskIds.contains(taskId)) return;

    final targetCompleted = !currentCompleted;

    // Optimistic UI update
    setState(() {
      _togglingTaskIds.add(taskId);
      final index = _tasks.indexWhere((t) => t['id']?.toString() == taskId);
      if (index != -1) {
        _tasks[index]['completed'] = targetCompleted;
        if (targetCompleted) {
          _tasks[index]['completedAt'] = DateTime.now().toIso8601String();
        } else {
          _tasks[index]['completedAt'] = null;
        }
      }
    });

    try {
      final res = await ApiService.instance.toggleDailyTask(
        taskId: taskId,
        completed: targetCompleted,
      );
      if (res['success'] != true) {
        // Revert on failure
        if (mounted) {
          setState(() {
            final index = _tasks.indexWhere((t) => t['id']?.toString() == taskId);
            if (index != -1) {
              _tasks[index]['completed'] = currentCompleted;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error toggling task: $e');
      if (mounted) {
        setState(() {
          final index = _tasks.indexWhere((t) => t['id']?.toString() == taskId);
          if (index != -1) {
            _tasks[index]['completed'] = currentCompleted;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update task: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _togglingTaskIds.remove(taskId);
        });
      }
    }
  }

  void _showPhotoProofSheet(Map<String, dynamic> task) {
    final taskId = task['id']?.toString() ?? '';
    final title = task['title']?.toString() ?? 'Task';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        File? capturedImage;
        bool isSubmitting = false;
        final notesController = TextEditingController();

        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> pickImage(ImageSource source) async {
              try {
                final XFile? file = await _picker.pickImage(
                  source: source,
                  imageQuality: 80,
                  maxWidth: 1600,
                );
                if (file != null) {
                  setSheetState(() {
                    capturedImage = File(file.path);
                  });
                }
              } catch (e) {
                debugPrint('Error capturing photo: $e');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Could not access camera/gallery: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            }

            Future<void> submit() async {
              if (capturedImage == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please take a photo before completing this task.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              setSheetState(() => isSubmitting = true);
              try {
                // 1. Upload photo to media collection
                final uploadRes = await ApiService.instance.uploadTaskProofImage(capturedImage!);
                final photoId = uploadRes['id']?.toString();
                final photoUrl = uploadRes['url']?.toString();

                // 2. Toggle task complete with photo proof
                final res = await ApiService.instance.toggleDailyTask(
                  taskId: taskId,
                  completed: true,
                  photoId: photoId,
                  photoUrl: photoUrl,
                  notes: notesController.text.trim().isNotEmpty ? notesController.text.trim() : null,
                );

                if (res['success'] == true) {
                  if (mounted) {
                    setState(() {
                      final idx = _tasks.indexWhere((t) => t['id']?.toString() == taskId);
                      if (idx != -1) {
                        _tasks[idx]['completed'] = true;
                        _tasks[idx]['completedAt'] = DateTime.now().toIso8601String();
                        _tasks[idx]['photo'] = photoId;
                        _tasks[idx]['photoUrl'] = photoUrl;
                        if (notesController.text.trim().isNotEmpty) {
                          _tasks[idx]['notes'] = notesController.text.trim();
                        }
                      }
                    });
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text('Task "$title" completed with photo proof!')),
                          ],
                        ),
                        backgroundColor: Colors.green[700],
                      ),
                    );
                  }
                } else {
                  throw Exception(res['message'] ?? 'Failed to update task completion');
                }
              } catch (e) {
                debugPrint('Error uploading task photo: $e');
                if (context.mounted) {
                  setSheetState(() => isSubmitting = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Upload failed: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            }

            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return Container(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: 20 + bottomInset,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Header
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.amber,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Photo Proof Required',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                title,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Photo Area
                    if (capturedImage != null) ...[
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.file(
                              capturedImage!,
                              height: 220,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: CircleAvatar(
                              backgroundColor: Colors.black54,
                              radius: 18,
                              child: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.white, size: 18),
                                padding: EdgeInsets.zero,
                                onPressed: isSubmitting
                                    ? null
                                    : () => setSheetState(() => capturedImage = null),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: isSubmitting ? null : () => pickImage(ImageSource.camera),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Retake with Camera'),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: isSubmitting ? null : () => pickImage(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library, size: 16),
                            label: const Text('Gallery'),
                          ),
                        ],
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.indigo.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.add_a_photo_rounded,
                                size: 36,
                                color: Color(0xFF2E3192),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Take photo proof of completed work',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Camera capture is required to verify this task.',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => pickImage(ImageSource.camera),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2E3192),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    elevation: 0,
                                  ),
                                  icon: const Icon(Icons.camera_alt, size: 18),
                                  label: const Text(
                                    'Open Camera',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                OutlinedButton.icon(
                                  onPressed: () => pickImage(ImageSource.gallery),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  icon: const Icon(Icons.photo_library, size: 18),
                                  label: const Text('Gallery'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Notes (optional)
                    TextField(
                      controller: notesController,
                      enabled: !isSubmitting,
                      decoration: InputDecoration(
                        hintText: 'Notes / Remarks (optional)',
                        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        filled: true,
                        fillColor: Colors.grey[50],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Submit button
                    ElevatedButton(
                      onPressed: (capturedImage == null || isSubmitting) ? null : submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey[300],
                        disabledForegroundColor: Colors.grey[500],
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Verify & Mark Completed',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showImagePreviewDialog(String imageUrl, String title) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.photo, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: Container(
                color: Colors.black,
                constraints: const BoxConstraints(maxHeight: 500),
                child: InteractiveViewer(
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const SizedBox(
                        height: 250,
                        child: Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => const SizedBox(
                      height: 200,
                      child: Center(
                        child: Text(
                          'Failed to load image',
                          style: TextStyle(color: Colors.white70),
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

  @override
  Widget build(BuildContext context) {
    final completedCount = _tasks.where((t) => t['completed'] == true).length;
    final totalCount = _tasks.length;
    final pendingCount = totalCount - completedCount;

    List<Map<String, dynamic>> displayedTasks = _tasks;
    if (_filter == 'pending') {
      displayedTasks = displayedTasks.where((t) => t['completed'] != true).toList();
    } else if (_filter == 'completed') {
      displayedTasks = displayedTasks.where((t) => t['completed'] == true).toList();
    }

    if (_frequencyFilter != 'all') {
      displayedTasks = displayedTasks.where((t) {
        final f = (t['frequency']?.toString().toLowerCase().trim() ?? 'daily');
        return f == _frequencyFilter;
      }).toList();
    }

    final todayFormatted = DateFormat('EEEE, d MMMM yyyy').format(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Work Tasks',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchTasks,
            tooltip: 'Refresh tasks',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchTasks,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. DATE & SUMMARY CARD
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2E3192).withValues(alpha: 0.25),
                      blurRadius: 15,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.white70, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          todayFormatted,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Task Progress',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              totalCount == 0
                                  ? '0 Tasks'
                                  : '$completedCount / $totalCount Completed',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            totalCount == 0
                                ? '0%'
                                : '${((completedCount / totalCount) * 100).round()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: totalCount > 0 ? (completedCount / totalCount) : 0.0,
                        minHeight: 8,
                        backgroundColor: Colors.white.withValues(alpha: 0.25),
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 2. FILTER TABS (All | Pending | Completed)
              if (totalCount > 0) ...[
                Row(
                  children: [
                    _buildFilterChip('All', 'all', totalCount),
                    const SizedBox(width: 8),
                    _buildFilterChip('Pending', 'pending', pendingCount),
                    const SizedBox(width: 8),
                    _buildFilterChip('Completed', 'completed', completedCount),
                  ],
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFrequencyChip('All Periods', 'all', Icons.tune_rounded),
                      _buildFrequencyChip('Daily', 'daily', Icons.repeat_rounded),
                      _buildFrequencyChip('Weekly', 'weekly', Icons.date_range_rounded),
                      _buildFrequencyChip('Monthly', 'monthly', Icons.calendar_month_rounded),
                      _buildFrequencyChip('Hourly', 'hourly', Icons.access_time_rounded),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // 3. TASK LIST OR EMPTY STATE
              if (_isLoading && _tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF2E3192)),
                  ),
                )
              else if (_tasks.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.task_alt,
                          size: 40,
                          color: Color(0xFF2E3192),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'No Tasks Found',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'There are no active tasks assigned to your role or profile today.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              else if (displayedTasks.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text(
                      'No $_filter tasks',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: displayedTasks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final task = displayedTasks[index];
                    final taskId = task['id']?.toString() ?? '';
                    final isCompleted = task['completed'] == true;
                    final isToggling = _togglingTaskIds.contains(taskId);
                    final title = task['title']?.toString() ?? 'Task';
                    final desc = task['description']?.toString() ?? '';
                    final priority =
                        task['priority']?.toString().toLowerCase() ?? 'medium';
                    final assignedRole = task['assignedRole']?.toString() ?? '';
                    final completedAtStr = task['completedAt']?.toString();

                    final frequency = task['frequency']?.toString().toLowerCase().trim() ?? 'daily';

                    Color freqBg = Colors.blue.withValues(alpha: 0.08);
                    Color freqFg = Colors.blue[800]!;
                    Color freqBorder = Colors.blue.withValues(alpha: 0.25);
                    IconData freqIcon = Icons.repeat_rounded;
                    String freqLabel = 'DAILY';

                    if (frequency == 'hourly') {
                      freqBg = Colors.amber.withValues(alpha: 0.12);
                      freqFg = Colors.amber[900]!;
                      freqBorder = Colors.amber.withValues(alpha: 0.35);
                      freqIcon = Icons.access_time_rounded;
                      freqLabel = 'HOURLY';
                    } else if (frequency == 'weekly') {
                      freqBg = Colors.indigo.withValues(alpha: 0.1);
                      freqFg = const Color(0xFF2E3192);
                      freqBorder = Colors.indigo.withValues(alpha: 0.25);
                      freqIcon = Icons.date_range_rounded;
                      freqLabel = 'WEEKLY';
                    } else if (frequency == 'monthly') {
                      freqBg = Colors.teal.withValues(alpha: 0.1);
                      freqFg = Colors.teal[800]!;
                      freqBorder = Colors.teal.withValues(alpha: 0.25);
                      freqIcon = Icons.calendar_month_rounded;
                      freqLabel = 'MONTHLY';
                    }

                    String completionStatusText = 'Done';
                    if (completedAtStr != null && completedAtStr.isNotEmpty) {
                      try {
                        final dt = DateTime.parse(completedAtStr).toLocal();
                        final now = DateTime.now();
                        final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
                        final timeStr = DateFormat('hh:mm a').format(dt);
                        if (frequency == 'hourly') {
                          completionStatusText = 'Done this hour • $timeStr';
                        } else if (frequency == 'weekly') {
                          if (isToday) {
                            completionStatusText = 'Done this week • Today $timeStr';
                          } else {
                            completionStatusText = 'Done this week • ${DateFormat('EEE, MMM d').format(dt)}';
                          }
                        } else if (frequency == 'monthly') {
                          if (isToday) {
                            completionStatusText = 'Done this month • Today $timeStr';
                          } else {
                            completionStatusText = 'Done this month • ${DateFormat('MMM d').format(dt)}';
                          }
                        } else {
                          completionStatusText = 'Done today at $timeStr';
                        }
                      } catch (_) {
                        completionStatusText = 'Done';
                      }
                    }

                    Color priorityBg = Colors.grey[100]!;
                    Color priorityFg = Colors.grey[700]!;
                    if (priority == 'urgent') {
                      priorityBg = Colors.red[50]!;
                      priorityFg = Colors.red[700]!;
                    } else if (priority == 'high') {
                      priorityBg = Colors.orange[50]!;
                      priorityFg = Colors.orange[800]!;
                    } else if (priority == 'low') {
                      priorityBg = Colors.blue[50]!;
                      priorityFg = Colors.blue[700]!;
                    }

                    return InkWell(
                      onTap: isToggling ? null : () => _handleTaskAction(task),
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isCompleted
                              ? Colors.green.withValues(alpha: 0.04)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                          border: Border.all(
                            color: isCompleted
                                ? Colors.green.withValues(alpha: 0.35)
                                : Colors.grey[200]!,
                            width: isCompleted ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: SizedBox(
                                width: 26,
                                height: 26,
                                child: isToggling
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Checkbox(
                                        value: isCompleted,
                                        activeColor: Colors.green,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        onChanged: isToggling
                                            ? null
                                            : (_) => _handleTaskAction(task),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: isCompleted
                                          ? Colors.grey[500]
                                          : Colors.black87,
                                      decoration: isCompleted
                                          ? TextDecoration.lineThrough
                                          : TextDecoration.none,
                                    ),
                                  ),
                                  if (desc.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      desc,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.grey[600],
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: priorityBg,
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                        child: Text(
                                          priority.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: priorityFg,
                                          ),
                                        ),
                                      ),
                                      // Recurrence frequency badge (HOURLY, DAILY, WEEKLY, MONTHLY)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: freqBg,
                                          borderRadius: BorderRadius.circular(5),
                                          border: Border.all(
                                            color: freqBorder,
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              freqIcon,
                                              size: 10.5,
                                              color: freqFg,
                                            ),
                                            const SizedBox(width: 3.5),
                                            Text(
                                              freqLabel,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: freqFg,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (assignedRole.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.purple.withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: Text(
                                            assignedRole.toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.purple[700],
                                            ),
                                          ),
                                        ),
                                      if (task['requiresPhoto'] == true)
                                        GestureDetector(
                                          onTap: isCompleted && (task['photoUrl'] != null && task['photoUrl'].toString().isNotEmpty)
                                              ? () => _showImagePreviewDialog(task['photoUrl'].toString(), title)
                                              : (isToggling ? null : () => _handleTaskAction(task)),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 7,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isCompleted
                                                  ? Colors.teal.withValues(alpha: 0.12)
                                                  : Colors.amber.withValues(alpha: 0.16),
                                              borderRadius: BorderRadius.circular(5),
                                              border: Border.all(
                                                color: isCompleted
                                                    ? Colors.teal.withValues(alpha: 0.35)
                                                    : Colors.amber.withValues(alpha: 0.45),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  isCompleted ? Icons.camera_alt : Icons.add_a_photo,
                                                  size: 11,
                                                  color: isCompleted ? Colors.teal[800] : Colors.amber[900],
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  isCompleted ? 'PHOTO PROOF' : 'PHOTO REQUIRED',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: isCompleted ? Colors.teal[800] : Colors.amber[900],
                                                  ),
                                                ),
                                                if (isCompleted && task['photoUrl'] != null && task['photoUrl'].toString().isNotEmpty) ...[
                                                  const SizedBox(width: 3),
                                                  Icon(Icons.open_in_new, size: 10, color: Colors.teal[800]),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      if (isCompleted)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(5),
                                            border: Border.all(
                                              color: Colors.green.withValues(alpha: 0.3),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.check_circle_rounded,
                                                size: 11,
                                                color: Colors.green[800],
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                completionStatusText,
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.green[800],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (isCompleted && task['photoUrl'] != null && task['photoUrl'].toString().isNotEmpty) ...[
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: () => _showImagePreviewDialog(task['photoUrl'].toString(), title),
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey[300]!),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(7),
                                    child: Image.network(
                                      task['photoUrl'].toString(),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 20, color: Colors.grey),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, int count) {
    final isSelected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2E3192) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF2E3192) : Colors.grey[300]!,
          ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.25)
                    : Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.grey[700],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrequencyChip(String label, String value, IconData icon) {
    final isSelected = _frequencyFilter == value;
    final count = value == 'all'
        ? _tasks.length
        : _tasks.where((t) => (t['frequency']?.toString().toLowerCase().trim() ?? 'daily') == value).length;

    if (value != 'all' && count == 0) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => setState(() => _frequencyFilter = value),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2E3192) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF2E3192) : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.white : Colors.grey[700],
            ),
            const SizedBox(width: 5),
            Text(
              '$label ($count)',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

