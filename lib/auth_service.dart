import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:branch/stock_provider.dart';
import 'package:branch/cart_provider.dart';
import 'package:branch/return_provider.dart';

class AuthService {
  // Global navigator key to allow navigation without context
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // Centralized logout function
  static Future<void> logout() async {
    final context = navigatorKey.currentContext;
    
    // Clear Providers if context is available
    if (context != null) {
      try {
        Provider.of<StockProvider>(context, listen: false).clearData();
        Provider.of<CartProvider>(context, listen: false).clearData();
        Provider.of<ReturnProvider>(context, listen: false).clearData();
      } catch (e) {
        // Ignore provider errors during logout (e.g. if providers aren't found)
        print("Error clearing providers: $e");
      }
    }

    // Clear SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    // Navigate to Login Page
    navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (route) => false);
  }
}
