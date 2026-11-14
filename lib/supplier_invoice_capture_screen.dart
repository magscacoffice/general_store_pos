import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'db_helper.dart';
import 'invoice_unit_converter.dart';

class SupplierInvoiceCaptureScreen extends StatefulWidget {
  const SupplierInvoiceCaptureScreen({super.key});

  @override
  State<SupplierInvoiceCaptureScreen> createState() =>
      _SupplierInvoiceCaptureScreenState();
}

class _InvoiceLineDraft {
  int? productId;
  final name = TextEditingController();
  final barcode = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final unitLabel = TextEditingController();
  final conversionFactor = TextEditingController(text: '1');
  final baseUnit = TextEditingController();
  final unitCost = TextEditingController(text: '0');
  final lineTotal = TextEditingController();
  final salePrice = TextEditingController();

  void dispose() {
    name.dispose();
    barcode.dispose();
    quantity.dispose();
    unitLabel.dispose();
    conversionFactor.dispose();
    baseUnit.dispose();
    unitCost.dispose();
    lineTotal.dispose();
    salePrice.dispose();
  }
}

class _SupplierInvoiceCaptureScreenState
    extends State<SupplierInvoiceCaptureScreen> {
  final _picker = ImagePicker();
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final _invoiceNumber = TextEditingController();
  final _invoiceDate = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 10),
  );
  final _invoiceTotal = TextEditingController();
  final _invoiceDiscount = TextEditingController(text: '0');
  final _invoiceTax = TextEditingController(text: '0');
  final _paidAmount = TextEditingController(text: '0');
  final _ocrSupplierName = TextEditingController();
  final _ocrText = TextEditingController();
  final List<_InvoiceLineDraft> _lines = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _suppliers = [];
  int? _supplierId;
  File? _invoiceImage;
  String? _savedImagePath;
  bool _reading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadLookups();
    _lines.add(_InvoiceLineDraft());
  }

  Future<void> _loadLookups() async {
    final products = await DBHelper.getProducts();
    final suppliers = await DBHelper.getParties('supplier');
    if (!mounted) return;
    setState(() {
      _products = products;
      _suppliers = suppliers;
      if (suppliers.length == 1) {
        _supplierId = (suppliers.first['id'] as num).toInt();
      }
    });
  }

  @override
  void dispose() {
    unawaited(_recognizer.close());
    _invoiceNumber.dispose();
    _invoiceDate.dispose();
    _invoiceTotal.dispose();
    _invoiceDiscount.dispose();
    _invoiceTax.dispose();
    _paidAmount.dispose();
    _ocrSupplierName.dispose();
    _ocrText.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  String _normalized(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  int? _matchProduct(String name) {
    final needle = _normalized(name);
    if (needle.isEmpty) return null;
    for (final product in _products) {
      if (_normalized(product['name']?.toString() ?? '') == needle) {
        return (product['id'] as num).toInt();
      }
    }
    for (final product in _products) {
      final existing = _normalized(product['name']?.toString() ?? '');
      if (existing.length >= 4 &&
          (existing.contains(needle) || needle.contains(existing))) {
        return (product['id'] as num).toInt();
      }
    }
    return null;
  }

  void _addLine({
    String name = '',
    String quantity = '1',
    String unitLabel = '',
    String conversionFactor = '1',
    String baseUnit = '',
    String unitCost = '0',
    String lineTotal = '',
  }) {
    final line = _InvoiceLineDraft()
      ..name.text = name
      ..quantity.text = quantity
      ..unitLabel.text = unitLabel
      ..conversionFactor.text = conversionFactor
      ..baseUnit.text = baseUnit
      ..unitCost.text = unitCost
      ..lineTotal.text = lineTotal
      ..productId = _matchProduct(name);
    setState(() => _lines.add(line));
  }

  double _number(String value) =>
      double.tryParse(value.replaceAll(',', '').trim()) ?? 0;

  String _moneyToken(String value) => value.replaceAll(',', '').trim();

  String _suggestedStockUnit(String invoiceUnit) {
    switch (InvoiceUnitConverter.canonicalUnit(invoiceUnit)) {
      case 'kg':
      case 'g':
        return 'g';
      case 'l':
      case 'ml':
        return 'ml';
      case 'dozen':
      case 'pcs':
        return 'pcs';
      default:
        return '';
    }
  }

  void _suggestLineConversion(_InvoiceLineDraft line) {
    final factor = InvoiceUnitConverter.suggestedFactor(
      invoiceUnit: line.unitLabel.text,
      stockUnit: line.baseUnit.text,
    );
    if (factor != null) line.conversionFactor.text = factor.toString();
  }

  void _extractInvoiceFields(String text) {
    final invoiceMatch = RegExp(
      r'(?:invoice|bill)\s*(?:no|number|#)\s*[:\-]?\s*([A-Z0-9\-/]+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (invoiceMatch != null && _invoiceNumber.text.trim().isEmpty) {
      _invoiceNumber.text = invoiceMatch.group(1) ?? '';
    }

    final dateMatch = RegExp(
      r'(?:invoice\s*)?date\s*[:\-]?\s*(\d{1,2}[\/\-.]\d{1,2}[\/\-.]\d{2,4})',
      caseSensitive: false,
    ).firstMatch(text);
    if (dateMatch != null) {
      final rawDate = dateMatch.group(1) ?? '';
      final parts = rawDate.split(RegExp(r'[\/\-.]'));
      if (parts.length == 3) {
        final day = int.tryParse(parts[0]) ?? 0;
        final month = int.tryParse(parts[1]) ?? 0;
        var year = int.tryParse(parts[2]) ?? 0;
        if (year < 100) year += year < 50 ? 2000 : 1900;
        final parsed = DateTime.tryParse('${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}');
        if (parsed != null) {
          _invoiceDate.text = '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
        }
      }
    }

    final supplierMatch = RegExp(
      r'(?:supplier|vendor|company)\s*[:\-]\s*([^\r\n]+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (supplierMatch != null) {
      _ocrSupplierName.text = supplierMatch.group(1)?.trim() ?? '';
      final supplierName = _normalized(_ocrSupplierName.text);
      final matches = _suppliers.where((supplier) =>
        _normalized(supplier['name']?.toString() ?? '') == supplierName);
      if (matches.length == 1) {
        _supplierId = (matches.first['id'] as num).toInt();
      }
    }

    final discountMatch = RegExp(
      r'(?:discount|less)\s*[:\-]?\s*(?:rs\.?|pkr)?\s*([\d,]+(?:\.\d{1,2})?)',
      caseSensitive: false,
    ).firstMatch(text);
    if (discountMatch != null) {
      _invoiceDiscount.text = _moneyToken(discountMatch.group(1) ?? '');
    }
    final taxMatch = RegExp(
      r'(?:sales\s*tax|gst|tax)\s*[:\-]?\s*(?:rs\.?|pkr)?\s*([\d,]+(?:\.\d{1,2})?)',
      caseSensitive: false,
    ).firstMatch(text);
    if (taxMatch != null) {
      _invoiceTax.text = _moneyToken(taxMatch.group(1) ?? '');
    }

    final totalMatch = RegExp(
      r'(?:grand\s*total|net\s*total|total\s*payable|invoice\s*total|amount\s*due)\s*[:\-]?\s*(?:rs\.?|pkr)?\s*([\d,]+(?:\.\d{1,2})?)',
      caseSensitive: false,
    ).firstMatch(text);
    if (totalMatch != null) {
      _invoiceTotal.text = _moneyToken(totalMatch.group(1) ?? '');
    }

    final candidates = <_InvoiceLineDraft>[];
    final numericPattern = RegExp(r'\d[\d,]*(?:\.\d{1,2})?');
    for (final rawLine in text.split(RegExp(r'\r?\n'))) {
      final lineText = rawLine.trim();
      if (lineText.length < 4 ||
          RegExp(r'grand\s*total|net\s*total|subtotal|tax|invoice|bill\s*no|date',
                  caseSensitive: false)
              .hasMatch(lineText)) {
        continue;
      }
      final matches = numericPattern.allMatches(lineText).toList();
      if (matches.length < 3) continue;
      final unitMatch = RegExp(
        r'\b(kg|kgs|g|gm|gram|ltr|l|ml|pcs|pc|pack|box|dozen|ctn|carton|bag|bottle|tray)\b',
        caseSensitive: false,
      ).firstMatch(lineText);
      late RegExpMatch quantityMatch;
      late RegExpMatch rateMatch;
      late RegExpMatch amountMatch;
      var unitToken = unitMatch?.group(1) ?? '';
      var invoiceUnit = unitToken;
      var suggestedFactor = '1';
      var suggestedBaseUnit = '';
      if (unitMatch != null) {
        final beforeUnit = matches.where((match) => match.end <= unitMatch.start).toList();
        final afterUnit = matches.where((match) => match.start >= unitMatch.end).toList();
        if (beforeUnit.length >= 2 && afterUnit.length >= 2) {
          if (unitToken.toLowerCase() == 'pcs' &&
              RegExp(r'[x×]', caseSensitive: false).hasMatch(
                lineText.substring(beforeUnit[beforeUnit.length - 2].end, beforeUnit.last.start),
              )) {
            quantityMatch = beforeUnit[beforeUnit.length - 2];
            suggestedFactor = beforeUnit.last.group(0) ?? '1';
            invoiceUnit = 'pack';
            unitToken = 'pack';
            suggestedBaseUnit = 'pcs';
          } else {
            quantityMatch = beforeUnit.last;
          }
          rateMatch = afterUnit[0];
          amountMatch = afterUnit[1];
        } else if (afterUnit.length >= 3) {
          // Unit appears before quantity (e.g. "Tea box 2 1200 2400").
          // Ignore a leading invoice line number before the product name.
          quantityMatch = afterUnit[0];
          rateMatch = afterUnit[1];
          amountMatch = afterUnit[2];
        } else if (beforeUnit.length == 1 && afterUnit.length >= 2) {
          quantityMatch = beforeUnit.first;
          rateMatch = afterUnit[0];
          amountMatch = afterUnit[1];
        } else {
          final lastThree = matches.sublist(matches.length - 3);
          quantityMatch = lastThree[0];
          rateMatch = lastThree[1];
          amountMatch = lastThree[2];
        }
      } else {
        final lastThree = matches.sublist(matches.length - 3);
        quantityMatch = lastThree[0];
        rateMatch = lastThree[1];
        amountMatch = lastThree[2];
      }
      final nameEnd = unitMatch != null && unitMatch.start < quantityMatch.start
          ? unitMatch.start
          : quantityMatch.start;
      final name = lineText.substring(0, nameEnd).trim()
          .replaceAll(RegExp(r'^[\d\s.\-]+'), '')
          .replaceAll(RegExp(r'\s{2,}'), ' ');
      if (name.length < 2) continue;
      final qty = _number(quantityMatch.group(0) ?? '');
      final rate = _number(rateMatch.group(0) ?? '');
      final amount = _number(amountMatch.group(0) ?? '');
      if (qty <= 0 || qty > 100000 || rate < 0 || amount < 0) continue;
      final draft = _InvoiceLineDraft()
        ..name.text = name
        ..quantity.text = qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)
        ..unitLabel.text = invoiceUnit
        ..conversionFactor.text = suggestedFactor
        ..baseUnit.text = suggestedBaseUnit.isEmpty
            ? _suggestedStockUnit(unitToken)
            : suggestedBaseUnit
        ..unitCost.text = rate.toStringAsFixed(2)
        ..lineTotal.text = amount.toStringAsFixed(2)
        ..productId = _matchProduct(name);
      if (draft.productId != null) {
        final product = _products.firstWhere(
          (value) => (value['id'] as num).toInt() == draft.productId,
        );
        final storedUnit = product['stock_unit']?.toString() ?? '';
        if (storedUnit.isNotEmpty) draft.baseUnit.text = storedUnit;
      }
      _suggestLineConversion(draft);
      if (suggestedFactor != '1') draft.conversionFactor.text = suggestedFactor;
      candidates.add(draft);
    }

    if (candidates.isNotEmpty) {
      for (final old in _lines) {
        old.dispose();
      }
      _lines
        ..clear()
        ..addAll(candidates);
    }
  }

  Future<void> _captureAndReadInvoice() async {
    if (_reading) return;
    setState(() => _reading = true);
    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );
      if (image == null) return;
      final file = File(image.path);
      final recognized = await _recognizer.processImage(
        InputImage.fromFilePath(file.path),
      );
      if (!mounted) return;
      setState(() {
        _invoiceImage = file;
        _ocrText.text = recognized.text;
      });
      _extractInvoiceFields(recognized.text);
      await _persistInvoiceImage(file);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(recognized.text.trim().isEmpty
                ? 'Text read nahi ho saka. Manual entry kar sakte hain.'
                : 'Invoice text read ho gaya. Posting se pehle tamam fields verify karein.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invoice camera / OCR error: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _persistInvoiceImage(File source) async {
    final directory = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(directory.path, 'supplier_invoices'));
    await folder.create(recursive: true);
    final destination = File(p.join(
      folder.path,
      'supplier-invoice-${DateTime.now().microsecondsSinceEpoch}${p.extension(source.path).isEmpty ? '.jpg' : p.extension(source.path)}',
    ));
    await source.copy(destination.path);
    _savedImagePath = destination.path;
  }

  Future<void> _chooseInvoiceDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_invoiceDate.text) ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
    );
    if (selected != null) {
      _invoiceDate.text =
          '${selected.year.toString().padLeft(4, '0')}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _postInvoice() async {
    if (_saving) return;
    final invoiceNo = _invoiceNumber.text.trim();
    final total = _number(_invoiceTotal.text);
    final paid = _number(_paidAmount.text);
    if (_supplierId == null || invoiceNo.isEmpty || total <= 0 ||
        paid < 0 || paid > total || _lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supplier, invoice number, total aur valid items complete karein.')),
      );
      return;
    }

    final payload = <Map<String, dynamic>>[];
    for (final line in _lines) {
      final invoiceQuantity = double.tryParse(line.quantity.text.trim()) ?? 0;
      final conversionFactor = double.tryParse(line.conversionFactor.text.trim()) ?? 0;
      final baseUnit = InvoiceUnitConverter.canonicalUnit(line.baseUnit.text);
      final rate = _number(line.unitCost.text);
      if (baseUnit.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stock unit (base unit) select karein.')),
        );
        return;
      }
      int stockQuantity;
      try {
        stockQuantity = InvoiceUnitConverter.toStockQuantity(
          invoiceQuantity: invoiceQuantity,
          conversionFactor: conversionFactor,
        );
      } catch (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Invalid argument(s): ', ''))),
        );
        return;
      }
      final lineAmount = line.lineTotal.text.trim().isEmpty
          ? invoiceQuantity * rate
          : _number(line.lineTotal.text);
      if (invoiceQuantity <= 0 || rate < 0 || lineAmount < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Har item ki quantity, rate aur amount verify karein.')),
        );
        return;
      }
      if (line.productId == null &&
          (line.name.text.trim().isEmpty || line.barcode.text.trim().isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New product ke liye name aur barcode enter karein.')),
        );
        return;
      }
      payload.add({
        'product_id': line.productId,
        'new_product_name': line.productId == null ? line.name.text.trim() : null,
        'new_product_barcode': line.productId == null ? line.barcode.text.trim() : null,
        'quantity': stockQuantity,
        'invoice_quantity': invoiceQuantity,
        'conversion_factor': conversionFactor,
        'base_unit': baseUnit,
        'unit_label': line.unitLabel.text.trim(),
        'unit_cost': rate,
        'line_total': lineAmount,
        'sale_price': line.salePrice.text.trim().isEmpty
            ? null
            : _number(line.salePrice.text),
      });
    }

    setState(() => _saving = true);
    try {
      await DBHelper.recordPurchaseInvoice(
        supplierId: _supplierId!,
        invoiceNumber: invoiceNo,
        invoiceDate: _invoiceDate.text.trim(),
        invoiceTotal: total,
        paidAmount: paid,
        invoiceDiscount: _number(_invoiceDiscount.text),
        invoiceTax: _number(_invoiceTax.text),
        items: payload,
        invoiceImagePath: _savedImagePath,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildLine(_InvoiceLineDraft line, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('Invoice item ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              IconButton(
                tooltip: 'Remove item',
                onPressed: _lines.length <= 1 ? null : () {
                  setState(() {
                    _lines.remove(line);
                    line.dispose();
                  });
                },
                icon: const Icon(Icons.delete_outline),
              ),
            ]),
            DropdownButtonFormField<int?>(
              value: line.productId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Match inventory product'),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Create new product from this invoice'),
                ),
                ..._products.map((product) => DropdownMenuItem<int?>(
                  value: (product['id'] as num).toInt(),
                  child: Text(product['name']?.toString() ?? 'Product',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                )),
              ],
              onChanged: (value) => setState(() {
                line.productId = value;
                if (value != null) {
                  final product = _products.firstWhere(
                    (p) => (p['id'] as num).toInt() == value,
                  );
                  line.name.text = product['name']?.toString() ?? '';
                  line.baseUnit.text = product['stock_unit']?.toString() ?? '';
                } else if (line.baseUnit.text.isEmpty) {
                  line.baseUnit.text = _suggestedStockUnit(line.unitLabel.text);
                }
                _suggestLineConversion(line);
              }),
            ),
            if (line.productId == null) ...[
              const SizedBox(height: 8),
              TextField(
                controller: line.name,
                decoration: const InputDecoration(labelText: 'New product name'),
              ),
              TextField(
                controller: line.barcode,
                decoration: const InputDecoration(labelText: 'New product barcode'),
              ),
              TextField(
                controller: line.salePrice,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Retail sale price (optional)'),
              ),
            ],
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(
                controller: line.quantity,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Invoice quantity'),
              )),
              const SizedBox(width: 8),
              Expanded(child: TextField(
                controller: line.unitLabel,
                onChanged: (_) => _suggestLineConversion(line),
                decoration: const InputDecoration(labelText: 'Invoice unit / pack'),
              )),
              const SizedBox(width: 8),
              Expanded(child: TextField(
                controller: line.unitCost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Purchase rate'),
              )),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(
                controller: line.conversionFactor,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Stock units per pack'),
              )),
              const SizedBox(width: 8),
              Expanded(child: TextField(
                controller: line.baseUnit,
                onChanged: (_) => _suggestLineConversion(line),
                decoration: const InputDecoration(labelText: 'Stock unit (e.g. pcs, g, ml)'),
              )),
            ]),
            const SizedBox(height: 6),
            Text(
              'Stock quantity = invoice quantity × pack conversion. Existing product ka stock unit badalne se pehle purana stock bhi isi unit mein hona confirm karein.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: line.lineTotal,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Line total'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Supplier Invoice OCR & Review'),
        actions: [
          IconButton(
            tooltip: 'Capture supplier invoice with camera',
            onPressed: _reading || _saving ? null : _captureAndReadInvoice,
            icon: const Icon(Icons.document_scanner_outlined),
          ),
        ],
      ),
      body: _suppliers.isEmpty
          ? const Center(child: Text('Pehle Suppliers screen mein supplier account add karein.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                FilledButton.icon(
                  onPressed: _reading || _saving ? null : _captureAndReadInvoice,
                  icon: _reading
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.camera_alt_outlined),
                  label: Text(_reading ? 'Reading invoice...' : 'Capture Invoice Photo & Read Text'),
                ),
                if (_invoiceImage != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(_invoiceImage!, height: 190, fit: BoxFit.contain),
                  ),
                ],
                const SizedBox(height: 16),
                if (_ocrSupplierName.text.trim().isNotEmpty) ...[
                  TextField(
                    controller: _ocrSupplierName,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Supplier name read by OCR (verify account below)',
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                DropdownButtonFormField<int>(
                  value: _supplierId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Supplier *'),
                  items: _suppliers.map((supplier) => DropdownMenuItem<int>(
                    value: (supplier['id'] as num).toInt(),
                    child: Text(supplier['name']?.toString() ?? 'Supplier'),
                  )).toList(),
                  onChanged: (value) => setState(() => _supplierId = value),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _invoiceNumber,
                  decoration: const InputDecoration(labelText: 'Supplier invoice / bill number *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _invoiceDate,
                  readOnly: true,
                  onTap: _chooseInvoiceDate,
                  decoration: const InputDecoration(
                    labelText: 'Invoice date',
                    suffixIcon: Icon(Icons.calendar_month),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(
                    controller: _invoiceTotal,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Grand total *'),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(
                    controller: _invoiceDiscount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Discount'),
                  )),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(
                    controller: _invoiceTax,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Tax / GST'),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(
                    controller: _paidAmount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Paid to supplier now'),
                  )),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: Text('Editable item review',
                      style: Theme.of(context).textTheme.titleMedium)),
                  TextButton.icon(
                    onPressed: () => _addLine(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add item'),
                  ),
                ]),
                const Text(
                  'Printed invoice OCR offline try karta hai. Handwritten invoice photo recognition ke liye Google Cloud Vision ki online service aur billing approval darkar hai; jab tak woh enable na ho, handwritten fields manually verify/enter karein. Stock ya supplier balance update hone se pehle supplier, invoice number, products, quantity, rates, discount, tax aur total manually verify karein.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 10),
                ..._lines.asMap().entries.map((entry) => _buildLine(entry.value, entry.key)),
                ExpansionTile(
                  title: const Text('OCR text (editable reference)'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: TextField(
                        controller: _ocrText,
                        minLines: 4,
                        maxLines: 10,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Camera se read hua invoice text yahan show hoga.',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saving || _reading ? null : _postInvoice,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.inventory_2_outlined),
                  label: Text(_saving ? 'Posting invoice...' : 'Verify & Post Stock / Supplier Account'),
                ),
              ],
            ),
    );
  }
}
