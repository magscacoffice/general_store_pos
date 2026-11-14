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
  List<Map<String, dynamic>> _purchases = [];
  List<Map<String, dynamic>> _expenses = [];
  bool _loading = true;
  String _period = 'Daily';
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    try {
      final data = await DBHelper.getSales();
      final purchases = await DBHelper.getPurchases();
      final expenses = await DBHelper.getExpenses();
      if (!mounted) return;
      setState(() {
        _sales = data;
        _purchases = purchases;
        _expenses = expenses;
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

  bool _matchesPeriod(DateTime date) {
    final now = DateTime.now();
    if (_period == 'Custom') {
      final range = _customRange;
      if (range == null) return false;
      final start = DateTime(range.start.year, range.start.month, range.start.day);
      final endExclusive = DateTime(range.end.year, range.end.month, range.end.day + 1);
      return !date.isBefore(start) && date.isBefore(endExclusive);
    }
    if (_period == 'Daily') {
      return date.year == now.year && date.month == now.month && date.day == now.day;
    }
    if (_period == 'Monthly') {
      return date.year == now.year && date.month == now.month;
    }
    return date.year == now.year;
  }

  Future<void> _chooseCustomRange() async {
    final now = DateTime.now();
    final initial = _customRange ?? DateTimeRange(
      start: DateTime(now.year, now.month, now.day),
      end: DateTime(now.year, now.month, now.day),
    );
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initial,
    );
    if (selected != null && mounted) {
      setState(() {
        _customRange = selected;
        _period = 'Custom';
      });
    }
  }

  List<Map<String, dynamic>> get _filteredSales => _sales.where((sale) {
    final date = _saleDate(sale);
    return date != null && _matchesPeriod(date);
  }).toList();

  List<Map<String, dynamic>> get _filteredPurchases => _purchases.where((purchase) {
    final date = DateTime.tryParse('${purchase['invoice_date'] ?? ''}') ??
        DateTime.tryParse('${purchase['date'] ?? ''}');
    return date != null && _matchesPeriod(date);
  }).toList();

  List<Map<String, dynamic>> get _filteredExpenses => _expenses.where((expense) {
    final date = DateTime.tryParse('${expense['date'] ?? ''}');
    return date != null && _matchesPeriod(date);
  }).toList();

  double get _totalPurchases => _filteredPurchases.fold(
    0, (sum, item) => sum + ((item['total_cost'] as num?)?.toDouble() ?? 0),
  );

  double get _totalExpenses => _filteredExpenses.fold(
    0, (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0),
  );

  double get _netCashMovement => _totalRevenue - _totalPurchases - _totalExpenses;

  List<Map<String, dynamic>> get _dailyBreakdown {
    final days = <String, Map<String, double>>{};
    void add(String? rawDate, String key, double amount) {
      final date = DateTime.tryParse(rawDate ?? '');
      if (date == null) return;
      final day = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final values = days.putIfAbsent(day, () => {'sales': 0, 'purchases': 0, 'expenses': 0});
      values[key] = (values[key] ?? 0) + amount;
    }
    for (final sale in _filteredSales) add(sale['date']?.toString(), 'sales', _amount(sale));
    for (final purchase in _filteredPurchases) {
      add((purchase['invoice_date'] ?? purchase['date'])?.toString(),
          'purchases', (purchase['total_cost'] as num?)?.toDouble() ?? 0);
    }
    for (final expense in _filteredExpenses) {
      add(expense['date']?.toString(), 'expenses',
          (expense['amount'] as num?)?.toDouble() ?? 0);
    }
    final keys = days.keys.toList()..sort();
    return keys.map((day) {
      final values = days[day]!;
      return <String, dynamic>{
        'date': day,
        ...values,
        'net': values['sales']! - values['purchases']! - values['expenses']!,
      };
    }).toList();
  }

  String get _periodTitle {
    if (_period != 'Custom' || _customRange == null) return _period;
    final range = _customRange!;
    return '${range.start.day.toString().padLeft(2, '0')}-${range.start.month.toString().padLeft(2, '0')}-${range.start.year} to ${range.end.day.toString().padLeft(2, '0')}-${range.end.month.toString().padLeft(2, '0')}-${range.end.year}';
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
                  ButtonSegment(value: 'Custom', label: Text('Date Range')),
                ],
                selected: {_period},
                onSelectionChanged: (selection) {
                  if (selection.first == 'Custom') {
                    _chooseCustomRange();
                  } else {
                    setState(() => _period = selection.first);
                  }
                },
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
              metric('Purchases', _money(_totalPurchases), Icons.inventory_2_outlined),
              const SizedBox(width: 10),
              metric('Expenses', _money(_totalExpenses), Icons.money_off_outlined),
              const SizedBox(width: 10),
              metric('Net Activity', _money(_netCashMovement), Icons.account_balance_wallet_outlined),
            ],
          ),
          const SizedBox(height: 5),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Net Activity = Net Sales - Purchases - Expenses. Yeh comparison metric hai, accounting profit ya cash received nahi.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          const SizedBox(height: 7),
          if (_period == 'Custom' && _dailyBreakdown.length > 1)
            SizedBox(
              height: 178,
              child: Card(
                margin: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                      child: Text('Daily Sales / Purchases / Expenses',
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          child: DataTable(
                            headingRowHeight: 32,
                            dataRowMinHeight: 30,
                            dataRowMaxHeight: 36,
                            columns: const [
                              DataColumn(label: Text('Date')),
                              DataColumn(label: Text('Sales'), numeric: true),
                              DataColumn(label: Text('Purchases'), numeric: true),
                              DataColumn(label: Text('Expenses'), numeric: true),
                              DataColumn(label: Text('Net Activity'), numeric: true),
                            ],
                            rows: _dailyBreakdown.map((day) => DataRow(cells: [
                              DataCell(Text(day['date'].toString())),
                              DataCell(Text(_money(day['sales'] as double))),
                              DataCell(Text(_money(day['purchases'] as double))),
                              DataCell(Text(_money(day['expenses'] as double))),
                              DataCell(Text(_money(day['net'] as double),
                                  style: const TextStyle(fontWeight: FontWeight.w600))),
                            ])).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
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
                        Expanded(child: Text('$_periodTitle Transactions', style: Theme.of(context).textTheme.titleMedium)),
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
                              child: Scrollbar(
                                thumbVisibility: true,
                                notificationPredicate: (notification) => notification.metrics.axis == Axis.vertical,
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
            tooltip: 'Choose custom date range',
            onPressed: _chooseCustomRange,
            icon: const Icon(Icons.date_range),
          ),
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
                      ButtonSegment(value: 'Custom', label: Text('Date Range')),
                    ],
                    selected: {_period},
                    onSelectionChanged: (selection) {
                      if (selection.first == 'Custom') {
                        _chooseCustomRange();
                      } else {
                        setState(() => _period = selection.first);
                      }
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
                          _summaryRow('Purchases', _money(_totalPurchases)),
                          _summaryRow('Expenses', _money(_totalExpenses)),
                          _summaryRow('Net Activity', _money(_netCashMovement)),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Net Activity is Net Sales minus Purchases and Expenses; it is not accounting profit or cash received.',
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ),
                  if (_period == 'Custom' && _dailyBreakdown.length > 1) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Daily Breakdown',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            const Divider(),
                            ..._dailyBreakdown.map((day) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(day['date'].toString()),
                              subtitle: Text('Sales: ${_money(day['sales'] as double)}  •  Purchases: ${_money(day['purchases'] as double)}  •  Expenses: ${_money(day['expenses'] as double)}'),
                              trailing: Text(_money(day['net'] as double),
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                            )),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    '$_periodTitle Sales',
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
