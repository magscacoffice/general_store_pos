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
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
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
