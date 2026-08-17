import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:branch/common_scaffold.dart';
import 'package:branch/api_config.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img_lib;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http_parser/http_parser.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:branch/camera_page.dart';

class _ExpenseItem {
  String? source;
  final TextEditingController reason;
  final TextEditingController amount;
  String? imageId;
  File? imageFile;
  String? imageUrl;

  _ExpenseItem({
    this.source,
    TextEditingController? reason,
    TextEditingController? amount,
    this.imageId,
    this.imageFile,
    this.imageUrl,
  })  : reason = reason ?? TextEditingController(),
        amount = amount ?? TextEditingController();

  void dispose() {
    reason.dispose();
    amount.dispose();
  }
}

// CameraDialog class removed in favor of shared CameraPage in camera_page.dart

class ExpenseDetailsPage extends StatefulWidget {
  const ExpenseDetailsPage({Key? key}) : super(key: key);

  @override
  _ExpenseDetailsPageState createState() => _ExpenseDetailsPageState();
}

class _ExpenseDetailsPageState extends State<ExpenseDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  final List<_ExpenseItem> _expenseItems = [];
  final _totalExpensesController = TextEditingController(); // Only for display
  DateTime _selectedDate = DateTime.now();

  final List<String> _expenseSources = [
    'MAINTENANCE',
    'TRANSPORT',
    'FUEL',
    'PACKING',
    'STAFF WELFARE',
    'ADVERTISEMENT',
    'ADVANCE',
    'COMPLEMENTARY',
    'RAW MATERIAL',
    'SALARY',
    'OC PRODUCTS',
    'OTHERS'
  ];

  bool _isSubmitting = false;
  bool _loadingBranch = true;
  String? _branchId;
  String? _branchName;

  @override
  void initState() {
    super.initState();
    _loadBranch();
  }

  Future<void> _loadBranch() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _branchId = prefs.getString('branchId');
      _branchName = prefs.getString('branchName');
      _loadingBranch = false;
    });
  }

  void _addExpenseDetail() {
    setState(() {
      final newItem = _ExpenseItem();
      newItem.amount.addListener(_updateTotalExpenses);
      _expenseItems.add(newItem);
    });
  }

  void _removeExpenseDetail(int index) {
    setState(() {
      _expenseItems[index].amount.removeListener(_updateTotalExpenses);
      _expenseItems[index].dispose();
      _expenseItems.removeAt(index);
      _updateTotalExpenses();
    });
  }

  void _updateTotalExpenses() {
    double total = _expenseItems.fold(
      0.0,
      (sum, item) {
        final val = double.tryParse(item.amount.text);
        return sum + (val ?? 0.0);
      },
    );
    _totalExpensesController.text = total.toStringAsFixed(2);
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please correct errors in the form.')),
      );
      return;
    }
    if (_expenseItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one expense.')),
      );
      return;
    }
    if (_branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Branch not found. Please log in again.')),
      );
      return;
    }

    // Validate that all items have an image
    for (int i = 0; i < _expenseItems.length; i++) {
      if (_expenseItems[i].imageId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please add an image for Expense #${i + 1}')),
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final cashierId = prefs.getString('user_id') ?? prefs.getString('employee_id');
      final cashierName = prefs.getString('employee_name') ?? prefs.getString('user_name') ?? prefs.getString('username');

      final expenseData = {
        'branch': _branchId,
        'cashierId': cashierId,
        'cashierName': cashierName,
        'details': _expenseItems.map((e) {
          return {
            'source': e.source,
            'reason': e.reason.text.trim(),
            'amount': double.tryParse(e.amount.text) ?? 0.0,
            'image': e.imageId,
          };
        }).toList(),
        'total': double.tryParse(_totalExpensesController.text) ?? 0.0,
        'date': _selectedDate.toIso8601String(),
      };

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/expenses'),
        headers: ApiConfig.getHeaders(token),
        body: jsonEncode(expenseData),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Expenses submitted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        _resetForm();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit: ${response.statusCode} - ${response.body}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error submitting: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _captureExpensePhoto(int index) async {
    if (await Permission.camera.request().isDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera permission required')),
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
    final XFile? photo = await Navigator.push<XFile>(
      context,
      MaterialPageRoute(
        builder: (context) => CameraPage(cameras: cameras),
        fullscreenDialog: true,
      ),
    );
    if (photo == null) return;
    final bytes = await photo.readAsBytes();
    final image = img_lib.decodeImage(bytes)!;
    final compressed = img_lib.encodeJpg(image, quality: 70);
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempFile = File('${tempDir.path}/expense_${index}_$timestamp.jpg');
    await tempFile.writeAsBytes(compressed);

    final item = _expenseItems[index];
    final altText = 'Expense ${item.source ?? "Entry"} ${item.reason.text}';
    final mediaId = await _uploadPhoto(tempFile, altText);

    setState(() {
      item.imageFile = tempFile;
      if (mediaId != null) {
        item.imageId = mediaId;
        _fetchMediaUrl(mediaId).then((url) {
          if (url != null) {
            setState(() {
              item.imageUrl = url;
            });
          }
        });
      }
    });

    if (mediaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_lastUploadError ?? 'Upload failed, saved locally')),
      );
    }
  }

  Future<File> _prepareImageForUpload(File originalFile, String prefix) async {
    try {
      if (!await originalFile.exists()) return originalFile;
      final length = await originalFile.length();
      if (length < 1500 * 1024) return originalFile;

      final bytes = await originalFile.readAsBytes();
      final image = img_lib.decodeImage(bytes);
      if (image == null) return originalFile;

      img_lib.Image resized = image;
      if (image.width > 1280 || image.height > 1280) {
        if (image.width > image.height) {
          resized = img_lib.copyResize(image, width: 1280);
        } else {
          resized = img_lib.copyResize(image, height: 1280);
        }
      }
      final compressedBytes = img_lib.encodeJpg(resized, quality: 70);
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/opt_${prefix}_$timestamp.jpg');
      await tempFile.writeAsBytes(compressedBytes);
      return tempFile;
    } catch (_) {
      return originalFile;
    }
  }

  String? _lastUploadError;

  Future<String?> _uploadPhoto(File file, String altText) async {
    _lastUploadError = null;
    try {
      final uploadFile = await _prepareImageForUpload(file, 'expense');
      if (!await uploadFile.exists()) {
        _lastUploadError = 'Upload failed: File does not exist';
        return null;
      }
      if (await uploadFile.length() == 0) {
        _lastUploadError = 'Upload failed: File is empty (0 bytes)';
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) {
        _lastUploadError = 'Upload failed: No login token found';
        return null;
      }

      final filename = 'expense_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final urlsToTry = [
        '${ApiConfig.baseUrl}/media?prefix=expense',
        '${ApiConfig.baseUrl}/media/?prefix=expense',
      ];

      for (final urlStr in urlsToTry) {
        final request = http.MultipartRequest('POST', Uri.parse(urlStr));
        request.followRedirects = false;
        request.headers['Authorization'] = 'Bearer $token';
        request.fields['_payload'] = jsonEncode({
          'alt': altText,
          'prefix': 'expense',
        });
        request.fields['alt'] = altText;
        request.fields['prefix'] = 'expense';

        final multipartFile = await http.MultipartFile.fromPath(
          'file',
          uploadFile.path,
          filename: filename,
          contentType: MediaType('image', 'jpeg'),
        );
        request.files.add(multipartFile);

        final response = await request.send();
        final body = await response.stream.bytesToString();

        debugPrint('Upload attempt to $urlStr -> Status: ${response.statusCode}, Body: $body');

        if (response.statusCode == 201 || response.statusCode == 200) {
          final data = jsonDecode(body);
          final doc = data['doc'] ?? data;
          return doc['id']?.toString();
        }

        if (response.statusCode >= 300 && response.statusCode < 400) {
          final location = response.headers['location'];
          if (location != null) {
            final resolvedUri = Uri.parse(urlStr).resolve(location);
            final redirRequest = http.MultipartRequest('POST', resolvedUri);
            redirRequest.headers['Authorization'] = 'Bearer $token';
            redirRequest.fields['_payload'] = jsonEncode({
              'alt': altText,
              'prefix': 'expense',
            });
            redirRequest.fields['alt'] = altText;
            redirRequest.fields['prefix'] = 'expense';
            redirRequest.files.add(await http.MultipartFile.fromPath(
              'file',
              uploadFile.path,
              filename: filename,
              contentType: MediaType('image', 'jpeg'),
            ));
            final redirResponse = await redirRequest.send();
            final redirBody = await redirResponse.stream.bytesToString();
            debugPrint('Redirect upload response -> Status: ${redirResponse.statusCode}, Body: $redirBody');
            if (redirResponse.statusCode == 201 || redirResponse.statusCode == 200) {
              final data = jsonDecode(redirBody);
              final doc = data['doc'] ?? data;
              return doc['id']?.toString();
            }
            _lastUploadError = 'Upload failed (${redirResponse.statusCode}): $redirBody';
          }
        } else {
          _lastUploadError = 'Upload failed (${response.statusCode}): $body';
        }
      }
    } catch (e) {
      debugPrint('Upload exception: $e');
      _lastUploadError = 'Upload exception: $e';
    }
    return null;
  }

  Future<String?> _fetchMediaUrl(String mediaId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return null;
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/media/$mediaId?depth=0'),
        headers: ApiConfig.getHeaders(token),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['url'];
      }
    } catch (e) {
      print('Fetch URL error: $e');
    }
    return null;
  }

  Future<void> _handleCameraTap(int index) async {
    final item = _expenseItems[index];
    final hasPhoto = item.imageFile != null || item.imageUrl != null;
    if (!hasPhoto) {
      await _captureExpensePhoto(index);
    } else {
      Widget previewWidget;
      if (item.imageFile != null && await item.imageFile!.exists()) {
        previewWidget = Image.file(item.imageFile!);
      } else if (item.imageUrl != null) {
        previewWidget = CachedNetworkImage(imageUrl: item.imageUrl!, fit: BoxFit.contain);
      } else {
        previewWidget = const Text('No preview available');
      }
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Current Photo'),
          content: previewWidget,
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, 'remove'), child: const Text('Remove', style: TextStyle(color: Colors.red))),
            TextButton(onPressed: () => Navigator.pop(context, 'keep'), child: const Text('Keep')),
            TextButton(onPressed: () => Navigator.pop(context, 'retake'), child: const Text('Retake')),
          ],
        ),
      );
      if (result == 'retake') {
        await _captureExpensePhoto(index);
      } else if (result == 'remove') {
        _removeExpensePhoto(index);
      }
    }
  }

  void _removeExpensePhoto(int index) {
    setState(() {
      _expenseItems[index].imageFile = null;
      _expenseItems[index].imageId = null;
      _expenseItems[index].imageUrl = null;
    });
  }

  void _resetForm() {
    setState(() {
      for (var item in _expenseItems) {
        item.dispose();
      }
      _expenseItems.clear();
      _updateTotalExpenses();
      _selectedDate = DateTime.now();
    });
  }

  @override
  void dispose() {
    _totalExpensesController.dispose();
    for (var item in _expenseItems) {
      item.amount.removeListener(_updateTotalExpenses);
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingBranch) {
      return const CommonScaffold(
        title: 'Expense Details',
        pageType: PageType.expense,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return CommonScaffold(
      title: 'Expense Details',
      pageType: PageType.expense,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Expenses',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '₹${_totalExpensesController.text.isEmpty ? "0.00" : _totalExpensesController.text}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueAccent,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _branchName ?? 'Branch',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        InkWell(
                          onTap: () => _selectDate(context),
                          child: Row(
                            children: [
                              Text(
                                "${_selectedDate.toLocal()}".split(' ')[0],
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.calendar_today, size: 16),
                            ],
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Expense List Form
            Form(
              key: _formKey,
              child: Column(
                children: [
                  if (_expenseItems.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      alignment: Alignment.center,
                      child: const Text(
                        "No expenses added yet.\nTap 'Add Expense' to begin.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ..._expenseItems.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return _buildExpenseCard(index, item);
                  }).toList(),
                ],
              ),
            ),

            const SizedBox(height: 16),
            
            // Add Button
            ElevatedButton.icon(
              onPressed: _addExpenseDetail,
              icon: const Icon(Icons.add),
              label: const Text('Add Expense'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            
            // Submit Button
            ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submitForm,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check),
              label: Text(_isSubmitting ? 'Submitting...' : 'Submit Expenses'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseCard(int index, _ExpenseItem item) {
    return Dismissible(
      key: ObjectKey(item),
      direction: DismissDirection.endToStart,
      onDismissed: (direction) => _removeExpenseDetail(index),
      background: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Expense #${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _removeExpenseDetail(index),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              // Source Dropdown
              DropdownButtonFormField<String>(
                value: item.source,
                items: _expenseSources.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (val) => setState(() => item.source = val),
                decoration: InputDecoration(
                  labelText: 'Source',
                  prefixIcon: const Icon(Icons.category_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                validator: (val) => val == null ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              
              // Reason Input
              TextFormField(
                controller: item.reason,
                decoration: InputDecoration(
                  labelText: 'Reason',
                  prefixIcon: const Icon(Icons.description_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              
              // Amount Input
              TextFormField(
                controller: item.amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Required';
                  final num = double.tryParse(val);
                  if (num == null) return 'Invalid number';
                  if (num <= 0) return 'Must be > 0';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              
              // Camera / Image Preview
              Row(
                children: [
                  Expanded(
                    child: item.imageId != null || item.imageFile != null
                        ? GestureDetector(
                            onTap: () => _handleCameraTap(index),
                            child: Container(
                              height: 100,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: item.imageFile != null
                                    ? Image.file(item.imageFile!, fit: BoxFit.cover, width: double.infinity)
                                    : (item.imageUrl != null 
                                        ? CachedNetworkImage(
                                            imageUrl: item.imageUrl!,
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                                            errorWidget: (context, url, error) => const Icon(Icons.error),
                                          )
                                        : const Center(child: Text("Uploading..."))),
                              ),
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: () => _handleCameraTap(index),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Add Receipt/Photo'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                  ),
                  if (item.imageId != null || item.imageFile != null) ...[
                    const SizedBox(width: 8),
                    Column(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.blue),
                          onPressed: () => _captureExpensePhoto(index),
                          tooltip: 'Retake',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _removeExpensePhoto(index),
                          tooltip: 'Remove',
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}