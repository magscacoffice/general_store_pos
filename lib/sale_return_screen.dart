import 'package:flutter/material.dart';

import 'db_helper.dart';

class SaleReturnScreen extends StatefulWidget {
  final Map<String, dynamic> sale;
  const SaleReturnScreen({super.key, required this.sale});

  @override
  State<SaleReturnScreen> createState() => _SaleReturnScreenState();
}

class _SaleReturnScreenState extends State<SaleReturnScreen> {
  List<Map<String, dynamic>> _items = [];
  final Map<int, TextEditingController> _quantities = {};
  final Map<int, String> _conditions = {};
  final TextEditingController _reasonController = TextEditingController();
  String _refundMethod = 'Cash';
  bool _loading = true;
  bool _saving = false;

  int get _saleId => (widget.sale['id'] as num).toInt();
  int? get _customerId => (widget.sale['customer_id'] as num?)?.toInt();

  double get _saleTotal =>
      (widget.sale['effective_amount'] as num?)?.toDouble() ??
      (widget.sale['final_amount'] as num?)?.toDouble() ??
      (widget.sale['total_amount'] as num?)?.toDouble() ?? 0.0;

  double get _receivedAmount =>
      (widget.sale['received_amount'] as num?)?.toDouble() ??
      ((widget.sale['payment_type']?.toString() ?? 'Khata') == 'Cash'
          ? _saleTotal
          : 0.0);

  @override
  void initState() {
    super.initState();
    _refundMethod = _customerId != null && _receivedAmount <= 0 ? 'Khata' : 'Cash';
    _load();
  }

  @override
  void dispose() {
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await DBHelper.getReturnableSaleItems(_saleId);
    if (!mounted) return;
    for (final row in rows) {
      final id = (row['id'] as num).toInt();
      _quantities[id] = TextEditingController(text: '0');
      _conditions[id] = 'saleable';
    }
    setState(() {
      _items = rows;
      _loading = false;
    });
  }

  double get _estimatedRefund {
    var gross = 0.0;
    for (final item in _items) {
      final id = (item['id'] as num).toInt();
      final quantity = int.tryParse(_quantities[id]?.text ?? '') ?? 0;
      final allowed = (item['returnable_quantity'] as num?)?.toInt() ?? 0;
      if (quantity <= 0 || quantity > allowed) continue;
      gross += (item['sale_price'] as num).toDouble() * quantity;
    }
    final subtotal = (widget.sale['total_amount'] as num?)?.toDouble() ?? gross;
    final discount = (widget.sale['discount'] as num?)?.toDouble() ?? 0.0;
    if (subtotal <= 0) return gross;
    final discountShare = (discount * gross / subtotal).clamp(0.0, gross).toDouble();
    return (gross - discountShare).clamp(0.0, double.infinity).toDouble();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final selected = <Map<String, dynamic>>[];
    for (final item in _items) {
      final id = (item['id'] as num).toInt();
      final quantity = int.tryParse(_quantities[id]?.text.trim() ?? '') ?? 0;
      if (quantity == 0) continue;
      final allowed = (item['returnable_quantity'] as num?)?.toInt() ?? 0;
      if (quantity < 0 || quantity > allowed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Return quantity ${item['product_name']} ke available $allowed se zyada nahi ho sakti.')),
        );
        return;
      }
      selected.add({
        'sale_item_id': id,
        'quantity': quantity,
        'condition': _conditions[id] ?? 'saleable',
      });
    }
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Return quantity enter karein.')),
      );
      return;
    }
    if (_reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Return reason likhna zaroori hai.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final returnId = await DBHelper.recordSaleReturn(
        saleId: _saleId,
        reason: _reasonController.text.trim(),
        refundMethod: _refundMethod,
        items: selected,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Return #$returnId save ho gaya. Refund: Rs. ${_estimatedRefund.toStringAsFixed(2)}')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Return save nahi ho saka: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customerName = widget.sale['customer_id'] == null
        ? 'Walk-in'
        : 'Customer #${widget.sale['customer_id']}';
    return Scaffold(
      appBar: AppBar(
        title: Text('Return Bill #$_saleId'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Card(
                    child: ListTile(
                      title: Text('Original Bill #$_saleId'),
                      subtitle: Text('${widget.sale['date'] ?? ''}  |  $customerName'),
                      trailing: Text(
                        'Rs. ${_saleTotal.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _items.isEmpty
                      ? const Center(child: Text('Is invoice mein returnable item details nahi milin.'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            final id = (item['id'] as num).toInt();
                            final available = (item['returnable_quantity'] as num?)?.toInt() ?? 0;
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item['product_name'].toString(),
                                        style: const TextStyle(fontWeight: FontWeight.bold)),
                                    Text('Sold: ${item['quantity']}  |  Already returned: ${item['returned_quantity']}  |  Available: $available'),
                                    Text('Rate: Rs. ${(item['sale_price'] as num).toStringAsFixed(2)}'),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: _quantities[id],
                                            enabled: available > 0,
                                            keyboardType: TextInputType.number,
                                            onChanged: (_) => setState(() {}),
                                            decoration: InputDecoration(
                                              labelText: 'Return quantity (max $available)',
                                              isDense: true,
                                              border: const OutlineInputBorder(),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                            value: _conditions[id],
                                            decoration: const InputDecoration(
                                              labelText: 'Condition',
                                              isDense: true,
                                              border: OutlineInputBorder(),
                                            ),
                                            items: const [
                                              DropdownMenuItem(value: 'saleable', child: Text('Resalable')),
                                              DropdownMenuItem(value: 'damaged', child: Text('Damaged')),
                                            ],
                                            onChanged: available == 0 ? null : (value) {
                                              if (value != null) setState(() => _conditions[id] = value);
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: TextField(
                    controller: _reasonController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Return reason *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                if (_customerId != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: SegmentedButton<String>(
                      segments: [
                        if (_receivedAmount > 0)
                          const ButtonSegment(value: 'Cash', label: Text('Cash Refund')),
                        const ButtonSegment(value: 'Khata', label: Text('Adjust Khata')),
                      ],
                      selected: {_refundMethod},
                      onSelectionChanged: (selection) => setState(() => _refundMethod = selection.first),
                    ),
                  ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Estimated Refund'),
                              Text('Rs. ${_estimatedRefund.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _saving || _loading ? null : _submit,
                          icon: _saving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.assignment_return),
                          label: Text(_saving ? 'Saving...' : 'Save Return'),
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
