import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:branch/api_config.dart';
import 'package:branch/common_scaffold.dart';
import 'package:branch/kitchen_chef_page.dart';

class KitchensGridPage extends StatefulWidget {
  const KitchensGridPage({super.key});

  @override
  State<KitchensGridPage> createState() => _KitchensGridPageState();
}

class _KitchensGridPageState extends State<KitchensGridPage> {
  List<dynamic> _kitchens = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchKitchens();
  }

  String _extractId(dynamic obj) {
    if (obj == null) return '';
    if (obj is String) return obj;
    if (obj is Map) {
      return (obj['id'] ?? obj['_id'] ?? obj['value'] ?? '').toString();
    }
    return '';
  }

  String _extractName(dynamic obj) {
    if (obj == null) return 'Unknown';
    if (obj is String) return obj;
    if (obj is Map) {
      return (obj['name'] ?? obj['title'] ?? 'Unknown').toString();
    }
    return 'Unknown';
  }

  Future<void> _fetchKitchens() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) {
        setState(() {
          _errorMessage = 'No token found. Please login.';
          _isLoading = false;
        });
        return;
      }

      // Fetch user to get branch ID
      final userRes = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/users/me?depth=2'),
        headers: ApiConfig.getHeaders(token),
      );

      if (userRes.statusCode != 200) {
        throw Exception('Failed to get user data');
      }

      final userData = jsonDecode(userRes.body);
      final userDoc = userData['user'] ?? userData;

      String? branchId;
      if (userDoc['role'] == 'branch') {
        branchId = _extractId(userDoc['branch']);
      }

      final branchFilter = (branchId != null && branchId.isNotEmpty)
          ? '&where[branches][in][0]=$branchId'
          : '';

      final res = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/kitchens?depth=1&limit=100$branchFilter',
        ),
        headers: ApiConfig.getHeaders(token),
      );

      if (res.statusCode == 200) {
        _kitchens = jsonDecode(res.body)['docs'] ?? [];
      } else {
        throw Exception('Failed to fetch kitchens');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onKitchenTap(dynamic kitchen) {
    // For now, navigate to the Chef Assignments page.
    // We can pass the selected kitchen if needed in the future.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => KitchenChefPage(
          kitchenId: _extractId(kitchen),
          kitchenName: _extractName(kitchen),
        ),
      ),
    );
  }

  Widget _buildKitchenCard(dynamic kitchen) {
    final name = _extractName(kitchen);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _onKitchenTap(kitchen),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Color(0xFF8D6E63), Color(0xFFBCAAA4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.soup_kitchen, size: 48, color: Colors.white),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: 'Kitchens',
      pageType: PageType.home,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _fetchKitchens,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _kitchens.isEmpty
          ? const Center(child: Text('No kitchens found for this branch.'))
          : RefreshIndicator(
              onRefresh: _fetchKitchens,
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.0,
                ),
                itemCount: _kitchens.length,
                itemBuilder: (context, index) {
                  return _buildKitchenCard(_kitchens[index]);
                },
              ),
            ),
    );
  }
}
