import 'dart:convert';
import 'package:branch/api_config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class CartItem {
  final String id;
  final String name;
  final double price;
  final String? imageUrl;
  double quantity; // ✅ changed from int → double
  final String? unit; // ✅ optional, e.g. "pcs" or "kg"

  CartItem({
    required this.id,
    required this.name,
    required this.price,
    this.imageUrl,
    required this.quantity,
    this.unit,
  });

  factory CartItem.fromProduct(dynamic product, double quantity, {double? branchPrice}) {
    String? imageUrl;
    if (product['images'] != null && product['images'].isNotEmpty && product['images'][0]['image'] != null && product['images'][0]['image']['url'] != null) {
      imageUrl = product['images'][0]['image']['url'];
      if (imageUrl != null && imageUrl.startsWith('/')) {
        imageUrl = '${ApiConfig.domain}$imageUrl';
      }
    }

    double price = branchPrice ?? (product['defaultPriceDetails']?['price']?.toDouble() ?? 0.0);

    // ✅ read unit from product (default to 'pcs' if missing)
    String? unit = product['unit']?.toString().toLowerCase() ?? 'pcs';

    return CartItem(
      id: product['id'],
      name: product['name'] ?? 'Unknown',
      price: price,
      imageUrl: imageUrl,
      quantity: quantity,
      unit: unit,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'imageUrl': imageUrl,
      'quantity': quantity,
      'unit': unit,
    };
  }

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id'],
      name: json['name'],
      price: json['price'],
      imageUrl: json['imageUrl'],
      quantity: json['quantity'],
      unit: json['unit'],
    );
  }
}

class CartProvider extends ChangeNotifier {
  List<CartItem> _cartItems = [];
  String? _branchId;
  String? _printerIp;
  int _printerPort = 9100;
  String? _printerProtocol = 'esc_pos';

  List<CartItem> get cartItems => _cartItems;
  double get total => _cartItems.fold(0.0, (sum, item) => sum + (item.price * item.quantity));
  String? get printerIp => _printerIp;
  int get printerPort => _printerPort;
  String? get printerProtocol => _printerProtocol;

  CartProvider() {
    _loadCart();
  }

  void addOrUpdateItem(CartItem item) {
    final index = _cartItems.indexWhere((i) => i.id == item.id);
    if (index != -1) {
      // ✅ works for both kg and pcs
      _cartItems[index].quantity += item.quantity;
    } else {
      _cartItems.add(item);
    }
    notifyListeners();
    _saveCart();
  }

  void updateQuantity(String id, double newQuantity) { // ✅ double now
    final index = _cartItems.indexWhere((i) => i.id == id);
    if (index != -1 && newQuantity > 0) {
      _cartItems[index].quantity = newQuantity;
      notifyListeners();
      _saveCart();
    } else if (newQuantity <= 0) {
      removeItem(id);
    }
  }

  void removeItem(String id) {
    _cartItems.removeWhere((i) => i.id == id);
    notifyListeners();
    _saveCart();
  }

  void clearCart() {
    _cartItems.clear();
    notifyListeners();
    _saveCart();
  }

  void setBranchId(String? branchId) {
    _branchId = branchId;
  }

  void setPrinterDetails(String? printerIp, int? printerPort, String? printerProtocol) {
    _printerIp = printerIp;
    if (printerPort != null) _printerPort = printerPort;
    if (printerProtocol != null && printerProtocol.isNotEmpty) {
      _printerProtocol = printerProtocol;
    }
    notifyListeners();
  }

  Future<void> _saveCart() async {
    final prefs = await SharedPreferences.getInstance();
    final cartJson = _cartItems.map((item) => item.toJson()).toList();
    await prefs.setString('cart', jsonEncode(cartJson));
  }

  Future<void> _loadCart() async {
    final prefs = await SharedPreferences.getInstance();
    final cartString = prefs.getString('cart');
    if (cartString != null) {
      final List<dynamic> cartJson = jsonDecode(cartString);
      _cartItems = cartJson.map((json) => CartItem.fromJson(json)).toList();
      notifyListeners();
    }
  }

  /// 🧾 Submits billing and returns the generated invoice number
  Future<String?> submitBilling(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) throw Exception('No token found. Please login again.');

      final items = _cartItems.map((item) => {
        'product': item.id,
        'quantity': item.quantity, // ✅ supports decimals now
        'price': item.price,
        'unit': item.unit, // ✅ optional but helps in backend clarity
      }).toList();

      final body = jsonEncode({
        'branch': _branchId,
        'items': items,
        'totalAmount': total,
      });

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/billings'),
        headers: ApiConfig.getHeaders(token),
        body: body,
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final invoiceNumber = data['invoiceNumber'] ?? 'N/A';
        clearCart();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Billing Successful — Invoice: $invoiceNumber')),
        );
        return invoiceNumber;
      } else {
        throw Exception('Failed to submit billing: ${response.body}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting billing: $e')),
      );
      return null;
    }
  }
  // Clear all data on logout
  void clearData() {
    _cartItems.clear();
    _branchId = null;
    _printerIp = null;
    _printerPort = 9100;
    _printerProtocol = 'esc_pos';
    notifyListeners();
    _saveCart(); // Optional: do we want to clear persisted cart on logout? Usually yes for security/privacy.
  }
}