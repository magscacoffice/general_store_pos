import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'db_helper.dart';

import 'dart:typed_data';


class _LiveProductNameScannerDialog extends StatefulWidget {
  const _LiveProductNameScannerDialog();

  @override
  State<_LiveProductNameScannerDialog> createState() =>
      _LiveProductNameScannerDialogState();
}

class _LiveProductNameScannerDialogState
    extends State<_LiveProductNameScannerDialog> {
  CameraController? _cameraController;
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);
  bool _busy = false;
  bool _starting = true;
  String? _error;
  String _previewText = 'Product ka naam camera ke frame mein rakhein';
  DateTime _lastRead = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _startCamera();
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('Device camera available nahi hai.');
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      _cameraController = controller;
      await controller.initialize();
      if (!mounted) return;
      await controller.startImageStream(_processFrame);
      if (mounted) setState(() => _starting = false);
    } catch (e) {
      if (mounted) setState(() { _starting = false; _error = e.toString(); });
    }
  }

  Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final ySize = width * height;
    final output = Uint8List(ySize + (width * height ~/ 2));
    final yPlane = image.planes[0];
    var outputIndex = 0;
    for (var row = 0; row < height; row++) {
      final rowStart = row * yPlane.bytesPerRow;
      for (var col = 0; col < width; col++) {
        output[outputIndex++] = yPlane.bytes[rowStart + col];
      }
    }
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    for (var row = 0; row < height ~/ 2; row++) {
      for (var col = 0; col < width ~/ 2; col++) {
        final uIndex = row * uPlane.bytesPerRow + col * uPlane.bytesPerPixel!;
        final vIndex = row * vPlane.bytesPerRow + col * vPlane.bytesPerPixel!;
        output[outputIndex++] = vPlane.bytes[vIndex];
        output[outputIndex++] = uPlane.bytes[uIndex];
      }
    }
    return output;
  }

  InputImageRotation _rotationFor(int degrees) {
    switch (degrees) {
      case 90: return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default: return InputImageRotation.rotation0deg;
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    final now = DateTime.now();
    if (_busy || now.difference(_lastRead).inMilliseconds < 450) return;
    _busy = true;
    _lastRead = now;
    try {
      final camera = _cameraController;
      if (camera == null || !camera.value.isInitialized ||
          image.planes.length < 3) return;
      final rotation = _rotationFor(camera.description.sensorOrientation);
      final bytes = _yuv420ToNv21(image);
      final input = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
      final result = await _recognizer.processImage(input);
      final candidates = result.blocks
          .expand((block) => block.lines)
          .map((line) => line.text.trim())
          .where((line) => line.length >= 2 && line.length <= 60 &&
              RegExp(r'[A-Za-z]').hasMatch(line) &&
              !RegExp(r'^[0-9\\s.,:/-]+
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController controller = MobileScannerController();
  bool _isProcessing = false;
  bool _isReadingProductName = false;
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

  // Live camera preview se continuously text read karein; photo capture ki zaroorat nahi.
  Future<void> _readProductNameFromCamera(
    TextEditingController nameController,
    BuildContext dialogContext,
  ) async {
    if (_isReadingProductName) return;
    setState(() => _isReadingProductName = true);
    try {
      final recognizedText = await showDialog<String>(
        context: dialogContext,
        barrierDismissible: false,
        builder: (_) => const _LiveProductNameScannerDialog(),
      );
      if (!mounted || !dialogContext.mounted || recognizedText == null) return;
      nameController.text = recognizedText;
      nameController.selection = TextSelection.collapsed(
        offset: nameController.text.length,
      );
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        const SnackBar(content: Text('Product name live scan se read ho gaya. Save se pehle check kar lein.')),
      );
    } catch (e) {
      if (mounted && dialogContext.mounted) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(content: Text('Live text scan nahi ho saka: $e')),
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
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Product ka Naam',
                    hintText: 'Naam type karein ya live camera se scan karein',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _isReadingProductName
                      ? null
                      : () => _readProductNameFromCamera(
                            nameController,
                            context,
                          ),
                  icon: _isReadingProductName
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.document_scanner),
                  label: Text(
                    _isReadingProductName
                        ? 'Live camera scan ho raha hai...'
                        : 'Live Scan Product Name',
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
).hasMatch(line))
          .toList();
      if (!mounted) return;
      if (candidates.isNotEmpty) {
        candidates.sort((a, b) =>
            RegExp(r'[A-Za-z]').allMatches(b).length.compareTo(
              RegExp(r'[A-Za-z]').allMatches(a).length));
        setState(() => _previewText = candidates.first);
      }
    } catch (_) {
      // Ignore individual blurry frames; the next live frame is processed.
    } finally {
      _busy = false;
    }
  }

  Future<void> _acceptText() async {
    final text = _previewText.trim();
    if (text.isEmpty || text == 'Product ka naam camera ke frame mein rakhein') return;
    final camera = _cameraController;
    if (camera != null && camera.value.isStreamingImages) {
      await camera.stopImageStream();
    }
    if (mounted) Navigator.pop(context, text);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _recognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _cameraController;
    return AlertDialog(
      title: const Text('Live Product Name Scanner'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: camera?.value.isInitialized == true
                  ? camera!.value.aspectRatio : 4 / 3,
              child: _starting
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            CameraPreview(camera!),
                            Center(
                              child: Container(
                                width: 240,
                                height: 90,
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.greenAccent, width: 2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
            ),
            const SizedBox(height: 12),
            const Text('Camera ko product ke naam par seedha rakhein. Text live update hota rahega.'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_previewText,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _starting || _error != null ? null : _acceptText,
          child: const Text('Use This Name'),
        ),
      ],
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController controller = MobileScannerController();
  bool _isProcessing = false;
  bool _isReadingProductName = false;
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

  // Live camera preview se continuously text read karein; photo capture ki zaroorat nahi.
  Future<void> _readProductNameFromCamera(
    TextEditingController nameController,
    BuildContext dialogContext,
  ) async {
    if (_isReadingProductName) return;
    setState(() => _isReadingProductName = true);
    try {
      final recognizedText = await showDialog<String>(
        context: dialogContext,
        barrierDismissible: false,
        builder: (_) => const _LiveProductNameScannerDialog(),
      );
      if (!mounted || !dialogContext.mounted || recognizedText == null) return;
      nameController.text = recognizedText;
      nameController.selection = TextSelection.collapsed(
        offset: nameController.text.length,
      );
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        const SnackBar(content: Text('Product name live scan se read ho gaya. Save se pehle check kar lein.')),
      );
    } catch (e) {
      if (mounted && dialogContext.mounted) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(content: Text('Live text scan nahi ho saka: $e')),
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
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Product ka Naam',
                    hintText: 'Naam type karein ya live camera se scan karein',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _isReadingProductName
                      ? null
                      : () => _readProductNameFromCamera(
                            nameController,
                            context,
                          ),
                  icon: _isReadingProductName
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.document_scanner),
                  label: Text(
                    _isReadingProductName
                        ? 'Live camera scan ho raha hai...'
                        : 'Live Scan Product Name',
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
