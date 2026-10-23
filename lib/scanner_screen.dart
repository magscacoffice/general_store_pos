import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController controller = MobileScannerController();
  bool _isPermissionGranted = false;
  bool _isScanning = true;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (mounted) {
      setState(() {
        _isPermissionGranted = status.isGranted;
      });
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Product Barcode'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: !_isPermissionGranted
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Camera permission required.'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _checkPermission,
                    child: const Text('Grant Permission'),
                  )
                ],
              ),
            )
          : MobileScanner(
              controller: controller,
              onDetect: (capture) {
                if (!_isScanning) return;
                final List<Barcode> barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  if (barcode.rawValue != null) {
                    _isScanning = false;
                    Navigator.pop(context, barcode.rawValue);
                    break;
                  }
                }
              },
            ),
    );
  }
}