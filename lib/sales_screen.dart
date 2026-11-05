import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  int? selectedCustomerId; // Null means Quick / Walk-in Customer
  String selectedCustomerType = 'walk_in';
  final TextEditingController receivedController = TextEditingController(text: '0');

  Map<String, dynamic>? get selectedCustomer {
    if (selectedCustomerId == null) return null;
    for (final customer in customers) {
      if ((customer['id'] as num?)?.toInt() == selectedCustomerId) return customer;
    }
    return null;
  }

  double overallDiscount = 0.0;
  bool isPercentageDiscount = false;
  bool isCheckingOut = false;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    // parties table se type 'Customer' wale get karein
    final data = await DBHelper.getParties('customer');
    if (!mounted) return;
    setState(() {
      customers = data;
      if (selectedCustomerId != null &&
          !customers.any((c) => (c['id'] as num?)?.toInt() == selectedCustomerId)) {
        selectedCustomerId = null;
      }
    });
  }

  Future<void> _addKhataCustomer() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    try {
      final createdId = await showDialog<int>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Add New Khata Customer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Customer Name *'),
              ),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone Number'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Customer name is required.')),
                  );
                  return;
                }
                try {
                  final id = await DBHelper.insertParty({
                    'name': name,
                    'phone': phoneController.text.trim(),
                    'type': 'customer',
                    'customer_type': selectedCustomerType == 'wholesale' ? 'wholesale' : 'khata',
                    'balance': 0.0,
                  });
                  if (dialogContext.mounted) Navigator.pop(dialogContext, id);
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('Customer save nahi ho saka: $e')),
                    );
                  }
                }
              },
              child: const Text('Save Customer'),
            ),
          ],
        ),
      );
      if (createdId != null && mounted) {
        await _loadCustomers();
        if (!mounted) return;
        setState(() => selectedCustomerId = createdId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New Khata customer added and selected.')),
        );
      }
    } finally {
      nameController.dispose();
      phoneController.dispose();
    }
  }

  void _scanAndAddToCart() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ScannerScreen()),
    );

    if (!mounted) return;
    if (result != null && result is List<Map<String, dynamic>>) {
      final currentProducts = await DBHelper.getProducts();
      if (!mounted) return;
      final stockByBarcode = <String, int>{
        for (final product in currentProducts)
          product['barcode'].toString(): (product['quantity'] as num).toInt(),
      };
      final requested = <String, int>{};
      for (final item in cart) {
        final code = item['barcode'].toString();
        requested[code] = (requested[code] ?? 0) + (item['quantity'] as num).toInt();
      }
      for (final item in result) {
        final code = item['barcode'].toString();
        requested[code] = (requested[code] ?? 0) + (item['quantity'] as num).toInt();
        if (requested[code]! > (stockByBarcode[code] ?? 0)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Stock se zyada quantity select ho rahi hai: ${item['name']}')),
          );
          return;
        }
      }
      setState(() {
        for (var scannedItem in result) {
          int index = cart.indexWhere(
            (item) => item['barcode'] == scannedItem['barcode'],
          );
          if (index >= 0) {
            cart[index]['quantity'] += scannedItem['quantity'];
          } else {
            cart.add(Map<String, dynamic>.from(scannedItem));
          }
        }
      });
    }
  }

  Future<void> _editWholesaleRate(int index) async {
    final controller = TextEditingController(text: (cart[index]['salePrice'] ?? 0).toString());
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Wholesale rate: ${cart[index]['name']}'),
        content: TextField(controller: controller, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Unit selling price (Rs.)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final rate = double.tryParse(controller.text.trim());
            if (rate == null || !rate.isFinite || rate < 0) return;
            Navigator.pop(ctx, rate);
          }, child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (value != null && mounted) setState(() => cart[index]['salePrice'] = value);
  }

  double get subTotal => cart.fold(0.0, (sum, item) {
    double itemPrice =
        (item['salePrice'] - (item['itemDiscount'] ?? 0.0)) * item['quantity'];
    return sum + itemPrice;
  });

  double get calculatedDiscount {
    if (isPercentageDiscount) {
      return (subTotal * overallDiscount) / 100;
    }
    return overallDiscount;
  }

  double get finalTotal =>
      (subTotal - calculatedDiscount) < 0 ? 0 : (subTotal - calculatedDiscount);

  Future<void> _showDiscountDialog() async {
    TextEditingController discountController = TextEditingController(
      text: overallDiscount.toString(),
    );
    bool isPercent = isPercentageDiscount;

    await showDialog(
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
                    decoration: const InputDecoration(
                      labelText: 'Discount ki miqdar',
                    ),
                  ),
                  const SizedBox(height: 10),
                  RadioGroup<bool>(
                    groupValue: isPercent,
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => isPercent = val);
                      }
                    },
                    child: Row(
                      children: [
                        Expanded(
                          child: RadioListTile<bool>(
                            title: const Text('Rupe'),
                            value: false,
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<bool>(
                            title: const Text('FeeSad (%)'),
                            value: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final value = double.tryParse(discountController.text.trim());
                    final invalid = value == null || !value.isFinite || value < 0 ||
                        (isPercent && value > 100) ||
                        (!isPercent && value > subTotal);
                    if (invalid) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(isPercent
                            ? 'Discount 0 se 100 percent ke darmiyan hona chahiye.'
                            : 'Discount valid aur subtotal se kam ya barabar hona chahiye.')),
                      );
                      return;
                    }
                    setState(() {
                      overallDiscount = value;
                      isPercentageDiscount = isPercent;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
    discountController.dispose();
  }

  Future<void> _checkout() async {
    if (cart.isEmpty || isCheckingOut) return;

    setState(() {
      isCheckingOut = true;
    });

    // Receipt ke liye cart ki copy mehfooz rakhein.
    final completedCart = cart
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    // Sale values database operation se pehle calculate karein.
    final saleSubtotal = subTotal;
    final saleDiscount = calculatedDiscount;
    final saleFinalTotal = finalTotal;
    if (selectedCustomerType != 'walk_in' && selectedCustomer == null) {
      setState(() => isCheckingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a customer for this customer type.')));
      return;
    }
    final customerType = selectedCustomer == null ? 'retail' : selectedCustomerType;
    final receivedAmount = customerType == 'wholesale'
        ? (double.tryParse(receivedController.text.trim()) ?? -1)
        : (customerType == 'khata' ? 0.0 : saleFinalTotal);
    if (!receivedAmount.isFinite || receivedAmount < 0 || receivedAmount > saleFinalTotal) {
      setState(() => isCheckingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Received cash must be between zero and the bill total.')));
      return;
    }
    final balanceDue = customerType == 'wholesale' ? saleFinalTotal - receivedAmount : (customerType == 'khata' ? saleFinalTotal : 0.0);

    final customer = selectedCustomer == null
        ? null
        : Map<String, dynamic>.from(selectedCustomer!);

    final customerName = customer != null
        ? customer['name'].toString()
        : ' Walk-in Customer (Quick Bill)';

    final customerPhone = customer != null
        ? (customer['phone']?.toString() ?? '')
        : '';

    final currentUser = FirebaseAuth.instance.currentUser;
    final sale = <String, dynamic>{
      'salesman_uid': currentUser?.uid,
      'salesman_name': currentUser?.displayName ?? currentUser?.email ?? 'Unknown',
      'total_amount': saleSubtotal,
      'discount': saleDiscount,
      'final_amount': saleFinalTotal,
      'payment_type': customer == null || receivedAmount >= saleFinalTotal ? 'Cash' : (receivedAmount > 0 ? 'Partial' : 'Khata'),
      'customer_id': customer?['id'],
      'customer_type': customerType,
      'received_amount': receivedAmount,
      'balance_due': balanceDue,
      'date': DateTime.now().toString().substring(0, 19),
    };

    try {
      // Stock, sale aur customer balance ek transaction mein update honge.
      final saleId = await DBHelper.completeSale(
        sale: sale,
        items: completedCart,
      );

      if (!mounted) return;

      // Sirf successful sale ke baad cart clear karein.
      setState(() {
        cart.clear();
        overallDiscount = 0.0;
        isPercentageDiscount = false;
        selectedCustomerId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sale successfully save ho gayi.'),
          backgroundColor: Colors.green,
        ),
      );

      // Receipt printing ka purana feature barqarar hai.
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PrinterScreen(
            cartItems: completedCart,
            totalAmount: saleFinalTotal,
            customerName: customerName,
            customerPhone: customerPhone,
            invoiceId: saleId,
            subtotalAmount: saleSubtotal,
            discountAmount: saleDiscount,
            paymentType: sale['payment_type'].toString(),
            receivedAmount: receivedAmount,
            balanceDue: balanceDue,
            saleDate: sale['date'].toString(),
            cashierName: currentUser?.displayName ?? currentUser?.email ?? 'Admin',
            salesType: customerType == 'wholesale' ? 'Wholesale' : (customerType == 'khata' ? 'Khata' : 'Retail'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sale could not be saved: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isCheckingOut = false;
        });
      }
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
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: DropdownButtonFormField<String>(
              value: selectedCustomerType,
              decoration: const InputDecoration(labelText: 'Customer Type'),
              items: const [
                DropdownMenuItem(value: 'walk_in', child: Text('Walk-in')),
                DropdownMenuItem(value: 'khata', child: Text('Khata')),
                DropdownMenuItem(value: 'wholesale', child: Text('Wholesale')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  selectedCustomerType = value;
                  selectedCustomerId = null;
                  for (final item in cart) {
                    final retail = (item['retailSalePrice'] ?? item['salePrice'] ?? 0) as num;
                    final wholesale = (item['wholesalePrice'] ?? 0) as num;
                    item['salePrice'] = value == 'wholesale' && wholesale > 0 ? wholesale.toDouble() : retail.toDouble();
                  }
                });
              },
            ),
          ),
          // Customer / Khata Selection Dropdown
          if (selectedCustomerType != 'walk_in')
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.teal.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                const Icon(Icons.person, color: Colors.teal),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButton<int?>(
                    isExpanded: true,
                    value: selectedCustomerId,
                    hint: const Text('Walk-in Customer (Quick Bill)'),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text(
                          'Walk-in Customer (Quick Bill)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...customers.where((c) => (c['customer_type']?.toString() ?? 'khata') == selectedCustomerType).map((c) {
                        final id = (c['id'] as num).toInt();
                        return DropdownMenuItem<int?>(
                          value: id,
                          child: Text('${c['name']} (Khata: Rs.${c['balance']})'),
                        );
                      }),
                    ],
                    onChanged: (id) => setState(() => selectedCustomerId = id),
                  ),
                ),
                IconButton(
                  tooltip: 'Add New Khata Customer',
                  onPressed: _addKhataCustomer,
                  icon: const Icon(Icons.person_add_alt_1, color: Colors.teal),
                ),
                  ],
                ),
                if (selectedCustomer != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 34, top: 2),
                    child: Text(
                      'Selected Khata Customer: ${selectedCustomer!['name']}  |  Balance: Rs. ${selectedCustomer!['balance']}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(left: 34, top: 2),
                    child: Text('Walk-in Customer (Cash Sale)', style: TextStyle(color: Colors.black54)),
                  ),
              ],
            ),
          ),

          if (selectedCustomerType == 'wholesale')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextField(
                controller: receivedController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Cash received now (Rs.)', helperText: 'Remaining amount will be added to this Wholesale customer Khata.', border: OutlineInputBorder()),
              ),
            ),
          // Live Bill Items Display
          Expanded(
            child: cart.isEmpty
                ? const Center(child: Text('Cart is empty. Scan items.'))
                : ListView.builder(
                    itemCount: cart.length,
                    itemBuilder: (context, index) {
                      final item = cart[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        child: ListTile(
                          onTap: selectedCustomerType == 'wholesale' ? () => _editWholesaleRate(index) : null,
                          title: Text(
                            item['name'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Rs. ${item['salePrice']} x ${item['quantity']}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Rs. ${(item['salePrice'] * item['quantity'])}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () =>
                                    setState(() => cart.removeAt(index)),
                              ),
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
                      label: Text(
                        'Discount: ${calculatedDiscount > 0 ? "Rs. $calculatedDiscount" : "Apply"}',
                      ),
                    ),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Payable Bill:'),
                        Text(
                          'Rs. $finalTotal',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                      ),
                      onPressed: cart.isEmpty ? null : _checkout,
                      icon: const Icon(Icons.print),
                      label: const Text('Checkout / Print'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
