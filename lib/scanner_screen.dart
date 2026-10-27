import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'db_helper.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  String _hardwareScanBuffer = '';
  bool _isProcessing = false;
  
  List<Map<String, dynamic>> scannedItems = [];

  @override
  void initState() {
    super.initState();
    ServicesBinding.instance.keyboard.addHandler(_handleHardwareKey);
  }

  @override
  void dispose() {
    ServicesBinding.instance.keyboard.removeHandler(_handleHardwareKey);
    super.dispose();
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_hardwareScanBuffer.isNotEmpty) {
          _processScannedBarcode(_hardwareScanBuffer.trim());
          _hardwareScanBuffer = '';
        }
      } else if (event.character != null) {
        _hardwareScanBuffer += event.character!;
      }
    }
    return false;
  }

  Future<void> _captureFromCamera() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );

      if (image != null) {
        String mockBarcode = "1045C002"; 
        await _processScannedBarcode(mockBarcode);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );

      if (image != null) {
        String mockBarcode = "1045C002";
        await _processScannedBarcode(mockBarcode);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gallery error: $e')),
        );
      }
    } finally {
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
            const SnackBar(content: Text('Yeh item stock mein nahi hai!')),
          );
        }
        return;
      }

      int? enteredQty = await _showQuantityDialog(product['name'], stock);
      if (enteredQty == null || enteredQty <= 0) return;

      if (enteredQty > stock) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Stock mein itni miqdar maujood nahi hai!')),
          );
        }
        return;
      }

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
          SnackBar(content: Text('${product['name']} add ho gaya (${enteredQty} adad)')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product database mein nahi mili!')),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    final manualController = TextEditingController();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Continuous Multi-Scan'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _isProcessing ? null : _captureFromCamera,
                    icon: const Icon(Icons.camera_alt, size: 20),
                    label: const Text('Camera Scan'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      foregroundColor: Colors.teal,
                    ),
                    onPressed: _isProcessing ? null : _pickFromGallery,
                    icon: const Icon(Icons.photo_library, size: 20),
                    label: const Text('Gallery Photo'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: manualController,
                    decoration: const InputDecoration(
                      hintText: 'Barcode type karein ya scanner use karein...',
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
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  ),
                  onPressed: () {
                    _processScannedBarcode(manualController.text.trim());
                    manualController.clear();
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
            const SizedBox(height: 15),
            const Text(
              'Scan kiye gaye items (Live Cart):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 5),
            Expanded(
              child: scannedItems.isEmpty
                  ? const Center(
                      child: Text(
                        'Abhi tak koi item scan nahi kiya gaya.\nScan karte jayein, items yahan dikhenge.',
                        textAlign: TextAlign.center,
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
                            subtitle: Text('Rs. ${item['salePrice']} x ${item['quantity']}'),
                            trailing: Text('Rs. ${item['quantity'] * item['salePrice']}', 
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
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
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () {
                Navigator.pop(context, scannedItems);
              },
              child: Text(
                'Done - ${scannedItems.length} items pooray hue',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}