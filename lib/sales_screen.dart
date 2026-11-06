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
  int? selectedCustomerId;
  String selectedSaleType = 'Walk-in';
  String customerPaymentMode = 'Cash';
  final TextEditingController receivedAmountController = TextEditingController();

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

  @override
  void dispose() {
    receivedAmountController.dispose();
    super.dispose();
  }

  void _setSaleType(String type) {
    if (cart.isNotEmpty && type != selectedSaleType) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer type badalne se pehle cart clear karein.')),
      );
      return;
    }
    setState(() {
      selectedSaleType = type;
      selectedCustomerId = null;
      customerPaymentMode = 'Cash';
      receivedAmountController.clear();
    });
  }

  Future<void> _loadCustomers() async {
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
          title: Text('Add New Khata Customer'),
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
                    'customer_type': 'Khata',
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
        for (final scannedItem in result) {
          final prepared = Map<String, dynamic>.from(scannedItem);
          final index = cart.indexWhere((item) => item['barcode'] == prepared['barcode']);
          if (index >= 0) {
            cart[index]['quantity'] += prepared['quantity'];
          } else {
            cart.add(prepared);
          }
        }
      });
    }
  }

  Future<void> _editSalePrice(int index) async {
    final currentPrice = (cart[index]['salePrice'] as num?)?.toDouble() ?? 0.0;
    final purchasePrice =
        (cart[index]['purchasePrice'] as num?)?.toDouble() ?? 0.0;
    final controller = TextEditingController(text: currentPrice.toString());
    try {
      final updatedPrice = await showDialog<double>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Sale Price: ${cart[index]['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Purchase Price: Rs. $purchasePrice'),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Unit Sale Price (Rs.)',
                  helperText: 'Minimum allowed: Rs. $purchasePrice',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(controller.text.trim());
                if (value == null || !value.isFinite || value < purchasePrice) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Sale Price purchase price (Rs. $purchasePrice) se kam nahi ho sakti.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (updatedPrice != null && mounted) {
        setState(() => cart[index]['salePrice'] = updatedPrice);
      }
    } finally {
      controller.dispose();
    }
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

    final saleType = selectedSaleType;
    final selected = selectedCustomer;
    if (saleType != 'Walk-in' && selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pehle customer select karein.')),
      );
      return;
    }

    final saleSubtotal = subTotal;
    final saleDiscount = calculatedDiscount;
    final saleFinalTotal = finalTotal;
    var receivedAmount = 0.0;
    var paymentType = 'Cash';
    if (saleType == 'Walk-in' || customerPaymentMode == 'Cash') {
      receivedAmount = saleFinalTotal;
      paymentType = 'Cash';
    } else if (customerPaymentMode == 'Credit') {
      receivedAmount = 0.0;
      paymentType = 'Khata';
    } else {
      receivedAmount = double.tryParse(receivedAmountController.text.trim()) ?? -1;
      paymentType = 'Partial';
      if (!receivedAmount.isFinite || receivedAmount <= 0 || receivedAmount >= saleFinalTotal) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Partial payment bill total se kam aur zero se zyada honi chahiye.')),
        );
        return;
      }
    }

    setState(() => isCheckingOut = true);

    // Receipt ke liye cart ki copy mehfooz rakhein.
    final completedCart = cart
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    final customer = selected == null ? null : Map<String, dynamic>.from(selected);
    final customerName = customer != null
        ? customer['name'].toString()
        : 'Walk-in Customer (Quick Bill)';
    final customerPhone = customer != null
        ? (customer['phone']?.toString() ?? '')
        : '';
    final balanceDue = (saleFinalTotal - receivedAmount).clamp(0.0, double.infinity).toDouble();
    final currentUser = FirebaseAuth.instance.currentUser;
    final sale = <String, dynamic>{
      'salesman_uid': currentUser?.uid,
      'salesman_name': currentUser?.displayName ?? currentUser?.email ?? 'Unknown',
      'total_amount': saleSubtotal,
      'discount': saleDiscount,
      'final_amount': saleFinalTotal,
      'payment_type': paymentType,
      'customer_type': saleType,
      'received_amount': receivedAmount,
      'balance_due': balanceDue,
      'customer_id': customer?['id'],
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
        customerPaymentMode = 'Cash';
        receivedAmountController.clear();
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
            salesType: saleType,
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
        title: const Text('POS Billing (Quick & Khata)'),
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
          // Customer category is independent from the payment method.
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            color: Colors.teal.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, color: Colors.teal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: selectedSaleType,
                        decoration: const InputDecoration(
                          labelText: 'Customer Type',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Walk-in', child: Text('Walk-in / Retail')),
                          DropdownMenuItem(value: 'Khata', child: Text('Khata Customer')),
                        ],
                        onChanged: (value) {
                          if (value != null) _setSaleType(value);
                        },
                      ),
                    ),
                    if (selectedSaleType != 'Walk-in')
                      IconButton(
                        tooltip: 'Add ${selectedSaleType} Customer',
                        onPressed: _addKhataCustomer,
                        icon: const Icon(Icons.person_add_alt_1, color: Colors.teal),
                      ),
                  ],
                ),
                if (selectedSaleType != 'Walk-in') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: selectedCustomerId,
                    decoration: InputDecoration(
                      labelText: 'Select Khata Customer',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    items: customers
                        .map((c) => DropdownMenuItem<int>(
                              value: (c['id'] as num).toInt(),
                              child: Text('${c['name']}  |  Balance Rs. ${c['balance']}'),
                            ))
                        .toList(),
                    onChanged: (id) => setState(() => selectedCustomerId = id),
                  ),
                ] else
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Walk-in sale: cash payment.', style: TextStyle(color: Colors.black54)),
                  ),
                if (selectedSaleType == 'Khata') ...[
                  const SizedBox(height: 8),
                  const Text('Payment Method', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Cash', label: Text('Cash')),
                      ButtonSegment(value: 'Credit', label: Text('Credit')),
                      ButtonSegment(value: 'Partial', label: Text('Partial')),
                    ],
                    selected: {customerPaymentMode},
                    onSelectionChanged: (selection) => setState(() {
                      customerPaymentMode = selection.first;
                      receivedAmountController.clear();
                    }),
                  ),
                  if (customerPaymentMode == 'Partial') ...[
                    const SizedBox(height: 6),
                    TextField(
                      controller: receivedAmountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Cash Received (Rs.)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
                if (selectedCustomer != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      '${selectedCustomer!['name']}  |  Outstanding: Rs. ${selectedCustomer!['balance']}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                    ),
                  ),
              ],
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
                          onTap: () => _editSalePrice(index),
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
                                'Rs. ${((item['salePrice'] as num).toDouble() * (item['quantity'] as num).toInt())}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Edit sale price',
                                icon: const Icon(Icons.edit, color: Colors.teal),
                                onPressed: () => _editSalePrice(index),
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
          SafeArea(
            top: false,
            child: Container(
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
                      onPressed: cart.isEmpty || isCheckingOut ? null : _checkout,
                      icon: isCheckingOut
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.print),
                      label: Text(isCheckingOut ? 'Saving...' : 'Checkout / Print'),
                    ),
                  ],
                ),
              ],
            ),
            ),
          ),
        ],
      ),
    );
  }
}
