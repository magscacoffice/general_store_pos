import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'scanner_screen.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('khan_baba.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        barcode TEXT PRIMARY KEY,
        name TEXT,
        stock INTEGER,
        purchasePrice REAL,
        salePrice REAL,
        oldSalePrice REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        totalAmount REAL,
        totalProfit REAL,
        timestamp TEXT
      )
    ''');
  }
}

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
    final db = await DatabaseHelper.instance.database;
    final result = await db.query('products');
    setState(() {
      products = result;
    });
  }

  void _showAddOrEditProductDialog({Map<String, dynamic>? product}) {
    final barcodeController = TextEditingController(text: product != null ? product['barcode'] : '');
    final nameController = TextEditingController(text: product != null ? product['name'] : '');
    final stockController = TextEditingController(text: product != null ? product['stock'].toString() : '0');
    final purchasePriceController = TextEditingController(text: product != null ? product['purchasePrice'].toString() : '0');
    final salePriceController = TextEditingController(text: product != null ? product['salePrice'].toString() : '0');

    double oldSalePrice = product != null ? (product['salePrice'] ?? 0.0) : 0.0;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(product == null ? 'Add Product' : 'Adjust Stock / Price'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: barcodeController,
                        decoration: const InputDecoration(labelText: 'Barcode'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.qr_code_scanner, color: Colors.teal),
                      onPressed: () async {
                        final code = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ScannerScreen()),
                        );
                        if (code != null) {
                          barcodeController.text = code;
                        }
                      },
                    )
                  ],
                ),
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Product Name')),
                TextField(controller: stockController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Add Stock Quantity')),
                TextField(controller: purchasePriceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Purchase Price')),
                TextField(controller: salePriceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'New Sale Price')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final db = await DatabaseHelper.instance.database;
                String barcode = barcodeController.text.trim();
                String name = nameController.text.trim();
                int addedStock = int.tryParse(stockController.text) ?? 0;
                double purchasePrice = double.tryParse(purchasePriceController.text) ?? 0.0;
                double salePrice = double.tryParse(salePriceController.text) ?? 0.0;

                if (barcode.isEmpty || name.isEmpty) return;

                if (product == null) {
                  await db.insert('products', {
                    'barcode': barcode,
                    'name': name,
                    'stock': addedStock,
                    'purchasePrice': purchasePrice,
                    'salePrice': salePrice,
                    'oldSalePrice': salePrice,
                  }, conflictAlgorithm: ConflictAlgorithm.replace);
                } else {
                  int currentStock = (product['stock'] as int?) ?? 0;
                  await db.update('products', {
                    'name': name,
                    'stock': currentStock + addedStock,
                    'purchasePrice': purchasePrice,
                    'salePrice': salePrice,
                    'oldSalePrice': oldSalePrice,
                  }, where: 'barcode = ?', whereArgs: [barcode]);
                }

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
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Stock: ${item['stock']} | Purchase: Rs.${item['purchasePrice']} | Sale: Rs.${item['salePrice']} (Old: Rs.${item['oldSalePrice']})'),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit, color: Colors.teal),
                      onPressed: () => _showAddOrEditProductDialog(product: item),
                    ),
                  ),
                );
              },
            ),
    );
  }
}