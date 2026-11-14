import 'windows/desktop_app_bar.dart';
import 'dart:io';
import 'package:flutter/material.dart';

import 'db_helper.dart';
import 'scanner_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<Map<String, dynamic>> products = [];
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _inventoryVerticalController = ScrollController();
  bool _isLoading = true;
  String _searchQuery = '';

  List<Map<String, dynamic>> get _visibleProducts {
    final term = _searchQuery.trim().toLowerCase();
    if (term.isEmpty) return products;
    return products.where((item) =>
      (item['name']?.toString().toLowerCase() ?? '').contains(term) ||
      (item['barcode']?.toString().toLowerCase() ?? '').contains(term)
    ).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final data = await DBHelper.getProducts();
      if (!mounted) return;
      setState(() {
        products = data;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Inventory load nahi ho saki: $error')),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _inventoryVerticalController.dispose();
    super.dispose();
  }

  void _showAddOrEditProductDialog({Map<String, dynamic>? product}) {
    final barcodeController = TextEditingController(
      text: product != null ? product['barcode'] : '',
    );
    final nameController = TextEditingController(
      text: product != null ? product['name'] : '',
    );
    final stockController = TextEditingController(
      text: product != null ? product['quantity'].toString() : '0',
    );
    final stockUnitController = TextEditingController(
      text: product?['stock_unit']?.toString() ?? 'pcs',
    );
    final purchasePriceController = TextEditingController(
      text: product != null
          ? (product['purchasePrice']?.toString() ?? '0')
          : '0',
    );
    final salePriceController = TextEditingController(
      text: product != null ? product['price'].toString() : '0',
    );

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(product == null ? 'Add New Product' : 'Update Product'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: barcodeController,
                        onSubmitted: (value) async {
                          final scannedBarcode = value.trim();
                          if (scannedBarcode.isEmpty) return;
                          final allProducts = await DBHelper.getProducts();
                          final duplicate = allProducts.where((item) =>
                            item['barcode']?.toString().trim() == scannedBarcode &&
                            (product == null || (item['id'] as num).toInt() != (product['id'] as num).toInt())
                          );
                          if (duplicate.isNotEmpty && dialogContext.mounted) {
                            final existingName = duplicate.first['name']?.toString() ?? 'another product';
                            await showDialog<void>(
                              context: dialogContext,
                              builder: (alertContext) => AlertDialog(
                                title: const Text('Duplicate barcode'),
                                content: Text('Barcode $scannedBarcode pehle se "$existingName" ke saath registered hai.'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(alertContext),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                            );
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Barcode *',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.qr_code_scanner,
                        color: Colors.teal,
                      ),
                      onPressed: () async {
                        final code = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ScannerScreen(captureBarcodeOnly: true),
                          ),
                        );
                        if (code != null) {
                          final scannedBarcode = code.toString().trim();
                          final allProducts = await DBHelper.getProducts();
                          final duplicate = allProducts.where((item) =>
                            item['barcode']?.toString().trim() == scannedBarcode &&
                            (product == null || (item['id'] as num).toInt() != (product['id'] as num).toInt())
                          );
                          if (duplicate.isNotEmpty) {
                            final existingName = duplicate.first['name']?.toString() ?? 'another product';
                            if (dialogContext.mounted) {
                              await showDialog<void>(
                                context: dialogContext,
                                builder: (alertContext) => AlertDialog(
                                  title: const Text('Duplicate barcode'),
                                  content: Text('Barcode $scannedBarcode pehle se "$existingName" ke saath registered hai.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(alertContext),
                                      child: const Text('OK'),
                                    ),
                                  ],
                                ),
                              );
                            }
                          } else {
                            barcodeController.text = scannedBarcode;
                          }
                        }
                      },
                    ),
                  ],
                ),
                TextField(
                  controller: nameController,
                  maxLength: DBHelper.maxReceiptProductNameLength,
                  decoration: const InputDecoration(
                    labelText: 'Product Name *',
                    helperText: '80mm bill par aik row: maximum 17 characters.',
                  ),
                ),
                TextField(
                  controller: stockUnitController,
                  decoration: const InputDecoration(
                    labelText: 'Stock Unit *',
                    helperText: 'Quantity aur rates isi unit mein honge. Existing stock ka unit badalne se pehle uski quantity convert karein (pcs, kg, g, ml).',
                  ),
                ),
                TextField(
                  controller: stockController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantity / Stock *',
                  ),
                ),
                TextField(
                  controller: purchasePriceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Purchase Price',
                  ),
                ),
                TextField(
                  controller: salePriceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Retail Sale Price *'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                String barcode = barcodeController.text.trim();
                String name = nameController.text.trim();
                int stock = int.tryParse(stockController.text) ?? 0;
                final stockUnit = stockUnitController.text.trim().toLowerCase();
                double purchasePrice =
                    double.tryParse(purchasePriceController.text) ?? 0.0;
                double salePrice =
                    double.tryParse(salePriceController.text) ?? 0.0;

                if (name.length > DBHelper.maxReceiptProductNameLength) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Product name 80mm bill ke liye maximum 17 characters ka ho sakta hai.')),
                  );
                  return;
                }

                if (barcode.isEmpty || name.isEmpty || stockUnit.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Barcode, Name aur Stock Unit lazmi hain!'),
                    ),
                  );
                  return;
                }

                final allProducts = await DBHelper.getProducts();
                final duplicate = allProducts.where((item) =>
                  item['barcode']?.toString().trim() == barcode &&
                  (product == null || (item['id'] as num).toInt() != (product['id'] as num).toInt())
                );
                if (duplicate.isNotEmpty) {
                  final existingName = duplicate.first['name']?.toString() ?? 'another product';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Barcode pehle se "$existingName" ke naam par mojood hai.')),
                  );
                  return;
                }

                final productData = {
                  'barcode': barcode,
                  'name': name,
                  'price': salePrice,
                  'purchasePrice': purchasePrice,
                  'damaged_quantity': product?['damaged_quantity'] ?? 0,
                  'quantity': stock,
                  'stock_unit': stockUnit,
                };

                // Edit par existing row update ho; naya product create na ho.
                try {
                  if (product == null) {
                    await DBHelper.insertProduct(productData);
                  } else {
                    await DBHelper.updateProduct(
                      product['id'] as int,
                      productData,
                    );
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Product save nahi ho saka: ${e.toString().replaceFirst('Exception: ', '')}',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                  return;
                }

                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _loadProducts();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeleteProduct(Map<String, dynamic> product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('Kya "${product['name']}" ko inventory se delete karna hai? Agar is product ki sale ya purchase history hai to system deletion rok dega.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await DBHelper.deleteProduct((product['id'] as num).toInt());
      await _loadProducts();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product inventory se delete ho gaya.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !Platform.isWindows,
        leading: desktopWorkspaceButton(),
        title: const Text('Inventory Management'),
        backgroundColor: Platform.isWindows ? const Color(0xFFF7F9FB) : Colors.teal,
        foregroundColor: Platform.isWindows ? const Color(0xFF263442) : Colors.white,
      ),
      floatingActionButton: Platform.isWindows ? null : FloatingActionButton(
        backgroundColor: Platform.isWindows ? const Color(0xFFF7F9FB) : Colors.teal,
        onPressed: () => _showAddOrEditProductDialog(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Platform.isWindows
          ? Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(children: [
                    Expanded(child: SizedBox(
                      height: 38,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _searchQuery = value),
                        onSubmitted: (value) => setState(() => _searchQuery = value),
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: const Icon(Icons.search, size: 18),
                          hintText: 'Search product name or barcode',
                          suffixIcon: IconButton(
                            tooltip: 'Clear search',
                            onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); },
                            icon: const Icon(Icons.clear, size: 17),
                          ),
                        ),
                      ),
                    )),
                    const SizedBox(width: 8),
                    SizedBox(height: 38, child: FilledButton.icon(
                      onPressed: () => setState(() => _searchQuery = _searchController.text),
                      icon: const Icon(Icons.search, size: 16),
                      label: const Text('Search'),
                    )),
                    const SizedBox(width: 8),
                    SizedBox(height: 38, child: OutlinedButton.icon(
                      onPressed: () => _showAddOrEditProductDialog(),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Product'),
                    )),
                  ]),
                  const SizedBox(height: 10),
                  Expanded(
                     child: _isLoading
                         ? const Center(child: CircularProgressIndicator())
                         : _visibleProducts.isEmpty
                             ? const Center(child: Text('No matching products found.'))
                             : Container(
                                 width: double.infinity,
                                 decoration: BoxDecoration(
                                   color: Theme.of(context).colorScheme.surface,
                                   border: Border.all(color: const Color(0xFFD9E0E6)),
                                   borderRadius: BorderRadius.circular(5),
                                 ),
                                 child: Scrollbar(
                                   controller: _inventoryVerticalController,
                                   thumbVisibility: true,
                                   interactive: true,
                                   child: ListView.builder(
                                     controller: _inventoryVerticalController,
                                     primary: false,
                                     itemCount: _visibleProducts.length,
                                     itemBuilder: (context, index) {
                                       final item = _visibleProducts[index];
                                       return Card(
                                         margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                         child: ListTile(
                                           dense: true,
                                           title: Text(item['name']?.toString() ?? '',
                                             maxLines: 1, overflow: TextOverflow.ellipsis,
                                             style: const TextStyle(fontWeight: FontWeight.w600)),
                                           subtitle: Text(
                                             'Barcode: ${item['barcode'] ?? '—'} | Stock: ${item['quantity'] ?? 0} ${item['stock_unit'] ?? 'pcs'} | Damaged: ${item['damaged_quantity'] ?? 0}\nPurchase: Rs. ${item['purchasePrice'] ?? 0} | Sale: Rs. ${item['price'] ?? 0}',
                                             maxLines: 2, overflow: TextOverflow.ellipsis),
                                           trailing: Wrap(
                                             spacing: 0,
                                             children: [
                                               IconButton(
                                                 tooltip: 'Modify product',
                                                 icon: const Icon(Icons.edit_outlined, size: 17),
                                                 onPressed: () => _showAddOrEditProductDialog(product: item),
                                               ),
                                               IconButton(
                                                 tooltip: 'Delete product',
                                                 icon: const Icon(Icons.delete_outline, size: 17, color: Colors.red),
                                                 onPressed: () => _confirmDeleteProduct(item),
                                               ),
                                             ],
                                           ),
                                         ),
                                       );
                                     },
                                   ),
                                 ),
                               ),
                   ),
Align(alignment: Alignment.centerRight, child: Text('${_visibleProducts.length} of ${products.length} products', style: const TextStyle(fontSize: 11, color: Colors.black54))),
                ],
              ),
            )
          : _isLoading
              ? const Center(child: CircularProgressIndicator())
              : products.isEmpty
                  ? const Center(child: Text('No products found. Add some!'))
                  : ListView.builder(
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final item = products[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Stock: ${item['quantity']} ${item['stock_unit'] ?? 'pcs'} | Damaged: ${item['damaged_quantity'] ?? 0} | Sale Price: Rs.${item['price']} per ${item['stock_unit'] ?? 'pcs'}'),
                        trailing: Wrap(spacing: 0, children: [
                          IconButton(tooltip: 'Modify product', icon: const Icon(Icons.edit, color: Colors.teal), onPressed: () => _showAddOrEditProductDialog(product: item)),
                          IconButton(tooltip: 'Delete product', icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _confirmDeleteProduct(item)),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }
}
