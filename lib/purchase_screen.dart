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
  final salePrice = TextEditingController();
  final productSearchController = TextEditingController();
  String _productSearchQuery = '';
  bool updateSalePrice = false;
  bool busy = false;

  List<Map<String, dynamic>> get _filteredProducts {
    final term = _productSearchQuery.trim().toLowerCase();
    if (term.isEmpty) return products;
    return products.where((item) =>
      (item['name']?.toString().toLowerCase() ?? '').contains(term) ||
      (item['barcode']?.toString().toLowerCase() ?? '').contains(term)
    ).toList();
  }

  void _selectProduct(Map<String, dynamic> product) {
    setState(() {
      productId = (product['id'] as num).toInt();
      cost.text = (product['purchasePrice'] ?? '').toString();
      salePrice.text = (product['price'] ?? '').toString();
    });
  }

  Future<void> _chooseWindowsProduct() async {
    final searchController = TextEditingController();
    var query = '';
    try {
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) {
          final term = query.trim().toLowerCase();
          final matches = products.where((item) =>
            (item['name']?.toString().toLowerCase() ?? '').contains(term) ||
            (item['barcode']?.toString().toLowerCase() ?? '').contains(term)
          ).toList();
          return AlertDialog(
            title: const Text('Select product for stock purchase'),
            content: SizedBox(width: 520, height: 420, child: Column(children: [
              TextField(controller: searchController, autofocus: true, onChanged: (value) => setDialogState(() => query = value), decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 18), hintText: 'Search product name or barcode')),
              const SizedBox(height: 8),
              Expanded(child: matches.isEmpty ? const Center(child: Text('No matching products found.')) : ListView.separated(
                itemCount: matches.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = matches[index];
                  return ListTile(dense: true,
                    title: Text(item['name']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    subtitle: Text('Barcode: ${item['barcode']}  |  Stock: ${item['quantity']}  |  Cost: Rs. ${item['purchasePrice']}', style: const TextStyle(fontSize: 11)),
                    onTap: () => Navigator.pop(dialogContext, item));
                },
              )),
            ])),
            actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel'))],
          );
        }),
      );
      if (selected != null && mounted) _selectProduct(selected);
    } finally { searchController.dispose(); }
  }
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
        final selected = p.where((item) => (item['id'] as num).toInt() == productId).toList();
        final current = selected.isNotEmpty ? selected.first : (p.isNotEmpty ? p.first : null);
        productId = current == null ? null : (current['id'] as num).toInt();
        if (current != null) {
          cost.text = (current['purchasePrice'] ?? '').toString();
          salePrice.text = (current['price'] ?? '').toString();
        }
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
      final newRetailPrice = updateSalePrice ? double.tryParse(salePrice.text) : null;
      if (updateSalePrice && (newRetailPrice == null || !newRetailPrice.isFinite || newRetailPrice < 0)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Valid new sale price enter karein.')));
        return;
      }
      final savedProductId = productId!;
      await DBHelper.recordPurchase(
        productId: savedProductId,
        quantity: q,
        unitCost: c,
        salePrice: updateSalePrice ? newRetailPrice : null,
      );
      qty.text = '1';
      setState(() => updateSalePrice = false);
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
          else if (Platform.isWindows)
            OutlinedButton(
              onPressed: _chooseWindowsProduct,
              style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
              child: Row(children: [
                const Icon(Icons.search, size: 17),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  productId == null ? 'Search and select product' :
                    (products.firstWhere((item) => (item['id'] as num).toInt() == productId, orElse: () => <String, dynamic>{})['name']?.toString() ?? 'Select product'),
                  style: const TextStyle(fontSize: 12),
                )),
                const Icon(Icons.arrow_drop_down, size: 18),
              ]),
            )
          else ...[
            Row(children: [
              Expanded(child: TextField(
                controller: productSearchController,
                onSubmitted: (value) => setState(() {
                  _productSearchQuery = value;
                  if (!_filteredProducts.any((item) => (item['id'] as num).toInt() == productId)) productId = null;
                }),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: 'Product name ya barcode search karein',
                  suffixIcon: IconButton(tooltip: 'Clear search', onPressed: () {
                    productSearchController.clear();
                    setState(() { _productSearchQuery = ''; });
                  }, icon: const Icon(Icons.clear, size: 17)),
                ),
              )),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => setState(() {
                  _productSearchQuery = productSearchController.text;
                  if (!_filteredProducts.any((item) => (item['id'] as num).toInt() == productId)) productId = null;
                }),
                icon: const Icon(Icons.search, size: 17),
                label: const Text('Search'),
              ),
            ]),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _filteredProducts.any((item) => (item['id'] as num).toInt() == productId) ? productId : null,
              decoration: InputDecoration(
                labelText: 'Product',
                helperText: '${_filteredProducts.length} matching products',
                border: const OutlineInputBorder(),
              ),
              items: _filteredProducts.map((p) => DropdownMenuItem<int>(
                value: (p['id'] as num).toInt(),
                child: Text('${p['name']} (Stock: ${p['quantity']})'),
              )).toList(),
              onChanged: (v) {
                final selected = products.where((item) => (item['id'] as num).toInt() == v).toList();
                if (selected.isNotEmpty) _selectProduct(selected.first);
              },
            ),
          ],
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
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: updateSalePrice,
            onChanged: busy ? null : (value) => setState(() => updateSalePrice = value ?? false),
            title: const Text('Is purchase ke sath retail sale price bhi update karein'),
            subtitle: Text('Maujooda sale price: Rs. ${(products.where((item) => (item['id'] as num).toInt() == productId).isEmpty ? '—' : products.firstWhere((item) => (item['id'] as num).toInt() == productId)['price'])}'),
          ),
          if (updateSalePrice) ...[
            TextField(
              controller: salePrice,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'New retail sale price (Rs.)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
          ],
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
    salePrice.dispose();
    productSearchController.dispose();
    super.dispose();
  }
}
