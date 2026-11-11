import 'windows/desktop_app_bar.dart';
import 'dart:io';
import 'package:flutter/material.dart';

import 'db_helper.dart';

class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key});
  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  List<Map<String, dynamic>> products = [], purchases = [];
  int? productId;
  final qty = TextEditingController(text: '1');
  final cost = TextEditingController();
  bool busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await DBHelper.getProducts();
    final h = await DBHelper.getPurchases();
    if (mounted) {
      setState(() {
        products = p;
        purchases = h;
        productId = p.isEmpty ? null : p.first['id'] as int;
      });
    }
  }

  Future<void> _save() async {
    final q = int.tryParse(qty.text) ?? 0, c = double.tryParse(cost.text) ?? -1;
    if (productId == null || q <= 0 || !c.isFinite || c < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Product, quantity and valid cost required.'),
        ),
      );
      return;
    }
    setState(() => busy = true);
    try {
      await DBHelper.recordPurchase(
        productId: productId!,
        quantity: q,
        unitCost: c,
      );
      qty.text = '1';
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase saved and stock updated.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
        automaticallyImplyLeading: !Platform.isWindows,
        leading: desktopWorkspaceButton(),
      title: const Text('Purchase / Stock Entry'),
      backgroundColor: Colors.teal,
      foregroundColor: Colors.white,
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (products.isEmpty)
            const Text('Pehle Inventory mein product add karein.')
          else
            DropdownButtonFormField<int>(
              initialValue: productId,
              decoration: const InputDecoration(
                labelText: 'Product',
                border: OutlineInputBorder(),
              ),
              items: products
                  .map(
                    (p) => DropdownMenuItem<int>(
                      value: p['id'] as int,
                      child: Text('${p['name']} (Stock: ${p['quantity']})'),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => productId = v),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: qty,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Purchase quantity',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: cost,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Unit purchase cost (Rs.)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy || products.isEmpty ? null : _save,
            icon: const Icon(Icons.add_shopping_cart),
            label: Text(busy ? 'Saving...' : 'Save Purchase'),
          ),
          const Divider(height: 32),
          const Text(
            'Purchase history',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          ...purchases.map(
            (p) => ListTile(
              title: Text('${p['product_name']} × ${p['quantity']}'),
              subtitle: Text('${p['date']} • Rs. ${p['unit_cost']} each'),
              trailing: Text('Rs. ${p['total_cost']}'),
            ),
          ),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    qty.dispose();
    cost.dispose();
    super.dispose();
  }
}
