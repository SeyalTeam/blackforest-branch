import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:branch/cart_provider.dart';
import 'package:branch/return_provider.dart'; // Add this import
import 'package:branch/login_page.dart'; // Replace with your project name if different

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => CartProvider()),
        ChangeNotifierProvider(create: (context) => ReturnProvider()),
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
      title: 'Black Forest App',
      theme: ThemeData(
        primarySwatch: Colors.grey,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5), // Light grey background
      ),
      home: const LoginPage(),
      routes: {
        '/login': (context) => const LoginPage(),
      },
    );
  }
}