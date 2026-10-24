import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final TextEditingController _manualBarcodeController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isProcessing = false;

  // 1. Built-in Camera se Photo khinch kar scan karna
  Future<void> _scanFromBuiltInCamera() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);

    if (image != null) {
      _processImage(image.path);
    }
  }

  // 2. Gallery se Photo chunn kar scan karna
  Future<void> _scanFromGallery() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      _processImage(image.path);
    }
  }

  Future<void> _processImage(String path) async {
    setState(() => _isProcessing = true);
    try {
      final BarcodeCapture? capture = await _scannerController.analyzeImage(path);
      if (capture != null && capture.barcodes.isNotEmpty) {
        final String? code = capture.barcodes.first.rawValue;
        if (code != null && mounted) {
          Navigator.pop(context, code);
          return;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tasweer mein barcode nahi mil saka! Manual type karein.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  void dispose() {
    _manualBarcodeController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan or Enter Barcode'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isProcessing) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 20),
              const Text('Barcode read kiya ja raha hai...', textAlign: TextAlign.center),
            ] else ...[
              const Icon(Icons.qr_code_scanner, size: 80, color: Colors.blue),
              const SizedBox(height: 30),

              // Button 1: Built-in Camera
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onPressed: _scanFromBuiltInCamera,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Mobile Camera Se Scan Karein', style: TextStyle(fontSize: 16)),
              ),

              const SizedBox(height: 15),

              // Button 2: Gallery
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onPressed: _scanFromGallery,
                icon: const Icon(Icons.photo_library),
                label: const Text('Gallery Se Photo Chunein', style: TextStyle(fontSize: 16)),
              ),

              const SizedBox(height: 30),
              const Divider(),
              const SizedBox(height: 10),

              // Manual Entry Option
              const Text(
                'Ya Barcode Number Type Karein:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualBarcodeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Barcode ID...',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                    ),
                    onPressed: () {
                      if (_manualBarcodeController.text.trim().isNotEmpty) {
                        Navigator.pop(context, _manualBarcodeController.text.trim());
                      }
                    },
                    child: const Text('OK'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}