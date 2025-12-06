import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:branch/common_scaffold.dart';
import 'package:branch/cart_page.dart';
import 'package:provider/provider.dart';
import 'package:branch/return_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img_lib;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http_parser/http_parser.dart';

class ReturnOrderPage extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  const ReturnOrderPage({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  _ReturnOrderPageState createState() => _ReturnOrderPageState();
}

class _ReturnOrderPageState extends State<ReturnOrderPage> {
  List<dynamic> _products = [];
  bool _isLoading = true;
  String? _branchId;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    _fetchProducts().then((_) {
      // Load pending AFTER products fetched (for alt text)
      final provider = Provider.of<ReturnProvider>(context, listen: false);
      provider.loadPendingPhotos(_products);
    });
  }

  int _ipToInt(String ip) {
    final parts = ip.split('.').map(int.parse).toList();
    return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
  }

  bool _isIpInRange(String deviceIp, String range) {
    final parts = range.split('-');
    if (parts.length != 2) return false;
    final startIp = _ipToInt(parts[0].trim());
    final endIp = _ipToInt(parts[1].trim());
    final device = _ipToInt(deviceIp);
    return device >= startIp && device <= endIp;
  }

  Future<String?> _fetchDeviceIp() async {
    try {
      final info = NetworkInfo();
      final ip = await info.getWifiIP();
      return ip?.trim();
    } catch (e) {
      return null;
    }
  }

  Future<void> _fetchUserData(String token) async {
    try {
      final response = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/users/me?depth=2'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final user = data['user'] ?? data;
        setState(() {
          _userRole = user['role'];
        });
        if (user['role'] == 'branch' && user['branch'] != null) {
          setState(() {
            _branchId = (user['branch'] is Map) ? user['branch']['id'] : user['branch'];
          });
          Provider.of<ReturnProvider>(context, listen: false).setBranchId(_branchId);
        } else if (user['role'] == 'waiter') {
          await _fetchWaiterBranch(token);
        }
      }
    } catch (e) {}
  }

  Future<void> _fetchWaiterBranch(String token) async {
    String? deviceIp = await _fetchDeviceIp();
    if (deviceIp == null) return;
    try {
      final response = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/branches?depth=1'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final branches = data['docs'] ?? [];
        for (var branch in branches) {
          String? branchIp = branch['ipAddress']?.toString().trim();
          if (branchIp == null) continue;
          if (branchIp == deviceIp || _isIpInRange(deviceIp, branchIp)) {
            setState(() {
              _branchId = branch['id'];
            });
            Provider.of<ReturnProvider>(context, listen: false).setBranchId(_branchId);
            break;
          }
        }
      }
    } catch (e) {}
  }

  Future<void> _fetchProducts() async {
    setState(() => _isLoading = true);
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
      final url = 'https://admin.theblackforestcakes.com/api/products?where[category][equals]=${widget.categoryId}&limit=100&depth=1';
      final response = await http.get(Uri.parse(url), headers: {
        'Authorization': 'Bearer $token',
      });
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        setState(() {
          _products = data['docs'] ?? [];
          _isLoading = false;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch products: ${response.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network error, try again')),
      );
    }
    setState(() => _isLoading = false);
  }

  void _toggleReturnSelection(int index) async {
    final product = _products[index];
    final provider = Provider.of<ReturnProvider>(context, listen: false);

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
    final existingItem = provider.returnItems.firstWhere(
          (i) => i.id == product['id'],
      orElse: () => ReturnItem(id: '', name: '', price: 0, quantity: 0),
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
    if (isWeightBased) {
      if (existingItem.id.isNotEmpty) {
        provider.updateQuantity(product['id'], quantity);
      } else {
        provider.addOrUpdateItem(product['id'], product['name'], quantity, price);
      }
    } else {
      provider.addOrUpdateItem(product['id'], product['name'], existingQty.toInt() + 1, price);
    }
  }

  void _handleScan(String scanResult) {
    final provider = Provider.of<ReturnProvider>(context, listen: false);
    for (int index = 0; index < _products.length; index++) {
      final product = _products[index];
      if (product['upc'] == scanResult) {
        _toggleReturnSelection(index);
        return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Product not found')),
    );
  }

  Future<void> _submitReturnOrders() async {
    final provider = Provider.of<ReturnProvider>(context, listen: false);
    await provider.submitReturn(context, _branchId);
    // Navigation handled in provider
  }

  Future<void> _capturePhoto(String productId) async {
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
    final XFile? photo = await showDialog<XFile>(
      context: context,
      builder: (context) => CameraDialog(cameras: cameras),
    );
    if (photo == null) return;
    final bytes = await photo.readAsBytes();
    final image = img_lib.decodeImage(bytes)!;
    final compressed = img_lib.encodeJpg(image, quality: 70);
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempFile = File('${tempDir.path}/return_${productId}_$timestamp.jpg');
    await tempFile.writeAsBytes(compressed);
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Photo Preview'),
        content: Image.file(tempFile),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Retake')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) {
      await tempFile.delete();
      return _capturePhoto(productId);
    }
    final product = _products.firstWhere((p) => p['id'] == productId, orElse: () => {'name': 'Unknown'});
    final altText = product['name'] ?? 'Return proof';
    final mediaId = await _uploadPhoto(tempFile, altText);
    final provider = Provider.of<ReturnProvider>(context, listen: false);
    if (mediaId != null) {
      final url = await _fetchMediaUrl(mediaId);
      provider.setPhoto(productId, mediaId, tempFile, url);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload failed, saved locally')),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_photo_$productId', tempFile.path);
      provider.setPhoto(productId, '', tempFile, null);
    }
  }

  Future<String?> _fetchMediaUrl(String mediaId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return null;
      final response = await http.get(
        Uri.parse('https://admin.theblackforestcakes.com/api/media/$mediaId?depth=0'),
        headers: {'Authorization': 'Bearer $token'},
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

  Future<String?> _uploadPhoto(File file, String altText) async {
    // Same as before
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return null;
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://admin.theblackforestcakes.com/api/media?prefix=returnorder'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['alt'] = altText;
      request.files.add(http.MultipartFile(
        'file',
        file.readAsBytes().asStream(),
        file.lengthSync(),
        filename: file.path.split('/').last,
        contentType: MediaType('image', 'jpeg'),
      ));
      final response = await request.send();
      if (response.statusCode == 201 || response.statusCode == 200) {
        final body = await response.stream.bytesToString();
        final data = jsonDecode(body);
        return data['doc']['id'];
      } else {
        final body = await response.stream.bytesToString();
        print('Upload error: ${response.statusCode} - $body');
        return null;
      }
    } catch (e) {
      print('Upload exception: $e');
      return null;
    }
  }

  Future<void> _handleCameraTap(String productId) async {
    final provider = Provider.of<ReturnProvider>(context, listen: false);
    final hasPhoto = provider.hasPhoto(productId);
    if (!hasPhoto) {
      await _capturePhoto(productId);
    } else {
      final file = provider.getTempPhoto(productId);
      String? previewUrl = provider.getPhotoUrl(productId);
      Widget previewWidget;
      if (file != null && await file.exists()) {
        previewWidget = Image.file(file);
      } else if (previewUrl != null) {
        previewWidget = CachedNetworkImage(imageUrl: previewUrl, fit: BoxFit.contain);
      } else {
        previewWidget = const Text('No preview available');
      }
      final retake = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Current Photo'),
          content: previewWidget,
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Retake')),
          ],
        ),
      );
      if (retake == true) {
        await _capturePhoto(productId);
      }
    }
  }

  Future<void> _unselectProduct(String productId) async {
    final provider = Provider.of<ReturnProvider>(context, listen: false);
    provider.removeItem(productId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Product unselected and photo removed')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: 'Return Order Products in ${widget.categoryName}',
      pageType: PageType.returnorder,
      onScanCallback: _handleScan,
      body: Column(
        children: [
          // Button removed as per request to use Cart Icon in header
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.black))
                : _products.isEmpty
                ? const Center(
              child: Text(
                'No products found',
                style: TextStyle(color: Color(0xFF4A4A4A), fontSize: 18),
              ),
            )
                : LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final crossAxisCount = (width > 600) ? 5 : 3;
                return GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: _products.length,
                  itemBuilder: (context, index) {
                    final product = _products[index];
                    final id = product['id'];
                    String? imageUrl;
                    if (product['images'] != null &&
                        product['images'].isNotEmpty &&
                        product['images'][0]['image'] != null &&
                        product['images'][0]['image']['url'] != null) {
                      imageUrl = product['images'][0]['image']['url'];
                      if (imageUrl != null && imageUrl.startsWith('/')) {
                        imageUrl = 'https://admin.theblackforestcakes.com$imageUrl';
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
                      onTap: () => _toggleReturnSelection(index),
                      child: Consumer<ReturnProvider>(
                        builder: (context, provider, child) {
                          final matching = provider.returnItems.where((i) => i.id == id).toList();
                          final isSelected = matching.isNotEmpty && matching.first.quantity > 0;
                          final qty = isSelected ? matching.first.quantity : 0.0;
                          String qtyText;
                          if (qty == qty.floorToDouble()) {
                            qtyText = qty.toInt().toString();
                          } else {
                            qtyText = qty.toStringAsFixed(2);
                          }
                          final hasPhoto = provider.hasPhoto(id);
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
                                          placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                                          errorWidget: (context, url, error) => const Center(child: Text('No Image', style: TextStyle(color: Colors.grey))),
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
                                  child: GestureDetector(
                                    onTap: () => _unselectProduct(id),
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
                                ),
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: GestureDetector(
                                    onTap: () => _handleCameraTap(id),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        borderRadius: BorderRadius.circular(4),
                                        border: hasPhoto ? Border.all(color: Colors.green, width: 2) : null,
                                      ),
                                      child: provider.getTempPhoto(id) != null && provider.getTempPhoto(id)!.existsSync()
                                          ? ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: Image.file(
                                          provider.getTempPhoto(id)!,
                                          width: 24,
                                          height: 24,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                          : provider.getPhotoUrl(id) != null
                                          ? ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: CachedNetworkImage(
                                          imageUrl: provider.getPhotoUrl(id)!,
                                          width: 24,
                                          height: 24,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) => const CircularProgressIndicator(strokeWidth: 2),
                                          errorWidget: (context, url, error) => Icon(
                                            Icons.camera_alt,
                                            color: hasPhoto ? Colors.green : Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                      )
                                          : Icon(Icons.camera_alt, color: hasPhoto ? Colors.green : Colors.white, size: 20),
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
          ),
        ],
      ),
    );
  }
}

class CameraDialog extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraDialog({super.key, required this.cameras});

  @override
  _CameraDialogState createState() => _CameraDialogState();
}

class _CameraDialogState extends State<CameraDialog> {
  late CameraController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.cameras[0], ResolutionPreset.high);
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    }).catchError((e) {
      print('Camera init error: $e');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return AlertDialog(
      content: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: CameraPreview(_controller),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () async {
            try {
              final XFile file = await _controller.takePicture();
              Navigator.pop(context, file);
            } catch (e) {
              print('Capture error: $e');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Failed to capture photo')),
              );
              Navigator.pop(context);
            }
          },
          child: const Text('Capture'),
        ),
      ],
    );
  }
}