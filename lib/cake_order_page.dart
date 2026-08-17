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
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

class CakeOrderPage extends StatefulWidget {
  const CakeOrderPage({super.key});

  @override
  State<CakeOrderPage> createState() => _CakeOrderPageState();
}

class _CakeOrderPageState extends State<CakeOrderPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  
  final _kotController = TextEditingController();
  final _priceController = TextEditingController();
  final _paymentController = TextEditingController();

  String? _paymentMethod = 'cash';
  String? _paymentType = 'advance';
  DateTime? _deliveryDateTime;

  File? _kotPhotoFile;
  String? _kotPhotoId;
  String? _kotPhotoUrl;
  bool _uploadingKotPhoto = false;

  File? _cakePhotoFile;
  String? _cakePhotoId;
  String? _cakePhotoUrl;
  bool _uploadingCakePhoto = false;

  bool _isSubmitting = false;
  bool _loadingBranch = true;
  String? _branchId;
  String? _branchName;

  double _pendingAmount = 0.0;

  List<dynamic> _submittedCakes = [];
  bool _loadingCakes = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1) {
        _fetchSubmittedCakes();
      }
    });
    _loadBranch();
    _priceController.addListener(_updatePendingAmount);
    _paymentController.addListener(_updatePendingAmount);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _kotController.dispose();
    _priceController.dispose();
    _paymentController.dispose();
    super.dispose();
  }

  Future<void> _loadBranch() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _branchId = prefs.getString('branchId');
      _branchName = prefs.getString('branchName');
      _loadingBranch = false;
    });
    _fetchSubmittedCakes();
  }

  Future<void> _fetchSubmittedCakes() async {
    if (_branchId == null) return;
    setState(() => _loadingCakes = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final url = '${ApiConfig.baseUrl}/cakes?where[branch][equals]=$_branchId&limit=100&sort=deliveryDate&depth=2';
      final response = await http.get(Uri.parse(url), headers: ApiConfig.getHeaders(token));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final docs = data['docs'] as List<dynamic>? ?? [];
        setState(() {
          _submittedCakes = docs;
        });
      }
    } catch (e) {
      debugPrint('Error fetching cakes: $e');
    } finally {
      setState(() => _loadingCakes = false);
    }
  }

  void _updatePendingAmount() {
    final price = double.tryParse(_priceController.text) ?? 0.0;
    final payment = double.tryParse(_paymentController.text) ?? 0.0;
    setState(() {
      final pending = price - payment;
      _pendingAmount = pending < 0.0 ? 0.0 : pending;
    });
  }

  void _resetFormFields() {
    _kotController.clear();
    _priceController.clear();
    _paymentController.clear();
    setState(() {
      _paymentMethod = 'cash';
      _paymentType = 'advance';
      _deliveryDateTime = null;
      _kotPhotoFile = null;
      _kotPhotoId = null;
      _kotPhotoUrl = null;
      _cakePhotoFile = null;
      _cakePhotoId = null;
      _cakePhotoUrl = null;
      _pendingAmount = 0.0;
    });
  }

  Future<void> _selectDeliveryDateTime(BuildContext context) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _deliveryDateTime ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blueAccent,
            ),
          ),
          child: child!,
        );
      },
    );
    if (pickedDate == null) return;

    if (!context.mounted) return;

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_deliveryDateTime ?? DateTime.now().add(const Duration(days: 1))),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blueAccent,
            ),
          ),
          child: child!,
        );
      },
    );
    if (pickedTime == null) return;

    setState(() {
      _deliveryDateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _pickPhoto(bool isKotPhoto) async {
    final pickedSource = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (pickedSource == null) return;

    if (pickedSource == ImageSource.camera) {
      if (await Permission.camera.request().isDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Camera permission required')),
          );
        }
        return;
      }
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No camera found')),
          );
        }
        return;
      }
      if (!mounted) return;
      final XFile? photo = await Navigator.push<XFile>(
        context,
        MaterialPageRoute(
          builder: (context) => CameraPage(cameras: cameras),
          fullscreenDialog: true,
        ),
      );
      if (photo == null) return;
      await _processAndUploadPhoto(photo, isKotPhoto);
    } else {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(source: ImageSource.gallery);
      if (photo == null) return;
      await _processAndUploadPhoto(photo, isKotPhoto);
    }
  }

  Future<void> _processAndUploadPhoto(XFile photo, bool isKotPhoto) async {
    setState(() {
      if (isKotPhoto) {
        _uploadingKotPhoto = true;
      } else {
        _uploadingCakePhoto = true;
      }
    });

    try {
      final bytes = await photo.readAsBytes();
      final image = img_lib.decodeImage(bytes);
      if (image == null) {
        throw Exception('Failed to decode image');
      }
      final compressed = img_lib.encodeJpg(image, quality: 70);
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final typeLabel = isKotPhoto ? 'kot' : 'cake';
      final tempFile = File('${tempDir.path}/cake_${typeLabel}_$timestamp.jpg');
      await tempFile.writeAsBytes(compressed);

      final altText = 'Cake Order ${isKotPhoto ? "KOT" : "Design"} Photo - KOT ${_kotController.text}';
      final mediaId = await _uploadPhoto(tempFile, altText);

      if (mediaId != null) {
        final url = await _fetchMediaUrl(mediaId);
        setState(() {
          if (isKotPhoto) {
            _kotPhotoFile = tempFile;
            _kotPhotoId = mediaId;
            _kotPhotoUrl = url;
          } else {
            _cakePhotoFile = tempFile;
            _cakePhotoId = mediaId;
            _cakePhotoUrl = url;
          }
        });
      } else {
        throw Exception('Failed to upload image');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image processing/upload failed: $e')),
        );
      }
    } finally {
      setState(() {
        if (isKotPhoto) {
          _uploadingKotPhoto = false;
        } else {
          _uploadingCakePhoto = false;
        }
      });
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

  Future<String?> _uploadPhoto(File file, String altText) async {
    try {
      final uploadFile = await _prepareImageForUpload(file, 'cake');
      if (!await uploadFile.exists()) return null;
      if (await uploadFile.length() == 0) return null;

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return null;

      final filename = 'cake_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final urlsToTry = [
        '${ApiConfig.baseUrl}/media?prefix=cake',
        '${ApiConfig.baseUrl}/media/?prefix=cake',
      ];

      for (final urlStr in urlsToTry) {
        final request = http.MultipartRequest('POST', Uri.parse(urlStr));
        request.followRedirects = false;
        request.headers['Authorization'] = 'Bearer $token';
        request.fields['_payload'] = jsonEncode({
          'alt': altText,
          'prefix': 'cake',
        });
        request.fields['alt'] = altText;
        request.fields['prefix'] = 'cake';

        final multipartFile = await http.MultipartFile.fromPath(
          'file',
          uploadFile.path,
          filename: filename,
          contentType: MediaType('image', 'jpeg'),
        );
        request.files.add(multipartFile);

        final response = await request.send();
        final body = await response.stream.bytesToString();

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
              'prefix': 'cake',
            });
            redirRequest.fields['alt'] = altText;
            redirRequest.fields['prefix'] = 'cake';
            redirRequest.files.add(await http.MultipartFile.fromPath(
              'file',
              uploadFile.path,
              filename: filename,
              contentType: MediaType('image', 'jpeg'),
            ));
            final redirResponse = await redirRequest.send();
            final redirBody = await redirResponse.stream.bytesToString();
            if (redirResponse.statusCode == 201 || redirResponse.statusCode == 200) {
              final data = jsonDecode(redirBody);
              final doc = data['doc'] ?? data;
              return doc['id']?.toString();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Upload exception: $e');
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
      debugPrint('Fetch URL error: $e');
    }
    return null;
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please correct errors in the form.')),
      );
      return;
    }

    if (_deliveryDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select delivery date and time.')),
      );
      return;
    }

    if (_kotPhotoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload KOT photo.')),
      );
      return;
    }

    if (_cakePhotoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload Cake photo.')),
      );
      return;
    }

    if (_branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Branch details not loaded.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final cakePrice = double.tryParse(_priceController.text) ?? 0.0;
    final paymentAmount = double.tryParse(_paymentController.text) ?? 0.0;
    final pendingAmount = cakePrice - paymentAmount;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final cashierId = prefs.getString('user_id') ?? prefs.getString('employee_id');
      final cashierName = prefs.getString('employee_name') ?? prefs.getString('user_name') ?? prefs.getString('username');

      final cakeData = {
        'kotNumber': _kotController.text.trim(),
        'cakePrice': cakePrice,
        'paymentMethod': _paymentMethod,
        'paymentType': _paymentType,
        'paymentAmount': paymentAmount,
        'pendingAmount': pendingAmount < 0.0 ? 0.0 : pendingAmount,
        'deliveryDate': _deliveryDateTime!.toUtc().toIso8601String(),
        'kotPhoto': _kotPhotoId,
        'cakePhoto': _cakePhotoId,
        'status': (pendingAmount <= 0.0 || _paymentType == 'full') ? 'paid' : 'pending',
        'branch': _branchId,
        'cashierId': cashierId,
        'cashierName': cashierName,
        'paymentHistory': [
          {
            'amount': paymentAmount,
            'method': _paymentMethod,
            'date': DateTime.now().toUtc().toIso8601String(),
          }
        ]
      };

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/cakes'),
        headers: ApiConfig.getHeaders(token),
        body: jsonEncode(cakeData),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cake order submitted successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          _resetFormFields();
          _fetchSubmittedCakes();
          _tabController.animateTo(1);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to submit: ${response.statusCode} - ${response.body}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _showUpdatePaymentDialog(Map<String, dynamic> cake) async {
    final price = (cake['cakePrice'] as num?)?.toDouble() ?? 0.0;
    final paid = (cake['paymentAmount'] as num?)?.toDouble() ?? 0.0;
    final pending = price - paid;
    final kotNumber = cake['kotNumber'] ?? 'N/A';
    final rawHistory = cake['paymentHistory'] as List<dynamic>? ?? [];

    if (pending <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This order is already fully paid.')),
      );
      return;
    }

    String? selectMethod = 'cash';
    bool dialogSubmitting = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Close Cake KOT Bill (KOT: $kotNumber)'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cake Price: ₹${price.toStringAsFixed(2)}'),
                    Text('Already Paid: ₹${paid.toStringAsFixed(2)}'),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Pending to Pay:',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
                          ),
                          Text(
                            '₹${pending.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.redAccent),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (rawHistory.isNotEmpty) ...[
                      const Text(
                        'Payment Logs:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      ...rawHistory.map((p) {
                        final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
                        final mthd = (p['method'] ?? 'cash').toString().toUpperCase();
                        final dtStr = p['date'] != null
                            ? DateFormat('dd MMM, hh:mm a').format(DateTime.parse(p['date']).toLocal())
                            : 'N/A';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '• ₹${amt.toStringAsFixed(2)} via $mthd on $dtStr',
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }),
                      const Divider(height: 24),
                    ],
                    DropdownButtonFormField<String>(
                      initialValue: selectMethod,
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'card', child: Text('Card')),
                        DropdownMenuItem(value: 'upi', child: Text('UPI')),
                        DropdownMenuItem(value: 'cashfree', child: Text('Cashfree')),
                        DropdownMenuItem(value: 'other', child: Text('Other')),
                      ],
                      onChanged: (val) => setDialogState(() => selectMethod = val),
                      decoration: const InputDecoration(
                        labelText: 'Payment Method',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: dialogSubmitting ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: dialogSubmitting
                      ? null
                      : () async {
                          setDialogState(() => dialogSubmitting = true);

                          final newHistoryEntry = {
                            'amount': pending,
                            'method': selectMethod,
                            'date': DateTime.now().toUtc().toIso8601String(),
                          };

                          final updatedHistory = [
                            ...rawHistory.map((h) => {
                                  'amount': h['amount'],
                                  'method': h['method'],
                                  'date': h['date'],
                                }),
                            newHistoryEntry
                          ];

                          try {
                            final prefs = await SharedPreferences.getInstance();
                            final token = prefs.getString('token');
                            
                            final response = await http.patch(
                              Uri.parse('${ApiConfig.baseUrl}/cakes/${cake['id']}'),
                              headers: ApiConfig.getHeaders(token),
                              body: jsonEncode({
                                'paymentHistory': updatedHistory,
                              }),
                            );

                            if (response.statusCode == 200 || response.statusCode == 201) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Payment updated successfully! Bill Closed.'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                                Navigator.pop(context);
                                _fetchSubmittedCakes();
                              }
                            } else {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to update: ${response.statusCode}')),
                                );
                              }
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error updating: $e')),
                              );
                            }
                          } finally {
                            setDialogState(() => dialogSubmitting = false);
                          }
                        },
                  child: dialogSubmitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Confirm & Close Bill'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showImagePreviewDialog(BuildContext context, String title, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: InteractiveViewer(
                  maxScale: 4.0,
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(child: CircularProgressIndicator(color: Colors.white)),
                    errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.white, size: 60),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPhotoSelector({
    required String label,
    required File? photoFile,
    required String? photoUrl,
    required bool uploading,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Container(
          height: 150,
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: uploading
                ? const Center(child: CircularProgressIndicator())
                : photoFile != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(photoFile, fit: BoxFit.cover),
                          Positioned(
                            right: 8,
                            top: 8,
                            child: CircleAvatar(
                              backgroundColor: Colors.black54,
                              child: IconButton(
                                icon: const Icon(Icons.edit, color: Colors.white),
                                onPressed: onTap,
                              ),
                            ),
                          )
                        ],
                      )
                    : InkWell(
                        onTap: onTap,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt, size: 40, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text(
                              'Tap to upload',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderFormView() {
    final formattedDelivery = _deliveryDateTime != null
        ? DateFormat('dd MMM yyyy, hh:mm a').format(_deliveryDateTime!)
        : 'Select date & time';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
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
                          'Pending Amount',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '₹${_pendingAmount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _pendingAmount > 0 ? Colors.redAccent : Colors.green,
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
                        Text(
                          (_pendingAmount <= 0.0 || _paymentType == 'full') ? 'PAID' : 'PENDING',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: (_pendingAmount <= 0.0 || _paymentType == 'full') ? Colors.green : Colors.orange,
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // KOT Number
            TextFormField(
              controller: _kotController,
              decoration: InputDecoration(
                labelText: 'KOT Number',
                prefixIcon: const Icon(Icons.receipt),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // Cake Price
            TextFormField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Cake Price',
                prefixText: '₹ ',
                prefixIcon: const Icon(Icons.cake),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (val) {
                if (val == null || val.isEmpty) return 'Required';
                final num = double.tryParse(val);
                if (num == null) return 'Invalid number';
                if (num <= 0) return 'Must be greater than 0';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Payment Method Dropdown
            DropdownButtonFormField<String>(
              initialValue: _paymentMethod,
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'card', child: Text('Card')),
                DropdownMenuItem(value: 'upi', child: Text('UPI')),
                DropdownMenuItem(value: 'cashfree', child: Text('Cashfree')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (val) => setState(() => _paymentMethod = val),
              decoration: InputDecoration(
                labelText: 'Payment Method',
                prefixIcon: const Icon(Icons.payment),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),

            // Payment Type Dropdown (Advance or Full)
            DropdownButtonFormField<String>(
              initialValue: _paymentType,
              items: const [
                DropdownMenuItem(value: 'advance', child: Text('Advance Payment')),
                DropdownMenuItem(value: 'full', child: Text('Full Payment')),
              ],
              onChanged: (val) {
                setState(() {
                  _paymentType = val;
                  if (_paymentType == 'full' && _priceController.text.isNotEmpty) {
                    _paymentController.text = _priceController.text;
                  }
                });
              },
              decoration: InputDecoration(
                labelText: 'Payment Type',
                prefixIcon: const Icon(Icons.assignment),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),

            // Payment Input Box
            TextFormField(
              controller: _paymentController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Payment Amount',
                prefixText: '₹ ',
                prefixIcon: const Icon(Icons.attach_money),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (val) {
                if (val == null || val.isEmpty) return 'Required';
                final num = double.tryParse(val);
                if (num == null) return 'Invalid number';
                if (num < 0) return 'Must be 0 or greater';
                if (_paymentType == 'full') {
                  final price = double.tryParse(_priceController.text) ?? 0.0;
                  if (num < price) {
                    return 'Full payment must match cake price';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Delivery Date and Time Picker Button
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                onTap: () => _selectDeliveryDateTime(context),
                leading: const Icon(Icons.calendar_today, color: Colors.blueAccent),
                title: const Text('Delivery Date & Time'),
                subtitle: Text(
                  formattedDelivery,
                  style: TextStyle(
                    fontWeight: _deliveryDateTime != null ? FontWeight.bold : FontWeight.normal,
                    color: _deliveryDateTime != null ? Colors.black : Colors.grey.shade600,
                  ),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              ),
            ),
            const SizedBox(height: 20),

            // Photo pickers
            Row(
              children: [
                Expanded(
                  child: _buildPhotoSelector(
                    label: 'KOT Photo',
                    photoFile: _kotPhotoFile,
                    photoUrl: _kotPhotoUrl,
                    uploading: _uploadingKotPhoto,
                    onTap: () => _pickPhoto(true),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildPhotoSelector(
                    label: 'Cake Photo',
                    photoFile: _cakePhotoFile,
                    photoUrl: _cakePhotoUrl,
                    uploading: _uploadingCakePhoto,
                    onTap: () => _pickPhoto(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

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
              label: Text(_isSubmitting ? 'Submitting...' : 'Submit Order'),
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

  Widget _buildSubmittedCakesList() {
    if (_loadingCakes) {
      return const Center(child: CircularProgressIndicator());
    }

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final futureCakes = _submittedCakes.where((cake) {
      if (cake['deliveryDate'] == null) return false;
      final delivery = DateTime.tryParse(cake['deliveryDate'])?.toLocal();
      if (delivery == null) return false;

      // Show if delivery is today or in the future
      final isTodayOrFuture = delivery.isAfter(startOfToday) || 
                              (delivery.year == now.year && delivery.month == now.month && delivery.day == now.day);
      
      // OR show if it is still pending payment (status is not paid / is pending)
      final status = (cake['status'] ?? 'pending').toString().toLowerCase();
      final isPending = status == 'pending';

      return isTodayOrFuture || isPending;
    }).toList();

    if (futureCakes.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchSubmittedCakes,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.6,
            alignment: Alignment.center,
            child: const Text(
              "No future cake orders found.\nSwipe down to refresh.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchSubmittedCakes,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: futureCakes.length,
        itemBuilder: (context, index) {
          final cake = futureCakes[index];
          final kotNumber = cake['kotNumber'] ?? 'N/A';
          final price = (cake['cakePrice'] as num?)?.toDouble() ?? 0.0;
          final paid = (cake['paymentAmount'] as num?)?.toDouble() ?? 0.0;
          final pending = (cake['pendingAmount'] as num?)?.toDouble() ?? (price - paid);
          final status = (cake['status'] ?? 'pending').toString().toUpperCase();
          final method = (cake['paymentMethod'] ?? 'cash').toString().toUpperCase();
          
          final deliveryStr = cake['deliveryDate'] != null
              ? DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(cake['deliveryDate']).toLocal())
              : 'N/A';

          String? getPhotoUrl(dynamic photoObj) {
            if (photoObj is Map) {
              return photoObj['url'] as String?;
            }
            return null;
          }

          final kotPhotoUrl = getPhotoUrl(cake['kotPhoto']);
          final cakePhotoUrl = getPhotoUrl(cake['cakePhoto']);

          return Card(
            elevation: 3,
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _showUpdatePaymentDialog(cake),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'KOT: $kotNumber',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: status == 'PAID' ? Colors.green.shade100 : Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: status == 'PAID' ? Colors.green.shade800 : Colors.orange.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Price: ₹${price.toStringAsFixed(2)}'),
                            const SizedBox(height: 4),
                            Text('Paid: ₹${paid.toStringAsFixed(2)} ($method)'),
                            const SizedBox(height: 4),
                            Text(
                              'Pending: ₹${pending.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: pending > 0 ? Colors.redAccent : Colors.green,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Delivery:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              deliveryStr,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    if (cake['paymentHistory'] is List && (cake['paymentHistory'] as List).isNotEmpty) ...[
                      const Text(
                        'Payment History Log:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 6),
                      ...(cake['paymentHistory'] as List).map((p) {
                        if (p is! Map) return const SizedBox.shrink();
                        final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
                        final mthd = (p['method'] ?? 'cash').toString().toUpperCase();
                        final dtStr = p['date'] != null
                            ? DateFormat('dd MMM, hh:mm a').format(DateTime.parse(p['date']).toLocal())
                            : 'N/A';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4, left: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, size: 12, color: Colors.green),
                              const SizedBox(width: 6),
                              Text(
                                '₹${amt.toStringAsFixed(2)} via $mthd ($dtStr)',
                                style: const TextStyle(fontSize: 12, color: Colors.black87),
                              ),
                            ],
                          ),
                        );
                      }),
                      const Divider(height: 20),
                    ],
                    Row(
                      children: [
                        if (kotPhotoUrl != null)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('KOT Photo', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onTap: () => _showImagePreviewDialog(context, 'KOT Photo (KOT: $kotNumber)', kotPhotoUrl),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CachedNetworkImage(
                                      imageUrl: kotPhotoUrl,
                                      height: 80,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                                      errorWidget: (context, url, error) => const Icon(Icons.broken_image),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (kotPhotoUrl != null && cakePhotoUrl != null) const SizedBox(width: 16),
                        if (cakePhotoUrl != null)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Cake Photo', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onTap: () => _showImagePreviewDialog(context, 'Cake Photo (KOT: $kotNumber)', cakePhotoUrl),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CachedNetworkImage(
                                      imageUrl: cakePhotoUrl,
                                      height: 80,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                                      errorWidget: (context, url, error) => const Icon(Icons.broken_image),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    if (pending > 0) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.payment, size: 14, color: Colors.blue.shade700),
                          const SizedBox(width: 4),
                          Text(
                            'Tap to record payment',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    ]
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingBranch) {
      return const CommonScaffold(
        title: 'Cake Orders',
        pageType: PageType.cake,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cake Orders'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.purple,
          labelColor: Colors.purple,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: "Order Here"),
            Tab(text: "Submitted KOTs"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOrderFormView(),
          _buildSubmittedCakesList(),
        ],
      ),
    );
  }
}
