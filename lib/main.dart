import 'backup_screen.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'inventory_screen.dart';
import 'sales_screen.dart';
import 'history_screen.dart';
import 'party_screen.dart';
import 'expense_screen.dart';

void main() {
  runApp(const GeneralStoreApp());
}

class GeneralStoreApp extends StatelessWidget {
  const GeneralStoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Khan Baba General Store',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Future<void> _openScanner() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }

    if (!mounted) return;

    if (status.isGranted) {
      final scannedCode = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (context) => const ScannerScreen()),
      );

      if (scannedCode != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('اسکین شدہ کوڈ: $scannedCode')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('بارکوڈ اسکین کرنے کے لیے کیمرے کی اجازت ضروری ہے!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('خان بابا جنرل اسٹور'),
        centerTitle: true,
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            const Icon(Icons.storefront, size: 70, color: Colors.blue),
            const SizedBox(height: 5),
            const Text(
              'Khan Baba General Store POS',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  _buildCard(
  icon: Icons.backup,
  title: 'بیک اپ اور ریسٹور',
  color: Colors.teal,
  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen())),
),
                  _buildCard(
                    icon: Icons.qr_code_scanner,
                    title: 'نیو سیل / اسکینر',
                    color: Colors.green,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesScreen())),
                  ),
                  _buildCard(
                    icon: Icons.inventory_2,
                    title: 'اسٹاک / انوینٹری',
                    color: Colors.orange,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryScreen())),
                  ),
                  _buildCard(
                    icon: Icons.receipt_long,
                    title: 'سیل ہسٹری',
                    color: Colors.purple,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
                  ),
                  _buildCard(
                    icon: Icons.people,
                    title: 'کسٹمرز (گراہک)',
                    color: Colors.amber[800]!,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PartyScreen(type: 'customer'))),
                  ),
                  _buildCard(
                    icon: Icons.local_shipping,
                    title: 'سپلائرز (سماان والے)',
                    color: Colors.indigo,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PartyScreen(type: 'supplier'))),
                  ),
                  _buildCard(
                    icon: Icons.money_off,
                    title: 'روزمرہ اخراجات',
                    color: Colors.red,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseScreen())),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required IconData icon, required String title, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class ScannerScreen extends StatelessWidget {
  const ScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بارکوڈ اسکین کریں'), backgroundColor: Colors.blue, foregroundColor: Colors.white),
      body: MobileScanner(
        onDetect: (capture) {
          final barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            final code = barcode.rawValue;
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