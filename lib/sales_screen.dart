
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import 'db_helper.dart';
import 'scanner_screen.dart';
import 'printer_screen.dart';

class SalesScreen extends StatefulWidget {
  final bool embeddedInDashboard;

  const SalesScreen({
    super.key,
    this.embeddedInDashboard = false,
  });

  @override
  State<SalesScreen> createState() => SalesScreenState();
}

class SalesScreenState extends State<SalesScreen> {
  List<Map<String, dynamic>> cart = [];
  List<Map<String, dynamic>> customers = [];
  int? selectedCustomerId;
  String selectedSaleType = 'Walk-in';
  String customerPaymentMode = 'Cash';
  final TextEditingController receivedAmountController = TextEditingController();
  final TextEditingController _productSearchController = TextEditingController();

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
    _productSearchController.dispose();
    super.dispose();
  }

  double _salePriceForProduct(Map<String, dynamic> product, {double? purchasePriceOverride}) {
    final purchasePrice = purchasePriceOverride ??
        (product['purchasePrice'] as num?)?.toDouble() ?? 0.0;
    final retailPrice = (product['price'] as num?)?.toDouble() ?? purchasePrice;
    final wholesalePrice = (product['wholesalePrice'] as num?)?.toDouble() ?? 0.0;
    final configuredPrice = selectedSaleType == 'Wholesale' && wholesalePrice > 0
        ? wholesalePrice
        : retailPrice;
    return configuredPrice < purchasePrice ? purchasePrice : configuredPrice;
  }

  Future<void> _loadCustomers() async {
    final data = await DBHelper.getParties('customer');
    if (!mounted) return;
    setState(() {
      customers = data;
      if (selectedCustomerId != null &&
          !customers.any((c) =>
              (c['id'] as num?)?.toInt() == selectedCustomerId &&
              (c['customer_type']?.toString() ?? 'Khata') == selectedSaleType)) {
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
          title: Text('Add New $selectedSaleType Customer'),
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
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final permission = await FlutterContacts.permissions.request(PermissionType.read);
                      if (permission != PermissionStatus.granted) {
                        if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(content: Text('Contacts permission allow karein.')),
                        );
                        return;
                      }
                      final contact = await FlutterContacts.native.showPicker(properties: {ContactProperty.phone});
                      if (contact != null && dialogContext.mounted) {
                        nameController.text = contact.displayName ?? '';
                        if (contact.phones.isNotEmpty) phoneController.text = contact.phones.first.number;
                      }
                    } catch (e) {
                      if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text('Contact open nahi ho saka: $e')),
                      );
                    }
                  },
                  icon: const Icon(Icons.contacts),
                  label: const Text('Phone Contacts Se Chunein'),
                ),
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
                    'customer_type': selectedSaleType,
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
          SnackBar(content: Text('New $selectedSaleType customer added and selected.')),
        );
      }
    } finally {
      nameController.dispose();
      phoneController.dispose();
    }
  }

  Future<void> _searchAndAddProduct() async {
    final products = await DBHelper.getProducts();
    if (!mounted) return;
    final searchController = TextEditingController(
      text: _productSearchController.text.trim(),
    );
    var query = searchController.text;
    try {
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final term = query.trim().toLowerCase();
            final matches = products.where((product) {
              final name = product['name']?.toString().toLowerCase() ?? '';
              final barcode = product['barcode']?.toString().toLowerCase() ?? '';
              return term.isEmpty || name.contains(term) || barcode.contains(term);
            }).toList();
            return AlertDialog(
              title: const Text('Find product by name or barcode'),
              content: SizedBox(
                width: 560,
                height: 460,
                child: Column(
                  children: [
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      onChanged: (value) => setDialogState(() => query = value),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Type product name or barcode',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${matches.length} matching products',
                        style: Theme.of(dialogContext).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: matches.isEmpty
                          ? const Center(child: Text('No matching products found.'))
                          : ListView.separated(
                              itemCount: matches.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final product = matches[index];
                                final stock = (product['quantity'] as num?)?.toInt() ?? 0;
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    product['name']?.toString() ?? 'Unnamed product',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    'Barcode: ${product['barcode'] ?? '—'}  |  Stock: $stock ${product['stock_unit'] ?? 'pcs'}  |  Rate: Rs. ${product['price'] ?? 0}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  enabled: stock > 0,
                                  trailing: stock > 0
                                      ? const Icon(Icons.add_circle_outline)
                                      : const Text('Out of stock'),
                                  onTap: stock > 0
                                      ? () => Navigator.pop(dialogContext, product)
                                      : null,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        ),
      );
      if (selected == null || !mounted) return;
      final barcode = selected['barcode']?.toString() ?? '';
      final stock = (selected['quantity'] as num?)?.toInt() ?? 0;
      final existingIndex = cart.indexWhere(
        (item) => item['barcode']?.toString() == barcode,
      );
      final alreadyInCart = existingIndex < 0
          ? 0
          : (cart[existingIndex]['quantity'] as num?)?.toInt() ?? 0;
      if (stock <= alreadyInCart) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Available stock sirf $stock ${selected['stock_unit'] ?? 'pcs'} hai.')),
        );
        return;
      }
      final purchasePrice = (selected['purchasePrice'] as num?)?.toDouble() ?? 0.0;
      final safeSalePrice = _salePriceForProduct(selected);
      setState(() {
        if (existingIndex >= 0) {
          cart[existingIndex]['quantity'] = alreadyInCart + 1;
        } else {
          cart.add({
            'barcode': barcode,
            'name': selected['name']?.toString() ?? 'Product',
            'purchasePrice': purchasePrice,
            'salePrice': safeSalePrice,
            'stockUnit': selected['stock_unit']?.toString() ?? 'pcs',
            'quantity': 1,
          });
        }
        _productSearchController.text = selected['name']?.toString() ?? '';
      });

    } finally {
      searchController.dispose();
    }
  }

  Future<void> _addSelectedSearchProduct(Map<String, dynamic> selected) async {
    if (!mounted) return;
    final barcode = selected['barcode']?.toString() ?? '';
    List<Map<String, dynamic>> latestProducts;
    try {
      latestProducts = await DBHelper.getProducts();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Product stock refresh nahi ho saka: $error')),
        );
      }
      return;
    }
    if (!mounted) return;
    
    final matches = latestProducts.where(
      (product) => product['barcode']?.toString() == barcode,
    );
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ye product ab inventory mein mojood nahi hai.')),
      );
      return;
    }
    final currentProduct = matches.first;
    final stock = (currentProduct['quantity'] as num?)?.toInt() ?? 0;
    final existingIndex = cart.indexWhere((item) => item['barcode']?.toString() == barcode);
    final alreadyInCart = existingIndex < 0
        ? 0
        : (cart[existingIndex]['quantity'] as num?)?.toInt() ?? 0;
    if (stock <= alreadyInCart) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Available stock sirf $stock ${currentProduct['stock_unit'] ?? 'pcs'} hai.')),
      );
      return;
    }
    final purchasePrice = (currentProduct['purchasePrice'] as num?)?.toDouble() ?? 0.0;
    final safeSalePrice = _salePriceForProduct(currentProduct);
    setState(() {
      if (existingIndex >= 0) {
        cart[existingIndex]['quantity'] = alreadyInCart + 1;
      } else {
        cart.add({
          'barcode': barcode,
          'name': currentProduct['name']?.toString() ?? 'Product',
          'purchasePrice': purchasePrice,
          'salePrice': safeSalePrice,
          'stockUnit': currentProduct['stock_unit']?.toString() ?? 'pcs',
          'quantity': 1,
        });
      }

    });

  }

  Future<void> _handleUnifiedProductInput(String rawInput) async {
    final value = rawInput.trim();
    if (value.isEmpty || !mounted) return;
    final products = await DBHelper.getProducts();
    final exactBarcode = products.any(
      (product) => product['barcode']?.toString().trim() == value,
    );
    if (exactBarcode) {
      await _addUsbBarcode(value);
      return;
    }
    _productSearchController.text = value;
    await _searchAndAddProduct();
  }

  Future<void> _addUsbBarcode(String rawBarcode) async {
    final barcode = rawBarcode.trim();
    if (barcode.isEmpty || !mounted) return;

    try {
      final products = await DBHelper.getProducts();
      if (!mounted) return;
      final matches = products.where(
        (product) => product['barcode']?.toString().trim() == barcode,
      );
      if (matches.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Barcode $barcode ka product inventory mein nahi mila.')),
        );
        return;
      }
      final product = matches.first;
      final stock = (product['quantity'] as num?)?.toInt() ?? 0;
      final purchasePrice = (product['purchasePrice'] as num?)?.toDouble() ?? 0.0;
      final safeSalePrice = _salePriceForProduct(product);
      final existingIndex = cart.indexWhere(
        (item) => item['barcode']?.toString() == barcode,
      );
      final alreadyInCart = existingIndex < 0
          ? 0
          : (cart[existingIndex]['quantity'] as num?)?.toInt() ?? 0;
      if (stock <= alreadyInCart) {
        await _showUsbRestockDialog(product, barcode);
        return;
      }
      setState(() {
        if (existingIndex >= 0) {
          cart[existingIndex]['quantity'] = alreadyInCart + 1;
        } else {
          cart.add({
            'barcode': barcode,
            'name': product['name']?.toString() ?? 'Product',
            'purchasePrice': purchasePrice,
            'salePrice': safeSalePrice,
            'stockUnit': product['stock_unit']?.toString() ?? 'pcs',
            'quantity': 1,
          });
        }
      });

    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Barcode add nahi ho saka: $error')),
      );
    } finally {
      
    }
  }

  Future<void> _showUsbRestockDialog(
    Map<String, dynamic> product,
    String barcode,
  ) async {
    final quantityController = TextEditingController(text: '10');
    final saleQuantityController = TextEditingController(text: '1');
    final costController = TextEditingController(
      text: ((product['purchasePrice'] as num?)?.toDouble() ?? 0).toString(),
    );
    try {
      final details = await showDialog<Map<String, double>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('${product['name']} - Stock khatam'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Naya stock record kar ke isi bill mein item add karein.'),
              const SizedBox(height: 10),
              TextField(
                controller: quantityController,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Restock quantity'),
              ),
              TextField(
                controller: costController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Purchase cost per item (Rs.)'),
              ),
              TextField(
                controller: saleQuantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity for this bill'),
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
                final quantity = int.tryParse(quantityController.text.trim());
                final saleQuantity = int.tryParse(saleQuantityController.text.trim());
                final cost = double.tryParse(costController.text.trim());
                if (quantity == null || quantity <= 0 ||
                    saleQuantity == null || saleQuantity <= 0 ||
                    saleQuantity > quantity || cost == null ||
                    !cost.isFinite || cost < 0) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Quantity aur purchase cost durust enter karein.')),
                  );
                  return;
                }
                Navigator.pop(dialogContext, {
                  'quantity': quantity.toDouble(),
                  'saleQuantity': saleQuantity.toDouble(),
                  'cost': cost,
                });
              },
              child: const Text('Restock & Add'),
            ),
          ],
        ),
      );
      if (details == null || !mounted) return;
      final quantity = details['quantity']!.toInt();
      final saleQuantity = details['saleQuantity']!.toInt();
      final cost = details['cost']!;
      await DBHelper.recordPurchase(
        productId: (product['id'] as num).toInt(),
        quantity: quantity,
        unitCost: cost,
      );
      final effectiveSalePrice = _salePriceForProduct(product, purchasePriceOverride: cost);
      setState(() {
        final index = cart.indexWhere((item) => item['barcode']?.toString() == barcode);
        if (index >= 0) {
          cart[index]['quantity'] = ((cart[index]['quantity'] as num).toInt()) + saleQuantity;
          cart[index]['purchasePrice'] = cost;
          if ((cart[index]['salePrice'] as num).toDouble() < cost) {
            cart[index]['salePrice'] = cost;
          }
        } else {
          cart.add({
            'barcode': barcode,
            'name': product['name']?.toString() ?? 'Product',
            'purchasePrice': cost,
            'salePrice': effectiveSalePrice,
            'stockUnit': product['stock_unit']?.toString() ?? 'pcs',
            'quantity': saleQuantity,
          });
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock purchase record ho gaya aur item bill mein add ho gaya.')),
      );
      
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restock nahi ho saka: $error')),
      );
    } finally {
      quantityController.dispose();
      saleQuantityController.dispose();
      costController.dispose();
    }
  }

  void _scanAndAddToCart() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ScannerScreen(customerType: selectedSaleType)),
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
            SnackBar(content: Text('Stock se zyada quantity select ho rahi hai: ${item['name']} (${item['stockUnit'] ?? 'pcs'})')),
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

  Future<void> _editQuantity(int index) async {
    final currentQuantity = (cart[index]['quantity'] as num?)?.toInt() ?? 1;
    final controller = TextEditingController(text: currentQuantity.toString());
    try {
      final updatedQuantity = await showDialog<int>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Quantity: ' + cart[index]['name'].toString()),
          content: TextField(
            controller: controller, autofocus: true, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Final quantity', helperText: 'Bill review mein quantity set karein.'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final value = int.tryParse(controller.text.trim());
                if (value == null || value <= 0) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Quantity zero se zyada honi chahiye.')));
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (updatedQuantity != null && mounted) {
        final products = await DBHelper.getProducts();
        final barcode = cart[index]['barcode']?.toString();
        final matchingProducts = products.where((p) => p['barcode']?.toString() == barcode).toList();
        final availableStock = matchingProducts.isEmpty ? 0 : (matchingProducts.first['quantity'] as num?)?.toInt() ?? 0;
        final stockUnit = matchingProducts.isEmpty ? 'pcs' : (matchingProducts.first['stock_unit']?.toString() ?? 'pcs');
        if (updatedQuantity > availableStock) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Available stock sirf $availableStock $stockUnit hai.')));
          return;
        }
        setState(() => cart[index]['quantity'] = updatedQuantity);

      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _editSalePrice(int index) async {
    if (selectedSaleType != 'Wholesale') return;
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
                    ;
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
    final currentUser = DBHelper.localOnlyMode ? null : FirebaseAuth.instance.currentUser;
    final sale = <String, dynamic>{
      'salesman_uid': currentUser?.uid,
      'salesman_name': DBHelper.localOnlyMode
          ? 'Local Windows User'
          : (currentUser?.displayName ?? currentUser?.email ?? 'Unknown'),
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


  Widget _buildCustomerPanel() => 
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
                              DropdownMenuItem(value: 'Wholesale', child: Text('Wholesale Customer')),
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
                            .where((c) => (c['customer_type']?.toString() ?? 'Khata') == selectedSaleType)
                            .map((c) => DropdownMenuItem<int>(
                                  value: (c['id'] as num).toInt(),
                                  child: Text('${c['name']}  |  Balance Rs. ${c['balance']}'),
                                ))
                            .toList(),
                        onChanged: (id) {
                          setState(() => selectedCustomerId = id);
                          ;
                        },
                      ),
                    ] else
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('Walk-in sale: cash payment.', style: TextStyle(color: Colors.black54)),
                      ),
                    if (selectedSaleType == 'Khata' || selectedSaleType == 'Wholesale') ...[
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
                        onSelectionChanged: (selection) {
                          setState(() {
                            customerPaymentMode = selection.first;
                            receivedAmountController.clear();
                          });
                          ;
                        },
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
              );

  Widget _buildBillReviewHeading() =>
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Align(alignment: Alignment.centerLeft, child: Text('Bill Review - Save/Print se pehle items check karein', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal))),
              );

  Widget _buildCartList() => Expanded(
    child: cart.isEmpty
        ? const Center(child: Text('Cart is empty. Scan or search for products.'))
        : ListView.builder(
            itemCount: cart.length,
            itemBuilder: (context, index) {
              final item = cart[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: ListTile(
                  title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Rate: Rs. ${item['salePrice']} per ${item['stockUnit'] ?? 'pcs'}  |  Qty: ${item['quantity']} ${item['stockUnit'] ?? 'pcs'}  |  Amount: Rs. ${((item['salePrice'] as num).toDouble() * (item['quantity'] as num).toInt()).toStringAsFixed(2)}'),
                  trailing: Wrap(
                    spacing: 0,
                    children: [
                      IconButton(tooltip: 'Edit quantity', icon: const Icon(Icons.numbers, color: Colors.deepOrange), onPressed: () => _editQuantity(index)),
                      if (selectedSaleType == 'Wholesale')
                        IconButton(tooltip: 'Edit wholesale unit rate', icon: const Icon(Icons.edit, color: Colors.teal), onPressed: () => _editSalePrice(index)),
                      IconButton(tooltip: 'Remove item', icon: const Icon(Icons.delete, color: Colors.red), onPressed: () {
                        setState(() => cart.removeAt(index));
                        ;
                      }),
                    ],
                  ),
                ),
              );
            },
          ),
  );

  Widget _buildCheckoutPanel() =>
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
                              style: TextStyle(
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
              );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embeddedInDashboard ? null : AppBar(
        automaticallyImplyLeading: true,
        title: Text(
          'POS Billing (Quick & Khata)',
          style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.3),
        ),
        backgroundColor: Colors.teal.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Scan barcode',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _scanAndAddToCart,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildCustomerPanel(),
          _buildBillReviewHeading(),
          _buildCartList(),
          _buildCheckoutPanel(),
        ],
      ),
    );
  }
}
