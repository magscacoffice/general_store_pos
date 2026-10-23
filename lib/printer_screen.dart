import 'package:flutter/material.dart';

class PrinterScreen extends StatelessWidget {
  final List<Map<String, dynamic>> cartItems;
  final double totalAmount;

  const PrinterScreen({super.key, required this.cartItems, required this.totalAmount});

  @override
  Widget build(BuildContext context) {
    String currentDate = DateTime.now().toString().substring(0, 16);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt Preview / Print'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('KHAN BABA GENERAL STORE', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const Text('Sanawan, Kot Addu', textAlign: TextAlign.center),
            const Divider(thickness: 2),
            Text('Date: $currentDate'),
            const Divider(thickness: 2),
            Expanded(
              child: ListView.builder(
                itemCount: cartItems.length,
                itemBuilder: (context, index) {
                  final item = cartItems[index];
                  return ListTile(
                    title: Text(item['name']),
                    subtitle: Text('${item['quantity']} x Rs. ${item['salePrice']}'),
                    trailing: Text('Rs. ${item['quantity'] * item['salePrice']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  );
                },
              ),
            ),
            const Divider(thickness: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('TOTAL:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('Rs. $totalAmount', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal)),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Receipt Printed Successfully!')),
                );
                Navigator.pop(context);
              },
              icon: const Icon(Icons.print),
              label: const Text('Print Receipt Now', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}