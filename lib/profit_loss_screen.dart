import 'windows/desktop_app_bar.dart';
import 'dart:io';
import 'package:flutter/material.dart';

import 'db_helper.dart';

class ProfitLossScreen extends StatefulWidget {
  const ProfitLossScreen({super.key});
  @override
  State<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends State<ProfitLossScreen> {
  Map<String, double> data = {};
  bool loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await DBHelper.getProfitLossSummary();
      if (mounted) setState(() => data = d);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget _desktopMetric(String title, double value, IconData icon, {Color? color}) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, size: 24, color: color ?? Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  'Rs. ${value.toStringAsFixed(2)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _tile(String title, double value, {Color? color}) => Card(
    child: ListTile(
      title: Text(title),
      trailing: Text(
        'Rs. ${value.toStringAsFixed(2)}',
        style: TextStyle(fontWeight: FontWeight.bold, color: color),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final profit = data['profit'] ?? 0;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !Platform.isWindows,
        leading: desktopWorkspaceButton(),
        title: const Text('Profit / Loss'),
        backgroundColor: Platform.isWindows ? const Color(0xFFF7F9FB) : Colors.teal,
        foregroundColor: Platform.isWindows ? const Color(0xFF263442) : Colors.white,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Platform.isWindows
              ? Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('All-time financial summary', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 14),
                      GridView.count(
                        crossAxisCount: 4,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        shrinkWrap: true,
                        childAspectRatio: 2.25,
                        children: [
                          _desktopMetric('Sales Revenue', data['revenue'] ?? 0, Icons.point_of_sale),
                          _desktopMetric('Cost of Sold Items', data['cost'] ?? 0, Icons.inventory_2_outlined),
                          _desktopMetric('Recorded Expenses', data['expenses'] ?? 0, Icons.money_off),
                          _desktopMetric(profit >= 0 ? 'Estimated Profit' : 'Estimated Loss', profit, Icons.account_balance, color: profit >= 0 ? Colors.green : Colors.red),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline, size: 20),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Important: Existing old sales do not have item-cost snapshots, so this report cannot calculate their actual cost. Profit figures become more reliable for sales recorded after this update. Existing expenses are included.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'All-time summary',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  _tile('Sales revenue', data['revenue'] ?? 0),
                  _tile('Recorded cost of sold items', data['cost'] ?? 0),
                  _tile('Recorded expenses', data['expenses'] ?? 0),
                  _tile(
                    profit >= 0 ? 'Estimated profit' : 'Estimated loss',
                    profit,
                    color: profit >= 0 ? Colors.green : Colors.red,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Important: Existing old sales do not have item-cost snapshots, so this report cannot calculate their actual cost. Profit figures become more reliable for sales recorded after this update. Existing expenses are included.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
    );
  }
}
