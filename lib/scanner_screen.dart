import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'db_helper.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController controller = MobileScannerController();
  bool _isProcessing = false;
  List<Map<String, dynamic>> scannedItems = [];

  @override
  void dispose() {
    controller.dispose();
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
      int stock = (product['quantity'] as int?) ?? 0;

      if (stock <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Yeh item stock mein khatam ho chuka hai!')),
          );
        }
        return;
      }

      int? enteredQty = await _showQuantityDialog(product['name'], stock);
      if (enteredQty == null || enteredQty <= 0) return;

      setState(() {
        int index = scannedItems.indexWhere((item) => item['barcode'] == barcode);
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
          SnackBar(content: Text('${product['name']} cart mein add ho gaya (${enteredQty} adad)')),
        );
      }
    } else {
      // Agar product inventory mein nahi hai, toh automatic naya product add karne ka dialog kholen!
      await _showAddNewProductDialog(barcode);
    }
  }

  Future<int?> _showQuantityDialog(String productName, int maxStock) async {
    TextEditingController qtyController = TextEditingController(text: '1');
    return showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('$productName ki miqdar darj karein'),
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
                int qty = int.tryParse(qtyController.text) ?? 1;
                Navigator.pop(context, qty);
              },
              child: const Text('Add Karein'),
            ),
          ],
        );
      },
    );
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
          title: const Text('Naya Product Inventory Mein Add Karein'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Barcode: $barcode', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                const SizedBox(height: 10),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Product ka Naam'),
                ),
                TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Sale Price (Rupe)'),
                ),
                TextField(
                  controller: purPriceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Purchase Price (Rupe)'),
                ),
                TextField(
                  controller: qtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Initial Stock Quantity'),
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
                double purPrice = double.tryParse(purPriceController.text) ?? 0.0;
                int qty = int.tryParse(qtyController.text) ?? 1;

                if (name.isNotEmpty && price > 0) {
                  // Database mein naya product save karein
                  await DBHelper.insertProduct({
                    'barcode': barcode,
                    'name': name,
                    'price': price,
                    'purchasePrice': purPrice,
                    'quantity': qty,
                  });

                  if (mounted) Navigator.pop(context);

                  // Foran cart mein bhi add kar dein
                  setState(() {
                    scannedItems.add({
                      'barcode': barcode,
                      'name': name,
                      'purchasePrice': purPrice,
                      'salePrice': price,
                      'quantity': 1,
                    });
                  });

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Naya product inventory mein save ho gaya aur cart mein add ho gaya!')),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Barah-e-karam saheeh naam aur price darj karein!')),
                  );
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
    final manualController = TextEditingController();

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
                MobileScanner(
                  controller: controller,
                  onDetect: _onDetect,
                ),
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
                          decoration: const InputDecoration(
                            hintText: 'Barcode manual type karein...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        onPressed: () {
                          if (manualController.text.trim().isNotEmpty) {
                            _processScannedBarcode(manualController.text.trim());
                            manualController.clear();
                          }
                        },
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text('Scan kiye gaye items (Live Cart):', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Expanded(
                    child: scannedItems.isEmpty
                        ? const Center(child: Text('Camera ke samne barcode layein ya manual type karein.', style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: scannedItems.length,
                            itemBuilder: (context, index) {
                              final item = scannedItems[index];
                              return Card(
                                child: ListTile(
                                  title: Text(item['name']),
                                  subtitle: Text('Rs. ${item['salePrice']} x ${item['quantity']}'),
                                  trailing: Text('Rs. ${item['quantity'] * item['salePrice']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: () => Navigator.pop(context, scannedItems),
                    child: Text('Done - ${scannedItems.length} Items Complete', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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