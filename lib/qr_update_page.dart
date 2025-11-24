import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:branch/common_scaffold.dart';
import 'qr_products_page.dart';

class QrUpdatePage extends StatefulWidget {
  const QrUpdatePage({super.key});

  @override
  _QrUpdatePageState createState() => _QrUpdatePageState();
}

class _QrUpdatePageState extends State<QrUpdatePage> {
  List<dynamic> _categories = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchBillingCategories();
  }

  Future<void> _fetchBillingCategories() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await http.get(
        Uri.parse(
            "https://admin.theblackforestcakes.com/api/categories?where[isBilling][equals]=true&limit=200&depth=1"),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _categories = data["docs"] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = "Failed to fetch categories: ${response.statusCode}";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Network error. Check connection.";
        _isLoading = false;
      });
    }
  }

  String _getCategoryImage(dynamic category) {
    try {
      if (category["image"] != null &&
          category["image"]["url"] != null) {
        String url = category["image"]["url"];
        if (url.startsWith("/")) {
          return "https://admin.theblackforestcakes.com$url";
        }
        return url;
      }
    } catch (e) {}
    return "https://via.placeholder.com/200?text=No+Image";
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: "QR Update Categories",
      pageType: PageType.billing,
      body: RefreshIndicator(
        onRefresh: _fetchBillingCategories,
        child: _isLoading
            ? const Center(
            child: CircularProgressIndicator(color: Colors.black))
            : _errorMessage.isNotEmpty
            ? Center(child: Text(_errorMessage))
            : _categories.isEmpty
            ? const Center(child: Text("No categories found"))
            : LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          final crossCount = width > 600 ? 5 : 3;

          return GridView.builder(
            padding: const EdgeInsets.all(10),
            gridDelegate:
            SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossCount,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.75, // EXACT same as original
            ),
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final category = _categories[index];
              final imageUrl = _getCategoryImage(category);

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => QrProductsPage(
                        categoryId: category["id"],
                        categoryName: category["name"] ?? "",
                      ),
                    ),
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 2,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        flex: 8,
                        child: ClipRRect(
                          borderRadius:
                          const BorderRadius.vertical(
                              top: Radius.circular(8)),
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            placeholder: (context, url) =>
                            const Center(
                                child:
                                CircularProgressIndicator()),
                            errorWidget: (context, url, error) =>
                            const Center(
                                child: Text("No Image",
                                    style: TextStyle(
                                        color: Colors.grey))),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(8)),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            category["name"] ?? "",
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
