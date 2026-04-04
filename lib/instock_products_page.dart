import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:branch/common_scaffold.dart';
import 'package:branch/instock_provider.dart';
import 'package:branch/api_config.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img_lib;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';

class InstockProductsPage extends StatefulWidget {
  const InstockProductsPage({super.key});

  @override
  State<InstockProductsPage> createState() => _InstockProductsPageState();
}

class _ProductCameraDialog extends StatefulWidget {
  final List<CameraDescription> cameras;

  const _ProductCameraDialog({required this.cameras});

  @override
  State<_ProductCameraDialog> createState() => _ProductCameraDialogState();
}

class _ProductCameraDialogState extends State<_ProductCameraDialog> {
  late CameraController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.cameras[0], ResolutionPreset.high);
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {});
        })
        .catchError((e) {
          debugPrint('Camera init error: $e');
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return AlertDialog(
      content: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: CameraPreview(_controller),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            final navigator = Navigator.of(context);
            final messenger = ScaffoldMessenger.of(context);
            try {
              final XFile file = await _controller.takePicture();
              if (!mounted) return;
              navigator.pop(file);
            } catch (e) {
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(content: Text('Failed to capture photo')),
              );
              navigator.pop();
            }
          },
          child: const Text('Capture'),
        ),
      ],
    );
  }
}

class _InstockProductsPageState extends State<InstockProductsPage> {
  // No need to set live mode as InstockProvider handles it implicitly

  Future<File?> _captureAndConfirmPhoto() async {
    final messenger = ScaffoldMessenger.of(context);

    final permission = await Permission.camera.request();
    if (!permission.isGranted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Camera permission required')),
      );
      return null;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('No camera found')));
      return null;
    }
    if (!mounted) return null;

    final XFile? photo = await showDialog<XFile>(
      context: context,
      builder: (context) => _ProductCameraDialog(cameras: cameras),
    );
    if (photo == null) return null;

    final bytes = await photo.readAsBytes();
    final decoded = img_lib.decodeImage(bytes);
    if (decoded == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to process captured image')),
      );
      return null;
    }

    final compressed = img_lib.encodeJpg(decoded, quality: 70);
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempFile = File('${tempDir.path}/product_$timestamp.jpg');
    await tempFile.writeAsBytes(compressed);
    if (!mounted) return null;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Photo Preview'),
        content: Image.file(tempFile),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Retake'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed == true) return tempFile;

    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    return null;
  }

  Future<File?> _pickAndConfirmPhotoFromGallery() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picker = ImagePicker();
      final XFile? selected = await picker.pickImage(
        source: ImageSource.gallery,
      );
      if (selected == null) return null;

      final bytes = await selected.readAsBytes();
      final decoded = img_lib.decodeImage(bytes);
      if (decoded == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to process selected image')),
        );
        return null;
      }

      final compressed = img_lib.encodeJpg(decoded, quality: 70);
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/product_gallery_$timestamp.jpg');
      await tempFile.writeAsBytes(compressed);
      if (!mounted) return null;

      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Image Preview'),
          content: Image.file(tempFile),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Choose Another'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );

      if (confirmed == true) return tempFile;
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      return null;
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e')),
      );
      return null;
    }
  }

  Future<void> _showCreateProductDialog(InstockProvider sp) async {
    await sp.loadDealers();
    if (!mounted) return;

    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final rateCtrl = TextEditingController();

    String? selectedDealerId = sp.dealers.isNotEmpty
        ? sp.dealers.first["id"]?.toString()
        : null;
    String selectedUnit = "pcs";
    String selectedGst = "0";
    bool isVeg = false;
    bool isSubmitting = false;
    File? capturedImage;

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 24,
              ),
              title: const Text("Create New Product"),
              content: SizedBox(
                width: MediaQuery.of(dialogContext).size.width > 620
                    ? 520
                    : MediaQuery.of(dialogContext).size.width - 24,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                      TextFormField(
                        controller: nameCtrl,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: "Product Name",
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return "Product name is required";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedDealerId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: "Dealer",
                          border: OutlineInputBorder(),
                        ),
                        items: sp.dealers.map((dealer) {
                          final id = dealer["id"]?.toString() ?? "";
                          final name =
                              dealer["name"]?.toString() ?? "Unknown Dealer";
                          return DropdownMenuItem<String>(
                            value: id,
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          );
                        }).toList(),
                        onChanged: isSubmitting
                            ? null
                            : (value) {
                                setDialogState(() {
                                  selectedDealerId = value;
                                });
                              },
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return "Dealer is required";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: priceCtrl,
                        textInputAction: TextInputAction.next,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: "Price",
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final parsed = double.tryParse((value ?? "").trim());
                          if (parsed == null || parsed <= 0) {
                            return "Enter a valid price";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: rateCtrl,
                        textInputAction: TextInputAction.next,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: "Rate",
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final parsed = double.tryParse((value ?? "").trim());
                          if (parsed == null || parsed < 0) {
                            return "Enter a valid rate";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedUnit,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: "Unit",
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: "pcs", child: Text("pcs")),
                          DropdownMenuItem(value: "kg", child: Text("kg")),
                          DropdownMenuItem(value: "g", child: Text("g")),
                        ],
                        onChanged: isSubmitting
                            ? null
                            : (value) {
                                if (value == null) return;
                                setDialogState(() {
                                  selectedUnit = value;
                                });
                              },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedGst,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: "GST",
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: "0", child: Text("0%")),
                          DropdownMenuItem(value: "5", child: Text("5%")),
                          DropdownMenuItem(value: "12", child: Text("12%")),
                          DropdownMenuItem(value: "18", child: Text("18%")),
                          DropdownMenuItem(value: "22", child: Text("22%")),
                        ],
                        onChanged: isSubmitting
                            ? null
                            : (value) {
                                if (value == null) return;
                                setDialogState(() {
                                  selectedGst = value;
                                });
                              },
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.camera_alt_outlined, size: 18),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    "Product Image",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: isSubmitting
                                          ? null
                                          : () async {
                                              final file =
                                                  await _captureAndConfirmPhoto();
                                              if (file == null) return;
                                              setDialogState(() {
                                                capturedImage = file;
                                              });
                                            },
                                      child: Text(
                                        capturedImage == null
                                            ? "Capture"
                                            : "Retake",
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: isSubmitting
                                          ? null
                                          : () async {
                                              final file =
                                                  await _pickAndConfirmPhotoFromGallery();
                                              if (file == null) return;
                                              setDialogState(() {
                                                capturedImage = file;
                                              });
                                            },
                                      child: const Text("Select from Gallery"),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (capturedImage != null) ...[
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.file(
                                  capturedImage!,
                                  height: 140,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Is Veg"),
                        value: isVeg,
                        onChanged: (value) {
                          setDialogState(() {
                            isVeg = value;
                          });
                        },
                      ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.pop(dialogContext, false),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;

                          final messenger = ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(dialogContext);
                          if (capturedImage == null) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Please capture product image'),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isSubmitting = true;
                          });

                          final mediaId = await sp.uploadProductPhoto(
                            capturedImage!,
                            nameCtrl.text.trim().isEmpty
                                ? 'Product image'
                                : nameCtrl.text.trim(),
                          );
                          if (mediaId == null || mediaId.isEmpty) {
                            setDialogState(() {
                              isSubmitting = false;
                            });
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Failed to upload product image'),
                              ),
                            );
                            return;
                          }

                          final error = await sp.createProduct(
                            name: nameCtrl.text,
                            dealerId: selectedDealerId ?? "",
                            price: double.parse(priceCtrl.text.trim()),
                            rate: double.parse(rateCtrl.text.trim()),
                            isVeg: isVeg,
                            unit: selectedUnit,
                            gst: selectedGst,
                            imageId: mediaId,
                          );

                          if (!mounted) return;

                          if (error == null) {
                            navigator.pop(true);
                          } else {
                            setDialogState(() {
                              isSubmitting = false;
                            });
                            messenger.showSnackBar(
                              SnackBar(content: Text(error)),
                            );
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("Create"),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted) return;
    if (created == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Product created successfully")),
      );
    }
  }

  void _toggleProductSelection(int index) async {
    final sp = Provider.of<InstockProvider>(context, listen: false);
    final product = sp.filteredProducts[index];
    final String id = product["id"];

    // Detect Weight Based
    bool isWeightBased = false;
    try {
      final unit = product['defaultPriceDetails']?['unit']
          ?.toString()
          .toLowerCase();
      final isKgFlag =
          product['isKg'] == true ||
          product['sellByWeight'] == true ||
          product['weightBased'] == true;
      final pricingType = product['pricingType']?.toString().toLowerCase();

      if (unit != null && (unit.contains('kg') || unit.contains('gram'))) {
        isWeightBased = true;
      }
      if (isKgFlag) {
        isWeightBased = true;
      }
      if (pricingType != null && pricingType.contains('kg')) {
        isWeightBased = true;
      }
    } catch (e) {
      isWeightBased = false;
    }

    // Current InStock Value
    double currentStock = sp.inStockQuery[id] ?? 0.0;

    if (isWeightBased) {
      final unit = product['defaultPriceDetails']?['unit'] ?? 'kg';
      final TextEditingController weightController = TextEditingController(
        text: currentStock > 0 ? currentStock.toStringAsFixed(2) : '',
      );
      final enteredWeight = await showDialog<double>(
        context: context,
        barrierDismissible: true,
        builder: (context) {
          return AlertDialog(
            title: Text('Enter Instock Weight ($unit)'),
            content: TextField(
              controller: weightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. 0.5',
                labelText: 'Weight in $unit',
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final value =
                      double.tryParse(weightController.text.trim()) ?? 0.0;
                  Navigator.pop(context, value);
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );

      if (enteredWeight == null) return;
      sp.updateInStock(id, enteredWeight);
    } else {
      sp.updateInStock(id, currentStock + 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InstockProvider>(
      builder: (context, sp, child) {
        return CommonScaffold(
          title: 'Instock: ${sp.selectedCategoryName ?? "Products"}',
          pageType: PageType.instock,
          body: sp.isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.black),
                )
              : Column(children: [Expanded(child: _buildGrid(sp))]),
        );
      },
    );
  }

  Widget _buildGrid(InstockProvider sp) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = (width > 600) ? 5 : 3;
        return GridView.builder(
          padding: const EdgeInsets.all(10),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.75,
          ),
          itemCount: sp.filteredProducts.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return GestureDetector(
                onTap: () => _showCreateProductDialog(sp),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: const Color(0xFFEFFAF1),
                    border: Border.all(
                      color: const Color(0xFF2E7D32),
                      width: 2,
                    ),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_circle,
                        size: 48,
                        color: Color(0xFF2E7D32),
                      ),
                      SizedBox(height: 10),
                      Text(
                        "New Product",
                        style: TextStyle(
                          color: Color(0xFF1B5E20),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Add to this category",
                        style: TextStyle(
                          color: Color(0xFF2E7D32),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final product = sp.filteredProducts[index - 1];
            final String id = product["id"];

            String? imageUrl;
            if (product['images'] != null &&
                product['images'].isNotEmpty &&
                product['images'][0]['image'] != null &&
                product['images'][0]['image']['url'] != null) {
              imageUrl = product['images'][0]['image']['url'];
              if (imageUrl != null && imageUrl.startsWith('/')) {
                imageUrl = '${ApiConfig.domain}$imageUrl';
              }
            }
            imageUrl ??= 'https://via.placeholder.com/150?text=No+Image';

            final double pVal = sp.prices[id] ?? 0.0;
            final price = '₹${pVal % 1 == 0 ? pVal.toInt() : pVal}';

            final currentStock = sp.inStockQuery[id] ?? 0.0;
            final isSelected = currentStock > 0;

            String qtyText;
            if (currentStock == currentStock.floorToDouble()) {
              qtyText = currentStock.toInt().toString();
            } else {
              qtyText = currentStock.toStringAsFixed(2);
            }

            final unitDetails = product['defaultPriceDetails'];
            final double uQty =
                (unitDetails != null && unitDetails['quantity'] != null)
                ? (unitDetails['quantity'] as num).toDouble()
                : 1.0;
            final String uName = unitDetails?['unit'] ?? 'pcs';
            final String uQtyStr = uQty % 1 == 0
                ? uQty.toInt().toString()
                : uQty.toString();
            final String unitDisplay = '$uQtyStr$uName';

            return GestureDetector(
              onTap: () => _toggleProductSelection(index - 1),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(color: Colors.blue, width: 4)
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.1),
                      spreadRadius: 2,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Column(
                      children: [
                        Expanded(
                          flex: 8,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8),
                            ),
                            child: CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              placeholder: (context, url) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                              errorWidget: (context, url, error) =>
                                  const Center(
                                    child: Text(
                                      'No Image',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ),
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
                                bottom: Radius.circular(8),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              product['name'] ?? 'Unknown',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      top: 2,
                      left: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          price,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          unitDisplay,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    if (isSelected)
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.center,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              border: Border.all(color: Colors.white, width: 1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Text(
                              qtyText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
