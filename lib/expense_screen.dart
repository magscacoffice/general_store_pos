import 'windows/desktop_app_bar.dart';
import 'dart:io';
import 'package:flutter/material.dart';

import 'db_helper.dart';

class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  List<Map<String, dynamic>> _expenses = [];

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    final data = await DBHelper.getExpenses();
    if (!mounted) return;
    setState(() {
      _expenses = data;
    });
  }

  void _showAddExpenseDialog() {
    final titleController = TextEditingController();
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add New Expense'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Kharchay ki Wajah (Title)',
              ),
            ),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final title = titleController.text.trim();
              final amount = double.tryParse(amountController.text.trim());
              if (title.isEmpty || amount == null || !amount.isFinite || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Title aur positive valid amount darj karein.')),
                );
                return;
              }
              await DBHelper.insertExpense({
                  'title': title,
                  'amount': amount,
                  'date': DateTime.now().toString().substring(0, 16),
              });
              await _loadExpenses();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopExpenses() {
    if (_expenses.isEmpty) return const Center(child: Text('No expenses recorded yet.'));
    final total = _expenses.fold<double>(
      0,
      (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0),
    );
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
                  Expanded(child: Text('Expense Register', style: Theme.of(context).textTheme.titleLarge)),
                  Text('${_expenses.length} entries  •  Total Rs. ${total.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodySmall),
                  IconButton(tooltip: 'Refresh', onPressed: _loadExpenses, icon: const Icon(Icons.refresh)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                child: DataTable(
                  headingRowHeight: 42,
                  dataRowMinHeight: 40,
                  dataRowMaxHeight: 48,
                  columns: const [
                    DataColumn(label: Text('Expense Description')),
                    DataColumn(label: Text('Date / Time')),
                    DataColumn(label: Text('Amount'), numeric: true),
                  ],
                  rows: _expenses.map((expense) => DataRow(cells: [
                    DataCell(SizedBox(width: 360, child: Text('${expense['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis))),
                    DataCell(Text('${expense['date'] ?? ''}')),
                    DataCell(Text('Rs. ${((expense['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600))),
                  ])).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !Platform.isWindows,
        leading: desktopWorkspaceButton(),
        title: const Text('Rozmarra Kharchay (Expenses)'),
        backgroundColor: Platform.isWindows ? const Color(0xFFF7F9FB) : Colors.red,
        foregroundColor: Platform.isWindows ? const Color(0xFF263442) : Colors.white,
      ),
      body: Platform.isWindows
          ? _buildDesktopExpenses()
          : _expenses.isEmpty
              ? const Center(child: Text('No expenses recorded yet.'))
              : ListView.builder(
                  itemCount: _expenses.length,
                  itemBuilder: (context, index) {
                    final exp = _expenses[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        title: Text(exp['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Waqt: ${exp['date']}'),
                        trailing: Text(
                          'Rs. ${exp['amount']}',
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: Platform.isWindows ? FloatingActionButton.extended(
        onPressed: _showAddExpenseDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ) : FloatingActionButton(
        onPressed: _showAddExpenseDialog,
        backgroundColor: Colors.red,
        child: const Icon(Icons.money_off),
      ),
    );
  }
}
