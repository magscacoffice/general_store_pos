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

  @override
  Widget build(BuildContext context) {
    final balance = (widget.customer['balance'] as num?)?.toDouble() ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.customer['name']} - History'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Column(
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
                          separatorBuilder: (_, __) => const SizedBox(height: 2),
                          itemBuilder: (context, index) {
                            final e = entries[index];
                            final type = e['entry_type']?.toString() ?? '';
                            final isReceipt = type == 'receipt';
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
                                    Text(isReceipt ? 'Jama' : (isSale ? 'Khata Sale' : type),
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
