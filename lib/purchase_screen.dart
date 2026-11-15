import 'package:flutter/material.dart';

import 'db_helper.dart';
import 'supplier_invoice_capture_screen.dart';

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
      title: const Text('Purchase / Stock Entry'),
      backgroundColor: Colors.teal,
      foregroundColor: Colors.white,
      actions: [
        IconButton(
            tooltip: 'Capture supplier invoice with camera and OCR',
            onPressed: () async {
              final posted = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => const SupplierInvoiceCaptureScreen(),
                ),
              );
              if (posted == true) await _load();
            },
            icon: const Icon(Icons.document_scanner_outlined),
          ),
      ],
    ),
    body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (products.isEmpty)
                  const Text('Pehle Inventory mein product add karein.')
                else ...[
                  Row(children: [
                    Expanded(child: TextField(
                      controller: productSearchController,
                      onChanged: (value) => setState(() => _productSearchQuery = value),
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 18),
                        hintText: 'Product name ya barcode search karein',
                        suffixIcon: IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            productSearchController.clear();
                            setState(() => _productSearchQuery = '');
                          },
                          icon: const Icon(Icons.clear, size: 17),
                        ),
                      ),
                    )),
                  ]),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: _filteredProducts.any((item) => (item['id'] as num).toInt() == productId) ? productId : null,
                    decoration: InputDecoration(
                      labelText: 'Product',
                      helperText: '${_filteredProducts.length} matching products',
                    ),
                    items: _filteredProducts.map((product) => DropdownMenuItem<int>(
                      value: (product['id'] as num).toInt(),
                      child: Text('${product['name']} (Stock: ${product['quantity']})'),
                    )).toList(),
                    onChanged: (value) {
                      final selected = products.where((item) => (item['id'] as num).toInt() == value).toList();
                      if (selected.isNotEmpty) _selectProduct(selected.first);
                    },
                  ),
                ],
                const SizedBox(height: 12),
                TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Purchase quantity')),
                const SizedBox(height: 12),
                TextField(controller: cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Unit purchase cost (Rs.)')),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: updateSalePrice,
                  onChanged: busy ? null : (value) => setState(() => updateSalePrice = value ?? false),
                  title: const Text('Is purchase ke sath retail sale price bhi update karein'),
                ),
                if (updateSalePrice) ...[
                  TextField(controller: salePrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'New retail sale price (Rs.)')),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  onPressed: busy || products.isEmpty ? null : _save,
                  icon: const Icon(Icons.add_shopping_cart),
                  label: Text(busy ? 'Saving...' : 'Save Purchase'),
                ),
                const Divider(height: 32),
                const Text('Purchase history', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ...purchases.map((purchase) => ListTile(
                  title: Text('${purchase['product_name']} × ${purchase['quantity']} ${purchase['base_unit'] ?? ''}'),
                  subtitle: Text('${purchase['invoice_number'] == null ? purchase['date'] : 'Invoice ${purchase['invoice_number']} • ${purchase['invoice_date'] ?? purchase['date']}'} • ${purchase['invoice_quantity'] == null ? 'Rs. ${purchase['unit_cost']} per stock unit' : '${purchase['invoice_quantity']} ${purchase['unit_label'] ?? ''} @ Rs. ${purchase['invoice_unit_cost'] ?? 0}'}'),
                  trailing: Text('Rs. ${purchase['total_cost']}'),
                )),
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
