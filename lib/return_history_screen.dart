import 'windows/desktop_app_bar.dart';
import 'dart:io';
import 'package:flutter/material.dart';

import 'db_helper.dart';

class ReturnHistoryScreen extends StatefulWidget {
  const ReturnHistoryScreen({super.key});

  @override
  State<ReturnHistoryScreen> createState() => _ReturnHistoryScreenState();
}

class _ReturnHistoryScreenState extends State<ReturnHistoryScreen> {
  List<Map<String, dynamic>> _returns = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await DBHelper.getSaleReturns();
      if (!mounted) return;
      setState(() {
        _returns = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Return history load nahi hui: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !Platform.isWindows,
        leading: desktopWorkspaceButton(),
        title: const Text('Customer Return History'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _returns.isEmpty
              ? const Center(child: Text('Abhi koi return record nahi hai.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: _returns.length,
                    itemBuilder: (context, index) {
                      final row = _returns[index];
                      final returnId = (row['id'] as num).toInt();
                      final amount = (row['refund_amount'] as num?)?.toDouble() ?? 0.0;
                      return Card(
                        child: ExpansionTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFE0F2F1),
                            child: Icon(Icons.assignment_return, color: Colors.teal),
                          ),
                          title: Text(
                            'Return #$returnId  |  Bill #${row['sale_id']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${row['customer_name'] ?? 'Walk-in'}  |  ${row['date']}\n'
                            'Rs. ${amount.toStringAsFixed(2)}  |  ${row['refund_method']}\n'
                            'Reason: ${row['reason']}',
                          ),
                          children: [
                            FutureBuilder<List<Map<String, dynamic>>>(
                              future: DBHelper.getSaleReturnItems(returnId),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: LinearProgressIndicator(),
                                  );
                                }
                                final items = snapshot.data ?? [];
                                if (items.isEmpty) {
                                  return const ListTile(title: Text('No item details.'));
                                }
                                return Column(
                                  children: items.map((item) => ListTile(
                                    dense: true,
                                    title: Text(item['product_name'].toString()),
                                    subtitle: Text(
                                      'Qty: ${item['quantity']}  |  ${item['condition'] == 'damaged' ? 'Damaged' : 'Resalable'}',
                                    ),
                                    trailing: Text(
                                      'Rs. ${((item['line_total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                                    ),
                                  )).toList(),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
