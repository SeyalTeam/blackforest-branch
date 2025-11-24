// lib/billsheet.dart
import 'package:flutter/material.dart';
import 'common_scaffold.dart';

class BillSheetPage extends StatefulWidget {
  const BillSheetPage({super.key});

  @override
  State<BillSheetPage> createState() => _BillSheetPageState();
}

class _BillSheetPageState extends State<BillSheetPage> {
  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: 'Bill Sheet',
      pageType: PageType.home, // You can add a new PageType later if needed
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.table_chart, size: 100, color: Colors.grey),
            SizedBox(height: 20),
            Text(
              'Bill Sheet Feature\nComing Soon!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}