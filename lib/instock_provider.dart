import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img_lib;
import 'package:path_provider/path_provider.dart';
import 'package:branch/api_config.dart';

class InstockProvider extends ChangeNotifier {
  // ========== STEP SYSTEM ==========
  String _step = "categories";
  String get step => _step;

  // ========== CATEGORY DATA ==========
  List<dynamic> _categories = [];
  List<dynamic> get categories => _categories;

  // ========== PRODUCT DATA ==========
  List<dynamic> _products = [];
  List<dynamic> _filteredProducts = [];
  List<dynamic> get filteredProducts => _filteredProducts;

  // ========== DEALER DATA ==========
  final List<Map<String, dynamic>> _dealers = [];
  List<Map<String, dynamic>> get dealers => _dealers;

  String? _selectedDealerId;
  String? get selectedDealerId => _selectedDealerId;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  String? _selectedCategoryId;
  String? _selectedCategoryName;
  String? get selectedCategoryId => _selectedCategoryId;
  String? get selectedCategoryName => _selectedCategoryName;

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  String? _userRole;
  String? _companyId;
  String? _branchId;
  String? get userRole => _userRole;

  // ========== CART DATA (Separate from StockProvider) ==========
  // We only track inStock values here
  final Map<String, double> _inStockQuery = {};
  final Map<String, double> _baseQuantities = {};
  final Map<String, String> _productNames = {};
  final Map<String, double> _prices = {};

  Map<String, double> get inStockQuery => _inStockQuery;
  Map<String, String> get productNames => _productNames;
  Map<String, double> get prices => _prices;

  // ========== CONSTRUCTOR ==========
  InstockProvider() {
    _loadCategories();
  }

  // ========== USER & BRANCH LOGIC (Copied for consistency) ==========
  Future<String?> _deviceIp() async {
    try {
      final info = NetworkInfo();
      return await info.getWifiIP();
    } catch (_) {
      return null;
    }
  }

  int _ipToInt(String ip) {
    final parts = ip.split('.').map(int.parse).toList();
    return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
  }

  bool _ipInRange(String ip, String range) {
    final parts = range.split("-");
    if (parts.length != 2) return false;
    final start = _ipToInt(parts[0].trim());
    final end = _ipToInt(parts[1].trim());
    final device = _ipToInt(ip);
    return device >= start && device <= end;
  }

  Future<void> _loadUserData(String token) async {
    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/users/me?depth=2"),
        headers: ApiConfig.getHeaders(token),
      );

      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body);
      final user = data["user"] ?? data;

      _userRole = user["role"];

      if (_userRole == "company") {
        _companyId = user["company"] is Map
            ? user["company"]["id"]
            : user["company"];
      }

      if (user["branch"] != null) {
        _branchId = user["branch"] is Map
            ? user["branch"]["id"]
            : user["branch"];
        final comp = user["branch"] is Map ? user["branch"]["company"] : null;
        _companyId = comp is Map ? comp["id"] : comp;
      } else if (_userRole == "waiter" || _userRole == "kitchen" || _userRole == "chef" || _userRole == "manager" || _userRole == "cashier") {
        await _detectWaiterBranch(token);
      }
    } catch (_) {}
  }

  Future<void> _detectWaiterBranch(String token) async {
    final ip = await _deviceIp();
    if (ip == null) return;
    final res = await http.get(
      Uri.parse("${ApiConfig.baseUrl}/branches?depth=1"),
      headers: ApiConfig.getHeaders(token),
    );
    if (res.statusCode != 200) return;
    final docs = jsonDecode(res.body)["docs"] ?? [];
    for (var b in docs) {
      final range = b["ipAddress"]?.toString().trim();
      if (range != null && (_ipInRange(ip, range) || ip == range)) {
        _branchId = b["id"];
        final comp = b["company"];
        _companyId = comp is Map ? comp["id"] : comp;
        break;
      }
    }
  }

  Future<List<String>> _matchingCompanies(String token, String? ip) async {
    if (ip == null) return [];
    List<String> out = [];
    final res = await http.get(
      Uri.parse("${ApiConfig.baseUrl}/branches?depth=1"),
      headers: ApiConfig.getHeaders(token),
    );
    if (res.statusCode != 200) return [];
    final docs = jsonDecode(res.body)["docs"] ?? [];
    for (var b in docs) {
      final range = b["ipAddress"]?.toString().trim();
      if (range != null && _ipInRange(ip, range)) {
        final comp = b["company"];
        final cid = comp is Map ? comp["id"] : comp?.toString();
        if (cid != null) out.add(cid);
      }
    }
    return out;
  }

  // ========== LOAD CATEGORIES ==========
  Future<void> _loadCategories() async {
    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    if (token == null) return;

    if (_userRole == null) await _loadUserData(token);

    String query = "where[isStock][equals]=true";
    if (_userRole != "superadmin") {
      if (_companyId != null) {
        query += "&where[company][equals]=$_companyId";
      } else if (_userRole == "waiter" || _userRole == "kitchen" || _userRole == "chef" || _userRole == "manager" || _userRole == "cashier") {
        final ip = await _deviceIp();
        final matches = await _matchingCompanies(token, ip);
        if (matches.isNotEmpty) {
          query += "&where[company][in]=${matches.join(",")}";
        }
      }
    }

    final res = await http.get(
      Uri.parse("${ApiConfig.baseUrl}/categories?$query&limit=100&depth=1"),
      headers: ApiConfig.getHeaders(token),
    );

    if (res.statusCode == 200) {
      _categories = jsonDecode(res.body)["docs"] ?? [];
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadDealers({bool force = false}) async {
    if (_dealers.isNotEmpty && !force) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");
      if (token == null) return;

      String query = "where[status][equals]=active";
      if (_companyId != null && _companyId!.isNotEmpty) {
        query += "&where[allowedCompanies][contains]=$_companyId";
      }

      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/dealers?$query&limit=200&depth=0"),
        headers: ApiConfig.getHeaders(token),
      );

      if (res.statusCode == 200) {
        final docs = jsonDecode(res.body)["docs"] ?? [];
        _dealers.clear();
        for (final d in docs) {
          final id = d["id"]?.toString();
          if (id == null || id.isEmpty) continue;
          final name =
              d["companyName"]?.toString() ??
              d["name"]?.toString() ??
              "Unknown Dealer";
          _dealers.add({"id": id, "name": name});
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  // ========== SELECT CATEGORY & LOAD PRODUCTS ==========
  Future<void> selectCategory(dynamic category) async {
    _selectedCategoryId = category["id"];
    _selectedCategoryName = category["name"];
    _step = "products";
    notifyListeners();
    await _loadProducts();
  }

  Future<void> _loadProducts() async {
    if (_selectedCategoryId == null) return;
    _isLoading =
        true; // Use bool literal, not variable assignment outside method
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    if (token == null) return;

    final url =
        "${ApiConfig.baseUrl}/products?where[category][equals]=$_selectedCategoryId&limit=200&depth=2";
    final res = await http.get(
      Uri.parse(url),
      headers: ApiConfig.getHeaders(token),
    );

    if (res.statusCode == 200) {
      final docs = jsonDecode(res.body)["docs"] ?? [];
      _products = docs;
      _filteredProducts = docs;

      for (var p in docs) {
        _storeProductMetadata(p);
      }
    }
    _isLoading = false;
    notifyListeners();
  }

  // ========== CART DEALER FILTER (REMOVED) ==========
  // The backend handles dealer association automatically.
  // We keep _productDealers map populated in _loadProducts just in case we need it for display later,
  // but filtering logic is removed as per user request.

  final Map<String, Map<String, dynamic>> _productDealers =
      {}; // productId -> dealerData

  void _storeProductMetadata(dynamic product) {
    final id = product["id"]?.toString();
    if (id == null || id.isEmpty) return;

    dynamic priceDetails = product['defaultPriceDetails'];

    // Extract Dealer Info for this product
    var dealer = product["dealer"];
    dealer ??= product["vendor"]; // Fallback 1
    dealer ??= product["supplier"]; // Fallback 2
    dealer ??= product["dealers"]; // Fallback 3 (Plural)

    if (dealer != null) {
      String dId;
      String dName;
      if (dealer is Map) {
        dId = dealer["id"] ?? dealer["_id"] ?? "";
        dName = dealer["companyName"] ?? dealer["name"] ?? "Unknown Dealer";
      } else {
        dId = dealer.toString();
        dName = "Dealer $dId";
      }
      if (dId.isNotEmpty) {
        _productDealers[id] = {"id": dId, "name": dName};
      }
    }

    if (_branchId != null && product['branchOverrides'] != null) {
      for (var override in product['branchOverrides']) {
        var b = override['branch'];
        String bId = b is Map ? b['id'] ?? b['_id'] : b;
        if (bId == _branchId) {
          priceDetails = override;
          break;
        }
      }
    }

    _productNames[id] = product["name"] ?? "Unknown";
    _prices[id] = (priceDetails['price'] as num?)?.toDouble() ?? 0.0;
    _baseQuantities[id] = (priceDetails['quantity'] as num?)?.toDouble() ?? 1.0;
    if (_baseQuantities[id] == 0) _baseQuantities[id] = 1.0;
  }

  Future<String?> createProduct({
    required String name,
    required String dealerId,
    required double price,
    required double rate,
    required bool isVeg,
    required String unit,
    required String gst,
    required String imageId,
  }) async {
    if (_selectedCategoryId == null) {
      return "Please select a category first";
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");
      if (token == null) return "No token found. Please login again.";

      final normalizedName = name.trim();
      if (normalizedName.isEmpty) {
        return "Product name is required";
      }

      // Friendly precheck to avoid hard 500 on unique constraint.
      final duplicateRes = await http.get(
        Uri.parse(
          "${ApiConfig.baseUrl}/products?where[name][equals]=${Uri.encodeComponent(normalizedName)}&limit=1&depth=0",
        ),
        headers: ApiConfig.getHeaders(token),
      );
      if (duplicateRes.statusCode == 200) {
        final docs = jsonDecode(duplicateRes.body)["docs"];
        if (docs is List && docs.isNotEmpty) {
          return "Product name already exists";
        }
      }

      final payload = <String, dynamic>{
        "name": normalizedName,
        "category": _selectedCategoryId,
        "dealer": dealerId,
        "isVeg": isVeg,
        "images": [
          {"image": imageId},
        ],
        "defaultPriceDetails": {
          "price": price,
          "rate": rate,
          "quantity": 1,
          "unit": unit.trim(),
          "gst": gst,
        },
      };

      http.Response? res;
      String bodyText = "";
      const maxAttempts = 2;

      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        res = await http.post(
          Uri.parse("${ApiConfig.baseUrl}/products"),
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
            bodyText.contains("E11000") || lower.contains("duplicate key");
        if (attempt < maxAttempts - 1 &&
            res.statusCode == 500 &&
            isDuplicateKey) {
          await Future.delayed(const Duration(milliseconds: 250));
          continue;
        }

        break;
      }

      if (res == null) {
        return "Failed to create product";
      }

      if (res.statusCode == 200 || res.statusCode == 201) {
        final body = jsonDecode(bodyText);
        dynamic created = body["doc"] ?? body;

        if (created is Map) {
          _products.insert(0, created);
          _filteredProducts = List<dynamic>.from(_products);
          _storeProductMetadata(created);
          notifyListeners();
        } else {
          await _loadProducts();
        }
        return null;
      }

      String message = "Failed to create product (${res.statusCode})";
      try {
        final body = jsonDecode(bodyText);
        final errors = body["errors"];
        if (errors is List && errors.isNotEmpty) {
          final firstError = errors.first;
          if (firstError is Map && firstError["message"] != null) {
            message = firstError["message"].toString();
          }
        } else if (body["message"] != null) {
          message = body["message"].toString();
        }
      } catch (_) {}

      if (message.startsWith("Failed to create product")) {
        final preview = bodyText.trim();
        if (preview.isNotEmpty) {
          final shortPreview = preview.length > 180
              ? "${preview.substring(0, 180)}..."
              : preview;
          message = "$message: $shortPreview";
        }
      }

      return message;
    } catch (e) {
      return "Error creating product: $e";
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

  Future<String?> uploadProductPhoto(File file, String altText) async {
    try {
      final uploadFile = await _prepareImageForUpload(file, 'product');
      if (!await uploadFile.exists()) return null;
      if (await uploadFile.length() == 0) return null;

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return null;

      final filename = 'product_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final urlsToTry = [
        '${ApiConfig.baseUrl}/media?prefix=product',
        '${ApiConfig.baseUrl}/media/?prefix=product',
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

  // ========== CART OPERATIONS ==========
  void updateInStock(String productId, double qty) {
    if (qty <= 0) {
      _inStockQuery.remove(productId);
    } else {
      _inStockQuery[productId] = qty;
    }
    notifyListeners();
  }

  void clearCart() {
    _inStockQuery.clear();
    notifyListeners();
  }

  // ========== SUBMIT INSTOCK ==========
  Future<void> submitInstock(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    if (_isSubmitting) return;
    if (_inStockQuery.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text("No items updated")));
      return;
    }

    _isSubmitting = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");
      if (token == null) return;
      final cashierId = prefs.getString('user_id') ?? prefs.getString('employee_id');
      final cashierName = prefs.getString('employee_name') ?? prefs.getString('user_name') ?? prefs.getString('username');

      final List<Map<String, dynamic>> items = [];
      _inStockQuery.forEach((pid, qty) {
        items.add({
          "product": pid,
          "inStock": qty,
          "requiredQty": 0, // Explicitly 0 for instock entry
        });
      });

      // Instock is always "Live" sort of, so we use current time
      final now = DateTime.now();

      final payload = jsonEncode({
        "branch": _branchId,
        "cashierId": cashierId,
        "cashierName": cashierName,
        "date": now.toUtc().toIso8601String(),
        "items": items
            .map(
              (item) => {
                "product": item['product'],
                "instock":
                    item['inStock'], // Changed from 'quantity' to 'instock'
              },
            )
            .toList(),
      });

      final res = await http.post(
        Uri.parse("${ApiConfig.baseUrl}/instock-entries"),
        headers: ApiConfig.getHeaders(token),
        body: payload,
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        messenger.showSnackBar(
          const SnackBar(content: Text("Instock Updated Successfully!")),
        );
        clearCart();
        // Optional: Go back to categories
        _step = "categories";
        _products.clear();
        _filteredProducts.clear();
        _selectedCategoryId = null;
        await _loadCategories();
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text("Failed: ${res.statusCode}")),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
