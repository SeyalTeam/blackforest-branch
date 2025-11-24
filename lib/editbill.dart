import 'package:flutter/material.dart';
import 'package:branch/common_scaffold.dart';

class EditBillPage extends StatelessWidget {
  const EditBillPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: 'Edit Bill',
      body: const Center(
        child: Text('Edit Bill screen coming soon'),
      ),
      pageType: PageType.editbill,
    );
  }
}