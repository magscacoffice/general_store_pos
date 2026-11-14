import 'windows/desktop_app_bar.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'db_helper.dart';

class ScannerScreen extends StatefulWidget {
  final bool captureBarcodeOnly;

  const ScannerScreen({super.key, this.captureBarcodeOnly = false});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  MobileScannerController? controller;
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
    // mobile_scanner has no Windows implementation; Windows uses HID keyboard scanners.
    if (!Platform.isWindows) controller = MobileScannerController();
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
                (product['name']?.toString().toLowerCase() ?? '').contains(term) ||
                (product['barcode']?.toString().toLowerCase() ?? '').contains(term))
            .take(30)
            .toList();
      }
    });
  }

  @override
  void dispose() {
    controller?.dispose();
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

  Future<void> _playScanBeep() async {
    if (!mounted || widget.captureBarcodeOnly) return;
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {
      // Audio feedback is optional; never interrupt barcode handling.
    }
  }

  Future<void> _processScannedBarcode(String rawBarcode) async {
    final barcode = rawBarcode.trim();
    if (barcode.isEmpty) return;

    // Inventory form ko sirf barcode chahiye; product ka pehle se hona zaroori nahi.
    if (widget.captureBarcodeOnly) {
      if (mounted) Navigator.pop(context, barcode);
      return;
    }

    final products = await DBHelper.getProducts();
    final productList = products
        .where((p) => p['barcode']?.toString().trim() == barcode)
        .toList();
    if (productList.isEmpty) {
      // New Sale se unknown barcode par product yahin create ho kar
      // inventory aur isi bill dono mein add hoga.
      if (mounted) await _showAddNewProductDialog(barcode);
      return;
    }

    final product = productList.first;
    final stock = (product['quantity'] as num?)?.toInt() ?? 0;
    if (mounted) setState(() => lastScannedProduct = Map<String, dynamic>.from(product));
    final index = scannedItems.indexWhere((item) => item['barcode']?.toString() == barcode);
    final alreadyAdded = index >= 0
        ? (scannedItems[index]['quantity'] as num).toInt()
        : 0;
    if (stock <= alreadyAdded) {
      if (mounted) await _showAddStockAndAddToCartDialog(product);
      return;
    }

    // Har successful scan sirf aik piece add karta hai. Quantity popup nahi khulta.
    if (!mounted) return;
    setState(() {
      if (index >= 0) {
        scannedItems[index]['quantity'] = alreadyAdded + 1;
      } else {
        scannedItems.add({
          'barcode': barcode,
          'name': product['name'],
          'purchasePrice': product['purchasePrice'] ?? 0.0,
          'salePrice': (product['price'] as num).toDouble() <
                  (product['purchasePrice'] as num? ?? 0).toDouble()
              ? (product['purchasePrice'] as num? ?? 0).toDouble()
              : (product['price'] as num).toDouble(),
          'quantity': 1,
        });
      }
    });
    await _playScanBeep();
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
                const Text('Is item ka available stock is bill ki requirement se kam hai. Yahin stock purchase record ke sath add karein.'),
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
                      // This bill must never sell below the newly entered cost.
                      // The saved product sale price is deliberately unchanged.
                      'salePrice': (product['price'] as num).toDouble() < cost
                          ? cost
                          : (product['price'] as num).toDouble(),
                      'quantity': saleQty,
                    });
                  });
                  await _loadProducts();
                  if (!mounted) return;
                  await _playScanBeep();
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
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final purPriceController = TextEditingController();
    final qtyController = TextEditingController(text: '10');

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('New Product - Inventory Mein Add Karein'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Barcode: $barcode',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Product ka Naam *'),
                ),
                const SizedBox(height: 8),
                if (!Platform.isWindows)
                  OutlinedButton.icon(
                    onPressed: _isReadingProductName
                        ? null
                        : () => _readProductNameFromCamera(nameController, dialogContext),
                    icon: _isReadingProductName
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.camera_alt),
                    label: Text(_isReadingProductName ? 'Naam read ho raha hai...' : 'Camera se Product Name Read Karein'),
                  ),
                TextField(
                  controller: purPriceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Purchase Price (Rs.) *'),
                ),
                TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Sale Price (Rs.) *'),
                ),
                TextField(
                  controller: qtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Initial Stock Quantity *'),
                ),
                const SizedBox(height: 4),
                const Text('Product save hone ke baad isi bill mein 1 piece add ho jayega.'),
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
                final name = nameController.text.trim();
                final price = double.tryParse(priceController.text.trim());
                final purchasePrice = double.tryParse(purPriceController.text.trim());
                final quantity = int.tryParse(qtyController.text.trim());

                if (name.isEmpty ||
                    price == null || !price.isFinite || price <= 0 ||
                    purchasePrice == null || !purchasePrice.isFinite || purchasePrice < 0 ||
                    quantity == null || quantity <= 0 ||
                    price < purchasePrice) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Naam, stock aur prices durust likhein. Sale price purchase price se kam nahi ho sakti.')),
                  );
                  return;
                }

                try {
                  await DBHelper.insertProduct({
                    'barcode': barcode,
                    'name': name,
                    'price': price,
                    'purchasePrice': purchasePrice,
                    'damaged_quantity': 0,
                    'quantity': quantity,
                  });

                  if (!mounted || !dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  setState(() {
                    lastScannedProduct = {
                      'barcode': barcode,
                      'name': name,
                      'purchasePrice': purchasePrice,
                      'price': price,
                      'quantity': quantity,
                    };
                    final existingIndex = scannedItems.indexWhere(
                      (item) => item['barcode']?.toString() == barcode,
                    );
                    if (existingIndex >= 0) {
                      scannedItems[existingIndex]['quantity'] =
                          (scannedItems[existingIndex]['quantity'] as num).toInt() + 1;
                    } else {
                      scannedItems.add({
                        'barcode': barcode,
                        'name': name,
                        'purchasePrice': purchasePrice,
                        'salePrice': price,
                        'quantity': 1,
                      });
                    }
                  });
                  await _loadProducts();
                  if (mounted) {
                    await _playScanBeep();
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(content: Text('Naya product inventory mein save ho gaya aur isi bill mein add ho gaya.')),
                    );
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('Product save nahi ho saka: ${e.toString().replaceFirst('Exception: ', '')}')),
                    );
                  }
                }
              },
              child: const Text('Save & Add to Bill'),
            ),
          ],
        ),
      );
    } finally {
      nameController.dispose();
      priceController.dispose();
      purPriceController.dispose();
      qtyController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !Platform.isWindows,
        leading: desktopReturnButton(),
        toolbarHeight: Platform.isWindows ? 48 : 56,
        title: const Text('Live Barcode Scanner'),
        backgroundColor: Platform.isWindows ? const Color(0xFFF7F9FB) : Colors.teal,
        foregroundColor: Platform.isWindows ? const Color(0xFF263442) : Colors.white,
        actions: Platform.isWindows
            ? const []
            : [
                IconButton(
                  icon: const Icon(Icons.flash_on),
                  onPressed: () => controller?.toggleTorch(),
                  tooltip: 'Flash On/Off',
                ),
                IconButton(
                  icon: const Icon(Icons.camera_front),
                  onPressed: () => controller?.switchCamera(),
                  tooltip: 'Switch Camera',
                ),
              ],
      ),
      body: Column(
        children: [
          // Android/iOS camera scanner. Windows uses USB/Bluetooth HID input below.
          if (!Platform.isWindows)
            Expanded(
              flex: 2,
              child: Stack(
                children: [
                  MobileScanner(controller: controller!, onDetect: _onDetect),
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
            flex: Platform.isWindows ? 1 : 3,
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
                          keyboardType: TextInputType.text,
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
                          decoration: InputDecoration(
                            hintText: Platform.isWindows
                                ? 'Product name search karein ya USB barcode scan karein...'
                                : 'USB/Bluetooth scanner: scan barcode here...',
                            helperText: Platform.isWindows
                                ? 'Product name type karein aur matching result select karein; scanner Enter par item add hoga.'
                                : 'Scanner Enter bheje to product auto search hoga',
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
                      constraints: BoxConstraints(maxHeight: Platform.isWindows ? 180 : 180),
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
                            minTileHeight: Platform.isWindows ? 42 : 48,
                            leading: const Icon(Icons.inventory_2, color: Colors.teal, size: 18),
                            title: Text(product['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('Barcode: ${product['barcode']}  |  Rs. ${product['price']}', maxLines: 1, overflow: TextOverflow.ellipsis),
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
