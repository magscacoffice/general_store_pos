import 'package:flutter/material.dart';

import 'sales_screen.dart';
import 'inventory_screen.dart';
import 'history_screen.dart';
import 'sales_report_screen.dart';
import 'backup_screen.dart';
import 'purchase_screen.dart';
import 'customer_khata_screen.dart';
import 'profit_loss_screen.dart';
import 'party_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('خان بابا جنرل سٹور'),
        centerTitle: true,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Icon(Icons.store, size: 60, color: Colors.teal),
            const SizedBox(height: 8),
            const Text(
              'Khan Baba General Store POS',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  _buildMenuCard(
                    context,
                    'نیو سیل / اسکینر',
                    Icons.qr_code_scanner,
                    Colors.green,
                    const SalesScreen(),
                  ),
                  _buildMenuCard(
                    context,
                    'اسٹاک / انوینٹری',
                    Icons.inventory_2,
                    Colors.orange,
                    const InventoryScreen(),
                  ),
                  _buildMenuCard(
                    context,
                    'سیل ہسٹری',
                    Icons.receipt_long,
                    Colors.purple,
                    const HistoryScreen(),
                  ),
                  _buildMenuCard(
                    context,
                    'سیل رپورٹ / Reports',
                    Icons.bar_chart,
                    Colors.blue,
                    const SalesReportScreen(),
                  ),
                  _buildMenuCard(
                    context,
                    'Purchase / Stock Entry',
                    Icons.add_shopping_cart,
                    Colors.brown,
                    const PurchaseScreen(),
                  ),
                  _buildMenuCard(
                    context,
                    'Party / Customers',
                    Icons.people,
                    Colors.deepOrange,
                    const PartyScreen(type: 'customer'),
                  ),
                  _buildMenuCard(
                    context,
                    'Customer Khata',
                    Icons.menu_book,
                    Colors.indigo,
                    const CustomerKhataScreen(),
                  ),
                  _buildMenuCard(
                    context,
                    'Profit / Loss',
                    Icons.trending_up,
                    Colors.deepPurple,
                    const ProfitLossScreen(),
                  ),
                  _buildMenuCard(
                    context,
                    'سیٹنگز / بیک اپ',
                    Icons.settings,
                    Colors.teal,
                    const BackupScreen(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    Widget targetScreen,
  ) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => targetScreen),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 45, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
