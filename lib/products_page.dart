import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img_lib;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:branch/common_scaffold.dart';
import 'package:branch/cart_provider.dart';
import 'package:branch/api_config.dart';
import 'package:branch/camera_page.dart';


class ProductsPage extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  const ProductsPage({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  _ProductsPageState createState() => _ProductsPageState();
}

// _ProductCameraDialog class removed in favor of shared CameraPage in camera_page.dart


class _ProductsPageState extends State<ProductsPage> {
  List<dynamic> _products = [];
  bool _isLoading = true;
  String? _branchId;
  String? _userRole;
  static const List<String> _productCreatorRoles = [
    'superadmin',
    'admin',
    'company',
    'branch',
  ];

  bool get _canCreateProduct => _productCreatorRoles.contains(_userRole);

  @override
  void initState() {
    super.initState();
    _fetchProducts();
  }

  /// Fetch user data and determine branch or waiter roles
  Future<void> _fetchUserData(String token) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/users/me?depth=2'),
        headers: ApiConfig.getHeaders(token),
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final user = data['user'] ?? data;
        setState(() {
          _userRole = user['role'];
        });
        if (user['branch'] != null) {
          setState(() {
            _branchId = (user['branch'] is Map) ? user['branch']['id'] : user['branch'];
          });
        } else if (user['role'] == 'waiter' || user['role'] == 'kitchen' || user['role'] == 'chef' || user['role'] == 'manager' || user['role'] == 'cashier') {
          await _fetchWaiterBranch(token);
        }
      }
    } catch (e) {
      // Handle silently
    }
  }

  /// Get private device IP (LAN)
  Future<String?> _fetchDeviceIp() async {
    try {
      final info = NetworkInfo();
      final ip = await info.getWifiIP();
      return ip?.trim();
    } catch (e) {
      return null;
    }
  }

  /// Convert IP string to int for range comparison
  int _ipToInt(String ip) {
    final parts = ip.split('.').map(int.parse).toList();
    return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
  }

  /// Check if an IP falls inside a range "startIP - endIP"
  bool _isIpInRange(String deviceIp, String range) {
    final parts = range.split('-');
    if (parts.length != 2) return false;
    final startIp = _ipToInt(parts[0].trim());
    final endIp = _ipToInt(parts[1].trim());
    final device = _ipToInt(deviceIp);
    return device >= startIp && device <= endIp;
  }

  /// Find the waiter's branch by matching device IP to branch IP or range
  Future<void> _fetchWaiterBranch(String token) async {
    String? deviceIp = await _fetchDeviceIp();
    if (deviceIp == null) return;
    try {
      final allBranchesResponse = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/branches?depth=1'),
        headers: ApiConfig.getHeaders(token),
      );
      if (allBranchesResponse.statusCode == 200) {
        final branchesData = jsonDecode(allBranchesResponse.body);
        if (branchesData['docs'] != null && branchesData['docs'] is List) {
          for (var branch in branchesData['docs']) {
            String? bIpRange = branch['ipAddress']?.toString().trim();
            if (bIpRange != null) {
              if (bIpRange == deviceIp || _isIpInRange(deviceIp, bIpRange)) {
                setState(() {
                  _branchId = branch['id'];
                });
                break;
              }
            }
          }
        }
      }
    } catch (e) {
      // Handle silently
    }
  }

  /// Fetch all products under a category, filtered by role/branch
  Future<void> _fetchProducts() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No token found. Please login again.')),
        );
        return;
      }
      if (_branchId == null && _userRole == null) {
        await _fetchUserData(token);
      }
      // Updated: Fetch all products in the category without restricting to branch overrides
      String url = '${ApiConfig.baseUrl}/products?where[category][equals]=${widget.categoryId}&limit=100&depth=1';
      final response = await http.get(
        Uri.parse(url),
        headers: ApiConfig.getHeaders(token),
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        setState(() {
          _products = data['docs'] ?? [];
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch products: ${response.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network error: Check your internet')),
      );
    }
    setState(() {
      _isLoading = false;
    });
  }

  /// Add or update product in cart
  void _toggleProductSelection(int index) async {
    final product = _products[index];
    final cartProvider = Provider.of<CartProvider>(context, listen: false);

    // Step 1: Get product price
    double price = product['defaultPriceDetails']?['price']?.toDouble() ?? 0.0;
    if (_branchId != null && product['branchOverrides'] != null) {
      for (var override in product['branchOverrides']) {
        var branch = override['branch'];
        String branchOid = branch is Map ? (branch[r'$oid'] ?? branch['id'] ?? '') : (branch ?? '');
        if (branchOid == _branchId) {
          price = override['price']?.toDouble() ?? price;
          break;
        }
      }
    }

    // Step 2: Detect if the product is weight-based
    bool isWeightBased = false;
    try {
      final unit = product['defaultPriceDetails']?['unit']?.toString().toLowerCase();
      final isKgFlag = product['isKg'] == true || product['sellByWeight'] == true || product['weightBased'] == true;
      final pricingType = product['pricingType']?.toString().toLowerCase();

      if (unit != null && (unit.contains('kg') || unit.contains('gram'))) isWeightBased = true;
      if (isKgFlag) isWeightBased = true;
      if (pricingType != null && pricingType.contains('kg')) isWeightBased = true;
      // Removed name check to avoid false positives
    } catch (e) {
      isWeightBased = false;
    }

    // Step 3: Get current quantity if exists
    double existingQty = 0.0;
    final existingItem = cartProvider.cartItems.firstWhere(
          (i) => i.id == product['id'],
      orElse: () => CartItem(id: '', name: '', price: 0, quantity: 0),
    );
    if (existingItem.id.isNotEmpty) {
      existingQty = existingItem.quantity.toDouble();
    }

    double quantity = 1.0;
    if (isWeightBased) {
      // Step 4: Show popup if weight-based
      final unit = product['defaultPriceDetails']?['unit'] ?? 'kg';
      final TextEditingController weightController = TextEditingController(
        text: existingQty > 0 ? existingQty.toStringAsFixed(2) : '',
      );
      final enteredWeight = await showDialog<double>(
        context: context,
        barrierDismissible: true,
        builder: (context) {
          return AlertDialog(
            title: Text('Enter Weight ($unit)'),
            content: TextField(
              controller: weightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: 'e.g. 0.5',
                labelText: 'Weight in $unit',
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final value = double.tryParse(weightController.text.trim()) ?? 0.0;
                  Navigator.pop(context, value);
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      if (enteredWeight == null || enteredWeight <= 0) return;
      quantity = enteredWeight;
    }

    // Step 5: Update or add
    final item = CartItem.fromProduct(product, quantity, branchPrice: price);
    if (isWeightBased) {
      if (existingItem.id.isNotEmpty) {
        cartProvider.updateQuantity(product['id'], quantity);
      } else {
        cartProvider.addOrUpdateItem(item);
      }
    } else {
      cartProvider.addOrUpdateItem(item);
    }
  }

  Future<File?> _captureAndConfirmPhoto() async {
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
    if (!mounted) return null;

    final XFile? photo = await Navigator.push<XFile>(
      context,
      MaterialPageRoute(
        builder: (context) => CameraPage(cameras: cameras),
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
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempFile = File('${tempDir.path}/product_$timestamp.jpg');
    await tempFile.writeAsBytes(compressed);
    return tempFile;
  }

  Future<File?> _pickAndConfirmPhotoFromGallery() async {
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
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/product_gallery_$timestamp.jpg');
      await tempFile.writeAsBytes(compressed);
      if (!mounted) return null;

      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Image Preview'),
          content: Image.file(tempFile),
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

      if (confirmed == true) return tempFile;
      if (await tempFile.exists()) {
        await tempFile.delete();
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

  Future<String?> _uploadProductPhoto(File file, String altText) async {
    try {
      final uploadFile = await _prepareImageForUpload(file, 'product');
      if (!await uploadFile.exists()) return null;
      if (await uploadFile.length() == 0) return null;

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return null;

      final filename = 'product_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final urlsToTry = [
        '${ApiConfig.baseUrl}/media/?prefix=product',
        '${ApiConfig.baseUrl}/media?prefix=product',
      ];

      for (final urlStr in urlsToTry) {
        final request = http.MultipartRequest('POST', Uri.parse(urlStr));
        request.followRedirects = false;
        request.headers['Authorization'] = 'Bearer $token';
        request.fields['_payload'] = jsonEncode({
          'alt': altText,
          'prefix': 'product',
        });
        request.fields['alt'] = altText;
        request.fields['prefix'] = 'product';

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
              'prefix': 'product',
            });
            redirRequest.fields['alt'] = altText;
            redirRequest.fields['prefix'] = 'product';
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

  Future<String?> _createProduct({
    required String name,
    required double price,
    required double rate,
    required bool isVeg,
    required String unit,
    required String gst,
    required String imageId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return 'No token found. Please login again.';

      final normalizedName = name.trim();
      if (normalizedName.isEmpty) {
        return 'Product name is required';
      }

      // Friendly precheck to avoid hard 500 on unique constraint.
      final duplicateRes = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/products?where[name][equals]=${Uri.encodeComponent(normalizedName)}&limit=1&depth=0',
        ),
        headers: ApiConfig.getHeaders(token),
      );
      if (duplicateRes.statusCode == 200) {
        final docs = jsonDecode(duplicateRes.body)['docs'];
        if (docs is List && docs.isNotEmpty) {
          return 'Product name already exists';
        }
      }

      final payload = <String, dynamic>{
        'name': normalizedName,
        'category': widget.categoryId,
        'isVeg': isVeg,
        'images': [
          {'image': imageId},
        ],
        'defaultPriceDetails': {
          'price': price,
          'rate': rate,
          'quantity': 1,
          'unit': unit.trim(),
          'gst': gst,
        },
      };

      http.Response? res;
      String bodyText = '';
      const maxAttempts = 2;

      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        res = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/products'),
          headers: ApiConfig.getHeaders(token),
          body: jsonEncode(payload),
        );
        bodyText = res.body;

        if (res.statusCode == 200 || res.statusCode == 201) {
          break;
        }

        // Retry once for duplicate-key race from auto-generated productId/UPC.
        final lower = bodyText.toLowerCase();
        final isDuplicateKey =
            bodyText.contains('E11000') || lower.contains('duplicate key');
        if (attempt < maxAttempts - 1 &&
            res.statusCode == 500 &&
            isDuplicateKey) {
          await Future.delayed(const Duration(milliseconds: 250));
          continue;
        }

        break;
      }

      if (res == null) {
        return 'Failed to create product';
      }

      if (res.statusCode == 200 || res.statusCode == 201) {
        await _fetchProducts();
        return null;
      }

      String message = 'Failed to create product (${res.statusCode})';
      try {
        final body = jsonDecode(bodyText);
        final errors = body['errors'];
        if (errors is List && errors.isNotEmpty) {
          final firstError = errors.first;
          if (firstError is Map && firstError['message'] != null) {
            message = firstError['message'].toString();
          }
        } else if (body['message'] != null) {
          message = body['message'].toString();
        }
      } catch (_) {}

      if (message.startsWith('Failed to create product')) {
        final preview = bodyText.trim();
        if (preview.isNotEmpty) {
          final shortPreview = preview.length > 180
              ? '${preview.substring(0, 180)}...'
              : preview;
          message = '$message: $shortPreview';
        }
      }

      return message;
    } catch (e) {
      return 'Error creating product: $e';
    }
  }

  Future<void> _showCreateProductDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final rateCtrl = TextEditingController();

    String selectedUnit = 'pcs';
    String selectedGst = '0';
    bool isVeg = false;
    bool isSubmitting = false;
    File? capturedImage;

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
              title: const Text('Create New Product'),
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
                          labelText: 'Product Name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Product name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: priceCtrl,
                        textInputAction: TextInputAction.next,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Price',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final parsed = double.tryParse((value ?? '').trim());
                          if (parsed == null || parsed <= 0) {
                            return 'Enter a valid price';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: rateCtrl,
                        textInputAction: TextInputAction.next,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Rate',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final parsed = double.tryParse((value ?? '').trim());
                          if (parsed == null || parsed < 0) {
                            return 'Enter a valid rate';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedUnit,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Unit',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'pcs', child: Text('pcs')),
                          DropdownMenuItem(value: 'kg', child: Text('kg')),
                          DropdownMenuItem(value: 'g', child: Text('g')),
                        ],
                        onChanged: isSubmitting
                            ? null
                            : (value) {
                                if (value == null) return;
                                setDialogState(() {
                                  selectedUnit = value;
                                });
                              },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedGst,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'GST',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: '0', child: Text('0%')),
                          DropdownMenuItem(value: '5', child: Text('5%')),
                          DropdownMenuItem(value: '12', child: Text('12%')),
                          DropdownMenuItem(value: '18', child: Text('18%')),
                          DropdownMenuItem(value: '22', child: Text('22%')),
                        ],
                        onChanged: isSubmitting
                            ? null
                            : (value) {
                                if (value == null) return;
                                setDialogState(() {
                                  selectedGst = value;
                                });
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
                                    'Product Image',
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
                                                  await _captureAndConfirmPhoto();
                                              if (file == null) return;
                                              setDialogState(() {
                                                capturedImage = file;
                                              });
                                            },
                                      child: Text(
                                        capturedImage == null
                                            ? 'Capture'
                                            : 'Retake',
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: isSubmitting
                                          ? null
                                          : () async {
                                              final file =
                                                  await _pickAndConfirmPhotoFromGallery();
                                              if (file == null) return;
                                              setDialogState(() {
                                                capturedImage = file;
                                              });
                                            },
                                      child: const Text('Select from Gallery'),
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
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Is Veg'),
                        value: isVeg,
                        onChanged: (value) {
                          setDialogState(() {
                            isVeg = value;
                          });
                        },
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
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;

                          final messenger = ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(dialogContext);
                          if (capturedImage == null) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Please capture product image'),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isSubmitting = true;
                          });

                          final mediaId = await _uploadProductPhoto(
                            capturedImage!,
                            nameCtrl.text.trim().isEmpty
                                ? 'Product image'
                                : nameCtrl.text.trim(),
                          );
                          if (mediaId == null || mediaId.isEmpty) {
                            setDialogState(() {
                              isSubmitting = false;
                            });
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Failed to upload product image'),
                              ),
                            );
                            return;
                          }

                          final error = await _createProduct(
                            name: nameCtrl.text,
                            price: double.parse(priceCtrl.text.trim()),
                            rate: double.parse(rateCtrl.text.trim()),
                            isVeg: isVeg,
                            unit: selectedUnit,
                            gst: selectedGst,
                            imageId: mediaId,
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
                      : const Text('Create'),
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
        const SnackBar(content: Text('Product created successfully')),
      );
    }
  }

  /// Barcode scan support
  void _handleScan(String scanResult) {
    for (int index = 0; index < _products.length; index++) {
      final product = _products[index];
      if (product['upc'] == scanResult) {
        _toggleProductSelection(index);
        return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Product not found in this category')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: 'Products in ${widget.categoryName}',
      pageType: PageType.billing,
      onScanCallback: _handleScan,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : LayoutBuilder(
        builder: (context, constraints) {
          if (_products.isEmpty && !_canCreateProduct) {
            return const Center(
              child: Text(
                'No products found',
                style: TextStyle(color: Color(0xFF4A4A4A), fontSize: 18),
              ),
            );
          }

          final width = constraints.maxWidth;
          final crossAxisCount = (width > 600) ? 5 : 3;
          final extraTile = _canCreateProduct ? 1 : 0;
          return GridView.builder(
            padding: const EdgeInsets.all(10),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.75,
            ),
            itemCount: _products.length + extraTile,
            itemBuilder: (context, index) {
              if (_canCreateProduct && index == 0) {
                return GestureDetector(
                  onTap: _showCreateProductDialog,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: const Color(0xFFEFFAF1),
                      border: Border.all(
                        color: const Color(0xFF2E7D32),
                        width: 2,
                      ),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_circle,
                          size: 48,
                          color: Color(0xFF2E7D32),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'New Product',
                          style: TextStyle(
                            color: Color(0xFF1B5E20),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Add to this category',
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
              final product = _products[dataIndex];
              String? imageUrl;
              if (product['images'] != null &&
                  product['images'].isNotEmpty &&
                  product['images'][0]['image'] != null &&
                  product['images'][0]['image']['url'] != null) {
                imageUrl = product['images'][0]['image']['url'];
                if (imageUrl != null && imageUrl.startsWith('/')) {
                  imageUrl = '${ApiConfig.domain}$imageUrl';
                }
              }
              imageUrl ??= 'https://via.placeholder.com/150?text=No+Image';

              dynamic priceDetails = product['defaultPriceDetails'];
              if (_branchId != null && product['branchOverrides'] != null) {
                for (var override in product['branchOverrides']) {
                  var branch = override['branch'];
                  String branchOid = branch is Map ? branch[r'$oid'] ?? branch['id'] ?? '' : branch ?? '';
                  if (branchOid == _branchId) {
                    priceDetails = override;
                    break;
                  }
                }
              }
              final price = priceDetails != null ? '₹${priceDetails['price'] ?? 0}' : '₹0';

              return GestureDetector(
                onTap: () => _toggleProductSelection(dataIndex),
                child: Consumer<CartProvider>(
                  builder: (context, cartProvider, child) {
                    final isSelected = cartProvider.cartItems.any((i) => i.id == product['id']);
                    final qty = cartProvider.cartItems
                        .firstWhere(
                          (i) => i.id == product['id'],
                      orElse: () => CartItem(
                        id: '',
                        name: '',
                        price: 0,
                        quantity: 0,
                      ),
                    )
                        .quantity;
                    String qtyText;
                    if (qty == qty.floorToDouble()) {
                      qtyText = qty.toInt().toString();
                    } else {
                      qtyText = qty.toStringAsFixed(2);
                    }

                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected ? Border.all(color: Colors.green, width: 4) : null,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            spreadRadius: 2,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Column(
                            children: [
                              Expanded(
                                flex: 8,
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                  child: CachedNetworkImage(
                                    imageUrl: imageUrl!,
                                    fit: BoxFit.cover,
                                    width: double.infinity,

                                    placeholder: (context, url) =>
                                    const Center(child: CircularProgressIndicator()),
                                    errorWidget: (context, url, error) => const Center(
                                      child: Text('No Image', style: TextStyle(color: Colors.grey)),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Container(
                                  width: double.infinity,
                                  decoration: const BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    product['name'] ?? 'Unknown',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Positioned(
                            top: 2,
                            left: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                price,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                          if (isSelected)
                            Positioned.fill(
                              child: Align(
                                alignment: Alignment.center,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.7),
                                    border: Border.all(color: Colors.grey, width: 1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  child: Text(
                                    qtyText,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
