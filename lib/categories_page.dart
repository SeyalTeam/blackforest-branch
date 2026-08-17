// lib/categories_page.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:branch/api_config.dart';

import 'package:branch/common_scaffold.dart';
import 'package:branch/products_page.dart';
import 'package:branch/stock_order.dart';
import 'package:branch/return_order_page.dart';
import 'package:branch/instock_products_page.dart';
import 'package:branch/instock_provider.dart';
import 'package:branch/printer/printer_settings_action.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:branch/cart_provider.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img_lib;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:branch/camera_page.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

class CategoriesPage extends StatefulWidget {
  final bool isPastryFilter; // For pastry billing (rarely used)
  final bool isStockFilter; // For stock orders
  final bool isReturnOrder; // ⭐ NEW — For Return Orders
  final bool isInstockEntry; // ⭐ NEW — For Instock Entry (Billing-like UI)

  const CategoriesPage({
    super.key,
    this.isPastryFilter = false,
    this.isStockFilter = false,
    this.isReturnOrder = false,
    this.isInstockEntry = false,
  });

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  List<dynamic> _categories = [];
  List<dynamic> _companies = [];
  bool _isLoading = true;
  String _errorMessage = '';

  String? _companyId;
  String? _companyName;
  String? _branchId;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  String? _extractId(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is Map) {
      final direct = value['id'] ?? value['_id'] ?? value['value'];
      if (direct is String) return direct;
      if (direct is Map) return _extractId(direct);
    }
    return null;
  }

  // ------------------ USER DATA ------------------
  Future<void> _fetchUserData(String token) async {
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/users/me?depth=2'),
        headers: ApiConfig.getHeaders(token),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final user = data['user'] ?? data;

        _userRole = user['role'];

        if (user['role'] == 'company') {
          final companyRef = user['company'];
          if (companyRef is Map) {
            _companyName = companyRef['name']?.toString();
          }
          _companyId = _extractId(user['company']);
        } else {
          final branch = user['branch'];
          if (branch != null) {
            if (branch is Map) {
              _branchId = _extractId(branch);
              if (branch['company'] != null) {
                if (branch['company'] is Map) {
                  _companyName = branch['company']['name']?.toString();
                }
                _companyId = _extractId(branch['company']);
              }
            } else {
              _branchId = _extractId(branch) ?? branch.toString();
            }

            if ((_companyId == null || _companyId!.isEmpty) &&
                _branchId != null &&
                _branchId!.isNotEmpty) {
              final resolved = await _fetchCompanyIdFromBranch(token, _branchId!);
              if (resolved != null && resolved.isNotEmpty) {
                _companyId = resolved;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('companyId', resolved);
              }
            }
          }
        }

        // Final fallback from local session cache.
        if (_companyId == null || _companyId!.isEmpty) {
          final prefs = await SharedPreferences.getInstance();
          final cachedCompanyId = prefs.getString('companyId');
          if (cachedCompanyId != null && cachedCompanyId.isNotEmpty) {
            _companyId = cachedCompanyId;
          }
        } else {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('companyId', _companyId!);
        }

        if ((_companyName == null || _companyName!.isEmpty) &&
            _companyId != null &&
            _companyId!.isNotEmpty) {
          final resolvedName = await _fetchCompanyNameById(token, _companyId!);
          if (resolvedName != null && resolvedName.isNotEmpty) {
            _companyName = resolvedName;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('companyName', resolvedName);
          } else {
            final prefs = await SharedPreferences.getInstance();
            final cachedCompanyName = prefs.getString('companyName');
            if (cachedCompanyName != null && cachedCompanyName.isNotEmpty) {
              _companyName = cachedCompanyName;
            }
          }
        } else if (_companyName != null && _companyName!.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('companyName', _companyName!);
        }
      }
    } catch (_) {}
  }

  Future<String?> _fetchCompanyIdFromBranch(
    String token,
    String branchId,
  ) async {
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/branches/$branchId?depth=1'),
        headers: ApiConfig.getHeaders(token),
      );
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);
      final branch = data['doc'] ?? data;
      return _extractId(branch['company']);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetchCompanyNameById(String token, String companyId) async {
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/companies/$companyId?depth=0'),
        headers: ApiConfig.getHeaders(token),
      );
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      final company = data['doc'] ?? data;
      return company['name']?.toString();
    } catch (_) {
      return null;
    }
  }

  // ------------------ NETWORK HELPERS ------------------
  Future<String?> _deviceIp() async {
    try {
      final info = NetworkInfo();
      return await info.getWifiIP();
    } catch (_) {
      return null;
    }
  }

  int _ipToInt(String ip) {
    final p = ip.split('.').map(int.parse).toList();
    return (p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3];
  }

  bool _ipInRange(String deviceIp, String range) {
    final split = range.split('-');
    if (split.length != 2) return false;
    return _ipToInt(deviceIp) >= _ipToInt(split[0]) &&
        _ipToInt(deviceIp) <= _ipToInt(split[1]);
  }

  Future<List<String>> _matchingCompanies(
    String token,
    String? deviceIp,
  ) async {
    if (deviceIp == null) return [];

    List<String> ids = [];

    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/branches?depth=1'),
        headers: ApiConfig.getHeaders(token),
      );

      if (res.statusCode == 200) {
        final docs = jsonDecode(res.body)['docs'] ?? [];

        for (final b in docs) {
          final r = b['ipAddress']?.toString();
          if (r != null && _ipInRange(deviceIp, r)) {
            final c = b['company'];
            final id = c is Map ? c['id'] : c?.toString();
            if (id != null) ids.add(id);
          }
        }
      }
    } catch (_) {}

    return ids;
  }

  // ------------------ FETCH CATEGORIES ------------------
  Future<void> _fetchCategories() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        _errorMessage = "No token found. Please login.";
        setState(() => _isLoading = false);
        return;
      }

      if (_userRole == null) await _fetchUserData(token);

      if (_canCreateCategory && _userRole == "superadmin") {
        await _fetchCompanies(token);
      }

      /// TYPE OF CATEGORY
      String filter;

      if (widget.isReturnOrder) {
        filter = "where[isStock][equals]=true"; // Same products used
      } else if (widget.isStockFilter || widget.isInstockEntry) {
        filter = "where[isStock][equals]=true";
      } else {
        filter = "where[isBilling][equals]=true";
      }

      // Company filter
      if (_userRole != "superadmin") {
        String? extra;

        if (_companyId != null && _companyId!.isNotEmpty) {
          extra = "&where[company][contains]=$_companyId";
        } else if (_userRole == "waiter" || _userRole == "kitchen" || _userRole == "chef" || _userRole == "manager" || _userRole == "cashier") {
          final ip = await _deviceIp();
          final matches = await _matchingCompanies(token, ip);
          if (matches.isNotEmpty) {
            extra = "&where[company][in]=${matches.join(',')}";
          }
        }

        if (extra != null) filter += extra;
      }

      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/categories?$filter&limit=100&depth=1"),
        headers: ApiConfig.getHeaders(token),
      );

      if (res.statusCode == 200) {
        _categories = jsonDecode(res.body)['docs'] ?? [];
      } else {
        _errorMessage = "Failed: ${res.statusCode}";
      }
    } catch (e) {
      _errorMessage = "Network error";
    }

    setState(() => _isLoading = false);
  }

  Future<void> _fetchCompanies(String token) async {
    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/companies?limit=100&depth=0"),
        headers: ApiConfig.getHeaders(token),
      );
      if (res.statusCode == 200) {
        _companies = jsonDecode(res.body)['docs'] ?? [];
      }
    } catch (_) {}
  }

  bool get _canCreateCategory =>
      widget.isInstockEntry || (!widget.isStockFilter && !widget.isReturnOrder);

  Future<File?> _captureAndConfirmCategoryPhoto() async {
    final messenger = ScaffoldMessenger.of(context);
    final permission = await Permission.camera.request();
    if (!permission.isGranted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Camera permission required')),
      );
      return null;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('No camera found')));
      return null;
    }
    
    final XFile? photo = await Navigator.push<XFile>(
      context,
      MaterialPageRoute(
        builder: (context) => CameraPage(cameras: cameras),
        fullscreenDialog: true,
      ),
    );
    if (photo == null) return null;

    final bytes = await photo.readAsBytes();
    final decoded = img_lib.decodeImage(bytes);
    if (decoded == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to process captured image')),
      );
      return null;
    }

    final compressed = img_lib.encodeJpg(decoded, quality: 70);
    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}/category_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(compressed);
    
    return file;
  }

  Future<File?> _pickAndConfirmCategoryPhotoFromGallery() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picker = ImagePicker();
      final XFile? selected = await picker.pickImage(
        source: ImageSource.gallery,
      );
      if (selected == null) return null;

      final bytes = await selected.readAsBytes();
      final decoded = img_lib.decodeImage(bytes);
      if (decoded == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to process selected image')),
        );
        return null;
      }

      final compressed = img_lib.encodeJpg(decoded, quality: 70);
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/category_gallery_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(compressed);
      if (!mounted) return null;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Image Preview'),
          content: Image.file(file),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Choose Another'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );

      if (confirmed == true) return file;
      if (await file.exists()) {
        await file.delete();
      }
      return null;
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e')),
      );
      return null;
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

  Future<String?> _uploadCategoryPhoto(File file, String altText) async {
    try {
      final uploadFile = await _prepareImageForUpload(file, 'category');
      if (!await uploadFile.exists()) return null;
      if (await uploadFile.length() == 0) return null;

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return null;

      final filename = 'category_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final urlsToTry = [
        '${ApiConfig.baseUrl}/media?prefix=category',
        '${ApiConfig.baseUrl}/media/?prefix=category',
      ];

      for (final urlStr in urlsToTry) {
        final request = http.MultipartRequest('POST', Uri.parse(urlStr));
        request.followRedirects = false;
        request.headers['Authorization'] = 'Bearer $token';
        request.fields['_payload'] = jsonEncode({
          'alt': altText,
          'prefix': 'category',
        });
        request.fields['alt'] = altText;
        request.fields['prefix'] = 'category';

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

        if (response.statusCode >= 300 && response.statusCode < 400) {
          final location = response.headers['location'];
          if (location != null) {
            final resolvedUri = Uri.parse(urlStr).resolve(location);
            final redirRequest = http.MultipartRequest('POST', resolvedUri);
            redirRequest.headers['Authorization'] = 'Bearer $token';
            redirRequest.fields['_payload'] = jsonEncode({
              'alt': altText,
              'prefix': 'category',
            });
            redirRequest.fields['alt'] = altText;
            redirRequest.fields['prefix'] = 'category';
            redirRequest.files.add(await http.MultipartFile.fromPath(
              'file',
              uploadFile.path,
              filename: filename,
              contentType: MediaType('image', 'jpeg'),
            ));
            final redirResponse = await redirRequest.send();
            final redirBody = await redirResponse.stream.bytesToString();
            if (redirResponse.statusCode == 200 || redirResponse.statusCode == 201) {
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

  Future<String?> _createCategory({
    required String name,
    required String companyId,
    String? imageId,
  }) async {
    try {
      if (_userRole != 'superadmin' &&
          _userRole != 'company' &&
          _userRole != 'branch') {
        return "Category creation is not allowed for this account";
      }

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return "No token found. Please login again.";

      final normalizedName = name.trim();
      if (normalizedName.isEmpty) return "Category name is required";

      final duplicateRes = await http.get(
        Uri.parse(
          "${ApiConfig.baseUrl}/categories?where[name][equals]=${Uri.encodeComponent(normalizedName)}&limit=1&depth=0",
        ),
        headers: ApiConfig.getHeaders(token),
      );
      if (duplicateRes.statusCode == 200) {
        final docs = jsonDecode(duplicateRes.body)['docs'];
        if (docs is List && docs.isNotEmpty) {
          return "Category already exists";
        }
      }

      final payload = <String, dynamic>{
        "name": normalizedName,
        "isStock": widget.isInstockEntry,
        "isBilling": !widget.isInstockEntry,
        "isCake": false,
        "isKitchen": false,
        "company": [companyId],
      };
      if (imageId != null && imageId.isNotEmpty) {
        payload["image"] = imageId;
      }

      final res = await http.post(
        Uri.parse("${ApiConfig.baseUrl}/categories"),
        headers: ApiConfig.getHeaders(token),
        body: jsonEncode(payload),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        await _fetchCategories();
        return null;
      }

      String message = "Failed to create category (${res.statusCode})";
      try {
        final body = jsonDecode(res.body);
        final errors = body["errors"];
        if (errors is List && errors.isNotEmpty) {
          final first = errors.first;
          if (first is Map && first['message'] != null) {
            message = first['message'].toString();
          }
        } else if (body["message"] != null) {
          message = body["message"].toString();
        }
      } catch (_) {}
      if (message.startsWith("Failed to create category")) {
        final preview = res.body.trim();
        if (preview.isNotEmpty) {
          final shortPreview = preview.length > 180
              ? "${preview.substring(0, 180)}..."
              : preview;
          message = "$message: $shortPreview";
        }
      }
      return message;
    } catch (e) {
      return "Error creating category: $e";
    }
  }

  Future<void> _showCreateCategoryDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    File? capturedImage;
    bool isSubmitting = false;

    String? selectedCompanyId;
    if (_userRole == 'company' || _userRole == 'branch') {
      selectedCompanyId = _companyId;
      if ((_userRole == 'branch') &&
          (selectedCompanyId == null || selectedCompanyId.isEmpty) &&
          _branchId != null &&
          _branchId!.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token');
        if (token != null) {
          final resolved = await _fetchCompanyIdFromBranch(token, _branchId!);
          if (resolved != null && resolved.isNotEmpty) {
            selectedCompanyId = resolved;
            _companyId = resolved;
          }
        }
      }
    } else if (_userRole == 'superadmin' && _companies.isNotEmpty) {
      selectedCompanyId = _companies.first['id']?.toString();
    }

    final canChangeCompany = _userRole == 'superadmin';
    final List<Map<String, String>> companyOptions = [];
    if (_userRole == 'superadmin') {
      for (final c in _companies) {
        final id = c['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final name = c['name']?.toString() ?? 'Unknown Company';
        companyOptions.add({'id': id, 'name': name});
      }
    } else if (selectedCompanyId != null && selectedCompanyId.isNotEmpty) {
      String label = _companyName?.trim().isNotEmpty == true
          ? _companyName!
          : 'Default Company';
      for (final c in _companies) {
        final id = c['id']?.toString();
        if (id == selectedCompanyId) {
          label = c['name']?.toString() ?? label;
          break;
        }
      }
      companyOptions.add({'id': selectedCompanyId, 'name': label});
    }

    if (!mounted) return;

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 24,
              ),
              title: const Text("Create New Category"),
              content: SizedBox(
                width: MediaQuery.of(dialogContext).size.width > 620
                    ? 520
                    : MediaQuery.of(dialogContext).size.width - 24,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                      TextFormField(
                        controller: nameCtrl,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: "Category Name",
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return "Category name is required";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCompanyId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: "Company",
                          border: OutlineInputBorder(),
                        ),
                        items: companyOptions.map((company) {
                          final id = company['id'] ?? '';
                          final label = company['name'] ?? 'Unknown Company';
                          return DropdownMenuItem<String>(
                            value: id,
                            child: Text(
                              label,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          );
                        }).toList(),
                        onChanged: (isSubmitting || !canChangeCompany)
                            ? null
                            : (value) {
                                setDialogState(() {
                                  selectedCompanyId = value;
                                });
                              },
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return "Company is required";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.camera_alt_outlined, size: 18),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    "Category Image (optional)",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: isSubmitting
                                          ? null
                                          : () async {
                                              final file =
                                                  await _captureAndConfirmCategoryPhoto();
                                              if (file == null) return;
                                              setDialogState(() {
                                                capturedImage = file;
                                              });
                                            },
                                      child: Text(
                                        capturedImage == null
                                            ? "Capture"
                                            : "Retake",
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: isSubmitting
                                          ? null
                                          : () async {
                                              final file =
                                                  await _pickAndConfirmCategoryPhotoFromGallery();
                                              if (file == null) return;
                                              setDialogState(() {
                                                capturedImage = file;
                                              });
                                            },
                                      child: const Text("Select from Gallery"),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (capturedImage != null) ...[
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.file(
                                  capturedImage!,
                                  height: 140,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.pop(dialogContext, false),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          final messenger = ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(dialogContext);
                          if (selectedCompanyId == null ||
                              selectedCompanyId!.trim().isEmpty) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text("Company is required"),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isSubmitting = true;
                          });

                          String? imageId;
                          if (capturedImage != null) {
                            imageId = await _uploadCategoryPhoto(
                              capturedImage!,
                              nameCtrl.text.trim().isEmpty
                                  ? 'Category image'
                                  : nameCtrl.text.trim(),
                            );
                            if (imageId == null || imageId.isEmpty) {
                              setDialogState(() {
                                isSubmitting = false;
                              });
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Failed to upload category image',
                                  ),
                                ),
                              );
                              return;
                            }
                          }

                          final error = await _createCategory(
                            name: nameCtrl.text,
                            companyId: selectedCompanyId!,
                            imageId: imageId,
                          );
                          if (!mounted) return;
                          if (error == null) {
                            navigator.pop(true);
                          } else {
                            setDialogState(() {
                              isSubmitting = false;
                            });
                            messenger.showSnackBar(
                              SnackBar(content: Text(error)),
                            );
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("Create"),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted) return;
    if (created == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Category created successfully")),
      );
    }
  }

  // ------------------ GLOBAL SCAN (Billing Only) ------------------
  Future<void> _handleScan(String scanResult) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;

      final res = await http.get(
        Uri.parse(
          "${ApiConfig.baseUrl}/products?where[upc][equals]=$scanResult&limit=1&depth=1",
        ),
        headers: ApiConfig.getHeaders(token),
      );

      if (res.statusCode == 200) {
        final product = jsonDecode(res.body)['docs']?[0];
        if (product != null) {
          if (!mounted) return;
          final cart = Provider.of<CartProvider>(context, listen: false);
          double price =
              product['defaultPriceDetails']?['price']?.toDouble() ?? 0;

          cart.addOrUpdateItem(
            CartItem.fromProduct(product, 1, branchPrice: price),
          );
        }
      }
    } catch (_) {}
  }

  // ------------------ UI ------------------
  @override
  Widget build(BuildContext context) {
    // PAGE TITLE + FOOTER TYPE
    String title;
    PageType pageType;

    if (widget.isReturnOrder) {
      title = "Return Order Categories";
      pageType = PageType.returnorder; // ⭐ FIXED
    } else if (widget.isStockFilter) {
      title = "Stock Order Categories";
      pageType = PageType.stock; // ⭐ FIXED
    } else if (widget.isInstockEntry) {
      title = "Instock Categories";
      pageType = PageType.stock;
    } else {
      title = "Billing Categories";
      pageType = PageType.billing; // Billing footer highlight
    }

    return CommonScaffold(
      title: title,
      pageType: pageType,
      actions: pageType == PageType.billing
          ? const [PrinterSettingsAction()]
          : null,
      onScanCallback: _handleScan,
      body: RefreshIndicator(
        onRefresh: _fetchCategories,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.black),
              )
            : _errorMessage.isNotEmpty
            ? Center(child: Text(_errorMessage))
            : _categories.isEmpty && !_canCreateCategory
            ? const Center(
                child: Text(
                  "No categories found",
                  style: TextStyle(fontSize: 18),
                ),
              )
            : _buildGrid(),
      ),
    );
  }

  // ------------------ CATEGORY GRID ------------------
  Widget _buildGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cross = constraints.maxWidth > 600 ? 5 : 3;
        final extraTile = _canCreateCategory ? 1 : 0;

        return GridView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: _categories.length + extraTile,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.75,
          ),
          itemBuilder: (_, index) {
            if (_canCreateCategory && index == 0) {
              return GestureDetector(
                onTap: _showCreateCategoryDialog,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: const Color(0xFFEFFAF1),
                    border: Border.all(
                      color: const Color(0xFF2E7D32),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_circle,
                        size: 48,
                        color: Color(0xFF2E7D32),
                      ),
                      SizedBox(height: 10),
                      Text(
                        "New Category",
                        style: TextStyle(
                          color: Color(0xFF1B5E20),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        widget.isInstockEntry
                            ? "Add stock category"
                            : "Add billing category",
                        style: TextStyle(
                          color: Color(0xFF2E7D32),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final dataIndex = index - extraTile;
            final c = _categories[dataIndex];

            String? img = c['image']?['url'];
            if (img != null && img.startsWith('/')) {
              img = "${ApiConfig.domain}$img";
            }
            img ??= "https://via.placeholder.com/150?text=No+Image";

            return GestureDetector(
              onTap: () {
                Widget page;

                if (widget.isReturnOrder) {
                  page = ReturnOrderPage(
                    categoryId: c['id'],
                    categoryName: c['name'],
                  );
                } else if (widget.isStockFilter) {
                  page = const StockOrderPage();
                } else if (widget.isInstockEntry) {
                  // Initialize InstockProvider before navigation
                  Provider.of<InstockProvider>(
                    context,
                    listen: false,
                  ).selectCategory(c);
                  page = const InstockProductsPage();
                } else {
                  page = ProductsPage(
                    categoryId: c['id'],
                    categoryName: c['name'],
                  );
                }

                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => page),
                );
              },
              child: _buildCard(c, img),
            );
          },
        );
      },
    );
  }

  // ------------------ CARD UI ------------------
  Widget _buildCard(dynamic c, String img) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.15), blurRadius: 4),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            flex: 8,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
              child: CachedNetworkImage(
                imageUrl: img,
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
              ),
              child: Text(
                c['name'] ?? "Unknown",
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// _CategoryCameraDialog class removed in favor of shared CameraPage in camera_page.dart
