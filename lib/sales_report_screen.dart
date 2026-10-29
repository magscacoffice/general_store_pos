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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sales load nahi ho sakin: $e')),
      );
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
    final finalAmount = (sale['final_amount'] as num?)?.toDouble() ?? 0.0;
    final totalAmount = (sale['total_amount'] as num?)?.toDouble() ?? 0.0;

    // Purane records mein final_amount zero ho sakta hai.
    return finalAmount > 0 ? finalAmount : totalAmount;
  }

  double get _totalRevenue =>
      _filteredSales.fold(0.0, (sum, sale) => sum + _amount(sale));

  String _money(double amount) => 'Rs. ${amount.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final sales = _filteredSales;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Reports / سیل رپورٹ'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
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
                          const Icon(
                            Icons.payments,
                            size: 38,
                            color: Colors.teal,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _money(_totalRevenue),
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                          const Text('Total Sales Amount'),
                          const SizedBox(height: 8),
                          Text('Number of Sales: ${sales.length}'),
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
                          child: Text('Is period mein koi sale record nahi hai.'),
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
                            _money(amount),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            'Date: $date\nPayment: ${sale['payment_type'] ?? 'Cash'}',
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
