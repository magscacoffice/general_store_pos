import 'windows/desktop_app_bar.dart';
import 'dart:io';
import 'package:flutter/material.dart';

import 'db_helper.dart';
import 'customer_history_screen.dart';

class CustomerKhataScreen extends StatefulWidget {
  const CustomerKhataScreen({super.key});
  @override
  State<CustomerKhataScreen> createState() => _CustomerKhataScreenState();
}

class _CustomerKhataScreenState extends State<CustomerKhataScreen> {
  List<Map<String, dynamic>> customers = [];
  bool busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final x = await DBHelper.getParties('customer');
    if (mounted) setState(() => customers = x);
  }

  Future<void> _receipt(Map<String, dynamic> c) async {
    final amount = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Receipt: ${c['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Received amount (Rs.)',
              ),
            ),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save receipt'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final a = double.tryParse(amount.text) ?? 0;
    if (a <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Enter a valid amount.')));
      }
      return;
    }
    try {
      await DBHelper.recordKhataReceipt(
        partyId: c['id'] as int,
        amount: a,
        note: note.text.trim(),
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Receipt saved; customer balance reduced.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      amount.dispose();
      note.dispose();
    }
  }

  Widget _buildDesktopKhata() {
    if (customers.isEmpty) return const Center(child: Text('No customers found. Add customers in Party screen.'));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(child: Text('Customer Khata Ledger', style: Theme.of(context).textTheme.titleLarge)),
                  Text('${customers.length} accounts', style: Theme.of(context).textTheme.bodySmall),
                  IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                child: DataTable(
                  headingRowHeight: 42,
                  dataRowMinHeight: 42,
                  dataRowMaxHeight: 52,
                  columns: const [
                    DataColumn(label: Text('Customer')),
                    DataColumn(label: Text('Phone')),
                    DataColumn(label: Text('Outstanding Balance'), numeric: true),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: customers.map((customer) {
                    final balance = (customer['balance'] as num?)?.toDouble() ?? 0;
                    return DataRow(
                      onSelectChanged: (_) async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => CustomerHistoryScreen(customer: customer)),
                        );
                        await _load();
                      },
                      cells: [
                        DataCell(SizedBox(
                          width: 220,
                          child: Text(customer['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                        )),
                        DataCell(Text(customer['phone']?.toString() ?? '—')),
                        DataCell(Text('Rs. ${balance.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'View ledger',
                              icon: const Icon(Icons.receipt_long_outlined),
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => CustomerHistoryScreen(customer: customer)),
                                );
                                await _load();
                              },
                            ),
                            IconButton(
                              tooltip: 'Record receipt',
                              icon: const Icon(Icons.payments_outlined, color: Colors.green),
                              onPressed: () => _receipt(customer),
                            ),
                          ],
                        )),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
        automaticallyImplyLeading: !Platform.isWindows,
        leading: desktopWorkspaceButton(),
      title: const Text('Customer Khata'),
      backgroundColor: Platform.isWindows ? const Color(0xFFF7F9FB) : Colors.teal,
      foregroundColor: Platform.isWindows ? const Color(0xFF263442) : Colors.white,
    ),
    body: Platform.isWindows
        ? _buildDesktopKhata()
        : RefreshIndicator(
      onRefresh: _load,
      child: customers.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 180),
                Center(
                  child: Text(
                    'No customers found. Add customers in Party screen.',
                  ),
                ),
              ],
            )
          : ListView.builder(
              itemCount: customers.length,
              itemBuilder: (ctx, i) {
                final c = customers[i];
                final b = (c['balance'] as num?)?.toDouble() ?? 0;
                return Card(
                  child: ListTile(
                    title: Text('${c['name']}'),
                    subtitle: Text(
                      'Khata Customer  |  ${c['phone'] ?? ''}\nBalance: Rs. ${b.toStringAsFixed(2)}',
                    ),
                    isThreeLine: true,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CustomerHistoryScreen(customer: c),
                        ),
                      );
                      await _load();
                    },
                    trailing: IconButton(
                      tooltip: 'Record receipt',
                      icon: const Icon(Icons.payments),
                      onPressed: () => _receipt(c),
                    ),
                  ),
                );
              },
            ),
    ),
  );
}
