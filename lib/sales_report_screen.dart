import 'windows/desktop_app_bar.dart';
import 'dart:io';
import 'package:flutter/material.dart';

import 'db_helper.dart';

class SalesReportScreen extends StatefulWidget {
  const SalesReportScreen({super.key});

  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  List<Map<String, dynamic>> _sales = [];
  bool _loading = true;
  String _period = 'Daily';

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    try {
      final data = await DBHelper.getSales();
      if (!mounted) return;
      setState(() {
        _sales = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not load sales: $e')));
    }
  }

  DateTime? _saleDate(Map<String, dynamic> sale) {
    return DateTime.tryParse('${sale['date'] ?? ''}');
  }

  List<Map<String, dynamic>> get _filteredSales {
    final now = DateTime.now();

    return _sales.where((sale) {
      final date = _saleDate(sale);
      if (date == null) return false;

      if (_period == 'Daily') {
        return date.year == now.year &&
            date.month == now.month &&
            date.day == now.day;
      }

      if (_period == 'Monthly') {
        return date.year == now.year && date.month == now.month;
      }

      return date.year == now.year;
    }).toList();
  }

  double _amount(Map<String, dynamic> sale) {
    final gross = (sale['effective_amount'] as num?)?.toDouble() ??
        ((sale['final_amount'] as num?)?.toDouble() ?? 0.0);
    final returned = (sale['returned_amount'] as num?)?.toDouble() ?? 0.0;
    return (gross - returned).clamp(0.0, double.infinity).toDouble();
  }

  double get _totalRevenue =>
      _filteredSales.fold(0.0, (sum, sale) => sum + _amount(sale));

  double get _totalDiscount => _filteredSales.fold(
        0.0,
        (sum, sale) => sum + ((sale['discount'] as num?)?.toDouble() ?? 0.0),
      );

  double get _totalReturned => _filteredSales.fold(
        0.0,
        (sum, sale) => sum + ((sale['returned_amount'] as num?)?.toDouble() ?? 0.0),
      );

  int get _totalReturnsCount => _filteredSales.fold(
        0,
        (sum, sale) => sum + ((sale['returned_count'] as num?)?.toInt() ?? 0),
      );

  String _money(double amount) => 'Rs. ${amount.toStringAsFixed(2)}';

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildDesktopReport(List<Map<String, dynamic>> sales) {
    Widget metric(String label, String value, IconData icon) => Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 3),
                    Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text('Sales Performance', style: Theme.of(context).textTheme.titleLarge)),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Daily', label: Text('Daily')),
                  ButtonSegment(value: 'Monthly', label: Text('Monthly')),
                  ButtonSegment(value: 'Yearly', label: Text('Yearly')),
                ],
                selected: {_period},
                onSelectionChanged: (selection) => setState(() => _period = selection.first),
              ),
              const SizedBox(width: 8),
              IconButton(tooltip: 'Refresh', onPressed: _loadSales, icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              metric('Net Sales', _money(_totalRevenue), Icons.payments_outlined),
              const SizedBox(width: 10),
              metric('Bills', '${sales.length}', Icons.receipt_long_outlined),
              const SizedBox(width: 10),
              metric('Discounts', _money(_totalDiscount), Icons.discount_outlined),
              const SizedBox(width: 10),
              metric('Returns', _money(_totalReturned), Icons.assignment_return_outlined),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              margin: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    child: Row(
                      children: [
                        Expanded(child: Text('$_period Transactions', style: Theme.of(context).textTheme.titleMedium)),
                        Text('${_totalReturnsCount} return entries', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: sales.isEmpty
                        ? const Center(child: Text('No sales recorded for this period.'))
                        : Scrollbar(
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SingleChildScrollView(
                                child: DataTable(
                                  headingRowHeight: 40,
                                  dataRowMinHeight: 38,
                                  dataRowMaxHeight: 48,
                                  columns: const [
                                    DataColumn(label: Text('Invoice')),
                                    DataColumn(label: Text('Date / Time')),
                                    DataColumn(label: Text('Payment')),
                                    DataColumn(label: Text('Discount'), numeric: true),
                                    DataColumn(label: Text('Returned'), numeric: true),
                                    DataColumn(label: Text('Net Amount'), numeric: true),
                                  ],
                                  rows: sales.map((sale) => DataRow(cells: [
                                    DataCell(Text('#${sale['id']}')),
                                    DataCell(Text('${sale['date'] ?? ''}')),
                                    DataCell(Text('${sale['payment_type'] ?? 'Cash'}')),
                                    DataCell(Text(_money((sale['discount'] as num?)?.toDouble() ?? 0))),
                                    DataCell(Text(_money((sale['returned_amount'] as num?)?.toDouble() ?? 0))),
                                    DataCell(Text(_money(_amount(sale)), style: const TextStyle(fontWeight: FontWeight.w600))),
                                  ])).toList(),
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
    final sales = _filteredSales;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !Platform.isWindows,
        leading: desktopWorkspaceButton(),
        title: const Text('Sales Reports / سیل رپورٹ'),
        backgroundColor: Platform.isWindows ? const Color(0xFFF7F9FB) : Colors.teal,
        foregroundColor: Platform.isWindows ? const Color(0xFF263442) : Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadSales,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Platform.isWindows
              ? _buildDesktopReport(sales)
              : RefreshIndicator(
              onRefresh: _loadSales,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Daily', label: Text('Daily')),
                      ButtonSegment(value: 'Monthly', label: Text('Monthly')),
                      ButtonSegment(value: 'Yearly', label: Text('Yearly')),
                    ],
                    selected: {_period},
                    onSelectionChanged: (selection) {
                      setState(() => _period = selection.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  Card(
                    color: Colors.teal.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          Icon(
                            Icons.payments,
                            size: Platform.isWindows ? 20 : 38,
                            color: Colors.teal,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _money(_totalRevenue),
                            style: TextStyle(
                              fontSize: Platform.isWindows ? 16 : 25,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                          const Text('Net Sales (discount aur returns ke baad)'),
                          const Divider(height: 24),
                          _summaryRow('Bills', '${sales.length}'),
                          _summaryRow('Discount', _money(_totalDiscount)),
                          _summaryRow('Returns', '${_totalReturnsCount}  |  ${_money(_totalReturned)}'),
                          _summaryRow('Net Sales', _money(_totalRevenue)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$_period Sales',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (sales.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text('No sales recorded for this period.'),
                        ),
                      ),
                    )
                  else
                    ...sales.map((sale) {
                      final amount = _amount(sale);
                      final date = sale['date']?.toString() ?? '';
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.teal,
                            child: Icon(
                              Icons.receipt_long,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            'Bill #${sale['id']}  |  ${_money(amount)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Date: $date  |  Payment: ${sale['payment_type'] ?? 'Cash'}\n'
                            'Discount: ${_money((sale['discount'] as num?)?.toDouble() ?? 0)}  |  '
                            'Returned: ${_money((sale['returned_amount'] as num?)?.toDouble() ?? 0)}',
                          ),
                          isThreeLine: true,
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
