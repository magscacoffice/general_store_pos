import 'package:flutter/material.dart';

import 'db_helper.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _sales = [];

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  void _loadSales() async {
    final data = await DBHelper.getSales();
    setState(() {
      _sales = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sale History'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
      ),
      body: _sales.isEmpty
          ? const Center(child: Text('No sales records found yet.'))
          : ListView.builder(
              itemCount: _sales.length,
              itemBuilder: (context, index) {
                final sale = _sales[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.purple,
                      child: Icon(Icons.receipt, color: Colors.white),
                    ),
                    title: Text(
                      'Total: Rs. ${sale['total_amount']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('Waqt: ${sale['date']}'),
                  ),
                );
              },
            ),
    );
  }
}
