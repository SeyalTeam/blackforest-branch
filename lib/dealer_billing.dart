import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:branch/common_scaffold.dart';
import 'package:branch/api_config.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img_lib;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http_parser/http_parser.dart';
import 'package:branch/camera_page.dart';

class _PhotoSlot {
  final String label;
  final String prefix;
  File? file;
  String? mediaId;
  String? url;

  _PhotoSlot({required this.label, required this.prefix});
}

class DealerBillingPage extends StatefulWidget {
  const DealerBillingPage({super.key});

  @override
  State<DealerBillingPage> createState() => _DealerBillingPageState();
}

class _DealerBillingPageState extends State<DealerBillingPage> {
  final _formKey = GlobalKey<FormState>();
  
  List<Map<String, dynamic>> _dealers = [];
  String? _selectedDealerId;
  bool _isLoadingDealers = false;
  bool _isSubmitting = false;

  final List<TextEditingController> _billControllers = [];
  final List<TextEditingController> _invoiceNumberControllers = [];

  List<Map<String, dynamic>> _products = [];
  Map<String, Map<String, double>> _selectedProductQuantities = {};
  bool _isLoadingProducts = false;

  late final _PhotoSlot _billCopySlot;
  late final _PhotoSlot _deliveryPersonSlot;
  final List<File> _productPhotos = [];

  @override
  void initState() {
    super.initState();
    _billCopySlot = _PhotoSlot(label: 'Dealer Bill Copy', prefix: 'dealerbill');
    _deliveryPersonSlot = _PhotoSlot(label: 'Delivery Person Photo', prefix: 'deliveryperson');
    _addBillField(); // Start with one field
    _fetchDealers();
  }

  @override
  void dispose() {
    for (var controller in _billControllers) {
      controller.dispose();
    }
    for (var controller in _invoiceNumberControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addBillField() {
    setState(() {
      final controller = TextEditingController();
      controller.addListener(() {
        setState(() {}); // Recalculate total dynamically
      });
      _billControllers.add(controller);
      _invoiceNumberControllers.add(TextEditingController());
    });
  }

  void _removeBillField(int index) {
    if (_billControllers.length > 1 && _invoiceNumberControllers.length > index) {
      setState(() {
        _billControllers[index].dispose();
        _billControllers.removeAt(index);
        _invoiceNumberControllers[index].dispose();
        _invoiceNumberControllers.removeAt(index);
      });
    }
  }

  double _calculateTotal() {
    double total = 0.0;
    for (var controller in _billControllers) {
      total += double.tryParse(controller.text) ?? 0.0;
    }
    return total;
  }

  Future<void> _fetchDealers() async {
    setState(() => _isLoadingDealers = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) throw Exception('No token found');

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/dealers?limit=200&depth=0'),
        headers: ApiConfig.getHeaders(token),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        final List<dynamic> docs = body['docs'] ?? [];
        final List<Map<String, dynamic>> loadedDealers = [];
        for (var doc in docs) {
          final id = doc['id']?.toString() ?? '';
          final name = doc['companyName']?.toString() ??
              doc['name']?.toString() ??
              'Unknown Dealer';
          loadedDealers.add({'id': id, 'name': name});
        }
        // Sort alphabetically by name
        loadedDealers.sort((a, b) => a['name'].toString().toLowerCase().compareTo(b['name'].toString().toLowerCase()));
        setState(() {
          _dealers = loadedDealers;
        });
      } else {
        throw Exception('Failed to load dealers: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching dealers: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isLoadingDealers = false);
    }
  }

  Future<void> _fetchProducts(String dealerId) async {
    setState(() => _isLoadingProducts = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) throw Exception('No token found');

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/products?where[dealer][equals]=$dealerId&limit=500&depth=0'),
        headers: ApiConfig.getHeaders(token),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        final List<dynamic> docs = body['docs'] ?? [];
        final List<Map<String, dynamic>> loadedProducts = [];
        for (var doc in docs) {
          final id = doc['id']?.toString() ?? '';
          final name = doc['name']?.toString() ?? 'Unknown Product';
          loadedProducts.add({'id': id, 'name': name});
        }
        loadedProducts.sort((a, b) => a['name'].toString().toLowerCase().compareTo(b['name'].toString().toLowerCase()));
        setState(() {
          _products = loadedProducts;
        });
      } else {
        throw Exception('Failed to load products: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching products: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isLoadingProducts = false);
    }
  }

  Future<void> _capturePhoto(_PhotoSlot slot) async {
    if (await Permission.camera.request().isDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission required')),
        );
      }
      return;
    }
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No camera found')),
        );
      }
      return;
    }
    if (!mounted) return;
    final XFile? photo = await Navigator.push<XFile>(
      context,
      MaterialPageRoute(
        builder: (context) => CameraPage(cameras: cameras),
        fullscreenDialog: true,
      ),
    );
    if (photo == null) return;

    final bytes = await photo.readAsBytes();
    final image = img_lib.decodeImage(bytes);
    if (image == null) return;
    final compressed = img_lib.encodeJpg(image, quality: 70);

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempFile = File('${tempDir.path}/${slot.prefix}_$timestamp.jpg');
    await tempFile.writeAsBytes(compressed);

    setState(() {
      slot.file = tempFile;
      slot.mediaId = null;
      slot.url = null;
    });
  }

  void _removePhoto(_PhotoSlot slot) {
    setState(() {
      if (slot.file != null && slot.file!.existsSync()) {
        try {
          slot.file!.deleteSync();
        } catch (_) {}
      }
      slot.file = null;
      slot.mediaId = null;
      slot.url = null;
    });
  }

  Future<void> _captureProductPhoto() async {
    if (await Permission.camera.request().isDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission required')),
        );
      }
      return;
    }
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No camera found')),
        );
      }
      return;
    }
    if (!mounted) return;
    final XFile? photo = await Navigator.push<XFile>(
      context,
      MaterialPageRoute(
        builder: (context) => CameraPage(cameras: cameras),
        fullscreenDialog: true,
      ),
    );
    if (photo == null) return;

    final bytes = await photo.readAsBytes();
    final image = img_lib.decodeImage(bytes);
    if (image == null) return;
    final compressed = img_lib.encodeJpg(image, quality: 70);

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempFile = File('${tempDir.path}/dealerproducts_$timestamp.jpg');
    await tempFile.writeAsBytes(compressed);

    setState(() {
      _productPhotos.add(tempFile);
    });
  }

  Widget _buildProductPhotosWidget() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Products Photos (Take one or more)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_productPhotos.length} taken',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_productPhotos.isNotEmpty) ...[
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _productPhotos.length,
                  itemBuilder: (context, index) {
                    return Stack(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(right: 12),
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              _productPhotos[index],
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 4,
                          top: -4,
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.red.withOpacity(0.9),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.close, size: 14, color: Colors.white),
                              onPressed: () {
                                setState(() {
                                  try {
                                    _productPhotos[index].deleteSync();
                                  } catch (_) {}
                                  _productPhotos.removeAt(index);
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: _captureProductPhoto,
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Add Product Photo'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 45),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _uploadPhoto(File file, String altText, String prefix) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return null;

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/media?prefix=$prefix'),
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
        debugPrint('Upload error: ${response.statusCode} - $body');
      }
    } catch (e) {
      debugPrint('Upload exception: $e');
    }
    return null;
  }

  Future<void> _submitBilling() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDealerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a dealer'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_selectedProductQuantities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one product'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_billCopySlot.file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dealer Bill Copy photo is required'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_deliveryPersonSlot.file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery Person photo is required'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_productPhotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one Dealer Product photo is required'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final branchId = prefs.getString('branchId');
      if (token == null) throw Exception('No session token found. Please login again.');

      // 1. Upload Bill Copy Photo
      final billCopyAlt = 'Dealer Bill Copy for dealer $_selectedDealerId';
      final billCopyId = await _uploadPhoto(_billCopySlot.file!, billCopyAlt, 'dealerbill');
      if (billCopyId == null) throw Exception('Failed to upload Dealer Bill Copy photo.');

      // 2. Upload Delivery Person Photo
      final deliveryPersonAlt = 'Delivery Person for dealer $_selectedDealerId';
      final deliveryPersonId = await _uploadPhoto(_deliveryPersonSlot.file!, deliveryPersonAlt, 'deliveryperson');
      if (deliveryPersonId == null) throw Exception('Failed to upload Delivery Person photo.');

      // 3. Upload Multiple Product Photos
      final List<String> productsPhotoIds = [];
      for (var i = 0; i < _productPhotos.length; i++) {
        final productsAlt = 'Dealer Product Photo ${i + 1} for dealer $_selectedDealerId';
        final id = await _uploadPhoto(_productPhotos[i], productsAlt, 'dealerproducts');
        if (id == null) throw Exception('Failed to upload Dealer Product Photo ${i + 1}.');
        productsPhotoIds.add(id);
      }

      // 4. Compile Bills list
      final List<Map<String, dynamic>> billsData = [];
      for (var i = 0; i < _billControllers.length; i++) {
        final val = double.tryParse(_billControllers[i].text) ?? 0.0;
        final invNum = _invoiceNumberControllers[i].text.trim();
        billsData.add({
          'amount': val,
          'invoiceNumber': invNum,
        });
      }

      // 5. Compile productsList
      final List<Map<String, dynamic>> productsListData = [];
      _selectedProductQuantities.forEach((id, data) {
        productsListData.add({
          'product': id,
          'quantity': data['quantity'] ?? 0.0,
          'totalAmount': data['totalAmount'] ?? 0.0,
        });
      });

      // 6. Submit Dealer Billing Document
      final payload = {
        'dealer': _selectedDealerId,
        'branch': branchId,
        'bills': billsData,
        'total': _calculateTotal(),
        'billCopyPhoto': billCopyId,
        'deliveryPersonPhoto': deliveryPersonId,
        'productsPhoto': productsPhotoIds,
        'products': _selectedProductQuantities.keys.toList(),
        'productsList': productsListData,
        'date': DateTime.now().toUtc().toIso8601String(),
      };

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/dealer-billings'),
        headers: ApiConfig.getHeaders(token),
        body: jsonEncode(payload),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Dealer Billing submitted successfully!'), backgroundColor: Colors.green),
          );
          Navigator.pop(context);
        }
      } else {
        throw Exception('Server returned ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Submission failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  Widget _buildPhotoSlotWidget(_PhotoSlot slot) {
    final hasPhoto = slot.file != null;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              slot.label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: hasPhoto
                      ? Container(
                          height: 120,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              slot.file!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                            ),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: () => _capturePhoto(slot),
                          icon: const Icon(Icons.camera_alt),
                          label: Text('Take ${slot.label}'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                ),
                if (hasPhoto) ...[
                  const SizedBox(width: 12),
                  Column(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.blue),
                        onPressed: () => _capturePhoto(slot),
                        tooltip: 'Retake',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _removePhoto(slot),
                        tooltip: 'Remove',
                      ),
                    ],
                  )
                ]
              ],
            )
          ],
        ),
      ),
    );
  }

  Future<void> _navigateToProductSelection() async {
    final Map<String, Map<String, double>>? result = await Navigator.push<Map<String, Map<String, double>>>(
      context,
      MaterialPageRoute(
        builder: (context) => ProductSelectionPage(
          products: _products,
          initialData: _selectedProductQuantities,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _selectedProductQuantities = result;
      });
    }
  }

  Widget _buildProductSelector() {
    if (_selectedDealerId == null) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Products',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (_isLoadingProducts)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_products.isEmpty)
              const Text(
                'No products associated with this dealer.',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: _navigateToProductSelection,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _selectedProductQuantities.isEmpty
                                  ? 'Select products'
                                  : '${_selectedProductQuantities.length} products selected',
                              style: TextStyle(
                                color: _selectedProductQuantities.isEmpty ? Colors.grey : Colors.black87,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  if (_selectedProductQuantities.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 48,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _selectedProductQuantities.entries.map((entry) {
                            final id = entry.key;
                            final qty = entry.value['quantity'] ?? 0.0;
                            final amt = entry.value['totalAmount'] ?? 0.0;
                            final product = _products.firstWhere((p) => p['id'] == id, orElse: () => {'name': 'Unknown'});
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Chip(
                                label: Text('${product['name']} (Qty: $qty, ₹$amt)'),
                                onDeleted: () {
                                  setState(() {
                                    _selectedProductQuantities.remove(id);
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: 'Dealer Billing',
      pageType: PageType.dealerBilling,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dealer Dropdown card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Select Dealer',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _selectedDealerId,
                            hint: _isLoadingDealers
                                ? const Text('Loading dealers...', overflow: TextOverflow.ellipsis)
                                : const Text('Select a dealer', overflow: TextOverflow.ellipsis),
                            items: _dealers.map((dealer) {
                              return DropdownMenuItem<String>(
                                value: dealer['id'],
                                child: Text(
                                  dealer['name'],
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: _isLoadingDealers
                                ? null
                                : (val) {
                                    setState(() {
                                      _selectedDealerId = val;
                                      _selectedProductQuantities = {};
                                      _products = [];
                                    });
                                    if (val != null) {
                                      _fetchProducts(val);
                                    }
                                  },
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.business_outlined),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            validator: (val) => val == null ? 'Dealer selection is required' : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  _selectedDealerId == null ? const SizedBox.shrink() : const SizedBox(height: 16),
                  _buildProductSelector(),
                  const SizedBox(height: 16),

                  // Bill copy entries card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Bill Amount Entries',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              TextButton.icon(
                                onPressed: _addBillField,
                                icon: const Icon(Icons.add),
                                label: const Text('Add Bill'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _billControllers.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              return Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _billControllers[index],
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: InputDecoration(
                                        labelText: 'Bill #${index + 1} Amount',
                                        prefixText: '₹ ',
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      ),
                                      validator: (val) {
                                        if (val == null || val.isEmpty) return 'Required';
                                        final num = double.tryParse(val);
                                        if (num == null) return 'Invalid amount';
                                        if (num <= 0) return 'Must be > 0';
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _invoiceNumberControllers[index],
                                      decoration: InputDecoration(
                                        labelText: 'Invoice Number',
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      ),
                                      validator: (val) {
                                        if (val == null || val.trim().isEmpty) {
                                          return 'Required';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  if (_billControllers.length > 1) ...[
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      onPressed: () => _removeBillField(index),
                                      tooltip: 'Remove entry',
                                    )
                                  ]
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Photo slots
                  _buildPhotoSlotWidget(_billCopySlot),
                  const SizedBox(height: 16),
                  _buildPhotoSlotWidget(_deliveryPersonSlot),
                  const SizedBox(height: 16),
                  _buildProductPhotosWidget(),
                  const SizedBox(height: 24),

                  // Total amount and submit card
                  Card(
                    elevation: 4,
                    color: Colors.teal.shade50,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total Billing Amount:',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black54),
                              ),
                              Text(
                                '₹ ${_calculateTotal().toStringAsFixed(2)}',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.teal.shade900),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _submitBilling,
                              child: const Text(
                                'SUBMIT DEALER BILLING',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isSubmitting)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'Uploading files & submitting...',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ProductSelectionPage extends StatefulWidget {
  final List<dynamic> products;
  final Map<String, Map<String, double>> initialData;

  const ProductSelectionPage({
    super.key,
    required this.products,
    required this.initialData,
  });

  @override
  State<ProductSelectionPage> createState() => _ProductSelectionPageState();
}

class _ProductSelectionPageState extends State<ProductSelectionPage> {
  final Map<String, double> _quantities = {};
  final Map<String, double> _amounts = {};
  final Map<String, TextEditingController> _qtyControllers = {};
  final Map<String, TextEditingController> _amtControllers = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Restore previously selected data
    for (var entry in widget.initialData.entries) {
      final id = entry.key;
      final data = entry.value;
      _quantities[id] = data['quantity'] ?? 0.0;
      _amounts[id] = data['totalAmount'] ?? 0.0;
    }
    // Create controllers for all products
    for (var p in widget.products) {
      final id = p['id'] as String;
      final qty = _quantities[id];
      final amt = _amounts[id];
      _qtyControllers[id] = TextEditingController(text: qty != null && qty > 0 ? qty.toString() : '');
      _amtControllers[id] = TextEditingController(text: amt != null && amt > 0 ? amt.toString() : '');
    }
  }

  @override
  void dispose() {
    for (var ctrl in _qtyControllers.values) {
      ctrl.dispose();
    }
    for (var ctrl in _amtControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.products.where((p) {
      final name = p['name'].toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Products'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () {
              final result = <String, Map<String, double>>{};
              bool hasInvalid = false;

              _quantities.forEach((id, qty) {
                final amt = _amounts[id] ?? 0.0;
                if (qty <= 0.0) {
                  hasInvalid = true;
                } else {
                  result[id] = {
                    'quantity': qty,
                    'totalAmount': amt,
                  };
                }
              });

              if (hasInvalid) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a quantity greater than 0 for all selected items.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              Navigator.pop(context, result);
            },
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search products...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10.0)),
                ),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No products found'))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final product = filtered[index];
                      final id = product['id'] as String;
                      final isSelected = _quantities.containsKey(id);

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                  value: isSelected,
                                  onChanged: (bool? checked) {
                                    setState(() {
                                      if (checked == true) {
                                        _quantities[id] = 0.0;
                                        _amounts[id] = 0.0;
                                        _qtyControllers[id]?.text = '';
                                        _amtControllers[id]?.text = '';
                                      } else {
                                        _quantities.remove(id);
                                        _amounts.remove(id);
                                        _qtyControllers[id]?.clear();
                                        _amtControllers[id]?.clear();
                                      }
                                    });
                                  },
                                ),
                                Expanded(
                                  child: Text(
                                    product['name'],
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                            if (isSelected)
                              Padding(
                                padding: const EdgeInsets.only(left: 48.0, right: 8.0, top: 4.0, bottom: 4.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _qtyControllers[id],
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          hintText: 'Qty',
                                          labelText: 'Quantity',
                                          isDense: true,
                                          border: OutlineInputBorder(),
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        ),
                                        onChanged: (val) {
                                          final qty = double.tryParse(val) ?? 0.0;
                                          setState(() {
                                            _quantities[id] = qty;
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextField(
                                        controller: _amtControllers[id],
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          hintText: 'Amount',
                                          labelText: 'Total Amount',
                                          isDense: true,
                                          prefixText: '₹ ',
                                          border: OutlineInputBorder(),
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        ),
                                        onChanged: (val) {
                                          final amt = double.tryParse(val) ?? 0.0;
                                          setState(() {
                                            _amounts[id] = amt;
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
