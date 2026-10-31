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
                            builder: (context) => const ScannerScreen(),
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
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Sale Price *'),
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

                // DBHelper ke zariye database mein save karna
                await DBHelper.insertProduct({
                  'barcode': barcode,
                  'name': name,
                  'price': salePrice,
                  'purchasePrice': purchasePrice,
                  'quantity': stock,
                });

                if (mounted) Navigator.pop(dialogContext);
                _loadProducts();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
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
                      'Stock: ${item['quantity']} | Sale Price: Rs.${item['price']}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit, color: Colors.teal),
                      onPressed: () =>
                          _showAddOrEditProductDialog(product: item),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
