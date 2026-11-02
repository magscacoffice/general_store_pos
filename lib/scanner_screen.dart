import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'db_helper.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController controller = MobileScannerController();
  bool _isProcessing = false;
  bool _isReadingProductName = false;
  final ImagePicker _imagePicker = ImagePicker();
  List<Map<String, dynamic>> scannedItems = [];
  final TextEditingController manualController = TextEditingController();
  final FocusNode barcodeInputFocus = FocusNode();
  Map<String, dynamic>? lastScannedProduct;
  List<Map<String, dynamic>> allProducts = [];
  List<Map<String, dynamic>> searchResults = [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final products = await DBHelper.getProducts();
    if (!mounted) return;
    setState(() => allProducts = products);
  }

  void _searchProducts(String query) {
    final term = query.trim().toLowerCase();
    setState(() {
      if (term.isEmpty) {
        searchResults = [];
      } else {
        // contains() har position par match karta hai, sirf starting letters par nahi.
        searchResults = allProducts
            .where((product) =>
                (product['name']?.toString().toLowerCase() ?? '')
                    .contains(term))
            .take(30)
            .toList();
      }
    });
  }

  @override
  void dispose() {
    controller.dispose();
    manualController.dispose();
    barcodeInputFocus.dispose();
    super.dispose();
  }

  // Camera se real-time barcode detect hone par yeh function chale ga
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? code = barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      await _processScannedBarcode(code);
    } finally {
      // Thora delay taaki bar bar ek hi code scan na ho jaye
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _processScannedBarcode(String barcode) async {
    final products = await DBHelper.getProducts();
    final productList = products.where((p) => p['barcode'] == barcode).toList();

    if (productList.isNotEmpty) {
      final product = productList.first;
      int stock = (product['quantity'] as num?)?.toInt() ?? 0;
      if (mounted) {
        setState(() => lastScannedProduct = Map<String, dynamic>.from(product));
      }

      if (stock <= 0) {
        await _showAddStockAndAddToCartDialog(product);
        return;
      }

      final index = scannedItems.indexWhere((item) => item['barcode'] == barcode);
      final alreadyAdded = index >= 0 ? (scannedItems[index]['quantity'] as num).toInt() : 0;
      final remainingStock = stock - alreadyAdded;
      if (remainingStock <= 0) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cart mein ${product['name']} ki tamam available quantity add ho chuki hai.')),
        );
        return;
      }
      int? enteredQty = await _showQuantityDialog(product['name'], remainingStock);
      if (enteredQty == null || enteredQty <= 0) return;
      if (enteredQty > remainingStock) return;
      if (!mounted) return;
      setState(() {
        if (index >= 0) {
          scannedItems[index]['quantity'] += enteredQty;
        } else {
          scannedItems.add({
            'barcode': barcode,
            'name': product['name'],
            'purchasePrice': product['purchasePrice'] ?? 0.0,
            'salePrice': product['price'],
            'quantity': enteredQty,
          });
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${product['name']} added to cart (Quantity: $enteredQty)',
            ),
          ),
        );
      }
    } else {
      // Agar product inventory mein nahi hai, toh automatic naya product add karne ka dialog kholen!
      await _showAddNewProductDialog(barcode);
    }
  }

  Future<void> _showAddStockAndAddToCartDialog(
    Map<String, dynamic> product,
  ) async {
    final stockController = TextEditingController(text: '10');
    final saleQtyController = TextEditingController(text: '1');
    final costController = TextEditingController(
      text: (product['purchasePrice'] ?? 0).toString(),
    );
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('${product['name']} - Stock Add Karein'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Is item ka stock zero hai. Yahin stock purchase record ke sath add karein.'),
                TextField(
                  controller: stockController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Naya stock quantity'),
                ),
                TextField(
                  controller: costController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Purchase price per item (Rs.)'),
                ),
                TextField(
                  controller: saleQtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Sale mein kitni quantity add karni hai'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final addQty = int.tryParse(stockController.text.trim());
                final saleQty = int.tryParse(saleQtyController.text.trim());
                final cost = double.tryParse(costController.text.trim());
                if (addQty == null || addQty <= 0 ||
                    saleQty == null || saleQty <= 0 || saleQty > addQty ||
                    cost == null || !cost.isFinite || cost < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Stock aur sale quantity valid hon; sale quantity added stock se zyada na ho. Purchase price zero ya us se zyada ho.')),
                  );
                  return;
                }
                try {
                  final productId = (product['id'] as num).toInt();
                  await DBHelper.recordPurchase(
                    productId: productId,
                    quantity: addQty,
                    unitCost: cost,
                  );
                  if (!mounted) return;
                  setState(() {
                    scannedItems.add({
                      'barcode': product['barcode'].toString(),
                      'name': product['name'].toString(),
                      'purchasePrice': cost,
                      'salePrice': (product['price'] as num).toDouble(),
                      'quantity': saleQty,
                    });
                  });
                  await _loadProducts();
                  if (!mounted) return;
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$addQty stock purchase mein record hua aur $saleQty sale cart mein add ho gaya.')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Stock add nahi ho saka: $e')),
                  );
                }
              },
              child: const Text('Stock Add & Sale Cart'),
            ),
          ],
        ),
      );
    } finally {
      stockController.dispose();
      saleQtyController.dispose();
      costController.dispose();
    }
  }

  Future<int?> _showQuantityDialog(String productName, int maxStock) async {
    TextEditingController qtyController = TextEditingController(text: '1');
    return showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('$productName Enter quantity for'),
          content: TextField(
            controller: qtyController,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Dastyab stock: $maxStock'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final qty = int.tryParse(qtyController.text);
                if (qty == null || qty <= 0 || qty > maxStock) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Quantity 1 se $maxStock ke darmiyan honi chahiye.')),
                  );
                  return;
                }
                Navigator.pop(context, qty);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  // Product packaging ki photo se Latin/English text OCR ke zariye read karein.
  Future<void> _readProductNameFromCamera(
    TextEditingController nameController,
    BuildContext dialogContext,
  ) async {
    if (_isReadingProductName) return;
    setState(() => _isReadingProductName = true);
    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (photo == null) return;

      final recognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );
      try {
        final result = await recognizer.processImage(
          InputImage.fromFilePath(photo.path),
        );
        final candidates = result.blocks
            .expand((block) => block.lines)
            .map((line) => line.text.trim())
            .where((line) =>
                line.length >= 2 &&
                line.length <= 60 &&
                RegExp(r'[A-Za-z]').hasMatch(line) &&
                !RegExp(r'^[0-9\s.,:/-]+$').hasMatch(line))
            .toList();

        if (!mounted || !dialogContext.mounted) return;
        if (candidates.isEmpty) {
          ScaffoldMessenger.of(dialogContext).showSnackBar(
            const SnackBar(
              content: Text('Product ka naam clear nahi parha gaya. Dobara photo lein ya naam type karein.'),
            ),
          );
          return;
        }

        candidates.sort((a, b) =>
            RegExp(r'[A-Za-z]').allMatches(b).length.compareTo(
              RegExp(r'[A-Za-z]').allMatches(a).length,
            ));
        nameController.text = candidates.first;
        nameController.selection = TextSelection.collapsed(
          offset: nameController.text.length,
        );
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(content: Text('Product name read ho gaya. Save se pehle naam check kar lein.')),
        );
      } finally {
        await recognizer.close();
      }
    } catch (e) {
      if (mounted && dialogContext.mounted) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(content: Text('Text read nahi ho saka: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isReadingProductName = false);
    }
  }

  // Naya product inventory mein automatic save karne ka dialog
  Future<void> _showAddNewProductDialog(String barcode) async {
    TextEditingController nameController = TextEditingController();
    TextEditingController priceController = TextEditingController();
    TextEditingController purPriceController = TextEditingController();
    TextEditingController qtyController = TextEditingController(text: '10');

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add New Product to Inventory'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Barcode: $barcode',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Product ka Naam',
                  ),
                ),
                TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Sale Price (Rupe)',
                  ),
                ),
                TextField(
                  controller: purPriceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Purchase Price (Rupe)',
                  ),
                ),
                TextField(
                  controller: qtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Initial Stock Quantity',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                String name = nameController.text.trim();
                double price = double.tryParse(priceController.text) ?? 0.0;
                double purPrice =
                    double.tryParse(purPriceController.text) ?? 0.0;
                int qty = int.tryParse(qtyController.text) ?? 0;

                if (name.isNotEmpty && price > 0 && purPrice >= 0 && qty > 0) {
                  // Database mein naya product save karein
                  await DBHelper.insertProduct({
                    'barcode': barcode,
                    'name': name,
                    'price': price,
                    'purchasePrice': purPrice,
                    'quantity': qty,
                  });

                  if (!mounted || !context.mounted) return;
                  Navigator.pop(context);

                  // Foran cart mein bhi add kar dein
                  setState(() {
                    lastScannedProduct = {
                      'barcode': barcode,
                      'name': name,
                      'purchasePrice': purPrice,
                      'price': price,
                      'quantity': qty,
                    };
                    scannedItems.add({
                      'barcode': barcode,
                      'name': name,
                      'purchasePrice': purPrice,
                      'salePrice': price,
                      'quantity': 1,
                    });
                  });
                  await _loadProducts();

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'New product saved to inventory and added to cart!',
                        ),
                      ),
                    );
                  }
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a name, positive sale price, non-negative purchase price and stock quantity.'),
                      ),
                    );
                  }
                }
              },
              child: const Text('Save & Add'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Barcode Scanner'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          // Simple Flash Toggle Button (No torchState dependency error)
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => controller.toggleTorch(),
            tooltip: 'Flash On/Off',
          ),
          IconButton(
            icon: const Icon(Icons.camera_front),
            onPressed: () => controller.switchCamera(),
            tooltip: 'Switch Camera',
          ),
        ],
      ),
      body: Column(
        children: [
          // Live Camera Scanner View
          Expanded(
            flex: 2,
            child: Stack(
              children: [
                MobileScanner(controller: controller, onDetect: _onDetect),
                Center(
                  child: Container(
                    width: 250,
                    height: 150,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.green, width: 3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Manual input & scanned items list section
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: manualController,
                          focusNode: barcodeInputFocus,
                          autofocus: true,
                          textInputAction: TextInputAction.done,
                          onChanged: _searchProducts,
                          onSubmitted: (value) async {
                            final barcode = value.trim();
                            if (barcode.isEmpty || _isProcessing) return;
                            manualController.clear();
                            _searchProducts('');
                            _isProcessing = true;
                            try {
                              await _processScannedBarcode(barcode);
                            } finally {
                              if (mounted) {
                                _isProcessing = false;
                                barcodeInputFocus.requestFocus();
                              }
                            }
                          },
                          decoration: const InputDecoration(
                            hintText: 'USB/Bluetooth scanner: scan barcode here...',
                            helperText: 'Scanner Enter bheje to product auto search hoga',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          if (manualController.text.trim().isNotEmpty) {
                            _processScannedBarcode(
                              manualController.text.trim(),
                            );
                            manualController.clear();
                            _searchProducts('');
                          }
                        },
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                  if (lastScannedProduct != null) ...[
                    const SizedBox(height: 8),
                    Card(
                      color: Colors.teal.shade50,
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.inventory_2, color: Colors.teal),
                        title: Text(lastScannedProduct!['name']?.toString() ?? ''),
                        subtitle: Text(
                          'Barcode: ${lastScannedProduct!['barcode']}  |  Price: Rs. ${lastScannedProduct!['price']}  |  Stock: ${lastScannedProduct!['quantity']}',
                        ),
                      ),
                    ),
                  ],
                  if (searchResults.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.teal.shade100),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: searchResults.length,
                        itemBuilder: (context, index) {
                          final product = searchResults[index];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.inventory_2, color: Colors.teal),
                            title: Text(product['name']?.toString() ?? ''),
                            subtitle: Text('Barcode: ${product['barcode']}  |  Rs. ${product['price']}'),
                            onTap: () async {
                              FocusScope.of(context).unfocus();
                              await _processScannedBarcode(product['barcode'].toString());
                              if (mounted) {
                                manualController.clear();
                                _searchProducts('');
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  const Text(
                    'Scan kiye gaye items (Live Cart):',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Expanded(
                    child: scannedItems.isEmpty
                        ? const Center(
                            child: Text(
                              'Scan the barcode with the camera or enter it manually.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: scannedItems.length,
                            itemBuilder: (context, index) {
                              final item = scannedItems[index];
                              return Card(
                                child: ListTile(
                                  title: Text(item['name']),
                                  subtitle: Text(
                                    'Rs. ${item['salePrice']} x ${item['quantity']}',
                                  ),
                                  trailing: Text(
                                    'Rs. ${item['quantity'] * item['salePrice']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[800],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(context, scannedItems),
                    child: Text(
                      'Done - ${scannedItems.length} Items Complete',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
