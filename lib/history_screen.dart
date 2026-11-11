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

  Future<void> _openReturn(Map<String, dynamic> sale) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SaleReturnScreen(sale: sale)),
    );
    await _loadSales();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !Platform.isWindows,
        leading: desktopWorkspaceButton(),
        title: const Text('Sale History'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
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
