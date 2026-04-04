import 'dart:convert';
import 'package:branch/api_config.dart';
import 'package:branch/common_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StockStatusPage extends StatefulWidget {
  const StockStatusPage({super.key});

  @override
  State<StockStatusPage> createState() => _StockStatusPageState();
}

class _StockStatusPageState extends State<StockStatusPage> {
  bool _isLoading = true;
  String _errorMessage = '';

  List<dynamic> _categories = [];
  List<dynamic> _products = [];
  List<dynamic> _filteredProducts = [];

  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _updatingProductIds = {};

  String? _token;
  String? _branchId;
  String? _companyId;
  String? _userRole;
  String? _selectedCategoryId;
  String? _selectedCategoryName;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_filterProducts);
    _loadCategories();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('token');

      if (_token == null) {
        setState(() {
          _errorMessage = 'No token found. Please login again.';
          _isLoading = false;
        });
        return;
      }

      if (_userRole == null) {
        await _fetchUserData(_token!);
      }

      await _ensureBranchContext(_token!);

      String query = 'where[isStock][equals]=true';

      if (_userRole != 'superadmin') {
        if (_userRole == 'waiter') {
          final ip = await _deviceIp();
          final matches = await _matchingCompanies(_token!, ip);
          if (matches.isNotEmpty) {
            query += '&where[company][in]=${matches.join(",")}';
          }
        } else if (_companyId != null) {
          query += '&where[company][contains]=$_companyId';
        }
      }

      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/categories?$query&limit=200&depth=1'),
        headers: ApiConfig.getHeaders(_token),
      );

      if (res.statusCode != 200) {
        setState(() {
          _errorMessage = 'Failed to load categories (${res.statusCode})';
          _isLoading = false;
        });
        return;
      }

      final docs = jsonDecode(res.body)['docs'] ?? [];
      docs.sort((a, b) {
        final aName = (a['name'] ?? '').toString().toLowerCase();
        final bName = (b['name'] ?? '').toString().toLowerCase();
        return aName.compareTo(bName);
      });

      if (!mounted) return;
      setState(() {
        _categories = docs;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Network error. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchUserData(String token) async {
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/users/me?depth=2'),
        headers: ApiConfig.getHeaders(token),
      );

      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body);
      final user = data['user'] ?? data;
      _userRole = user['role'];

      if (_userRole == 'company') {
        _companyId =
            user['company'] is Map ? user['company']['id'] : user['company'];
      } else if (_userRole == 'branch') {
        final branch = user['branch'];
        if (branch != null) {
          _branchId = branch is Map ? branch['id'] : branch?.toString();
          final branchCompany = branch is Map ? branch['company'] : null;
          if (branchCompany != null) {
            _companyId =
                branchCompany is Map ? branchCompany['id'] : branchCompany;
          }
        }
      }
    } catch (_) {}
  }

  Future<String?> _deviceIp() async {
    try {
      final info = NetworkInfo();
      return await info.getWifiIP();
    } catch (_) {
      return null;
    }
  }

  int _ipToInt(String ip) {
    final p = ip.split('.').map(int.parse).toList();
    return (p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3];
  }

  bool _ipInRange(String deviceIp, String range) {
    final split = range.split('-');
    if (split.length != 2) return false;
    return _ipToInt(deviceIp) >= _ipToInt(split[0].trim()) &&
        _ipToInt(deviceIp) <= _ipToInt(split[1].trim());
  }

  Future<List<String>> _matchingCompanies(
    String token,
    String? deviceIp,
  ) async {
    if (deviceIp == null) return [];

    final ids = <String>[];
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/branches?depth=1'),
        headers: ApiConfig.getHeaders(token),
      );

      if (res.statusCode != 200) return [];

      final docs = jsonDecode(res.body)['docs'] ?? [];
      for (final b in docs) {
        final raw = b['ipAddress']?.toString();
        if (raw == null || raw.isEmpty) continue;

        final matches =
            raw.contains('-')
                ? _ipInRange(deviceIp, raw)
                : raw.trim() == deviceIp;

        if (!matches) continue;

        final company = b['company'];
        final id = company is Map ? company['id'] : company?.toString();
        if (id != null && id.isNotEmpty) {
          ids.add(id);
        }
      }
    } catch (_) {}

    return ids;
  }

  Future<void> _ensureBranchContext(String token) async {
    if ((_branchId?.isNotEmpty ?? false) && (_companyId?.isNotEmpty ?? false)) {
      return;
    }

    final deviceIp = await _deviceIp();
    if (deviceIp == null || deviceIp.isEmpty) return;

    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/branches?depth=1'),
        headers: ApiConfig.getHeaders(token),
      );

      if (res.statusCode != 200) return;

      final docs = jsonDecode(res.body)['docs'] ?? [];
      for (final branch in docs) {
        final raw = branch['ipAddress']?.toString();
        if (raw == null || raw.isEmpty) continue;

        final matches =
            raw.contains('-')
                ? _ipInRange(deviceIp, raw)
                : raw.trim() == deviceIp;
        if (!matches) continue;

        _branchId ??= branch['id']?.toString();
        final company = branch['company'];
        _companyId ??=
            company is Map ? company['id']?.toString() : company?.toString();
        break;
      }
    } catch (_) {}
  }

  Future<void> _selectCategory(dynamic category) async {
    final id = category['id']?.toString();
    if (id == null || id.isEmpty) return;

    setState(() {
      _selectedCategoryId = id;
      _selectedCategoryName = category['name']?.toString() ?? 'Products';
      _isLoading = true;
      _errorMessage = '';
      _searchCtrl.clear();
      _products = [];
      _filteredProducts = [];
    });

    try {
      final res = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/products?where[category][equals]=$id&limit=500&depth=1',
        ),
        headers: ApiConfig.getHeaders(_token),
      );

      if (res.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Failed to load products (${res.statusCode})';
          _isLoading = false;
        });
        return;
      }

      final docs = jsonDecode(res.body)['docs'] ?? [];
      docs.sort((a, b) => _compareProducts(a, b));

      if (!mounted) return;
      setState(() {
        _products = docs;
        _filteredProducts = List<dynamic>.from(docs);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Network error while loading products.';
        _isLoading = false;
      });
    }
  }

  void _filterProducts() {
    final query = _searchCtrl.text.trim().toLowerCase();
    final list =
        _products.where((raw) {
          if (query.isEmpty) return true;
          final name = (raw['name'] ?? '').toString().toLowerCase();
          final desc = (raw['description'] ?? '').toString().toLowerCase();
          return name.contains(query) || desc.contains(query);
        }).toList();

    list.sort((a, b) => _compareProducts(a, b));

    if (!mounted) return;
    setState(() {
      _filteredProducts = list;
    });
  }

  int _compareProducts(dynamic a, dynamic b) {
    final aOut = _isOutOfStock(a);
    final bOut = _isOutOfStock(b);
    if (aOut != bOut) return aOut ? -1 : 1;

    final aName = (a['name'] ?? '').toString().toLowerCase();
    final bName = (b['name'] ?? '').toString().toLowerCase();
    return aName.compareTo(bName);
  }

  String _productId(dynamic product) =>
      (product['id'] ?? product['_id'])?.toString().trim() ?? '';

  String _extractBranchId(dynamic branch) {
    if (branch is Map) {
      return (branch['id'] ?? branch[r'$oid'] ?? '').toString().trim();
    }
    return branch?.toString().trim() ?? '';
  }

  List<String> _extractBranchIds(dynamic value) {
    if (value is! List) return <String>[];

    final ids = <String>[];
    for (final entry in value) {
      final id = _extractBranchId(entry);
      if (id.isNotEmpty && !ids.contains(id)) {
        ids.add(id);
      }
    }
    return ids;
  }

  bool _isOutOfStock(dynamic product) {
    if (_branchId != null && _branchId!.isNotEmpty) {
      final outOfStockBranches = _extractBranchIds(
        product['outOfStockBranches'],
      );
      if (outOfStockBranches.contains(_branchId)) {
        return true;
      }
    }

    final isStock = product['isStock'];
    if (isStock is bool) return !isStock;
    final isOut = product['isOutOfStock'];
    if (isOut is bool) return isOut;
    return false;
  }

  List<String> _buildOutOfStockBranchesPayload(
    dynamic product, {
    required bool isInStock,
  }) {
    final ids = _extractBranchIds(product['outOfStockBranches']);
    if (_branchId == null || _branchId!.isEmpty) {
      return ids;
    }

    if (isInStock) {
      ids.removeWhere((id) => id == _branchId);
    } else if (!ids.contains(_branchId)) {
      ids.add(_branchId!);
    }

    return ids;
  }

  void _setLocalOutOfStockBranches(
    String productId,
    dynamic outOfStockBranches,
  ) {
    void patchInList(List<dynamic> list) {
      for (final item in list) {
        if (_productId(item) == productId) {
          item['outOfStockBranches'] = jsonDecode(
            jsonEncode(outOfStockBranches),
          );
        }
      }
    }

    patchInList(_products);
    patchInList(_filteredProducts);
  }

  void _setLocalStockValue(String productId, bool isInStock) {
    void patchInList(List<dynamic> list) {
      for (final item in list) {
        if (_productId(item) == productId) {
          item['outOfStockBranches'] = _buildOutOfStockBranchesPayload(
            item,
            isInStock: isInStock,
          );
        }
      }
    }

    patchInList(_products);
    patchInList(_filteredProducts);
  }

  Future<void> _toggleStock(dynamic product, bool isInStock) async {
    final productId = _productId(product);
    if (productId.isEmpty || _updatingProductIds.contains(productId)) return;
    if (_branchId == null || _branchId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to detect this branch for stock update.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final previousOutOfStockBranches = jsonDecode(
      jsonEncode(product['outOfStockBranches'] ?? []),
    );

    setState(() {
      _updatingProductIds.add(productId);
      _setLocalStockValue(productId, isInStock);
      _filteredProducts.sort((a, b) => _compareProducts(a, b));
    });

    try {
      final res = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/products/$productId'),
        headers: ApiConfig.getHeaders(_token),
        body: jsonEncode({
          'outOfStockBranches': _buildOutOfStockBranchesPayload(
            product,
            isInStock: isInStock,
          ),
        }),
      );

      if (res.statusCode != 200 && res.statusCode != 202) {
        throw Exception('Failed (${res.statusCode})');
      }

      final verify = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/products/$productId?depth=0'),
        headers: ApiConfig.getHeaders(_token),
      );

      if (verify.statusCode == 200) {
        final saved = jsonDecode(verify.body);

        if (!mounted) return;
        setState(() {
          _setLocalOutOfStockBranches(
            productId,
            saved['outOfStockBranches'] ?? [],
          );
          _filteredProducts.sort((a, b) => _compareProducts(a, b));
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _setLocalOutOfStockBranches(productId, previousOutOfStockBranches);
        _filteredProducts.sort((a, b) => _compareProducts(a, b));
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Stock update failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingProductIds.remove(productId);
        });
      } else {
        _updatingProductIds.remove(productId);
      }
    }
  }

  void _goBackToCategories() {
    setState(() {
      _selectedCategoryId = null;
      _selectedCategoryName = null;
      _searchCtrl.clear();
      _products = [];
      _filteredProducts = [];
      _errorMessage = '';
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title =
        _selectedCategoryId == null
            ? 'Stock Categories'
            : (_selectedCategoryName ?? 'Products');

    return PopScope(
      canPop: _selectedCategoryId == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedCategoryId != null) {
          _goBackToCategories();
        }
      },
      child: CommonScaffold(
        title: title,
        pageType: PageType.stockstatus,
        body: RefreshIndicator(
          onRefresh:
              _selectedCategoryId == null
                  ? _loadCategories
                  : () async {
                    final selected = _categories.firstWhere(
                      (c) => c['id']?.toString() == _selectedCategoryId,
                      orElse:
                          () => {
                            'id': _selectedCategoryId,
                            'name': _selectedCategoryName,
                          },
                    );
                    await _selectCategory(selected);
                  },
          child:
              _selectedCategoryId == null
                  ? _buildCategoriesBody()
                  : _buildProductsBody(),
        ),
      ),
    );
  }

  Widget _buildCategoriesBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.black),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          Center(child: Text(_errorMessage)),
        ],
      );
    }

    if (_categories.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          const Center(
            child: Text(
              'No stock categories found',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    }

    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: _categories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemBuilder: (_, index) {
        final c = _categories[index];
        String? img = c['image']?['url']?.toString();
        if (img != null && img.startsWith('/')) {
          img = '${ApiConfig.domain}$img';
        }

        return GestureDetector(
          onTap: () => _selectCategory(c),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                    child:
                        img == null
                            ? Container(
                              color: Colors.grey[200],
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.inventory_2_rounded,
                                color: Colors.grey,
                              ),
                            )
                            : Image.network(
                              img,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder:
                                  (_, __, ___) => Container(
                                    color: Colors.grey[200],
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.inventory_2_rounded,
                                      color: Colors.grey,
                                    ),
                                  ),
                            ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  child: Text(
                    (c['name'] ?? 'CATEGORY').toString().toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProductsBody() {
    if (_isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 180),
          Center(child: CircularProgressIndicator(color: Colors.black)),
        ],
      );
    }

    if (_errorMessage.isNotEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          Center(child: Text(_errorMessage)),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Search products...',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (_filteredProducts.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(
              child: Text(
                'No products found.',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
        else
          ..._filteredProducts.map((product) {
            final id = _productId(product);
            final name = (product['name'] ?? 'N/A').toString().toUpperCase();
            final description = (product['description'] ?? '').toString();
            final isOut = _isOutOfStock(product);
            final isUpdating = _updatingProductIds.contains(id);

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              height: 1.2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (isUpdating)
                    const SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    _buildStockSwitch(
                      isOn: !isOut,
                      onChanged: (val) => _toggleStock(product, val),
                    ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildStockSwitch({
    required bool isOn,
    required ValueChanged<bool> onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!isOn),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 85,
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isOn ? const Color(0xFF1A237E) : const Color(0xFFFFA726),
          boxShadow: [
            BoxShadow(
              color: (isOn ? const Color(0xFF1A237E) : const Color(0xFFFFA726))
                  .withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Align(
              alignment: isOn ? Alignment.centerLeft : Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  isOn ? 'IN' : 'OUT',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            AnimatedAlign(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: isOn ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
