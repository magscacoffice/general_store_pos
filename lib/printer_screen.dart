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

  double get _subtotal => widget.subtotalAmount ?? widget.totalAmount;

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _itemTotal(Map<String, dynamic> item) {
    return _number(item['quantity']) * _number(item['salePrice']);
  }

  String _money(double amount) => amount.toStringAsFixed(2);

  String _line(String left, String right, {int width = 32}) {
    final available = width - left.length - right.length;
    if (available <= 1) {
      return '${left.substring(0, left.length > width - right.length - 1 ? width - right.length - 1 : left.length)} $right';
    }
    return left + List.filled(available, ' ').join() + right;
  }

  String _billText({required bool plain}) {
    const width = 32;
    final separator = List.filled(width, '-').join();
    final received = widget.receivedAmount ?? widget.totalAmount;
    final change = (received - widget.totalAmount).clamp(0, double.infinity).toDouble();
    final tax = widget.taxAmount;
    final buffer = StringBuffer()
      ..writeln('       KHAN BABA')
      ..writeln(' GENERAL STORE & PERFUMERY')
      ..writeln(' Perfume | Cosmetics | Daily Needs')
      ..writeln('        Gift Items')
      ..writeln('       GT Road Sanawa')
      ..writeln('      WhatsApp: 0345-1444325')
      ..writeln(separator)
      ..writeln(_line('Bill No', ': ${widget.invoiceId.toString().padLeft(6, '0')}', width: width))
      ..writeln(_line('Date', ': ${DateFormat('dd-MM-yyyy').format(DateTime.tryParse(widget.saleDate) ?? DateTime.now())}', width: width))
      ..writeln(_line('Time', ': ${DateFormat('hh:mm a').format(DateTime.tryParse(widget.saleDate) ?? DateTime.now())}', width: width))
      ..writeln(_line('Cashier', ': ${widget.cashierName}', width: width))
      ..writeln(_line('Sales Type', ': ${widget.salesType}', width: width))
      ..writeln(separator)
      ..writeln('Customer : ${widget.customerName}')
      ..writeln('Phone    : ${widget.customerPhone.isEmpty ? 'N/A' : widget.customerPhone}')
      ..writeln(separator)
      ..writeln(_line('No  Description', 'Amount', width: width));
    for (var i = 0; i < widget.cartItems.length; i++) {
      final item = widget.cartItems[i];
      final name = (item['name']?.toString() ?? 'Product');
      final qty = _number(item['quantity']).toStringAsFixed(0);
      final rate = _number(item['salePrice']);
      final amount = _itemTotal(item);
      buffer
        ..writeln('${i + 1}. ${name.length > 25 ? name.substring(0, 25) : name}')
        ..writeln('   ${_money(rate)} x $qty = ${_money(amount)}');
    }
    buffer
      ..writeln(separator)
      ..writeln(_line('Sub Total', _money(_subtotal), width: width))
      ..writeln(_line('Discount', _money(widget.discountAmount), width: width))
      ..writeln(_line('Tax (GST)', _money(tax), width: width))
      ..writeln(separator)
      ..writeln(_line('TOTAL AMOUNT', _money(widget.totalAmount), width: width))
      ..writeln(separator)
      ..writeln(_line('Payment Method', widget.paymentType, width: width))
      ..writeln(_line('Received Amount', _money(received), width: width))
      ..writeln(_line('Change', _money(change), width: width))
      ..writeln(separator)
      ..writeln('       Thank You For Shopping')
      ..writeln('             Visit Again')
      ..writeln('\n\n');
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
        for (final line in _billText(plain: true).split(String.fromCharCode(10))) {
          ticket.text(line);
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
    final invoiceNumber =
        widget.invoiceId > 0 ? widget.invoiceId.toString() : 'N/A';
    final parsedDate = DateTime.tryParse(widget.saleDate) ?? DateTime.now();
    final received = widget.receivedAmount ?? widget.totalAmount;
    final change =
        (received - widget.totalAmount).clamp(0, double.infinity).toDouble();

    // 58mm thermal receipt: compact width with height based on item count.
    final pageHeight = (155 + widget.cartItems.length * 13).toDouble();
    final pageFormat = PdfPageFormat(
      58 * PdfPageFormat.mm,
      pageHeight * PdfPageFormat.mm,
      marginAll: 4 * PdfPageFormat.mm,
    );

    document.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                'KHAN BABA',
                style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Center(
              child: pw.Text(
                'GENERAL STORE & PERFUMERY',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Center(child: pw.Text('Perfume | Cosmetics | Daily Needs', style: const pw.TextStyle(fontSize: 6))),
            pw.Center(child: pw.Text('Gift Items', style: const pw.TextStyle(fontSize: 7))),
            pw.Center(child: pw.Text('GT Road Sanawa', style: const pw.TextStyle(fontSize: 7))),
            pw.Center(child: pw.Text('WhatsApp: 0345-1444325', style: const pw.TextStyle(fontSize: 7))),
            pw.Divider(),
            _pdfInfoRow('Bill No', invoiceNumber),
            _pdfInfoRow('Date', DateFormat('dd-MM-yyyy').format(parsedDate)),
            _pdfInfoRow('Time', DateFormat('hh:mm a').format(parsedDate)),
            _pdfInfoRow('Cashier', widget.cashierName),
            _pdfInfoRow('Sales Type', widget.salesType),
            pw.Divider(),
            pw.Text('Customer: ${widget.customerName}', style: const pw.TextStyle(fontSize: 7)),
            pw.Text('Phone: ${widget.customerPhone.isEmpty ? 'N/A' : widget.customerPhone}', style: const pw.TextStyle(fontSize: 7)),
            pw.Divider(),
            pw.Row(
              children: [
                pw.Expanded(flex: 5, child: pw.Text('Description', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                pw.Expanded(flex: 2, child: pw.Text('Qty', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
                pw.Expanded(flex: 3, child: pw.Text('Amount', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
              ],
            ),
            pw.SizedBox(height: 3),
            ...widget.cartItems.map((item) {
              final name = item['name']?.toString() ?? 'Product';
              final qty = _number(item['quantity']);
              final rate = _number(item['salePrice']);
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Text(name, style: const pw.TextStyle(fontSize: 7)),
                    pw.Row(
                      children: [
                        pw.Expanded(child: pw.Text('${_money(rate)} x ${qty.toStringAsFixed(0)}', style: const pw.TextStyle(fontSize: 6))),
                        pw.Text(_money(_itemTotal(item)), style: const pw.TextStyle(fontSize: 7)),
                      ],
                    ),
                  ],
                ),
              );
            }),
            pw.Divider(),
            _pdfInfoRow('Sub Total', _money(_subtotal)),
            _pdfInfoRow('Discount', _money(widget.discountAmount)),
            _pdfInfoRow('Tax (GST)', _money(widget.taxAmount)),
            pw.Divider(),
            _pdfInfoRow('TOTAL AMOUNT', _money(widget.totalAmount), bold: true),
            pw.Divider(),
            _pdfInfoRow('Payment', widget.paymentType),
            _pdfInfoRow('Received', _money(received)),
            _pdfInfoRow('Change', _money(change)),
            pw.SizedBox(height: 8),
            pw.Center(child: pw.Text('Thank You For Shopping', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
            pw.Center(child: pw.Text('Visit Again', style: const pw.TextStyle(fontSize: 7))),
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
            appBar: AppBar(title: const Text('58mm Bill Preview')),
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
            Row(
              children: [
                const Text('USB Paper Size:'),
                const SizedBox(width: 12),
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
