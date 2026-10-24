import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isProcessing = false;

  // Camera se photo khinch kar barcode capture karna
  Future<void> _captureFromCamera() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );

      if (image != null) {
        // Safe check ke sath mock barcode ya processing
        String mockBarcode = "1045C002";
        if (mounted) {
          Navigator.pop(context, mockBarcode);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // Gallery se photo chun kar barcode lena (Null safe handling)
  Future<void> _pickFromGallery() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );

      if (image != null && mounted) {
        String mockBarcode = "1045C002";
        Navigator.pop(context, mockBarcode);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gallery Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manualController = TextEditingController();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan or Enter Barcode'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              const Icon(Icons.qr_code_scanner, size: 90, color: Colors.teal),
              const SizedBox(height: 30),
              
              // 1. Camera Button
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _isProcessing ? null : _captureFromCamera,
                icon: const Icon(Icons.camera_alt, size: 24),
                label: const Text('Mobile Camera Se Scan Karein', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 15),

              // 2. Gallery Button
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  foregroundColor: Colors.teal,
                ),
                onPressed: _isProcessing ? null : _pickFromGallery,
                icon: const Icon(Icons.photo_library, size: 24),
                label: const Text('Gallery Se Photo Chunen', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 40),
              const Divider(thickness: 2),
              const SizedBox(height: 20),

              // 3. Manual Barcode Input
              const Text(
                'Ya Barcode Number Type Karein:',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: manualController,
                      decoration: const InputDecoration(
                        hintText: 'Barcode ID...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    ),
                    onPressed: () {
                      String code = manualController.text.trim();
                      if (code.isNotEmpty) {
                        Navigator.pop(context, code);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Pehle Barcode type karein!')),
                        );
                      }
                    },
                    child: const Text('OK', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}