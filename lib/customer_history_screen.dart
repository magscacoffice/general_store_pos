import 'windows/desktop_app_bar.dart';
import 'dart:io';
import 'package:flutter/material.dart';

import 'db_helper.dart';

class CustomerHistoryScreen extends StatefulWidget {
  final Map<String, dynamic> customer;
  const CustomerHistoryScreen({super.key, required this.customer});

  @override
  State<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<CustomerHistoryScreen> {
  List<Map<String, dynamic>> entries = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await DBHelper.getCustomerHistory(widget.customer['id'] as int);
    if (!mounted) return;
    setState(() {
      entries = rows;
      loading = false;
    });
  }

  String _date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return value?.toString() ?? '';
    final d = parsed.toLocal();
    return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildDesktopCustomerHistory(double balance) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.customer['name']?.toString() ?? 'Customer', style: Theme.of(context).textTheme.titleMedium),
                        Text(widget.customer['phone']?.toString() ?? 'No phone number', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Outstanding Balance', style: Theme.of(context).textTheme.bodySmall),
                      Text('Rs. ${balance.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.teal)),
                    ],
                  ),
                  IconButton(tooltip: 'Refresh ledger', onPressed: _load, icon: const Icon(Icons.refresh)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              margin: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text('Account Transactions  •  ${entries.length} entries', style: Theme.of(context).textTheme.titleMedium),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : entries.isEmpty
                            ? const Center(child: Text('Is customer ki abhi koi history nahi hai.'))
                            : SingleChildScrollView(
                                child: DataTable(
                                  headingRowHeight: 42,
                                  dataRowMinHeight: 40,
                                  dataRowMaxHeight: 54,
                                  columns: const [
                                    DataColumn(label: Text('Date / Time')),
                                    DataColumn(label: Text('Description')),
                                    DataColumn(label: Text('Transaction Type')),
                                    DataColumn(label: Text('Amount'), numeric: true),
                                  ],
                                  rows: entries.map((entry) {
                                    final type = entry['entry_type']?.toString() ?? '';
                                    final isReceipt = type == 'receipt' || type == 'return_adjustment';
                                    final isSale = type == 'sale';
                                    final amount = (entry['amount'] as num?)?.toDouble() ?? 0;
                                    final label = type == 'return_adjustment'
                                        ? 'Return Adjustment'
                                        : isReceipt ? 'Receipt / Jama' : isSale ? 'Khata Sale' : type;
                                    return DataRow(cells: [
                                      DataCell(Text(_date(entry['date']))),
                                      DataCell(SizedBox(width: 340, child: Text(entry['description']?.toString() ?? type, maxLines: 1, overflow: TextOverflow.ellipsis))),
                                      DataCell(Text(label)),
                                      DataCell(Text(
                                        'Rs. ${amount.toStringAsFixed(2)}',
                                        style: TextStyle(fontWeight: FontWeight.w600, color: isReceipt ? Colors.green : Colors.red),
                                      )),
                                    ]);
                                  }).toList(),
                                ),
                              ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final balance = (widget.customer['balance'] as num?)?.toDouble() ?? 0;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !Platform.isWindows,
        leading: desktopWorkspaceButton(),
        title: Text('${widget.customer['name']} - History'),
        backgroundColor: Platform.isWindows ? const Color(0xFFF7F9FB) : Colors.teal,
        foregroundColor: Platform.isWindows ? const Color(0xFF263442) : Colors.white,
      ),
      body: Platform.isWindows
          ? _buildDesktopCustomerHistory(balance)
          : Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.account_balance_wallet)),
              title: const Text('Current Khata Balance'),
              subtitle: Text(widget.customer['phone']?.toString() ?? ''),
              trailing: Text(
                'Rs. ${balance.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal),
              ),
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : entries.isEmpty
                    ? const Center(child: Text('Is customer ki abhi koi history nahi hai.'))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 2),
                          itemBuilder: (context, index) {
                            final e = entries[index];
                            final type = e['entry_type']?.toString() ?? '';
                            final isReceipt = type == 'receipt' || type == 'return_adjustment';
                            final amount = (e['amount'] as num?)?.toDouble() ?? 0;
                            final isSale = type == 'sale';
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isReceipt ? Colors.green.shade50 : Colors.teal.shade50,
                                  child: Icon(
                                    isReceipt ? Icons.payments : (isSale ? Icons.shopping_cart : Icons.receipt_long),
                                    color: isReceipt ? Colors.green : Colors.teal,
                                  ),
                                ),
                                title: Text(e['description']?.toString() ?? type,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(_date(e['date'])),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('Rs. ${amount.toStringAsFixed(2)}',
                                      style: TextStyle(fontWeight: FontWeight.bold,
                                        color: isReceipt ? Colors.green : Colors.red)),
                                    Text(type == 'return_adjustment' ? 'Return Adjustment' : (isReceipt ? 'Jama' : (isSale ? 'Khata Sale' : type)),
                                      style: const TextStyle(fontSize: 11)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
