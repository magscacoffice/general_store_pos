import 'package:flutter/material.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class PrinterScreen extends StatefulWidget {
  final List<Map<String, dynamic>> cartItems;
  final double totalAmount;

  const PrinterScreen({super.key, required this.cartItems, required this.totalAmount});

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selectedDevice;
  bool _connected = false;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  Future<void> _initBluetooth() async {
    bool? isConnected = await bluetooth.isConnected;
    List<BluetoothDevice> devices = [];
    try {
      devices = await bluetooth.getBondedDevices();
    } catch (e) {
      // Handle error
    }

    if (!mounted) return;
    setState(() {
      _devices = devices;
      _connected = isConnected ?? false;
    });
  }

  // Bluetooth Printer Connection
  void _connect(BluetoothDevice device) async {
    setState(() => _isConnecting = true);
    try {
      await bluetooth.connect(device);
      setState(() {
        _selectedDevice = device;
        _connected = true;
        _isConnecting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Printer Connect Ho Gaya!')),
        );
      }
    } catch (e) {
      setState(() => _isConnecting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection Error: $e')),
        );
      }
    }
  }

  // Disconnect Printer
  void _disconnect() async {
    await bluetooth.disconnect();
    setState(() {
      _connected = false;
      _selectedDevice = null;
    });
  }

  // Print Receipt
  void _printReceipt() async {
    if (_connected) {
      String currentDate = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

      bluetooth.printNewLine();
      bluetooth.printCustom("KHAN BABA GENERAL STORE", 2, 1); // Size 2: Bold/Large, Alignment 1: Center
      bluetooth.printCustom("Sanawan, Kot Addu", 1, 1);
      bluetooth.printCustom("--------------------------------", 1, 1);
      bluetooth.printCustom("Waqt: $currentDate", 1, 0);
      bluetooth.printCustom("--------------------------------", 1, 1);
      
      bluetooth.printLeftRight("Item", "Total", 1);
      bluetooth.printCustom("--------------------------------", 1, 1);

      for (var item in widget.cartItems) {
        String name = item['name'];
        String qtyPrice = "${item['quantity']} x ${item['price']}";
        String total = "${item['quantity'] * item['price']}";
        
        bluetooth.printLeftRight(name, "Rs. $total", 1);
        bluetooth.printLeftRight("  ($qtyPrice)", "", 1);
      }

      bluetooth.printCustom("--------------------------------", 1, 1);
      bluetooth.printLeftRight("TOTAL AMOUNT:", "Rs. ${widget.totalAmount}", 2);
      bluetooth.printCustom("--------------------------------", 1, 1);
      bluetooth.printCustom("Shukriya! Dobara tashreef layein.", 1, 1);
      bluetooth.printNewLine();
      bluetooth.printNewLine();
      bluetooth.paperCut();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pehle Bluetooth Printer Connect Karein!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thermal Bluetooth Bill Print'),
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Paired Bluetooth Printers:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 150,
              child: ListView.builder(
                itemCount: _devices.length,
                itemBuilder: (context, index) {
                  final device = _devices[index];
                  return ListTile(
                    title: Text(device.name ?? "Unknown Device"),
                    subtitle: Text(device.address ?? ""),
                    trailing: ElevatedButton(
                      onPressed: _connected ? null : () => _connect(device),
                      child: Text(_connected && _selectedDevice?.address == device.address ? 'Connected' : 'Connect'),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _connected ? 'Status: Connected ✅' : 'Status: Disconnected ❌',
                  style: TextStyle(fontSize: 16, color: _connected ? Colors.green : Colors.red, fontWeight: FontWeight.bold),
                ),
                if (_connected)
                  TextButton(
                    onPressed: _disconnect,
                    child: const Text('Disconnect', style: TextStyle(color: Colors.red)),
                  ),
              ],
            ),
            const Spacer(),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _connected ? _printReceipt : null,
              icon: const Icon(Icons.print),
              label: const Text('Bill Print Karein', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}