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
  int _usbPaperWidth = 58;
  int _receiptTextScale = 1;
  int _paperMarginMm = 2;

  usb_print.TextSize get _receiptTextSize {
    switch (_receiptTextScale) {
      case 2:
        return usb_print.TextSize.size2;
      case 3:
        return usb_print.TextSize.size3;
      default:
        return usb_print.TextSize.size1;
    }
  }

  double get _subtotal => widget.subtotalAmount ?? widget.totalAmount;

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _itemTotal(Map<String, dynamic> item) {
    return _number(item['quantity'] ?? item['qty']) *
        _number(item['salePrice'] ?? item['sale_price'] ?? item['price']);
  }

  String _itemName(Map<String, dynamic> item) =>
      (item['name'] ?? item['product_name'] ?? 'Product').toString();

  double _itemRate(Map<String, dynamic> item) =>
      _number(item['salePrice'] ?? item['sale_price'] ?? item['price']);

  double _itemQuantity(Map<String, dynamic> item) =>
      _number(item['quantity'] ?? item['qty']);

  String _money(double amount) => amount.toStringAsFixed(2);

  String _line(String left, String right, {int width = 32}) {
    final available = width - left.length - right.length;
    if (available <= 1) {
      return '${left.substring(0, left.length > width - right.length - 1 ? width - right.length - 1 : left.length)} $right';
    }
    return left + List.filled(available, ' ').join() + right;
  }

  List<String> _wrapReceiptText(String value, int maxWidth) {
    final words = value.trim().split(RegExp(r'\s+'));
    final lines = <String>[];
    var current = '';
    for (final word in words) {
      if (current.isEmpty) {
        current = word;
      } else if ((current.length + word.length + 1) <= maxWidth) {
        current = '$current $word';
      } else {
        lines.add(current);
        current = word;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines.isEmpty ? [''] : lines;
  }

  String _billText({required bool plain}) {
    final paperDots = _usbPaperWidth == 80 ? 576 : 384;
    final marginDots = _paperMarginMm * 8;
    final baseCharacters = _usbPaperWidth == 80 ? 48 : 32;
    final width = (baseCharacters *
            (paperDots - marginDots * 2) /
            paperDots /
            _receiptTextScale)
        .floor()
        .clamp(10, baseCharacters);
    final separator = List.filled(width, '-').join();
    final parsedDate = DateTime.tryParse(widget.saleDate) ?? DateTime.now();
    final received = widget.receivedAmount ?? widget.totalAmount;
    final change = (received - widget.totalAmount).clamp(0, double.infinity).toDouble();
    final due = widget.balanceDue ?? (widget.totalAmount - received).clamp(0, double.infinity).toDouble();
    final buffer = StringBuffer()
      ..writeln('🛒 KHAN BABA 🛒')
      ..writeln('GENERAL STORE')
      ..writeln('G.T ROAD SANAWAN')
      ..writeln('PH#03451444325')
      ..writeln(separator)
      ..writeln('Bill# ${widget.invoiceId.toString().padLeft(6, '0')}  Date: ${DateFormat('dd-MM-yyyy').format(parsedDate)}  Time: ${DateFormat('hh:mm a').format(parsedDate)}  Cashier: ${widget.cashierName}  Type: ${widget.salesType}')
      ..writeln(separator)
      ..writeln('Customer: ${widget.customerName}');
    if (widget.customerPhone.trim().isNotEmpty) {
      buffer.writeln('Phone: ${widget.customerPhone}');
    }
    buffer
      ..writeln(separator)
      ..writeln(_line('Sr# Item', 'Qty Amount', width: width))
      ..writeln(separator);

    for (var i = 0; i < widget.cartItems.length; i++) {
      final item = widget.cartItems[i];
      final qty = _itemQuantity(item).toStringAsFixed(0);
      final amount = _money(_itemTotal(item));
      final leftWidth = (width - qty.length - amount.length - 2).clamp(4, width - 1);
      final itemLabel = '${i + 1} ${_itemName(item)}';
      final compactItem = itemLabel.length > leftWidth
          ? itemLabel.substring(0, leftWidth)
          : itemLabel;
      buffer.writeln(_line(compactItem, '$qty $amount', width: width));
    }

    buffer
      ..writeln(separator)
      ..writeln(_line('Sub Total', _money(_subtotal), width: width));
    if (widget.discountAmount > 0) {
      buffer.writeln(_line('Discount', _money(widget.discountAmount), width: width));
    }
    if (widget.taxAmount > 0) {
      buffer.writeln(_line('Tax (GST)', _money(widget.taxAmount), width: width));
    }
    buffer
      ..writeln(_line('TOTAL', _money(widget.totalAmount), width: width))
      ..writeln(separator)
      ..writeln(_line('Payment', widget.paymentType, width: width))
      ..writeln(_line('Received', _money(received), width: width));
    if (due > 0) buffer.writeln(_line('Balance Due', _money(due), width: width));
    if (change > 0) buffer.writeln(_line('Change', _money(change), width: width));
    buffer
      ..writeln(separator)
      ..writeln('       THANK YOU - VISIT AGAIN')
      ..writeln(' Developed by SohaibTech')
      ..writeln(' WhatsApp: 03401832381')
      ..writeln('\n');
    return buffer.toString();
  }

  @override
  void initState() {
    super.initState();
    _getBluetoothDevices();
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
          const SnackBar(content: Text('USB printer nahi mila. OTG cable aur printer connection check karein.')),
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
        const SnackBar(content: Text('Pehle USB ya Bluetooth printer connect karein.')),
      );
      return;
    }
    try {
      if (_isUsbConnected) {
        final paperSize = _usbPaperWidth == 80
            ? usb_print.PaperSize.mm80
            : usb_print.PaperSize.mm58;
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
          if (line.contains('KHAN BABA')) {
            await ticket.textRaster(
              '🛒 KHAN BABA 🛒',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              align: usb_print.PrintAlign.center,
            );
          } else if (line.trim() == 'GENERAL STORE' || line.trim() == 'G.T ROAD SANAWAN' || line.trim() == 'PH#03451444325') {
            ticket.text(
              line.trim(),
              align: usb_print.PrintAlign.center,
              style: usb_print.PrintTextStyle(bold: line.trim() == 'GENERAL STORE'),
            );
          } else if (line.startsWith('TOTAL')) {
            final totalValue = line.trim().split(RegExp(r'\s+')).last;
            ticket.text(
              'TOTAL',
              style: const usb_print.PrintTextStyle(
                bold: true,
                height: usb_print.TextSize.size2,
                width: usb_print.TextSize.size2,
              ),
            );
            ticket.text(
              totalValue,
              align: usb_print.PrintAlign.right,
              style: const usb_print.PrintTextStyle(
                bold: true,
                height: usb_print.TextSize.size2,
                width: usb_print.TextSize.size2,
              ),
            );
          } else {
            ticket.text(
              line,
              style: usb_print.PrintTextStyle(
                height: _receiptTextSize,
                width: _receiptTextSize,
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
    final invoiceNumber = widget.invoiceId > 0 ? widget.invoiceId.toString() : 'N/A';
    final parsedDate = DateTime.tryParse(widget.saleDate) ?? DateTime.now();
    final received = widget.receivedAmount ?? widget.totalAmount;
    final change = (received - widget.totalAmount).clamp(0, double.infinity).toDouble();
    final due = widget.balanceDue ??
        (widget.totalAmount - received).clamp(0, double.infinity).toDouble();

    // Compact 58mm receipt: short header, aligned Qty/Rate/Amount and tight spacing.
    final pageHeight = (116 + widget.cartItems.length * 8).toDouble();
    final pageFormat = PdfPageFormat(
      _usbPaperWidth * PdfPageFormat.mm,
      pageHeight * PdfPageFormat.mm,
      marginLeft: _paperMarginMm * PdfPageFormat.mm,
      marginRight: _paperMarginMm * PdfPageFormat.mm,
      marginTop: _paperMarginMm * PdfPageFormat.mm,
      marginBottom: _paperMarginMm * PdfPageFormat.mm,
    );

    document.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(child: pw.Text('🛒 KHAN BABA 🛒',
              style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold))),
            pw.Center(child: pw.Text('GENERAL STORE',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
            pw.Center(child: pw.Text('G.T ROAD SANAWAN', style: const pw.TextStyle(fontSize: 7.5))),
            pw.Center(child: pw.Text('PH#03451444325', style: const pw.TextStyle(fontSize: 7))),
            pw.Divider(height: 5, thickness: 0.6),
            pw.Text(
              'Bill# $invoiceNumber  Date: ${DateFormat('dd-MM-yyyy').format(parsedDate)}  Time: ${DateFormat('hh:mm a').format(parsedDate)}  Cashier: ${widget.cashierName}  Type: ${widget.salesType}',
              style: const pw.TextStyle(fontSize: 5.5),
            ),
            pw.Divider(height: 5, thickness: 0.6),
            pw.Text(
              'Customer: ${widget.customerName}',
              style: const pw.TextStyle(fontSize: 6.5),
            ),
            if (widget.customerPhone.trim().isNotEmpty)
              pw.Text(
                'Phone: ${widget.customerPhone}',
                style: const pw.TextStyle(fontSize: 6.5),
              ),
            pw.Divider(height: 5, thickness: 0.6),
            pw.Row(children: [
              pw.Expanded(flex: 1, child: pw.Text('Sr#', style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold))),
              pw.Expanded(flex: 5, child: pw.Text('Item', style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold))),
              pw.Expanded(flex: 2, child: pw.Text('Qty', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold))),
              pw.Expanded(flex: 3, child: pw.Text('Amount', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold))),
            ]),
            pw.SizedBox(height: 2),
            ...widget.cartItems.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Row(children: [
                  pw.Expanded(flex: 1, child: pw.Text('${index + 1}', style: const pw.TextStyle(fontSize: 6.5))),
                  pw.Expanded(flex: 5, child: pw.Text(_itemName(item), style: const pw.TextStyle(fontSize: 6.5))),
                  pw.Expanded(flex: 2, child: pw.Text(_itemQuantity(item).toStringAsFixed(0), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 6.5))),
                  pw.Expanded(flex: 3, child: pw.Text(_money(_itemTotal(item)), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 6.5))),
                ]),
              );
            }),
            pw.Divider(height: 5, thickness: 0.6),
            _pdfInfoRow('Sub Total', _money(_subtotal)),
            if (widget.discountAmount > 0)
              _pdfInfoRow('Discount', _money(widget.discountAmount)),
            if (widget.taxAmount > 0)
              _pdfInfoRow('Tax (GST)', _money(widget.taxAmount)),
            _pdfInfoRow('TOTAL', _money(widget.totalAmount), bold: true),
            pw.Divider(height: 5, thickness: 0.6),
            _pdfInfoRow('Payment', widget.paymentType),
            _pdfInfoRow('Received', _money(received)),
            if (due > 0) _pdfInfoRow('Balance Due', _money(due)),
            if (change > 0) _pdfInfoRow('Change', _money(change)),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'THANK YOU - VISIT AGAIN',
                style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Center(
              child: pw.Text(
                'Developed by SohaibTech\nWhatsApp: 03401832381',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 6),
              ),
            ),
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
              title: const Text('58mm Bill Preview'),
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
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !Platform.isWindows,
        leading: desktopReturnButton(),
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
            const SizedBox(height: 8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Paper:'),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _usbPaperWidth,
                      items: const [
                        DropdownMenuItem(value: 58, child: Text('58 mm')),
                        DropdownMenuItem(value: 80, child: Text('80 mm')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _usbPaperWidth = value);
                      },
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Text Size:'),
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
                        DropdownMenuItem(value: 4, child: Text('4 mm')),
                        DropdownMenuItem(value: 6, child: Text('6 mm')),
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
              label: Text(_isUsbScanning ? 'USB printer search ho raha hai...' : 'Find USB OTG Printer'),
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('USB printer connect kar ke Find USB OTG Printer dabayein.', style: TextStyle(color: Colors.black54)),
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
                    onPressed: _isGeneratingPdf ? null : _previewPdf,
                    icon: const Icon(Icons.preview),
                    label: const Text('58mm Preview'),
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
