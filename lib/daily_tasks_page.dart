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

  bool _isTaskYes(Map<String, dynamic> task) {
    final status = task['status']?.toString().toLowerCase().trim();
    if (status == 'yes') return true;
    if (status == null && task['completed'] == true) return true;
    return false;
  }

  bool _isTaskNo(Map<String, dynamic> task) {
    final status = task['status']?.toString().toLowerCase().trim();
    return status == 'no';
  }

  bool _isTaskNoComplaint(Map<String, dynamic> task) {
    final status = task['status']?.toString().toLowerCase().trim();
    return status == 'no_complaint';
  }

  bool _isTaskAnswered(Map<String, dynamic> task) {
    final status = task['status']?.toString().toLowerCase().trim();
    if (status != null && status.isNotEmpty) return true;
    if (task['completed'] == true) return true;
    return false;
  }

  IconData _getTaskIcon(String title, String desc) {
    final lower = '$title $desc'.toLowerCase();
    if (lower.contains('complaint') || lower.contains('புகார்') || lower.contains('customer') || lower.contains('வாடிக்கையாளர்')) {
      return Icons.chat_bubble_rounded;
    }
    if (lower.contains('equipment') || lower.contains('machine') || lower.contains('clean & maintain') || lower.contains('கருவி')) {
      return Icons.settings_rounded;
    }
    if (lower.contains('clean') || lower.contains('neat') || lower.contains('sweep') || lower.contains('தூய்மை') || lower.contains('சுத்தம்')) {
      return Icons.cleaning_services_rounded;
    }
    if (lower.contains('team') || lower.contains('support') || lower.contains('cooperate') || lower.contains('குழு') || lower.contains('உதவி')) {
      return Icons.groups_rounded;
    }
    if (lower.contains('stock') || lower.contains('order') || lower.contains('inventory') || lower.contains('பொருட்கள்')) {
      return Icons.inventory_2_rounded;
    }
    if (lower.contains('cash') || lower.contains('bill') || lower.contains('money') || lower.contains('பணம்')) {
      return Icons.payments_rounded;
    }
    if (lower.contains('kitchen') || lower.contains('food') || lower.contains('cake') || lower.contains('bake') || lower.contains('சமையல்')) {
      return Icons.restaurant_rounded;
    }
    return Icons.task_alt_rounded;
  }

  Color _getTaskIconColor(String title, String desc) {
    final lower = '$title $desc'.toLowerCase();
    if (lower.contains('complaint') || lower.contains('புகார்') || lower.contains('customer')) {
      return const Color(0xFFF59E0B);
    }
    if (lower.contains('equipment') || lower.contains('machine') || lower.contains('clean & maintain') || lower.contains('கருவி')) {
      return const Color(0xFF334155);
    }
    if (lower.contains('clean') || lower.contains('neat') || lower.contains('sweep') || lower.contains('தூய்மை') || lower.contains('சுத்தம்')) {
      return const Color(0xFFEA580C);
    }
    if (lower.contains('team') || lower.contains('support') || lower.contains('cooperate') || lower.contains('குழு') || lower.contains('உதவி')) {
      return const Color(0xFF2563EB);
    }
    return const Color(0xFF2E3192);
  }

  Future<void> _handleTaskAction(Map<String, dynamic> task, String targetStatus) async {
    final taskId = task['id']?.toString() ?? '';
    final currentStatus = task['status']?.toString();
    final requiresPhoto = task['requiresPhoto'] == true;

    if (currentStatus == targetStatus) {
      return;
    }

    if (targetStatus == 'yes') {
      if (requiresPhoto) {
        _showPhotoProofSheet(task);
      } else {
        await _updateTaskStatus(taskId, 'yes');
      }
    } else if (targetStatus == 'no') {
      // Direct update to 'no' - no photo required!
      await _updateTaskStatus(taskId, 'no');
    } else if (targetStatus == 'no_complaint') {
      await _updateTaskStatus(taskId, 'no_complaint');
    }
  }

  Future<void> _updateTaskStatus(
    String taskId,
    String targetStatus, {
    String? photoId,
    String? photoUrl,
    String? notes,
  }) async {
    if (_togglingTaskIds.contains(taskId)) return;

    final index = _tasks.indexWhere((t) => t['id']?.toString() == taskId);
    if (index == -1) return;

    final previousStatus = _tasks[index]['status']?.toString();
    final previousCompleted = _tasks[index]['completed'] == true;
    final previousCompletedAt = _tasks[index]['completedAt'];
    final previousPhotoUrl = _tasks[index]['photoUrl'];

    final bool targetCompleted = targetStatus == 'yes' || targetStatus == 'no_complaint';

    // Optimistic UI update
    setState(() {
      _togglingTaskIds.add(taskId);
      _tasks[index]['status'] = targetStatus;
      _tasks[index]['completed'] = targetCompleted;
      _tasks[index]['completedAt'] = DateTime.now().toIso8601String();
      if (photoId != null) _tasks[index]['photo'] = photoId;
      if (photoUrl != null) _tasks[index]['photoUrl'] = photoUrl;
      if (notes != null) _tasks[index]['notes'] = notes;
    });

    try {
      final res = await ApiService.instance.toggleDailyTask(
        taskId: taskId,
        status: targetStatus,
        completed: targetCompleted,
        photoId: photoId,
        photoUrl: photoUrl,
        notes: notes,
      );

      if (res['success'] != true) {
        // Revert on failure
        if (mounted) {
          setState(() {
            final idx = _tasks.indexWhere((t) => t['id']?.toString() == taskId);
            if (idx != -1) {
              _tasks[idx]['status'] = previousStatus;
              _tasks[idx]['completed'] = previousCompleted;
              _tasks[idx]['completedAt'] = previousCompletedAt;
              _tasks[idx]['photoUrl'] = previousPhotoUrl;
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to update task status in database.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error updating task: $e');
      if (mounted) {
        setState(() {
          final idx = _tasks.indexWhere((t) => t['id']?.toString() == taskId);
          if (idx != -1) {
            _tasks[idx]['status'] = previousStatus;
            _tasks[idx]['completed'] = previousCompleted;
            _tasks[idx]['completedAt'] = previousCompletedAt;
            _tasks[idx]['photoUrl'] = previousPhotoUrl;
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
                  status: 'yes',
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
                        _tasks[idx]['status'] = 'yes';
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
    final totalCount = _tasks.length;
    final answeredCount = _tasks.where(_isTaskAnswered).length;
    final yesCount = _tasks.where(_isTaskYes).length;
    final noCount = _tasks.where(_isTaskNo).length;
    final pendingCount = totalCount - answeredCount;

    List<Map<String, dynamic>> displayedTasks = _tasks;
    if (_filter == 'pending') {
      displayedTasks = displayedTasks.where((t) => !_isTaskAnswered(t)).toList();
    } else if (_filter == 'yes' || _filter == 'completed') {
      displayedTasks = displayedTasks.where(_isTaskYes).toList();
    } else if (_filter == 'no') {
      displayedTasks = displayedTasks.where(_isTaskNo).toList();
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
      bottomNavigationBar: _buildCompleteWorkBottomBar(totalCount, answeredCount),
      body: RefreshIndicator(
        onRefresh: _fetchTasks,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                totalCount == 0
                                    ? 'Daily Tasks'
                                    : '$yesCount Yes • $noCount No • $pendingCount Pending',
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                totalCount == 0
                                    ? '0 Tasks'
                                    : (answeredCount == totalCount
                                        ? 'All $totalCount Answered ✓'
                                        : '$answeredCount / $totalCount Answered'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
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
                                : '${((answeredCount / totalCount) * 100).round()}%',
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
                        value: totalCount > 0 ? (answeredCount / totalCount) : 0.0,
                        minHeight: 8,
                        backgroundColor: Colors.white.withValues(alpha: 0.25),
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // 2. FILTER TABS (All | Pending | Yes | No)
              if (totalCount > 0) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All', 'all', totalCount),
                      const SizedBox(width: 8),
                      _buildFilterChip('Pending', 'pending', pendingCount),
                      const SizedBox(width: 8),
                      _buildFilterChip('Yes', 'yes', yesCount),
                      const SizedBox(width: 8),
                      _buildFilterChip('No', 'no', noCount),
                    ],
                  ),
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
                    final isYes = _isTaskYes(task);
                    final isNo = _isTaskNo(task);
                    final isNoComplaint = _isTaskNoComplaint(task);
                    final isAnswered = _isTaskAnswered(task);
                    final isToggling = _togglingTaskIds.contains(taskId);
                    final title = task['title']?.toString() ?? 'Task';
                    final desc = task['description']?.toString() ?? '';
                    final priority =
                        task['priority']?.toString().toLowerCase() ?? 'medium';
                    final assignedRole = task['assignedRole']?.toString() ?? '';
                    final completedAtStr = task['completedAt']?.toString();
                    final requiresPhoto = task['requiresPhoto'] == true;

                    final frequency = task['frequency']?.toString().toLowerCase().trim() ?? 'daily';

                    final hasComplaintOption = title.toLowerCase().contains('complaint') ||
                        title.contains('புகார்') ||
                        desc.toLowerCase().contains('complaint') ||
                        desc.contains('புகார்');

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
                          completionStatusText = 'Done • $timeStr';
                        } else if (frequency == 'weekly') {
                          completionStatusText = isToday ? 'Done • Today $timeStr' : 'Done • ${DateFormat('EEE, MMM d').format(dt)}';
                        } else if (frequency == 'monthly') {
                          completionStatusText = isToday ? 'Done • Today $timeStr' : 'Done • ${DateFormat('MMM d').format(dt)}';
                        } else {
                          completionStatusText = 'Done • $timeStr';
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

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: isYes
                            ? const Color(0xFFF0FDF4)
                            : (isNo
                                ? const Color(0xFFFEF2F2)
                                : (isNoComplaint ? const Color(0xFFF0F9FF) : Colors.white)),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        border: Border.all(
                          color: isYes
                              ? const Color(0xFF86EFAC)
                              : (isNo
                                  ? const Color(0xFFFECACA)
                                  : (isNoComplaint ? const Color(0xFFBAE6FD) : Colors.grey[200]!)),
                          width: isAnswered ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Number Badge (matches user screenshot)
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // 2. Icon (matches user screenshot)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              _getTaskIcon(title, desc),
                              color: _getTaskIconColor(title, desc),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 10),

                          // 3. Title, description & tags
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: isYes
                                        ? const Color(0xFF15803D)
                                        : (isNo ? const Color(0xFF991B1B) : const Color(0xFF1E293B)),
                                    height: 1.25,
                                  ),
                                ),
                                if (desc.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    desc,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                      height: 1.25,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 5,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    // Priority pill
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: priorityBg,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        priority.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: priorityFg,
                                        ),
                                      ),
                                    ),
                                    // Recurrence pill
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: freqBg,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: freqBorder, width: 0.8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(freqIcon, size: 9.5, color: freqFg),
                                          const SizedBox(width: 3),
                                          Text(
                                            freqLabel,
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                              color: freqFg,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (assignedRole.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.purple.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          assignedRole.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.purple[700],
                                          ),
                                        ),
                                      ),
                                    // Photo proof requirement / preview pill
                                    if (requiresPhoto)
                                      GestureDetector(
                                        onTap: isYes && (task['photoUrl'] != null && task['photoUrl'].toString().isNotEmpty)
                                            ? () => _showImagePreviewDialog(task['photoUrl'].toString(), title)
                                            : (isToggling ? null : () => _handleTaskAction(task, 'yes')),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isYes
                                                ? Colors.teal.withValues(alpha: 0.12)
                                                : Colors.amber.withValues(alpha: 0.16),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(
                                              color: isYes
                                                  ? Colors.teal.withValues(alpha: 0.35)
                                                  : Colors.amber.withValues(alpha: 0.45),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                isYes ? Icons.camera_alt : Icons.add_a_photo,
                                                size: 10.5,
                                                color: isYes ? Colors.teal[800] : Colors.amber[900],
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                isYes ? 'PHOTO PROOF' : 'PHOTO REQ',
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: isYes ? Colors.teal[800] : Colors.amber[900],
                                                ),
                                              ),
                                              if (isYes && task['photoUrl'] != null && task['photoUrl'].toString().isNotEmpty) ...[
                                                const SizedBox(width: 2),
                                                Icon(Icons.open_in_new, size: 9.5, color: Colors.teal[800]),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    // Status tag
                                    if (isAnswered)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isYes
                                              ? Colors.green.withValues(alpha: 0.1)
                                              : (isNo ? Colors.red.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1)),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: isYes
                                                ? Colors.green.withValues(alpha: 0.3)
                                                : (isNo ? Colors.red.withValues(alpha: 0.3) : Colors.blue.withValues(alpha: 0.3)),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isYes ? Icons.check_circle_rounded : (isNo ? Icons.cancel_rounded : Icons.info_rounded),
                                              size: 10.5,
                                              color: isYes ? Colors.green[800] : (isNo ? Colors.red[800] : Colors.blue[800]),
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              isYes ? completionStatusText : (isNo ? 'No (Incomplete)' : 'No Complaint'),
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w600,
                                                color: isYes ? Colors.green[800] : (isNo ? Colors.red[800] : Colors.blue[800]),
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
                          const SizedBox(width: 10),

                          // 4. Action Buttons (Yes & No, matches user screenshot)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // YES BUTTON
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: isToggling ? null : () => _handleTaskAction(task, 'yes'),
                                      borderRadius: BorderRadius.circular(8),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 180),
                                        constraints: const BoxConstraints(minWidth: 48, minHeight: 32),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: isYes ? const Color(0xFF00C853) : const Color(0xFFDCFCE7),
                                          borderRadius: BorderRadius.circular(8),
                                          border: isYes ? null : Border.all(color: const Color(0xFF86EFAC), width: 1),
                                          boxShadow: isYes
                                              ? [
                                                  BoxShadow(
                                                    color: const Color(0xFF00C853).withValues(alpha: 0.25),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  )
                                                ]
                                              : null,
                                        ),
                                        alignment: Alignment.center,
                                        child: isToggling && isYes
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                              )
                                            : Text(
                                                'Yes',
                                                style: TextStyle(
                                                  color: isYes ? Colors.white : const Color(0xFF15803D),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // NO BUTTON
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: isToggling ? null : () => _handleTaskAction(task, 'no'),
                                      borderRadius: BorderRadius.circular(8),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 180),
                                        constraints: const BoxConstraints(minWidth: 48, minHeight: 32),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: isNo ? const Color(0xFFDC2626) : const Color(0xFFFEE2E2),
                                          borderRadius: BorderRadius.circular(8),
                                          border: isNo ? null : Border.all(color: const Color(0xFFFECACA), width: 1),
                                          boxShadow: isNo
                                              ? [
                                                  BoxShadow(
                                                    color: const Color(0xFFDC2626).withValues(alpha: 0.25),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  )
                                                ]
                                              : null,
                                        ),
                                        alignment: Alignment.center,
                                        child: isToggling && isNo
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                              )
                                            : Text(
                                                'No',
                                                style: TextStyle(
                                                  color: isNo ? Colors.white : const Color(0xFFDC2626),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (hasComplaintOption) ...[
                                const SizedBox(height: 6),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: isToggling ? null : () => _handleTaskAction(task, 'no_complaint'),
                                    borderRadius: BorderRadius.circular(6),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 180),
                                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isNoComplaint ? const Color(0xFF0284C7) : const Color(0xFFE0F2FE),
                                        borderRadius: BorderRadius.circular(6),
                                        border: isNoComplaint ? null : Border.all(color: const Color(0xFFBAE6FD), width: 0.8),
                                      ),
                                      child: Text(
                                        'No Complaint',
                                        style: TextStyle(
                                          color: isNoComplaint ? Colors.white : const Color(0xFF0284C7),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
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

  Widget _buildCompleteWorkBottomBar(int totalCount, int answeredCount) {
    if (totalCount == 0) return const SizedBox.shrink();

    final allAnswered = answeredCount == totalCount;
    final remainingCount = totalCount - answeredCount;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12, top: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (!allAnswered) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Please answer all questions ($remainingCount remaining).'),
                    backgroundColor: Colors.orange[800],
                    duration: const Duration(seconds: 2),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        SizedBox(width: 8),
                        Expanded(child: Text('All tasks completed and recorded!')),
                      ],
                    ),
                    backgroundColor: Color(0xFF15803D),
                    duration: Duration(seconds: 2),
                  ),
                );
                Future.delayed(const Duration(milliseconds: 600), () {
                  if (mounted) Navigator.pop(context);
                });
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              decoration: BoxDecoration(
                color: allAnswered ? const Color(0xFF2E3192) : const Color(0xFF78909C),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'COMPLETE MY WORK',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        allAnswered
                            ? '(All $totalCount questions answered ✓)'
                            : '(Please answer all questions)',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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

