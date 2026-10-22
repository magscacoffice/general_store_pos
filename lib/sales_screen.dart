import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'db_helper.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final List<Map<String, dynamic>> _cart = [];
  double _totalAmount = 0.0;

  // Barcode scan karne ke liye dedicated screen par jana
  void _scanAndAddToCart() async {
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => const DedicatedScannerScreen(),
      ),
    );

    if (scannedCode != null && scannedCode.isNotEmpty) {
      // Database se product search karein
      final products = await DBHelper.getProducts();
      final matchingProduct = products.firstWhere(
        (p) => p['barcode'] == scannedCode,
        orElse: () => {},
      );

      if (matchingProduct.isNotEmpty) {
        setState(() {
          final index = _cart.indexWhere((item) => item['barcode'] == scannedCode);
          if (index >= 0) {
            _cart[index]['quantity'] += 1;
          } else {
            _cart.add({
              'id': matchingProduct['id'],
              'name': matchingProduct['name'],
              'price': matchingProduct['price'],
              'barcode': matchingProduct['barcode'],
              'quantity': 1,
            });
          }
          _calculateTotal();
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Yeh barcode ($scannedCode) inventory mein nahi mila!')),
          );
        }
      }
    }
  }

  void _calculateTotal() {
    _totalAmount = 0.0;
    for (var item in _cart) {
      _totalAmount += (item['price'] * item['quantity']);
    }
  }

  // Checkout karke database mein sale save karna
  void _completeCheckout() async {
    if (_cart.isEmpty) return;

    await DBHelper.insertSale({
      'total_amount': _totalAmount,
      'date': DateTime.now().toString().substring(0, 16),
    });

    setState(() {
      _cart.clear();
      _totalAmount = 0.0;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sale kamyabi ke sath save ho gayi!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Sale / Billing'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: _cart.isEmpty
                ? const Center(
                    child: Text(
                      'Cart khali hai.\nBarcode scan karne ke liye neech wale button par click karein.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _cart.length,
                    itemBuilder: (context, index) {
                      final item = _cart[index];
                      return ListTile(
                        title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Qeemat: Rs. ${item['price']} x ${item['quantity']}'),
                        trailing: Text(
                          'Rs. ${item['price'] * item['quantity']}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[200],
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Amount:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Rs. $_totalAmount', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        onPressed: _scanAndAddToCart,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan Item'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                        onPressed: _completeCheckout,
                        icon: const Icon(Icons.check),
                        label: const Text('Checkout'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Separate Scanner Widget with explicit runtime permission check
class DedicatedScannerScreen extends StatefulWidget {
  const DedicatedScannerScreen({super.key});

  @override
  State<DedicatedScannerScreen> createState() => _DedicatedScannerScreenState();
}

class _DedicatedScannerScreenState extends State<DedicatedScannerScreen> {
  late MobileScannerController controller;
  bool _hasPermission = false;
  bool _isCheckingPermission = true;

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
    controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  Future<void> _checkCameraPermission() async {
    final status = await Permission.camera.request();
    setState(() {
      _hasPermission = status.isGranted;
      _isCheckingPermission = false;
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingPermission) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Scan Item Barcode'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasPermission) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Scan Item Barcode'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.camera_alt, size: 60, color: Colors.red),
                const SizedBox(height: 15),
                const Text(
                  'Camera permission zaroori hai barcode scan karne ke liye!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    await openAppSettings();
                  },
                  child: const Text('Permission Deni Hogi'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Item Barcode'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: MobileScanner(
        controller: controller,
        errorBuilder: (context, error, child) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                'Camera Error: ${error.errorCode}\n\nKripya phone ki settings mein ja kar camera permission allow karein.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontSize: 16),
              ),
            ),
          );
        },
        onDetect: (BarcodeCapture capture) {
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            final String? code = barcode.rawValue;
            if (code != null && code.isNotEmpty) {
              Navigator.pop(context, code);
              break;
            }
          }
        },
      ),
    );
  }
}