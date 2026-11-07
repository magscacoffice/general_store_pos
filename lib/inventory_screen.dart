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

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final data = await DBHelper.getProducts();
    setState(() {
      products = data;
    });
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
                          barcodeController.text = code;
                        }
                      },
                    ),
                  ],
                ),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Product Name *',
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
                double purchasePrice =
                    double.tryParse(purchasePriceController.text) ?? 0.0;
                double salePrice =
                    double.tryParse(salePriceController.text) ?? 0.0;

                if (barcode.isEmpty || name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Bar code aur Name lazmi hain!'),
                    ),
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
        title: const Text('Inventory Management'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.teal,
        onPressed: () => _showAddOrEditProductDialog(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: products.isEmpty
          ? const Center(child: Text('No products found. Add some!'))
          : ListView.builder(
              itemCount: products.length,
              itemBuilder: (context, index) {
                final item = products[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: ListTile(
                    title: Text(
                      item['name'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Stock: ${item['quantity']} | Damaged: ${item['damaged_quantity'] ?? 0} | Sale Price: Rs.${item['price']}',
                    ),
                    trailing: Wrap(
                      spacing: 0,
                      children: [
                        IconButton(tooltip: 'Modify product', icon: const Icon(Icons.edit, color: Colors.teal), onPressed: () => _showAddOrEditProductDialog(product: item)),
                        IconButton(tooltip: 'Delete product', icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _confirmDeleteProduct(item)),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
