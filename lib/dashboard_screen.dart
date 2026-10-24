import 'package:flutter/material.dart';
import 'inventory_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double totalSales = 0.0;
  double totalProfit = 0.0;
  int totalOrders = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    final db = await DatabaseHelper.instance.database;
    final sales = await db.query('sales');

    double salesSum = 0.0;
    double profitSum = 0.0;

    for (var s in sales) {
      salesSum += (s['totalAmount'] as num?)?.toDouble() ?? 0.0;
      profitSum += (s['totalProfit'] as num?)?.toDouble() ?? 0.0;
    }

    if (mounted) {
      setState(() {
        totalSales = salesSum;
        totalProfit = profitSum;
        totalOrders = sales.length;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ Yahan se _loadDashboardData() hata diya gaya hai taaki infinite loop aur crash khatam ho jaye!

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales & Profit Dashboard'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              color: Colors.teal[50],
              child: ListTile(
                leading: const Icon(Icons.attach_money, color: Colors.teal, size: 40),
                title: const Text('Total Sales'),
                subtitle: Text('Rs. $totalSales', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.teal)),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: Colors.green[50],
              child: ListTile(
                leading: const Icon(Icons.trending_up, color: Colors.green, size: 40),
                title: const Text('Total Net Profit'),
                subtitle: Text('Rs. $totalProfit', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: Colors.blue[50],
              child: ListTile(
                leading: const Icon(Icons.receipt_long, color: Colors.blue, size: 40),
                title: const Text('Total Orders'),
                subtitle: Text('$totalOrders Orders', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blue)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}