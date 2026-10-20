import 'package:flutter/material.dart';

void main() {
  runApp(const GeneralStoreApp());
}

class GeneralStoreApp extends StatelessWidget {
  const GeneralStoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'General Store POS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  void _openScanner() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Barcode/QR Scanner opening...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('General Store POS'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.store, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            const Text(
              'Welcome to General Store POS System',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _openScanner,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan Barcode / QR Code'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}