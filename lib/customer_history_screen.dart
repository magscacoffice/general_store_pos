import 'windows/desktop_app_bar.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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
  DateTimeRange? _statementRange;

  DateTime? _parsedEntryDate(Map<String, dynamic> entry) =>
      DateTime.tryParse(entry['date']?.toString() ?? '');

  double _entryBalanceChange(Map<String, dynamic> entry) {
    final amount = (entry['amount'] as num?)?.toDouble() ?? 0;
    return entry['entry_type']?.toString() == 'sale' ? amount : -amount;
  }

  Future<void> _chooseStatementRange() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _statementRange,
    );
    if (selected != null && mounted) {
      setState(() => _statementRange = selected);
    }
  }

  Future<void> _shareStatement({bool completeHistory = false}) async {
    if (loading) return;
    final range = completeHistory ? null : _statementRange;
    final all = List<Map<String, dynamic>>.from(entries);
    final start = range == null
        ? null
        : DateTime(range.start.year, range.start.month, range.start.day);
    final endExclusive = range == null
        ? null
        : DateTime(range.end.year, range.end.month, range.end.day + 1);

    final chronological = all.where((entry) {
      if (range == null) return true;
      final date = _parsedEntryDate(entry);
      return date != null && !date.isBefore(start!) && date.isBefore(endExclusive!);
    }).toList()
      ..sort((a, b) {
        final dateCompare = (_parsedEntryDate(a) ?? DateTime(1970))
            .compareTo(_parsedEntryDate(b) ?? DateTime(1970));
        return dateCompare != 0
            ? dateCompare
            : ((a['entry_id'] as num?)?.toInt() ?? 0)
                .compareTo((b['entry_id'] as num?)?.toInt() ?? 0);
      });

    if (chronological.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected period mein koi ledger entry nahi hai.')),
      );
      return;
    }

    final currentBalance =
        (widget.customer['balance'] as num?)?.toDouble() ?? 0;
    final movementFromPeriodStart = all.where((entry) {
      final date = _parsedEntryDate(entry);
      return date != null && (start == null || !date.isBefore(start));
    }).fold<double>(
      0, (sum, entry) => sum + _entryBalanceChange(entry),
    );
    // Reconcile the visible ledger with the saved account balance. This also
    // preserves any legacy opening balance that predates transaction history.
    final openingBalance = currentBalance - movementFromPeriodStart;
    var runningBalance = openingBalance;
    final tableRows = <List<String>>[];

    for (final entry in chronological) {
      final type = entry['entry_type']?.toString() ?? '';
      final amount = (entry['amount'] as num?)?.toDouble() ?? 0;
      final isSale = type == 'sale';
      var description = entry['description']?.toString() ?? type;
      if (isSale) {
        final saleItems = await DBHelper.getSaleItems(
          (entry['entry_id'] as num).toInt(),
        );
        if (saleItems.isNotEmpty) {
          final itemText = saleItems.map((item) {
            final name = item['product_name']?.toString() ?? 'Product';
            final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
            final rate = (item['sale_price'] as num?)?.toDouble() ?? 0;
            final lineTotal = (item['line_total'] as num?)?.toDouble() ?? quantity * rate;
            return '$name x${quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 2)} @ Rs. ${rate.toStringAsFixed(2)} = Rs. ${lineTotal.toStringAsFixed(2)}';
          }).join('\n');
          description = '$description\n$itemText';
        }
      }
      runningBalance += _entryBalanceChange(entry);
      final date = _parsedEntryDate(entry);
      tableRows.add([
        date == null ? '' : _date(date.toIso8601String()),
        description,
        isSale ? 'Credit Sale' : (type == 'receipt' ? 'Cash Receipt' : type),
        isSale ? amount.toStringAsFixed(2) : '',
        isSale ? '' : amount.toStringAsFixed(2),
        runningBalance.toStringAsFixed(2),
      ]);
    }

    final pdf = pw.Document();
    final periodText = range == null
        ? 'Complete history'
        : '${range.start.day.toString().padLeft(2, '0')}-${range.start.month.toString().padLeft(2, '0')}-${range.start.year} to ${range.end.day.toString().padLeft(2, '0')}-${range.end.month.toString().padLeft(2, '0')}-${range.end.year}';
    pdf.addPage(pw.MultiPage(
      build: (_) => [
        pw.Text('KHAN BABA GENERAL STORE',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Customer Khata Statement',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Text('Customer: ${widget.customer['name'] ?? 'Customer'}'),
        pw.Text('Phone: ${widget.customer['phone'] ?? ''}'),
        pw.Text('Period: $periodText'),
        pw.SizedBox(height: 8),
        pw.Text('Opening Balance: Rs. ${openingBalance.toStringAsFixed(2)}'),
        pw.Text('Closing Balance: Rs. ${runningBalance.toStringAsFixed(2)}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),
        pw.Table.fromTextArray(
          headers: const ['Date / Time', 'Description / Items', 'Type', 'Debit', 'Credit', 'Balance'],
          data: tableRows,
          headerStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 6),
          cellAlignment: pw.Alignment.centerLeft,
          columnWidths: {
            0: const pw.FlexColumnWidth(1.5),
            1: const pw.FlexColumnWidth(4.5),
            2: const pw.FlexColumnWidth(1.4),
            3: const pw.FlexColumnWidth(1),
            4: const pw.FlexColumnWidth(1),
            5: const pw.FlexColumnWidth(1),
          },
        ),
      ],
    ));
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'khata-${widget.customer['id']}-statement.pdf',
    );
  }

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
                            : Scrollbar(
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
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
        actions: [
          IconButton(
            tooltip: 'Select statement date range',
            onPressed: _chooseStatementRange,
            icon: const Icon(Icons.date_range),
          ),
          IconButton(
            tooltip: 'Share selected-period Khata PDF',
            onPressed: () => _shareStatement(),
            icon: const Icon(Icons.share),
          ),
          PopupMenuButton<String>(
            tooltip: 'Complete ledger',
            onSelected: (_) => _shareStatement(completeHistory: true),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'complete',
                child: Text('Share complete ledger PDF'),
              ),
            ],
          ),
        ],
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
