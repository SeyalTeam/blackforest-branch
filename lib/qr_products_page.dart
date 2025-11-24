import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:branch/common_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrProductsPage extends StatefulWidget {
  final dynamic categoryId;
  final String categoryName;

  const QrProductsPage({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  _QrProductsPageState createState() => _QrProductsPageState();
}

class _QrProductsPageState extends State<QrProductsPage>
    with TickerProviderStateMixin {
  List<dynamic> _products = [];
  bool _isLoading = true;
  String _errorMessage = '';
  String? _token;
  dynamic _selectedProduct;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString("token");
    _fetchProducts();
  }

  Future<void> _fetchProducts() async {
    setState(() => _isLoading = true);

    try {
      final resp = await http.get(
        Uri.parse(
            "https://admin.theblackforestcakes.com/api/products?where[category][equals]=${widget.categoryId}&limit=500&depth=1"),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        _products = data["docs"] ?? [];

        for (var p in _products) {
          p["upcController"] =
              TextEditingController(text: p["upc"]?.toString() ?? "");

          p["animController"] = AnimationController(
            duration: const Duration(milliseconds: 250),
            vsync: this,
          );

          p["animScale"] = Tween(begin: 1.0, end: 1.2)
              .animate(CurvedAnimation(parent: p["animController"], curve: Curves.easeOutBack));

          p["updated"] = false;
        }
      } else {
        _errorMessage = "Failed: ${resp.statusCode}";
      }
    } catch (e) {
      _errorMessage = "Network Error";
    }

    setState(() => _isLoading = false);
  }

  Future<void> _updateUPC(dynamic product) async {
    final upc = product["upcController"].text.trim();
    final productId = product["id"];

    product["animController"].forward().then((_) {
      product["animController"].reverse();
    });

    try {
      final resp = await http.patch(
        Uri.parse("https://admin.theblackforestcakes.com/api/products/$productId"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $_token",
        },
        body: jsonEncode({"upc": upc}),
      );

      if (resp.statusCode == 200) {
        setState(() {
          product["updated"] = true;
          _selectedProduct = null;     // UNSELECT AFTER UPDATE
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Updated Successfully!")),
        );

        await Future.delayed(const Duration(seconds: 1));

        setState(() => product["updated"] = false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Update failed: ${resp.statusCode}")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Network Error")),
      );
    }
  }

  Future<void> _scanQR(dynamic product) async {
    _selectedProduct = product;

    final scannedValue = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerPage()),
    );

    if (scannedValue != null && scannedValue.toString().isNotEmpty) {
      setState(() {
        _selectedProduct["upcController"].text = scannedValue.toString();
      });
    }
  }

  String _getImage(dynamic p) {
    try {
      if (p["images"] != null &&
          p["images"] is List &&
          p["images"].isNotEmpty &&
          p["images"][0]["image"]["url"] != null) {
        String url = p["images"][0]["image"]["url"];
        if (url.startsWith("/")) {
          return "https://admin.theblackforestcakes.com$url";
        }
        return url;
      }
    } catch (e) {}
    return "https://via.placeholder.com/150?text=No+Image";
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: "${widget.categoryName} (QR Update)",
      pageType: PageType.billing,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: _products.length,
          itemBuilder: (context, index) {
            final p = _products[index];
            final img = _getImage(p);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(
                    color: p == _selectedProduct ? Colors.green : Colors.transparent,
                    width: 2),
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  )
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ---------------- IMAGE TAP ----------------
                  GestureDetector(
                    onTap: () => _scanQR(p),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: img,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // ---------------- TITLE + INPUT ----------------
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 60,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p["name"] ?? "",
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),

                          SizedBox(
                            height: 32,
                            child: TextField(
                              controller: p["upcController"],
                              decoration: InputDecoration(
                                contentPadding:
                                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  // ---------------- UPDATE BUTTON ----------------
                  AnimatedBuilder(
                    animation: p["animController"],
                    builder: (_, child) {
                      return Transform.scale(
                        scale: p["animScale"].value,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              )
                            ],
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => _updateUPC(p),
                            icon: Icon(
                              p["updated"]
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              color: p["updated"] ? Colors.green : Colors.black,
                              size: 26,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          }),
    );
  }
}

// =====================================================================
//                    QR SCANNER SAFE PAGE
// =====================================================================
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final MobileScannerController controller = MobileScannerController();

  bool scanned = false;

  @override
  void dispose() {
    controller.dispose(); // SAFE CAMERA RELEASE
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Scan Code"),
        backgroundColor: Colors.black,
      ),
      body: MobileScanner(
        controller: controller,
        onDetect: (capture) {
          if (scanned) return;
          scanned = true;

          controller.stop();  // <<< IMPORTANT: STOP CAMERA SAFELY

          final barcode = capture.barcodes.first;
          final value = barcode.rawValue;

          if (value != null) {
            Future.delayed(const Duration(milliseconds: 200), () {
              Navigator.pop(context, value);
            });
          }
        },
      ),
    );
  }
}

