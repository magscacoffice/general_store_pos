import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import 'db_helper.dart';
import 'scanner_screen.dart';
import 'printer_screen.dart';
import 'windows/pos_windows.dart';

// Dashboard restore uses this hook to flush the active cashier bill first.
Future<void> Function()? windowsBeforeDatabaseRestore;

class SalesScreen extends StatefulWidget {
  final String? billId;

  const SalesScreen({super.key, this.billId});

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
  final TextEditingController _usbBarcodeController = TextEditingController();
  final FocusNode _usbBarcodeFocusNode = FocusNode();
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
  late String _activeBillId;
  List<Map<String, dynamic>> _openBills = [];
  Future<void> _pendingSaveQueue = Future<void>.value();
  bool _restoringBills = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) windowsBeforeDatabaseRestore = _flushBillBeforeDatabaseRestore;
    _activeBillId = widget.billId ?? PosWindows.newBillId();
    _loadCustomers();
    if (Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_focusUsbScanner());
      });
      unawaited(_restorePendingBills().whenComplete(_focusUsbScanner));
    }
  }

  Future<void> _focusUsbScanner() async {
    if (!Platform.isWindows || !mounted) return;
    try {
      final window = WindowManager.instance.getCurrent();
      window?.show();
      window?.focus();
    } catch (_) {
      // The scanner field can still receive focus if native focus is unavailable.
    }
    if (mounted) _usbBarcodeFocusNode.requestFocus();
  }

  Map<String, dynamic> _snapshotCurrentBill() => {
    'bill_id': _activeBillId,
    'label': _billLabel(_activeBillId),
    'cart': cart.map((item) => Map<String, dynamic>.from(item)).toList(),
    'selectedCustomerId': selectedCustomerId,
    'selectedSaleType': selectedSaleType,
    'customerPaymentMode': customerPaymentMode,
    'overallDiscount': overallDiscount,
    'isPercentageDiscount': isPercentageDiscount,
    'receivedAmount': receivedAmountController.text,
  };

  String _billLabel(String billId) {
    for (final bill in _openBills) {
      if (bill['bill_id'] == billId) return bill['label']?.toString() ?? 'Pending Bill';
    }
    final suffix = billId.length > 4
        ? billId.substring(billId.length - 4)
        : billId;
    return 'Bill #$suffix';
  }

  Future<void> _persistActiveBill() async {
    if (!Platform.isWindows || _restoringBills || _activeBillId.isEmpty) return;
    if (cart.isEmpty) {
      final billId = _activeBillId;
      _openBills.removeWhere((bill) => bill['bill_id'] == billId);
      _pendingSaveQueue = _pendingSaveQueue.then((_) async {
        await DBHelper.deletePendingBill(billId);
      }).catchError((Object error) {
        debugPrint('Empty pending bill cleanup failed: $error');
      });
      await _pendingSaveQueue;
      return;
    }
    final snapshot = _snapshotCurrentBill();
    final index = _openBills.indexWhere((bill) => bill['bill_id'] == _activeBillId);
    if (index >= 0) {
      _openBills[index] = snapshot;
    } else {
      _openBills.insert(0, snapshot);
    }
    _pendingSaveQueue = _pendingSaveQueue.then((_) async {
      await DBHelper.savePendingBill(snapshot);
    }).catchError((Object error) {
      debugPrint('Pending bill save failed: $error');
    });
    await _pendingSaveQueue;
  }

  Future<void> _restorePendingBills() async {
    _restoringBills = true;
    try {
      final saved = await DBHelper.getPendingBills();
      if (!mounted) return;
      final matching = saved.where(
        (bill) => bill['bill_id']?.toString() == _activeBillId,
      ).toList();
      if (matching.isNotEmpty) {
        _openBills = [matching.first];
        _applyBillSnapshot(matching.first);
      } else {
        _openBills = [_snapshotCurrentBill()];
      }
    } catch (error) {
      debugPrint('Pending bills restore failed: $error');
      if (mounted) _openBills = [_snapshotCurrentBill()];
    } finally {
      _restoringBills = false;
      if (mounted) await _persistActiveBill();
    }
  }

  void _applyBillSnapshot(Map<String, dynamic> snapshot) {
    _restoringBills = true;
    setState(() {
      _activeBillId = snapshot['bill_id'].toString();
      cart = (snapshot['cart'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      selectedCustomerId = (snapshot['selectedCustomerId'] as num?)?.toInt();
      selectedSaleType = snapshot['selectedSaleType']?.toString() ?? 'Walk-in';
      customerPaymentMode = snapshot['customerPaymentMode']?.toString() ?? 'Cash';
      overallDiscount = (snapshot['overallDiscount'] as num?)?.toDouble() ?? 0.0;
      isPercentageDiscount = snapshot['isPercentageDiscount'] == true;
      receivedAmountController.text = snapshot['receivedAmount']?.toString() ?? '';
    });
    _restoringBills = false;
  }

  Future<void> _createNewBill() async {
    if (Platform.isWindows) {
      await _persistActiveBill();
      await PosWindows.openSale();
      return;
    }
    await _persistActiveBill();
    final nextId = PosWindows.newBillId();
    final nextLabel = 'Bill ${_openBills.length + 1}';
    setState(() {
      _activeBillId = nextId;
      cart = [];
      selectedCustomerId = null;
      selectedSaleType = 'Walk-in';
      customerPaymentMode = 'Cash';
      overallDiscount = 0;
      isPercentageDiscount = false;
      receivedAmountController.clear();
      _openBills.insert(0, {
        'bill_id': nextId,
        'label': nextLabel,
        'cart': <Map<String, dynamic>>[],
        'selectedCustomerId': null,
        'selectedSaleType': 'Walk-in',
        'customerPaymentMode': 'Cash',
        'overallDiscount': 0.0,
        'isPercentageDiscount': false,
        'receivedAmount': '',
      });
    });
    await _persistActiveBill();
  }

  Future<void> _switchBill(String billId) async {
    if (billId == _activeBillId) return;
    await _persistActiveBill();
    final selected = _openBills.firstWhere(
      (bill) => bill['bill_id'] == billId,
      orElse: () => <String, dynamic>{},
    );
    if (selected.isEmpty || !mounted) return;
    _applyBillSnapshot(selected);
  }

  Future<void> _completeActiveBill() async {
    await _pendingSaveQueue;
    await DBHelper.deletePendingBill(_activeBillId);
    _openBills.removeWhere((bill) => bill['bill_id'] == _activeBillId);
    if (_openBills.isNotEmpty) {
      _applyBillSnapshot(_openBills.first);
    } else {
      final nextId = DateTime.now().microsecondsSinceEpoch.toString();
      setState(() {
        _activeBillId = nextId;
        cart = [];
        selectedCustomerId = null;
        selectedSaleType = 'Walk-in';
        customerPaymentMode = 'Cash';
        overallDiscount = 0;
        isPercentageDiscount = false;
        receivedAmountController.clear();
      });
      await _persistActiveBill();
    }
  }


  bool _isPreparingForDatabaseRestore = false;

  Future<void> _flushBillBeforeDatabaseRestore() async {
    if (!Platform.isWindows) return;
    _isPreparingForDatabaseRestore = true;
    try {
      await _pendingSaveQueue;
      await _persistActiveBill();
      await _pendingSaveQueue;
    } catch (_) {
      _isPreparingForDatabaseRestore = false;
      rethrow;
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) windowsBeforeDatabaseRestore = null;
    // The restore handler has already flushed the bill and closed SQLite.
    // Do not let dispose() reopen the database while the restore replaces it.
    if (!_isPreparingForDatabaseRestore) {
      unawaited(_persistActiveBill());
    }
    receivedAmountController.dispose();
    _usbBarcodeController.dispose();
    _productSearchController.dispose();
    _usbBarcodeFocusNode.dispose();
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
    unawaited(_persistActiveBill());
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
        await _persistActiveBill();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New Khata customer added and selected.')),
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
                                    'Barcode: ${product['barcode'] ?? '—'}  |  Stock: $stock  |  Rate: Rs. ${product['price'] ?? 0}',
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
          SnackBar(content: Text('Available stock sirf $stock pieces hai.')),
        );
        return;
      }
      final purchasePrice = (selected['purchasePrice'] as num?)?.toDouble() ?? 0.0;
      final configuredSalePrice = (selected['price'] as num?)?.toDouble() ?? 0.0;
      final safeSalePrice = configuredSalePrice < purchasePrice ? purchasePrice : configuredSalePrice;
      setState(() {
        if (existingIndex >= 0) {
          cart[existingIndex]['quantity'] = alreadyInCart + 1;
        } else {
          cart.add({
            'barcode': barcode,
            'name': selected['name']?.toString() ?? 'Product',
            'purchasePrice': purchasePrice,
            'salePrice': safeSalePrice,
            'quantity': 1,
          });
        }
        _productSearchController.text = selected['name']?.toString() ?? '';
      });
      await _persistActiveBill();
      if (Platform.isWindows) {
        final window = WindowManager.instance.getCurrent();
        window?.show();
        window?.focus();
      }
    } finally {
      searchController.dispose();
      if (mounted && Platform.isWindows) _usbBarcodeFocusNode.requestFocus();
    }
  }

  Future<void> _handleUnifiedProductInput(String rawInput) async {
    final value = rawInput.trim();
    if (value.isEmpty || !mounted) return;
    _usbBarcodeController.clear();
    final products = await DBHelper.getProducts();
    if (!mounted) return;
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
    _usbBarcodeController.clear();
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
      final configuredSalePrice = (product['price'] as num?)?.toDouble() ?? 0.0;
      final safeSalePrice = configuredSalePrice < purchasePrice ? purchasePrice : configuredSalePrice;
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
            'quantity': 1,
          });
        }
      });
      await _persistActiveBill();
      if (Platform.isWindows) {
        final window = WindowManager.instance.getCurrent();
        window?.show();
        window?.focus();
        _usbBarcodeFocusNode.requestFocus();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Barcode add nahi ho saka: $error')),
      );
    } finally {
      if (mounted && Platform.isWindows) _usbBarcodeFocusNode.requestFocus();
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
      final salePrice = (product['price'] as num?)?.toDouble() ?? cost;
      final effectiveSalePrice = salePrice < cost ? cost : salePrice;
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
            'quantity': saleQuantity,
          });
        }
      });
      await _persistActiveBill();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock purchase record ho gaya aur item bill mein add ho gaya.')),
      );
      _usbBarcodeFocusNode.requestFocus();
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
      await _persistActiveBill();
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
        if (updatedQuantity > availableStock) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Available stock sirf ' + availableStock.toString() + ' pieces hai.')));
          return;
        }
        setState(() => cart[index]['quantity'] = updatedQuantity);
        await _persistActiveBill();
      }
    } finally {
      controller.dispose();
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
        await _persistActiveBill();
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
                    unawaited(_persistActiveBill());
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

  Future<void> _openPendingBills() async {
    await _persistActiveBill();
    final pending = await DBHelper.getPendingBills();
    if (!mounted) return;
    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Koi held/pending bill mojood nahi hai.')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Held / Pending Bills'),
        content: SizedBox(
          width: 520,
          height: 380,
          child: ListView.separated(
            itemCount: pending.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final bill = pending[index];
              final id = bill['bill_id'].toString();
              final items = (bill['cart'] as List? ?? []).length;
              final updated = bill['updated_at']?.toString() ?? '';
              return ListTile(
                leading: const Icon(Icons.receipt_long, color: Colors.teal),
                title: Text(bill['label']?.toString() ?? 'Pending Bill'),
                subtitle: Text('$items items  •  $updated'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () {
                  Navigator.pop(dialogContext);
                  if (id == _activeBillId) return;
                  unawaited(PosWindows.openSale(billId: id));
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmLeaveBill() async {
    if (!Platform.isWindows) return true;
    if (cart.isEmpty) {
      await _persistActiveBill();
      return true;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bill abhi complete nahi hua'),
        content: const Text(
          'Aap ke bill mein items mojood hain. Billing jari rakhne ke liye Continue Billing dabayen, ya bill band karne ke liye Discard Bill.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Continue Billing'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard Bill'),
          ),
        ],
      ),
    );
    if (discard == true) {
      await _pendingSaveQueue;
      await DBHelper.deletePendingBill(_activeBillId);
      _openBills.removeWhere((bill) => bill['bill_id'] == _activeBillId);
      return true;
    }
    await _persistActiveBill();
    return false;
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
      if (Platform.isWindows) {
        await _completeActiveBill();
      } else {
        setState(() {
          cart.clear();
          overallDiscount = 0.0;
          isPercentageDiscount = false;
          selectedCustomerId = null;
          customerPaymentMode = 'Cash';
          receivedAmountController.clear();
        });
      }

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
                        onChanged: (id) {
                          setState(() => selectedCustomerId = id);
                          unawaited(_persistActiveBill());
                        },
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
                        onSelectionChanged: (selection) {
                          setState(() {
                            customerPaymentMode = selection.first;
                            receivedAmountController.clear();
                          });
                          unawaited(_persistActiveBill());
                        },
                      ),
                      if (customerPaymentMode == 'Partial') ...[
                        const SizedBox(height: 6),
                        TextField(
                          controller: receivedAmountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => unawaited(_persistActiveBill()),
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
        : Platform.isWindows
            ? Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(color: const Color(0xFFD9E0E6)),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                        headingRowHeight: 40,
                        dataRowMinHeight: 42,
                        dataRowMaxHeight: 50,
                        columns: const [
                          DataColumn(label: Text('Product')),
                          DataColumn(label: Text('Barcode')),
                          DataColumn(label: Text('Qty'), numeric: true),
                          DataColumn(label: Text('Unit Rate'), numeric: true),
                          DataColumn(label: Text('Line Total'), numeric: true),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: cart.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
                          final rate = (item['salePrice'] as num?)?.toDouble() ?? 0;
                          return DataRow(cells: [
                            DataCell(SizedBox(
                              width: 220,
                              child: Text(
                                item['name']?.toString() ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            )),
                            DataCell(SizedBox(
                              width: 120,
                              child: Text(item['barcode']?.toString() ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis),
                            )),
                            DataCell(Text('$quantity')),
                            DataCell(Text('Rs. ${rate.toStringAsFixed(2)}')),
                            DataCell(Text('Rs. ${(rate * quantity).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600))),
                            DataCell(Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(tooltip: 'Edit quantity', icon: const Icon(Icons.numbers, color: Colors.deepOrange), onPressed: () => _editQuantity(index)),
                                IconButton(tooltip: 'Edit sale rate', icon: const Icon(Icons.edit_outlined, color: Colors.teal), onPressed: () => _editSalePrice(index)),
                                IconButton(
                                  tooltip: 'Remove item',
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () {
                                    setState(() => cart.removeAt(index));
                                    unawaited(_persistActiveBill());
                                  },
                                ),
                              ],
                            )),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              )
            : ListView.builder(
                itemCount: cart.length,
                itemBuilder: (context, index) {
                  final item = cart[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: ListTile(
                      title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Rate: Rs. ${item['salePrice']}  |  Qty: ${item['quantity']}  |  Amount: Rs. ${((item['salePrice'] as num).toDouble() * (item['quantity'] as num).toInt()).toStringAsFixed(2)}'),
                      trailing: Wrap(
                        spacing: 0,
                        children: [
                          IconButton(tooltip: 'Edit quantity', icon: const Icon(Icons.numbers, color: Colors.deepOrange), onPressed: () => _editQuantity(index)),
                          IconButton(tooltip: 'Edit sale rate', icon: const Icon(Icons.edit, color: Colors.teal), onPressed: () => _editSalePrice(index)),
                          IconButton(tooltip: 'Remove item', icon: const Icon(Icons.delete, color: Colors.red), onPressed: () {
                            setState(() => cart.removeAt(index));
                            unawaited(_persistActiveBill());
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
                                fontSize: Platform.isWindows ? 16 : 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal,
                              ),
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Platform.isWindows ? const Color(0xFF263442) : Colors.white,
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
    return WillPopScope(
      onWillPop: _confirmLeaveBill,
      child: Focus(
        autofocus: Platform.isWindows,
        onKeyEvent: (node, event) {
          if (!Platform.isWindows) return KeyEventResult.ignored;
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.keyN &&
                HardwareKeyboard.instance.isControlPressed) {
              unawaited(_createNewBill());
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.f2) {
              unawaited(_searchAndAddProduct());
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.f5) {
              unawaited(_openPendingBills());
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.f4) {
              // Hold the current bill and open a fresh one.
              unawaited(_createNewBill());
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !Platform.isWindows,
        title: Text(
          Platform.isWindows ? 'KHAN BABA POS  |  NEW SALE' : 'POS Billing (Quick & Khata)',
          style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.3),
        ),
        backgroundColor: Platform.isWindows ? const Color(0xFFF7F9FB) : Colors.teal.shade800,
        foregroundColor: Platform.isWindows ? const Color(0xFF263442) : Colors.white,
        actions: [
          if (Platform.isWindows) ...[
            IconButton(
              tooltip: 'New Bill - Ctrl+N',
              icon: const Icon(Icons.add_box_outlined),
              onPressed: _createNewBill,
            ),
            IconButton(
              tooltip: 'Open Held Bills - F5',
              icon: const Icon(Icons.inventory_2_outlined),
              onPressed: _openPendingBills,
            ),
            IconButton(
              tooltip: 'Open Dashboard in a separate window',
              icon: const Icon(Icons.dashboard_outlined),
              onPressed: PosWindows.openDashboard,
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            tooltip: 'Scan barcode',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _scanAndAddToCart,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Platform.isWindows
          ? Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SizedBox(
                      height: 42,
                      child: TextField(
                        controller: _usbBarcodeController,
                        focusNode: _usbBarcodeFocusNode,
                        autofocus: true,
                        onSubmitted: _handleUnifiedProductInput,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.qr_code_scanner),
                          labelText: 'Scan / Search Product',
                          hintText: 'Scan barcode or type product name, then press Enter',
                          suffixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                  Expanded(
                    flex: 7,
                    child: Column(
                      children: [
                        _buildCustomerPanel(),
                        const SizedBox(height: 8),
                        _buildBillReviewHeading(),
                        _buildCartList(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(width: 340, child: _buildCheckoutPanel()),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                _buildCustomerPanel(),
                _buildBillReviewHeading(),
                _buildCartList(),
                _buildCheckoutPanel(),
              ],
            ),
      ),
      ),
    );
  }
}
