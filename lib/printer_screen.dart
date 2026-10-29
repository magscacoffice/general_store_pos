import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PrinterScreen extends StatefulWidget {
  final List<Map<String, dynamic>> cartItems;
  final double totalAmount;
  final String customerName;
  final String customerPhone;

  // Additional invoice information
  final int invoiceId;
  final double? subtotalAmount;
  final double discountAmount;
  final String paymentType;
  final String saleDate;

  const PrinterScreen({
    super.key,
    required this.cartItems,
    required this.totalAmount,
    this.customerName = 'Walk-in Customer',
    this.customerPhone = '',
    this.invoiceId = 0,
    this.subtotalAmount,
    this.discountAmount = 0,
    this.paymentType = 'Cash',
    this.saleDate = '',
  });

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  List<BluetoothInfo> _devices = [];
  String _selectedMac = '';
  bool _isConnected = false;
  bool _isLoading = false;
  bool _isGeneratingPdf = false;

  double get _subtotal => widget.subtotalAmount ?? widget.totalAmount;

  String get _formattedDate {
    final parsedDate = DateTime.tryParse(widget.saleDate);
    return DateFormat('dd-MMM-yyyy hh:mm a')
        .format(parsedDate ?? DateTime.now());
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _itemTotal(Map<String, dynamic> item) {
    return _number(item['quantity']) * _number(item['salePrice']);
  }

  String _money(double amount) {
    return 'Rs. ${amount.toStringAsFixed(2)}';
  }

  @override
  void initState() {
    super.initState();
    _getBluetoothDevices();
  }

  Future<void> _getBluetoothDevices() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final devices = await PrintBluetoothThermal.pairedBluetooths;
      if (mounted) setState(() => _devices = devices);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not find printers: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _connectDevice(String macAddress) async {
    setState(() => _isLoading = true);

    try {
      final result = await PrintBluetoothThermal.connect(
        macPrinterAddress: macAddress,
      );

      if (mounted && result) {
        setState(() {
          _isConnected = true;
          _selectedMac = macAddress;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Printer connected successfully!')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not connect to printer.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Connection error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _printReceipt() async {
    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect the printer first!')),
      );
      return;
    }

    final buffer = StringBuffer()
      ..writeln('KHAN BABA GENERAL STORE')
      ..writeln('Sanawan, Kot Addu')
      ..writeln('Invoice: ${widget.invoiceId > 0 ? widget.invoiceId : 'N/A'}')
      ..writeln('Customer: ${widget.customerName}')
      ..writeln('Date: $_formattedDate')
      ..writeln('Payment: ${widget.paymentType}')
      ..writeln('--------------------------------');

    for (final item in widget.cartItems) {
      final quantity = _number(item['quantity']);
      final price = _number(item['salePrice']);

      buffer
        ..writeln(item['name']?.toString() ?? 'Product')
        ..writeln(
          '${quantity.toStringAsFixed(0)} x ${_money(price)} = '
          '${_money(_itemTotal(item))}',
        );
    }

    buffer
      ..writeln('--------------------------------')
      ..writeln('Subtotal: ${_money(_subtotal)}')
      ..writeln('Discount: ${_money(widget.discountAmount)}')
      ..writeln('TOTAL: ${_money(widget.totalAmount)}')
      ..writeln('--------------------------------')
      ..writeln('Thank you for shopping!')
      ..writeln('\n\n');

    try {
      await PrintBluetoothThermal.writeBytes(buffer.toString().codeUnits);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt sent to printer.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Printing failed: $e')));
      }
    }
  }

  String _buildBillText() {
    final buffer = StringBuffer()
      ..writeln('*KHAN BABA GENERAL STORE*')
      ..writeln('Sanawan, Kot Addu')
      ..writeln('Invoice: ${widget.invoiceId > 0 ? widget.invoiceId : 'N/A'}')
      ..writeln('Customer: ${widget.customerName}')
      ..writeln('Date: $_formattedDate')
      ..writeln('Payment: ${widget.paymentType}')
      ..writeln('--------------------------------');

    for (final item in widget.cartItems) {
      buffer.writeln(
        '${item['name']} - ${item['quantity']} x '
        '${_money(_number(item['salePrice']))} = '
        '${_money(_itemTotal(item))}',
      );
    }

    buffer
      ..writeln('--------------------------------')
      ..writeln('Subtotal: ${_money(_subtotal)}')
      ..writeln('Discount: ${_money(widget.discountAmount)}')
      ..writeln('*Total Amount: ${_money(widget.totalAmount)}*')
      ..writeln('Thank you for shopping!');

    return buffer.toString();
  }

  void _shareOnWhatsApp() {
    Share.share(_buildBillText());
  }

  Future<void> _sendSMSAlert() async {
    final smsUri = Uri(
      scheme: 'sms',
      path: widget.customerPhone,
      queryParameters: {'body': _buildBillText()},
    );

    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
    } else {
      await Share.share(_buildBillText());
    }
  }

  Future<Uint8List> _generateInvoicePdf() async {
    final document = pw.Document();

    final invoiceNumber = widget.invoiceId > 0
        ? widget.invoiceId.toString()
        : 'N/A';

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Center(
            child: pw.Text(
              'KHAN BABA GENERAL STORE',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Center(
            child: pw.Text(
              'Sanawan, Kot Addu',
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Center(
            child: pw.Text(
              'SALES INVOICE',
              style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 15),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Invoice No: $invoiceNumber'),
                    pw.SizedBox(height: 5),
                    pw.Text('Customer: ${widget.customerName}'),
                    pw.SizedBox(height: 5),
                    pw.Text('Payment: ${widget.paymentType}'),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Text('Date: $_formattedDate'),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: ['Product', 'Qty', 'Price', 'Amount'],
            data: widget.cartItems.map((item) {
              return [
                item['name']?.toString() ?? 'Product',
                _number(item['quantity']).toStringAsFixed(0),
                _money(_number(item['salePrice'])),
                _money(_itemTotal(item)),
              ];
            }).toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.teal),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.all(7),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          ),
          pw.SizedBox(height: 20),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 230,
              child: pw.Column(
                children: [
                  _pdfTotalRow('Subtotal', _money(_subtotal)),
                  pw.SizedBox(height: 7),
                  _pdfTotalRow('Discount', _money(widget.discountAmount)),
                  pw.Divider(),
                  _pdfTotalRow(
                    'FINAL TOTAL',
                    _money(widget.totalAmount),
                    bold: true,
                  ),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 35),
          pw.Center(
            child: pw.Text(
              'Thank you for shopping with us!',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    return document.save();
  }

  pw.Widget _pdfTotalRow(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontSize: bold ? 13 : 11,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: style),
        pw.Text(value, style: style),
      ],
    );
  }

  String get _pdfFileName {
    final invoiceNumber = widget.invoiceId > 0
        ? widget.invoiceId.toString()
        : 'receipt';
    return 'invoice_$invoiceNumber.pdf';
  }

  Future<void> _sharePdf() async {
    if (_isGeneratingPdf) return;

    setState(() => _isGeneratingPdf = true);

    try {
      final bytes = await _generateInvoicePdf();

      await Printing.sharePdf(bytes: bytes, filename: _pdfFileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not create PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<void> _printPdf() async {
    if (_isGeneratingPdf) return;

    setState(() => _isGeneratingPdf = true);

    try {
      final bytes = await _generateInvoicePdf();

      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: _pdfFileName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not print PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer & Invoice'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              onPressed: _getBluetoothDevices,
              icon: const Icon(Icons.refresh),
              label: const Text('Find Paired Devices'),
            ),
            const SizedBox(height: 10),
            if (_isLoading)
              const LinearProgressIndicator()
            else
              SizedBox(
                height: 130,
                child: _devices.isEmpty
                    ? const Center(
                        child: Text('No paired Bluetooth printers found.'),
                      )
                    : ListView.builder(
                        itemCount: _devices.length,
                        itemBuilder: (context, index) {
                          final device = _devices[index];

                          return Card(
                            child: ListTile(
                              dense: true,
                              title: Text(device.name),
                              subtitle: Text(device.macAdress),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      _selectedMac == device.macAdress
                                      ? Colors.green
                                      : Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () =>
                                    _connectDevice(device.macAdress),
                                child: Text(
                                  _selectedMac == device.macAdress
                                      ? 'Connected'
                                      : 'Connect',
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            const Divider(thickness: 2),
            Expanded(
              child: widget.cartItems.isEmpty
                  ? const Center(child: Text('No invoice items found.'))
                  : ListView.builder(
                      itemCount: widget.cartItems.length,
                      itemBuilder: (context, index) {
                        final item = widget.cartItems[index];

                        return ListTile(
                          title: Text(item['name']?.toString() ?? 'Product'),
                          subtitle: Text(
                            '${item['quantity']} x '
                            '${_money(_number(item['salePrice']))}',
                          ),
                          trailing: Text(
                            _money(_itemTotal(item)),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(),
            _totalRow('Subtotal', _subtotal),
            _totalRow('Discount', widget.discountAmount),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Final Total:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  _money(widget.totalAmount),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _printReceipt,
                    icon: const Icon(Icons.print),
                    label: const Text('Thermal Receipt'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _shareOnWhatsApp,
                    icon: const Icon(Icons.share),
                    label: const Text('Share Bill'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isGeneratingPdf ? null : _printPdf,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Print PDF'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _isGeneratingPdf ? null : _sharePdf,
                    icon: _isGeneratingPdf
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.picture_as_pdf),
                    label: Text(
                      _isGeneratingPdf ? 'Preparing...' : 'Share PDF',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label), Text(_money(amount))],
      ),
    );
  }
}
