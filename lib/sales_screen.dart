import 'package:flutter/material.dart';
import 'db_helper.dart';
import 'scanner_screen.dart';
import 'printer_screen.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  List<Map<String, dynamic>> cart = [];

  void _scanAndAddToCart() async {
    final barcode = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ScannerScreen()),
    );

    if (barcode != null) {
      final products = await DBHelper.getProducts();
      final productList = products.where((p) => p['barcode'] == barcode).toList();

      if (productList.isNotEmpty) {
        final product = productList.first;
        int stock = (product['quantity'] as int?) ?? 0;

        if (stock <= 0) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item out of stock!')));
          }
          return;
        }

        setState(() {
          int index = cart.indexWhere((item) => item['barcode'] == barcode);
          if (index >= 0) {
            cart[index]['quantity'] += 1;
          } else {
            cart.add({
              'barcode': barcode,
              'name': product['name'],
              'purchasePrice': product['purchasePrice'] ?? 0.0,
              'salePrice': product['price'],
              'quantity': 1,
            });
          }
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product not found!')));
        }
      }
    }
  }

  double get totalAmount => cart.fold(0.0, (sum, item) => sum + (item['salePrice'] * item['quantity']));
  double get totalProfit => cart.fold(0.0, (sum, item) => sum + ((item['salePrice'] - item['purchasePrice']) * item['quantity']));

  void _checkout() async {
    if (cart.isEmpty) return;

    for (var item in cart) {
      final products = await DBHelper.getProducts();
      final pList = products.where((p) => p['barcode'] == item['barcode']).toList();
      if (pList.isNotEmpty) {
        int currentStock = (pList.first['quantity'] as int?) ?? 0;
        await DBHelper.insertProduct({
          'barcode': item['barcode'],
          'name': item['name'],
          'price': item['salePrice'],
          'quantity': currentStock - item['quantity'],
          'purchasePrice': item['purchasePrice'],
        });
      }
    }

    await DBHelper.insertSale({
      'total_amount': totalAmount,
      'date': DateTime.now().toString().substring(0, 19),
    });

    if (mounted) {
      List<Map<String, dynamic>> completedCart = List.from(cart);
      double finalTotal = totalAmount;
      setState(() {
        cart.clear();
      });

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PrinterScreen(cartItems: completedCart, totalAmount: finalTotal),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('POS Billing'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _scanAndAddToCart,
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: cart.isEmpty
                ? const Center(child: Text('Cart is empty. Scan items.'))
                : ListView.builder(
                    itemCount: cart.length,
                    itemBuilder: (context, index) {
                      final item = cart[index];
                      return ListTile(
                        title: Text(item['name']),
                        subtitle: Text('Rs. ${item['salePrice']} x ${item['quantity']}'),
                        trailing: Text('Rs. ${item['quantity'] * item['salePrice']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[200],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Bill:'),
                    Text('Rs. $totalAmount', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal)),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                  onPressed: cart.isEmpty ? null : _checkout,
                  icon: const Icon(Icons.print),
                  label: const Text('Checkout & Print'),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}