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

  Future<void> _showReturnDetails(Map<String, dynamic> row) async {
    final returnId = (row['id'] as num).toInt();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Return #$returnId  •  Bill #${row['sale_id']}'),
        content: SizedBox(
          width: 560,
          height: 380,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: DBHelper.getSaleReturnItems(returnId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snapshot.data ?? [];
              if (items.isEmpty) return const Center(child: Text('No item details.'));
              return ListView(
                children: items.map((item) => ListTile(
                  title: Text(item['product_name']?.toString() ?? 'Product'),
                  subtitle: Text('Qty: ${item['quantity']}  •  ${item['condition'] == 'damaged' ? 'Damaged' : 'Resalable'}'),
                  trailing: Text('Rs. ${((item['line_total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'),
                )).toList(),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
      ),
    );
  }

  Widget _buildDesktopReturns() {
    if (_returns.isEmpty) return const Center(child: Text('Abhi koi return record nahi hai.'));
    final total = _returns.fold<double>(0, (sum, row) => sum + ((row['refund_amount'] as num?)?.toDouble() ?? 0));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(child: Text('Customer Returns', style: Theme.of(context).textTheme.titleLarge)),
                  Text('${_returns.length} returns  •  Rs. ${total.toStringAsFixed(2)} refunded', style: Theme.of(context).textTheme.bodySmall),
                  IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  child: DataTable(
                  headingRowHeight: 42,
                  dataRowMinHeight: 42,
                  dataRowMaxHeight: 54,
                  columns: const [
                    DataColumn(label: Text('Return')),
                    DataColumn(label: Text('Bill')),
                    DataColumn(label: Text('Customer')),
                    DataColumn(label: Text('Date / Time')),
                    DataColumn(label: Text('Refund Amount'), numeric: true),
                    DataColumn(label: Text('Method')),
                    DataColumn(label: Text('Reason')),
                    DataColumn(label: Text('Details')),
                  ],
                  rows: _returns.map((row) {
                    final amount = (row['refund_amount'] as num?)?.toDouble() ?? 0;
                    return DataRow(cells: [
                      DataCell(Text('#${row['id']}')),
                      DataCell(Text('#${row['sale_id']}')),
                      DataCell(Text('${row['customer_name'] ?? 'Walk-in'}')),
                      DataCell(Text('${row['date'] ?? ''}')),
                      DataCell(Text('Rs. ${amount.toStringAsFixed(2)}')),
                      DataCell(Text('${row['refund_method'] ?? ''}')),
                      DataCell(SizedBox(width: 220, child: Text('${row['reason'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis))),
                      DataCell(TextButton(onPressed: () => _showReturnDetails(row), child: const Text('View items'))),
                    ]);
                  }).toList(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !Platform.isWindows,
        leading: desktopWorkspaceButton(),
        title: const Text('Customer Return History'),
        backgroundColor: Platform.isWindows ? const Color(0xFFF7F9FB) : Colors.teal,
        foregroundColor: Platform.isWindows ? const Color(0xFF263442) : Colors.white,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Platform.isWindows
              ? _buildDesktopReturns()
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
