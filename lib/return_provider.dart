import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http_parser/http_parser.dart';

class ReturnItem {
  final String id;
  final String name;
  final double price;
  final double quantity;  // Changed to double
  final double subtotal;

  ReturnItem({
    required this.id,
    required this.name,
    required this.price,
    required this.quantity,
  }) : subtotal = price * quantity;
}

class ReturnProvider extends ChangeNotifier {
  List<ReturnItem> _items = [];
  String? _branchId;
  Map<String, String> _productPhotos = {}; // productId: mediaId
  Map<String, File?> _tempPhotos = {}; // Temp file
  Map<String, String> _photoUrls = {}; // URL cache

  List<ReturnItem> get returnItems => List.unmodifiable(_items);
  double get total => _items.fold(0.0, (sum, item) => sum + item.subtotal);

  void addOrUpdateItem(String id, String name, double quantity, double price) {  // Changed quantity to double
    if (quantity <= 0) {
      removeItem(id);
      return;
    }
    final index = _items.indexWhere((item) => item.id == id);
    if (index != -1) {
      _items[index] = ReturnItem(
        id: id,
        name: name,
        price: price,
        quantity: quantity,
      );
    } else {
      _items.add(ReturnItem(id: id, name: name, price: price, quantity: quantity));
    }
    notifyListeners();
  }

  void updateQuantity(String id, double newQuantity) {  // New method
    final index = _items.indexWhere((i) => i.id == id);
    if (index != -1 && newQuantity > 0) {
      _items[index] = ReturnItem(
        id: id,
        name: _items[index].name,
        price: _items[index].price,
        quantity: newQuantity,
      );
      notifyListeners();
    } else if (newQuantity <= 0) {
      removeItem(id);
    }
  }

  void removeItem(String id) {
    _items.removeWhere((item) => item.id == id);
    removePhoto(id);
    notifyListeners();
  }

  void clearReturns() {
    _items.clear();
    clearPhotos();
    notifyListeners();
  }

  void setBranchId(String? branchId) {
    _branchId = branchId;
  }

  bool hasPhoto(String productId) {
    return _productPhotos.containsKey(productId) || _tempPhotos.containsKey(productId);
  }

  String? getPhotoId(String productId) {
    return _productPhotos[productId];
  }

  String? getPhotoUrl(String productId) {
    return _photoUrls[productId];
  }

  File? getTempPhoto(String productId) {
    return _tempPhotos[productId];
  }

  void setPhoto(String productId, String mediaId, File tempFile, String? url) {
    _productPhotos[productId] = mediaId;
    _tempPhotos[productId] = tempFile;
    if (url != null) _photoUrls[productId] = url;
    notifyListeners();
  }

  Future<void> removePhoto(String productId) async {
    _productPhotos.remove(productId);
    _photoUrls.remove(productId);
    final file = _tempPhotos.remove(productId);
    if (file != null && await file.exists()) {
      await file.delete();
    }
    final prefs = await SharedPreferences.getInstance();
    prefs.remove('pending_photo_$productId');
    notifyListeners();
  }

  Future<void> clearPhotos() async {
    for (var file in _tempPhotos.values) {
      if (file != null && await file.exists()) await file.delete();
    }
    _productPhotos.clear();
    _tempPhotos.clear();
    _photoUrls.clear();
    final prefs = await SharedPreferences.getInstance();
    for (var key in prefs.getKeys()) {
      if (key.startsWith('pending_photo_')) prefs.remove(key);
    }
    notifyListeners();
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

  Future<void> loadPendingPhotos([List<dynamic>? products]) async {
    final prefs = await SharedPreferences.getInstance();
    for (var key in prefs.getKeys()) {
      if (key.startsWith('pending_photo_')) {
        final productId = key.replaceFirst('pending_photo_', '');
        final path = prefs.getString(key);
        if (path != null) {
          final file = File(path);
          if (await file.exists()) {
            String altText = 'Proof for product $productId';
            if (products != null) {
              final product = products.firstWhere((p) => p['id'] == productId, orElse: () => null);
              if (product != null) {
                altText = product['name'] ?? altText;
              }
            }
            final mediaId = await _uploadPhoto(file, altText);
            if (mediaId != null) {
              final url = await _fetchMediaUrl(mediaId);
              setPhoto(productId, mediaId, file, url);
              prefs.remove(key);
            } else {
              // Still set for local preview if upload fails
              setPhoto(productId, '', file, null);
            }
          }
        }
      }
    }
  }

  Future<void> submitReturn(BuildContext context, String? branchId) async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items selected for return')),
      );
      return;
    }
    // Validate photos for ALL items (like working code)
    for (var item in _items) {
      if (!hasPhoto(item.id)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo proof required for all items')),
        );
        return;
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No token found. Please login again.')),
        );
        return;
      }
      final returnData = {
        'items': _items
            .map((item) => {
          'product': item.id,
          'name': item.name,
          'quantity': item.quantity,  // double is fine
          'unitPrice': item.price,
          'subtotal': item.subtotal,
          'proofPhoto': getPhotoId(item.id) ?? '',
        })
            .toList(),
        'totalAmount': total,
        'branch': branchId,
        'status': 'returned',
        'notes': '',
      };
      final response = await http.post(
        Uri.parse('https://admin.theblackforestcakes.com/api/return-orders'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(returnData),
      );
      if (response.statusCode == 201) {
        clearReturns();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Return order submitted successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit return order: ${response.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network error: Check your internet')),
      );
    }
  }
}