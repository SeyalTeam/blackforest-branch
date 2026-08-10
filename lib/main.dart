import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:branch/cart_provider.dart';
import 'package:branch/return_provider.dart';
import 'package:branch/instock_provider.dart';
import 'package:branch/stock_provider.dart';
import 'package:branch/auth_service.dart';
import 'package:branch/auth_session_manager.dart';
import 'package:branch/login_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AuthSessionManager.instance.attachNavigatorKey(AuthService.navigatorKey);
  AuthSessionManager.instance.startHeartbeat();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => CartProvider()),
        ChangeNotifierProvider(create: (context) => ReturnProvider()),
        ChangeNotifierProvider(create: (context) => StockProvider()),
        ChangeNotifierProvider(create: (context) => InstockProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AuthService.navigatorKey, // ADDED
      title: 'Black Forest App',
      theme: ThemeData(
        primarySwatch: Colors.grey,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      ),
      home: const LoginPage(),
      routes: {
        '/login': (context) => const LoginPage(),
      },
    );
  }
}