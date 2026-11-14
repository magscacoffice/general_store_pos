import 'windows/desktop_app_bar.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart' as usb_print;

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
  final String cashierName;
  final double? receivedAmount;
  final double? balanceDue;
  final double taxAmount;
  final String salesType;

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
    this.cashierName = 'Admin',
    this.receivedAmount,
    this.balanceDue,
    this.taxAmount = 0,
    this.salesType = 'Retail',
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
  final usb_print.PrinterManager _usbPrinterManager = usb_print.PrinterManager();
  List<usb_print.UsbPrinterDevice> _usbDevices = [];
  usb_print.UsbPrinterDevice? _selectedUsbDevice;
  bool _isUsbScanning = false;
  bool _isUsbConnected = false;
  static const int _usbPaperWidth = 80;
  int _receiptTextScale = 1;
  int _paperMarginMm = 2;

  double get _subtotal => widget.subtotalAmount ?? widget.totalAmount;

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _itemTotal(Map<String, dynamic> item) {
    final quantity = _number(item['quantity'] ?? item['qty']);
    final rate = _number(item['salePrice'] ?? item['sale_price'] ?? item['price']);
    final itemDiscount = _number(item['itemDiscount']);
    return (rate - itemDiscount).clamp(0.0, double.infinity).toDouble() * quantity;
  }

  String _itemName(Map<String, dynamic> item) =>
      (item['name'] ?? item['product_name'] ?? 'Product').toString();

  double _itemRate(Map<String, dynamic> item) =>
      _number(item['salePrice'] ?? item['sale_price'] ?? item['price']);

  double _itemQuantity(Map<String, dynamic> item) =>
      _number(item['quantity'] ?? item['qty']);

  String _money(double amount) => amount.toStringAsFixed(2);

  int get _receiptLineWidth => ((576 - (_paperMarginMm * 16)) ~/ 12).clamp(40, 48).toInt();

  String _singleLine(String value, int maxWidth) {
    if (maxWidth <= 0) return '';
    final normalized = value.replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxWidth) return normalized;
    if (maxWidth <= 2) return normalized.substring(0, maxWidth);
    return '${normalized.substring(0, maxWidth - 2)}..';
  }

  String _line(String left, String right, {int? width}) {
    final lineWidth = width ?? _receiptLineWidth;
    final safeRight = _singleLine(right, lineWidth);
    final leftWidth = (lineWidth - safeRight.length - 1).clamp(0, lineWidth).toInt();
    final safeLeft = _singleLine(left, leftWidth);
    final spaces = (lineWidth - safeLeft.length - safeRight.length).clamp(0, lineWidth).toInt();
    return safeLeft + List.filled(spaces, ' ').join() + safeRight;
  }

  String _center(String value, {int? width}) {
    final lineWidth = width ?? _receiptLineWidth;
    final safe = _singleLine(value, lineWidth);
    return safe.padLeft(((lineWidth + safe.length) / 2).floor()).padRight(lineWidth);
  }

  String _itemHeaderRow() =>
      'Qty'.padLeft(4) + ' ' + 'Description'.padRight(17) +
      ' ' + 'Rate'.padLeft(10) + ' ' + 'Amount'.padLeft(11);

  String _itemReceiptRow(Map<String, dynamic> item) {
    final qty = _itemQuantity(item).toStringAsFixed(0);
    final rate = _money(_itemRate(item));
    final amount = _money(_itemTotal(item));
    final qtyWidth = qty.length > 4 ? qty.length : 4;
    final rateWidth = rate.length > 10 ? rate.length : 10;
    final amountWidth = amount.length > 11 ? amount.length : 11;
    final descriptionWidth = (_receiptLineWidth - qtyWidth - rateWidth - amountWidth - 3)
        .clamp(1, 17).toInt();
    final name = _singleLine(_itemName(item), descriptionWidth);
    return qty.padLeft(qtyWidth) + ' ' + name.padRight(descriptionWidth) +
        ' ' + rate.padLeft(rateWidth) + ' ' + amount.padLeft(amountWidth);
  }

  String _billText({required bool plain}) {
    final separator = List.filled(_receiptLineWidth, '-').join();
    final parsedDate = DateTime.tryParse(widget.saleDate) ?? DateTime.now();
    final received = widget.receivedAmount ?? widget.totalAmount;
    final change = (received - widget.totalAmount).clamp(0, double.infinity).toDouble();
    final due = widget.balanceDue ??
        (widget.totalAmount - received).clamp(0, double.infinity).toDouble();
    final buffer = StringBuffer()
      ..writeln(_center('KHAN BABA'))
      ..writeln(_center('GENERAL STORE'))
      ..writeln(_center('G.T ROAD SANAWAN'))
      ..writeln(_center('PH#03451444325'))
      ..writeln()
      ..writeln(_line('Bill# ${widget.invoiceId.toString().padLeft(6, '0')}', 'Date: ${DateFormat('dd/MM/yy').format(parsedDate)}'))
      ..writeln(_line('Cashier: ${widget.cashierName}', 'Time: ${DateFormat('hh:mm:ss a').format(parsedDate)}'))
      ..writeln(_line('Type: ${widget.salesType}', ''))
      ..writeln(_line('Customer: ${widget.customerName}', ''))
      ..writeln(separator)
      ..writeln(_itemHeaderRow())
      ..writeln(separator);
    for (final item in widget.cartItems) {
      buffer.writeln(_itemReceiptRow(item));
    }
    buffer
      ..writeln(separator)
      ..writeln(_line('Total Items: ${widget.cartItems.length}', 'Gross: ${_money(_subtotal)}'))
      ..writeln(_line('Discount', _money(widget.discountAmount)));
    if (widget.taxAmount > 0) buffer.writeln(_line('Tax (GST)', _money(widget.taxAmount)));
    buffer
      ..writeln(separator)
      ..writeln(_center('NET AMOUNT: Rs. ${_money(widget.totalAmount)}'))
      ..writeln(separator)
      ..writeln(_line('Payment: ${widget.paymentType}', ''))
      ..writeln(_line('Received', _money(received)));
    if (due > 0) buffer.writeln(_line('Balance Due', _money(due)));
    if (change > 0) buffer.writeln(_line('Change', _money(change)));
    if (widget.customerPhone.trim().isNotEmpty) {
      buffer.writeln(_line('Phone: ${widget.customerPhone}', ''));
    }
    buffer
      ..writeln(separator)
      ..writeln(_center('THANK YOU - VISIT AGAIN'))
      ..writeln(_center('KHAN BABA GENERAL STORE'))
      ..writeln('\n');
    return buffer.toString();
  }

  @override
  void initState() {
    super.initState();
    if (!Platform.isWindows) _getBluetoothDevices();
  }

  @override
  void dispose() {
    unawaited(_usbPrinterManager.dispose());
    super.dispose();
  }

  Future<void> _scanUsbPrinters() async {
    if (_isUsbScanning) return;
    setState(() => _isUsbScanning = true);
    try {
      final found = await _usbPrinterManager.scanPrinters(
        timeout: const Duration(seconds: 5),
        types: {usb_print.PrinterConnectionType.usb},
      );
      if (!mounted) return;
      final devices = found.whereType<usb_print.UsbPrinterDevice>().toList();
      setState(() {
        _usbDevices = devices;
        if (_selectedUsbDevice != null &&
            !devices.any((device) => device.identifier == _selectedUsbDevice!.identifier)) {
          _selectedUsbDevice = null;
          _isUsbConnected = false;
        }
      });
      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Platform.isWindows ? 'USB printer nahi mila. PC USB connection aur printer driver check karein.' : 'USB printer nahi mila. OTG cable aur printer connection check karein.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('USB printer search nahi ho saka: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUsbScanning = false);
    }
  }

  Future<void> _connectUsbPrinter(usb_print.UsbPrinterDevice device) async {
    setState(() => _isUsbScanning = true);
    try {
      await _usbPrinterManager.connect(device);
      if (!mounted) return;
      setState(() {
        _selectedUsbDevice = device;
        _isUsbConnected = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('USB printer connected: ${device.name}')),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isUsbConnected = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('USB printer connect nahi hua: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUsbScanning = false);
    }
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
    if (!_isUsbConnected && !_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Platform.isWindows ? 'Pehle USB printer connect karein.' : 'Pehle USB ya Bluetooth printer connect karein.')),
      );
      return;
    }
    try {
      if (_isUsbConnected) {
        final paperSize = usb_print.PaperSize.mm80;
        final ticket = await usb_print.Ticket.create(paperSize);
        final paperDots = _usbPaperWidth == 80 ? 576 : 384;
        final marginDots = _paperMarginMm * 8;
        if (marginDots > 0) {
          final printWidth = paperDots - (marginDots * 2);
          ticket.rawBytes([
            0x1D, 0x4C, marginDots & 0xFF, (marginDots >> 8) & 0xFF,
            0x1D, 0x57, printWidth & 0xFF, (printWidth >> 8) & 0xFF,
          ]);
        }
        final lines = _billText(plain: true).split(String.fromCharCode(10));
        for (final line in lines) {
          if (line.trim() == 'KHAN BABA') {
            await ticket.textRaster(
              'KHAN BABA',
              style: TextStyle(fontSize: 20 + (_receiptTextScale * 3), fontWeight: FontWeight.bold),
              align: usb_print.PrintAlign.center,
            );
          } else if (line.trim() == 'GENERAL STORE' || line.trim() == 'G.T ROAD SANAWAN' || line.trim() == 'PH#03451444325') {
            ticket.text(
              line.trim(),
              align: usb_print.PrintAlign.center,
              style: usb_print.PrintTextStyle(bold: line.trim() == 'GENERAL STORE'),
            );
          } else if (line.contains('NET AMOUNT:')) {
            await ticket.textRaster(
              line.trim(),
              style: TextStyle(fontSize: 17 + (_receiptTextScale * 2), fontWeight: FontWeight.bold),
              align: usb_print.PrintAlign.center,
            );
          } else {
            ticket.text(
              line,
              style: usb_print.PrintTextStyle(
                height: usb_print.TextSize.size1,
                width: usb_print.TextSize.size1,
              ),
            );
          }
        }
        if (marginDots > 0) {
          ticket.rawBytes([
            0x1D, 0x4C, 0, 0,
            0x1D, 0x57, paperDots & 0xFF, (paperDots >> 8) & 0xFF,
          ]);
        }
        ticket.cut();
        await _usbPrinterManager.printTicket(ticket);
        await _usbPrinterManager.waitWriteComplete();
      } else {
        await PrintBluetoothThermal.writeBytes(_billText(plain: true).codeUnits);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isUsbConnected ? 'Receipt USB printer ko bhej di gayi.' : 'Receipt Bluetooth printer ko bhej di gayi.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Printing failed: $e')));
      }
    }
  }

  String _buildBillText() => _billText(plain: true);

  void _shareOnWhatsApp() {
    Share.share(_buildBillText());
  }


  Future<Uint8List> _generateInvoicePdf() async {
    final document = pw.Document();
    final parsedDate = DateTime.tryParse(widget.saleDate) ?? DateTime.now();
    final received = widget.receivedAmount ?? widget.totalAmount;
    final change = (received - widget.totalAmount).clamp(0, double.infinity).toDouble();
    final due = widget.balanceDue ??
        (widget.totalAmount - received).clamp(0, double.infinity).toDouble();
    final pageHeight = (112 + widget.cartItems.length * 8).toDouble();
    final pageFormat = PdfPageFormat(
      80 * PdfPageFormat.mm,
      pageHeight * PdfPageFormat.mm,
      marginLeft: _paperMarginMm * PdfPageFormat.mm,
      marginRight: _paperMarginMm * PdfPageFormat.mm,
      marginTop: _paperMarginMm * PdfPageFormat.mm,
      marginBottom: _paperMarginMm * PdfPageFormat.mm,
    );
    pw.Widget fittedCell(String value, {required pw.TextAlign align, required int flex, bool bold = false}) {
      final alignment = align == pw.TextAlign.right
          ? pw.Alignment.centerRight
          : align == pw.TextAlign.center
              ? pw.Alignment.center
              : pw.Alignment.centerLeft;
      return pw.Expanded(
        flex: flex,
        child: pw.FittedBox(
          fit: pw.BoxFit.scaleDown,
          alignment: alignment,
          child: pw.Text(value, maxLines: 1, style: pw.TextStyle(
            fontSize: 7,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          )),
        ),
      );
    }

    document.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(child: pw.Text('KHAN BABA', style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold))),
            pw.Center(child: pw.Text('GENERAL STORE', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold))),
            pw.Center(child: pw.Text('G.T ROAD SANAWAN', style: const pw.TextStyle(fontSize: 8))),
            pw.Center(child: pw.Text('PH#03451444325', style: const pw.TextStyle(fontSize: 8))),
            pw.SizedBox(height: 5),
            pw.Divider(height: 4, thickness: 0.8),
            pw.Row(children: [
              pw.Expanded(child: pw.Text('Bill# ${widget.invoiceId.toString().padLeft(6, '0')}', style: const pw.TextStyle(fontSize: 7))),
              pw.Expanded(child: pw.Text('Date: ${DateFormat('dd/MM/yy').format(parsedDate)}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 7))),
            ]),
            pw.Row(children: [
              pw.Expanded(child: pw.Text('Cashier: ${_singleLine(widget.cashierName, 18)}', style: const pw.TextStyle(fontSize: 7))),
              pw.Expanded(child: pw.Text('Time: ${DateFormat('hh:mm:ss a').format(parsedDate)}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 7))),
            ]),
            pw.Text('Type: ${_singleLine(widget.salesType, 20)}', style: const pw.TextStyle(fontSize: 7)),
            pw.Text('Customer: ${_singleLine(widget.customerName, 45)}', style: const pw.TextStyle(fontSize: 7)),
            if (widget.customerPhone.trim().isNotEmpty)
              pw.Text('Phone: ${_singleLine(widget.customerPhone, 30)}', style: const pw.TextStyle(fontSize: 7)),
            pw.Divider(height: 5, thickness: 0.8),
            pw.Row(children: [
              fittedCell('Qty', align: pw.TextAlign.left, flex: 4, bold: true),
              fittedCell('Description', align: pw.TextAlign.left, flex: 17, bold: true),
              fittedCell('Rate', align: pw.TextAlign.right, flex: 10, bold: true),
              fittedCell('Amount', align: pw.TextAlign.right, flex: 11, bold: true),
            ]),
            pw.Divider(height: 3, thickness: 0.5),
            ...widget.cartItems.map((item) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Row(children: [
                fittedCell(_itemQuantity(item).toStringAsFixed(0), align: pw.TextAlign.left, flex: 4),
                fittedCell(_singleLine(_itemName(item), 17), align: pw.TextAlign.left, flex: 17),
                fittedCell(_money(_itemRate(item)), align: pw.TextAlign.right, flex: 10),
                fittedCell(_money(_itemTotal(item)), align: pw.TextAlign.right, flex: 11),
              ]),
            )),
            pw.Divider(height: 5, thickness: 0.8),
            _pdfInfoRow('Total Items: ${widget.cartItems.length}', 'Gross: ${_money(_subtotal)}'),
            _pdfInfoRow('Discount', _money(widget.discountAmount)),
            if (widget.taxAmount > 0) _pdfInfoRow('Tax (GST)', _money(widget.taxAmount)),
            pw.Container(
              margin: const pw.EdgeInsets.symmetric(vertical: 5),
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.2)),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('NET AMOUNT', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Rs. ${_money(widget.totalAmount)}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            _pdfInfoRow('Payment', widget.paymentType),
            _pdfInfoRow('Received', _money(received)),
            if (due > 0) _pdfInfoRow('Balance Due', _money(due)),
            if (change > 0) _pdfInfoRow('Change', _money(change)),
            pw.SizedBox(height: 5),
            pw.Center(child: pw.Text('THANK YOU - VISIT AGAIN', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
            pw.Center(child: pw.Text('KHAN BABA GENERAL STORE', style: const pw.TextStyle(fontSize: 7))),
          ],
        ),
      ),
    );
    return document.save();
  }

  pw.Widget _pdfInfoRow(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontSize: bold ? 8 : 7,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(child: pw.Text(label, style: style)),
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

  Future<void> _savePdfToDevice() async {
    if (_isGeneratingPdf) return;
    setState(() => _isGeneratingPdf = true);
    try {
      final bytes = await _generateInvoicePdf();
      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Save invoice PDF',
        fileName: _pdfFileName,
        bytes: bytes,
      );
      if (!mounted) return;
      if (savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF saved successfully: $savedPath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<void> _previewPdf() async {
    if (_isGeneratingPdf) return;
    setState(() => _isGeneratingPdf = true);
    try {
      final bytes = await _generateInvoicePdf();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: !Platform.isWindows,
              leading: desktopReturnButton(),
              title: const Text('Invoice Preview'),
            ),
            body: PdfPreview(
              build: (_) async => bytes,
              canChangeOrientation: false,
              canChangePageFormat: false,
              allowPrinting: true,
              allowSharing: true,
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not preview PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }


  @override
  Widget build(BuildContext context) {

    final isWindows = Platform.isWindows;
    final cartItemsList = widget.cartItems.isEmpty
        ? const Center(child: Text('No invoice items found.'))
        : ListView.builder(
            itemCount: widget.cartItems.length,
            itemBuilder: (context, index) {
              final item = widget.cartItems[index];
              return ListTile(
                title: Text(item['name']?.toString() ?? 'Product'),
                subtitle: Text(
                  '${item['quantity']} x ${_money(_number(item['salePrice']))}',
                ),
                trailing: Text(
                  _money(_itemTotal(item)),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            },
          );
    final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isWindows) ...[
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
            ],
            const SizedBox(height: 8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Paper:'),
                    SizedBox(width: 8),
                    Text('80 mm'),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Header/Total Size:'),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _receiptTextScale,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('Small')),
                        DropdownMenuItem(value: 2, child: Text('Medium')),
                        DropdownMenuItem(value: 3, child: Text('Large')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _receiptTextScale = value);
                      },
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Margins:'),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _paperMarginMm,
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('0 mm')),
                        DropdownMenuItem(value: 2, child: Text('2 mm')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _paperMarginMm = value);
                      },
                    ),
                  ],
                ),
              ],
            ),
            OutlinedButton.icon(
              onPressed: _isUsbScanning ? null : _scanUsbPrinters,
              icon: _isUsbScanning
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.usb),
              label: Text(_isUsbScanning ? 'USB printer search ho raha hai...' : (Platform.isWindows ? 'Find USB Printer' : 'Find USB OTG Printer')),
            ),
            if (_usbDevices.isNotEmpty)
              SizedBox(
                height: 90,
                child: ListView.builder(
                  itemCount: _usbDevices.length,
                  itemBuilder: (context, index) {
                    final device = _usbDevices[index];
                    final isSelected = _selectedUsbDevice?.identifier == device.identifier && _isUsbConnected;
                    return Card(
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.print),
                        title: Text(device.name),
                        subtitle: Text('USB ID: ${device.identifier}'),
                        trailing: ElevatedButton(
                          onPressed: _isUsbScanning ? null : () => _connectUsbPrinter(device),
                          child: Text(isSelected ? 'Connected' : 'Connect'),
                        ),
                      ),
                    );
                  },
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(Platform.isWindows ? 'USB printer ko PC se connect kar ke Find USB Printer dabayein.' : 'USB printer connect kar ke Find USB OTG Printer dabayein.', style: const TextStyle(color: Colors.black54)),
              ),
            const Divider(thickness: 2),
            isWindows
                ? SizedBox(height: 180, child: cartItemsList)
                : Expanded(child: cartItemsList),
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
                    onPressed: _isGeneratingPdf ? null : _previewPdf,
                    icon: const Icon(Icons.preview),
                    label: const Text('Invoice Preview'),
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
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isGeneratingPdf ? null : _savePdfToDevice,
              icon: const Icon(Icons.save_alt),
              label: const Text('Save PDF to Device'),
            ),
          ],
        );
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !Platform.isWindows,
        leading: desktopReturnButton(),
        toolbarHeight: Platform.isWindows ? 48 : 56,
        title: const Text('Printer & Invoice'),
        backgroundColor: Platform.isWindows ? const Color(0xFFF7F9FB) : Colors.teal,
        foregroundColor: Platform.isWindows ? const Color(0xFF263442) : Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: isWindows
            ? Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(child: content),
              )
            : content,
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
