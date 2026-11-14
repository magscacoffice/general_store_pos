import 'windows/desktop_app_bar.dart';
import 'dart:io';
import 'package:flutter/material.dart';

import 'db_helper.dart';
import 'printer_screen.dart';
import 'sale_return_screen.dart';
import 'return_history_screen.dart';

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

  Future<void> _loadSales() async {
    final data = await DBHelper.getSales();
    if (!mounted) return;
    setState(() {
      _sales = data;
    });
  }

  Future<void> _reprintSale(Map<String, dynamic> sale) async {
    final saleId = (sale['id'] as num).toInt();
    final storedItems = await DBHelper.getSaleItems(saleId);
    if (!mounted) return;
    if (storedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Is invoice ki item details available nahi hain.')),
      );
      return;
    }
    final customerId = (sale['customer_id'] as num?)?.toInt();
    final customer = customerId == null ? null : await DBHelper.getPartyById(customerId);
    if (!mounted) return;
    final items = storedItems.map((item) {
      final name = (item['product_name'] ?? item['name'] ?? 'Product').toString();
      final rate = item['sale_price'] ?? item['salePrice'] ?? item['price'] ?? 0;
      final quantity = item['quantity'] ?? item['qty'] ?? 0;
      return <String, dynamic>{
        'barcode': item['barcode']?.toString() ?? '',
        'name': name, 'product_name': name,
        'quantity': quantity,
        'salePrice': rate, 'sale_price': rate,
        'purchasePrice': item['purchase_price'] ?? item['purchasePrice'] ?? 0,
      };
    }).toList();
    final total = (sale['effective_amount'] as num?)?.toDouble() ??
        (sale['final_amount'] as num?)?.toDouble() ??
        (sale['total_amount'] as num?)?.toDouble() ?? 0.0;
    final received = (sale['effective_received_amount'] as num?)?.toDouble() ??
        (sale['received_amount'] as num?)?.toDouble() ??
        ((sale['payment_type']?.toString() ?? 'Cash') == 'Cash' ? total : 0.0);
    final due = (sale['effective_balance_due'] as num?)?.toDouble() ??
        (sale['balance_due'] as num?)?.toDouble() ??
        (total - received).clamp(0.0, double.infinity).toDouble();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrinterScreen(
          cartItems: items,
          totalAmount: total,
          customerName: customer?['name']?.toString() ?? 'Walk-in Customer',
          customerPhone: customer?['phone']?.toString() ?? '',
          invoiceId: saleId,
          subtotalAmount: (sale['total_amount'] as num?)?.toDouble() ?? total,
          discountAmount: (sale['discount'] as num?)?.toDouble() ?? 0.0,
          paymentType: sale['payment_type']?.toString() ?? 'Cash',
          receivedAmount: received,
          balanceDue: due,
          saleDate: sale['date']?.toString() ?? '',
          cashierName: sale['salesman_name']?.toString() ?? 'Admin',
          salesType: sale['customer_type']?.toString() ?? (customerId == null ? 'Retail' : 'Khata'),
        ),
      ),
    );
  }

  Future<void> _showInvoiceDetails(Map<String, dynamic> sale) async {
    final saleId = (sale['id'] as num).toInt();
    final storedItems = await DBHelper.getSaleItems(saleId);
    final customerId = (sale['customer_id'] as num?)?.toInt();
    final customer = customerId == null ? null : await DBHelper.getPartyById(customerId);
    if (!mounted) return;

    final total = (sale['effective_amount'] as num?)?.toDouble() ??
        (sale['final_amount'] as num?)?.toDouble() ??
        (sale['total_amount'] as num?)?.toDouble() ?? 0.0;
    final received = (sale['effective_received_amount'] as num?)?.toDouble() ??
        (sale['received_amount'] as num?)?.toDouble() ?? 0.0;
    final due = (sale['effective_balance_due'] as num?)?.toDouble() ??
        (sale['balance_due'] as num?)?.toDouble() ??
        (total - received).clamp(0.0, double.infinity).toDouble();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Invoice #$saleId Details'),
        content: SizedBox(
          width: MediaQuery.of(dialogContext).size.width * 0.8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Date / Time: ${sale['date'] ?? ''}\n'
                  'Customer: ${customer?['name'] ?? 'Walk-in Customer'}  |  '
                  'Type: ${sale['customer_type'] ?? 'Walk-in'}\n'
                  'Payment: ${sale['payment_type'] ?? 'Cash'}',
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: storedItems.isEmpty
                    ? const Center(child: Text('Is invoice ki item details available nahi hain.'))
                    : Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Product')),
                              DataColumn(label: Text('Qty'), numeric: true),
                              DataColumn(label: Text('Rate'), numeric: true),
                              DataColumn(label: Text('Amount'), numeric: true),
                            ],
                            rows: storedItems.map((item) {
                              final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
                              final rate = (item['sale_price'] as num?)?.toDouble() ?? 0;
                              final amount = (item['line_total'] as num?)?.toDouble() ?? quantity * rate;
                              return DataRow(cells: [
                                DataCell(SizedBox(
                                  width: 260,
                                  child: Text(
                                    item['product_name']?.toString() ?? 'Product',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )),
                                DataCell(Text(quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 2))),
                                DataCell(Text('Rs. ${rate.toStringAsFixed(2)}')),
                                DataCell(Text('Rs. ${amount.toStringAsFixed(2)}')),
                              ]);
                            }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ),
              const Divider(),
              Align(
                alignment: Alignment.centerRight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Subtotal: Rs. ${((sale['total_amount'] as num?)?.toDouble() ?? total).toStringAsFixed(2)}'),
                    Text('Discount: Rs. ${((sale['discount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'),
                    Text('Grand Total: Rs. ${total.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Received: Rs. ${received.toStringAsFixed(2)}'),
                    Text('Balance Due: Rs. ${due.toStringAsFixed(2)}'),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _reprintSale(sale);
            },
            icon: const Icon(Icons.print),
            label: const Text('Reprint'),
          ),
        ],
      ),
    );
  }

  Future<void> _openReturn(Map<String, dynamic> sale) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SaleReturnScreen(sale: sale)),
    );
    await _loadSales();
  }

  Widget _buildDesktopSalesTable() {
    if (_sales.isEmpty) return const Center(child: Text('No sales records found yet.'));
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
                  Expanded(child: Text('Invoices', style: Theme.of(context).textTheme.titleLarge)),
                  Text('${_sales.length} records', style: Theme.of(context).textTheme.bodySmall),
                  IconButton(tooltip: 'Refresh', onPressed: _loadSales, icon: const Icon(Icons.refresh)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      child: DataTable(
                      headingRowHeight: 42,
                      dataRowMinHeight: 42,
                      dataRowMaxHeight: 54,
                      columns: const [
                        DataColumn(label: Text('Invoice')),
                        DataColumn(label: Text('Date / Time')),
                        DataColumn(label: Text('Customer Type')),
                        DataColumn(label: Text('Payment')),
                        DataColumn(label: Text('Net Total'), numeric: true),
                        DataColumn(label: Text('Received'), numeric: true),
                        DataColumn(label: Text('Balance Due'), numeric: true),
                        DataColumn(label: Text('Returned'), numeric: true),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: _sales.map((sale) {
                        final amount = (sale['effective_amount'] as num?)?.toDouble()
                            ?? (sale['final_amount'] as num?)?.toDouble()
                            ?? (sale['total_amount'] as num?)?.toDouble() ?? 0.0;
                        final received = (sale['effective_received_amount'] as num?)?.toDouble()
                            ?? (sale['received_amount'] as num?)?.toDouble() ?? 0.0;
                        final due = (sale['effective_balance_due'] as num?)?.toDouble()
                            ?? (sale['balance_due'] as num?)?.toDouble() ?? 0.0;
                        final returned = (sale['returned_amount'] as num?)?.toDouble() ?? 0.0;
                        return DataRow(cells: [
                          DataCell(Text('#${sale['id']}', style: const TextStyle(fontWeight: FontWeight.w600)), onTap: () => _showInvoiceDetails(sale)),
                          DataCell(Text('${sale['date'] ?? ''}')),
                          DataCell(Text('${sale['customer_type'] ?? 'Walk-in'}')),
                          DataCell(Text('${sale['payment_type'] ?? 'Cash'}')),
                          DataCell(Text('Rs. ${amount.toStringAsFixed(2)}')),
                          DataCell(Text('Rs. ${received.toStringAsFixed(2)}')),
                          DataCell(Text('Rs. ${due.toStringAsFixed(2)}')),
                          DataCell(Text('Rs. ${returned.toStringAsFixed(2)}')),
                          DataCell(PopupMenuButton<String>(
                            tooltip: 'Invoice actions',
                            onSelected: (value) {
                              if (value == 'reprint') _reprintSale(sale);
                              if (value == 'return') _openReturn(sale);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'reprint', child: Text('Reprint Bill')),
                              PopupMenuItem(value: 'return', child: Text('Return Items')),
                            ],
                          )),
                        ]);
                      }).toList(),
                      ),
                    ),
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
        title: const Text('Sale History'),
        backgroundColor: Platform.isWindows ? const Color(0xFFF7F9FB) : Colors.purple,
        foregroundColor: Platform.isWindows ? const Color(0xFF263442) : Colors.white,
        actions: [
          IconButton(
            tooltip: 'Return History',
            icon: const Icon(Icons.assignment_return),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ReturnHistoryScreen()));
            },
          ),
        ],
      ),
      body: Platform.isWindows
          ? _buildDesktopSalesTable()
          : _sales.isEmpty
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
                    onTap: () => _showInvoiceDetails(sale),
                    leading: const CircleAvatar(
                      backgroundColor: Colors.purple,
                      child: Icon(Icons.receipt, color: Colors.white),
                    ),
                    title: Text(
                      'Bill Total: Rs. ${sale['effective_amount'] ?? sale['final_amount'] ?? sale['total_amount']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Invoice #${sale['id']}  |  Waqt: ${sale['date']}\n'
                      'Payment: ${sale['payment_type'] ?? 'Cash'}  |  '
                      'Received: Rs. ${((sale['effective_received_amount'] as num?)?.toDouble() ?? (sale['received_amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}  |  '
                      'Due: Rs. ${((sale['effective_balance_due'] as num?)?.toDouble() ?? (sale['balance_due'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'
                      '${((sale['returned_amount'] as num?)?.toDouble() ?? 0) > 0 ? '\nReturned: Rs. ${((sale['returned_amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}' : ''}',
                    ),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Bill options',
                      onSelected: (value) {
                        if (value == 'reprint') _reprintSale(sale);
                        if (value == 'return') _openReturn(sale);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'reprint', child: Text('Reprint Bill')),
                        PopupMenuItem(value: 'return', child: Text('Return Items')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
