import 'package:flutter/material.dart';
import 'db_helper.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<Map<String, dynamic>> _products = [];

  @override
  void initState() {
    super.initState();
    _refreshProducts();
  }

  void _refreshProducts() async {
    final data = await DBHelper.getProducts();
    setState(() {
      _products = data;
    });
  }

  void _showAddProductDialog() {
    final nameController = TextEditingController();
    final barcodeController = TextEditingController();
    final priceController = TextEditingController();
    final qtyController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Naya Item Add Karein'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Item Ka Naam')),
              TextField(controller: barcodeController, decoration: const InputDecoration(labelText: 'Barcode')),
              TextField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qeemat (Price)')),
              TextField(controller: qtyController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty && barcodeController.text.isNotEmpty) {
                await DBHelper.insertProduct({
                  'name': nameController.text,
                  'barcode': barcodeController.text,
                  'price': double.tryParse(priceController.text) ?? 0.0,
                  'quantity': int.tryParse(qtyController.text) ?? 0,
                });
                _refreshProducts();
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock / Inventory'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _products.isEmpty
          ? const Center(child: Text('Koi item add nahi hua abhi tak.'))
          : ListView.builder(
              itemCount: _products.length,
              itemBuilder: (context, index) {
                final item = _products[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Barcode: ${item['barcode']} | Stock: ${item['quantity']}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Rs. ${item['price']}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            await DBHelper.deleteProduct(item['id']);
                            _refreshProducts();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddProductDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}