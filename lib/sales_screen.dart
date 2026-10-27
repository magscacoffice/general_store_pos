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
  List<Map<String, dynamic>> customers = [];
  Map<String, dynamic>? selectedCustomer; // Null means Quick / Walk-in Customer

  double overallDiscount = 0.0;
  bool isPercentageDiscount = false;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    // parties table se type 'Customer' wale get karein
    final data = await DBHelper.getParties('Customer');
    setState(() => customers = data);
  }

  void _scanAndAddToCart() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ScannerScreen()),
    );

    if (result != null && result is List<Map<String, dynamic>>) {
      setState(() {
        for (var scannedItem in result) {
          int index = cart.indexWhere((item) => item['barcode'] == scannedItem['barcode']);
          if (index >= 0) {
            cart[index]['quantity'] += scannedItem['quantity'];
          } else {
            cart.add(Map<String, dynamic>.from(scannedItem));
          }
        }
      });
    }
  }

  double get subTotal => cart.fold(0.0, (sum, item) {
        double itemPrice = (item['salePrice'] - (item['itemDiscount'] ?? 0.0)) * item['quantity'];
        return sum + itemPrice;
      });

  double get calculatedDiscount {
    if (isPercentageDiscount) {
      return (subTotal * overallDiscount) / 100;
    }
    return overallDiscount;
  }

  double get finalTotal => (subTotal - calculatedDiscount) < 0 ? 0 : (subTotal - calculatedDiscount);

  void _showDiscountDialog() {
    TextEditingController discountController = TextEditingController(text: overallDiscount.toString());
    bool isPercent = isPercentageDiscount;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Bill Par Discount Lagayein'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: discountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Discount ki miqdar'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<bool>(
                          title: const Text('Rupe'),
                          value: false,
                          groupValue: isPercent,
                          onChanged: (val) => setDialogState(() => isPercent = val!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<bool>(
                          title: const Text('FeeSad (%)'),
                          value: true,
                          groupValue: isPercent,
                          onChanged: (val) => setDialogState(() => isPercent = val!),
                        ),
                      ),
                    ],
                  )
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      overallDiscount = double.tryParse(discountController.text) ?? 0.0;
                      isPercentageDiscount = isPercent;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Lagoo Karein'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _checkout() async {
    if (cart.isEmpty) return;

    // Stock update in database
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
          'purchasePrice': pList.first['purchasePrice'] ?? 0.0,
        });
      }
    }

    // Save Sale record
    await DBHelper.insertSale({
      'total_amount': subTotal,
      'discount': calculatedDiscount,
      'final_amount': finalTotal,
      'payment_type': selectedCustomer == null ? 'Cash' : 'Khata',
      'customer_id': selectedCustomer?['id'],
      'date': DateTime.now().toString().substring(0, 19),
    });

    // If customer selected, update customer khata balance
    if (selectedCustomer != null) {
      await DBHelper.updatePartyBalance(selectedCustomer!['id'], finalTotal);
    }

    if (mounted) {
      List<Map<String, dynamic>> completedCart = List.from(cart);
      double totalToPrint = finalTotal;
      String custName = selectedCustomer != null ? selectedCustomer!['name'] : 'Aam Grahak (Quick Bill)';
      String custPhone = selectedCustomer != null ? selectedCustomer!['phone'] : '';

      setState(() {
        cart.clear();
        overallDiscount = 0.0;
        selectedCustomer = null;
      });

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PrinterScreen(
            cartItems: completedCart,
            totalAmount: totalToPrint,
            customerName: custName,
            customerPhone: custPhone,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('POS Billing (Quick & Khata)'),
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
          // Customer / Khata Selection Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.teal.shade50,
            child: Row(
              children: [
                const Icon(Icons.person, color: Colors.teal),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButton<Map<String, dynamic>?>(
                    isExpanded: true,
                    value: selectedCustomer,
                    hint: const Text('Baghair Khate Wala Grahak (Quick Bill)'),
                    items: [
                      const DropdownMenuItem<Map<String, dynamic>?>(
                        value: null,
                        child: Text('Baghair Khate Wala Grahak (Quick Bill)', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      ...customers.map((c) {
                        return DropdownMenuItem<Map<String, dynamic>?>(
                          value: c,
                          child: Text('${c['name']} (Khata: Rs.${c['balance']})'),
                        );
                      }),
                    ],
                    onChanged: (val) => setState(() => selectedCustomer = val),
                  ),
                ),
              ],
            ),
          ),

          // Live Bill Items Display
          Expanded(
            child: cart.isEmpty
                ? const Center(child: Text('Cart khali hai. Items scan karein.'))
                : ListView.builder(
                    itemCount: cart.length,
                    itemBuilder: (context, index) {
                      final item = cart[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: ListTile(
                          title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Rs. ${item['salePrice']} x ${item['quantity']}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Rs. ${(item['salePrice'] * item['quantity'])}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => setState(() => cart.removeAt(index)),
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Subtotal, Discount & Checkout Panel
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[200],
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('SubTotal: Rs. $subTotal'),
                    TextButton.icon(
                      onPressed: _showDiscountDialog,
                      icon: const Icon(Icons.discount, color: Colors.teal),
                      label: Text('Discount: ${calculatedDiscount > 0 ? "Rs. $calculatedDiscount" : "Shamil Karein"}'),
                    )
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Qabil-e-Ada Kul Bill:'),
                        Text('Rs. $finalTotal', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.teal)),
                      ],
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16)),
                      onPressed: cart.isEmpty ? null : _checkout,
                      icon: const Icon(Icons.print),
                      label: const Text('Checkout / Print'),
                    ),
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}