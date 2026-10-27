import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'v:url_launcher/url_launcher.dart';

class PrinterScreen extends StatefulWidget {
  final List<Map<String, dynamic>> cartItems;
  final double totalAmount;
  final String customerName;
  final String customerPhone;

  const PrinterScreen({
    super.key,
    required this.cartItems,
    required this.totalAmount,
    this.customerName = 'Aam Grahak (Quick Bill)',
    this.customerPhone = '',
  });

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  List<BluetoothInfo> _devices = [];
  String _selectedMac = '';
  bool _isConnected = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _getBluetoothDevices();
  }

  Future<void> _getBluetoothDevices() async {
    setState(() => _isLoading = true);
    try {
      final bool status = await PrintBluetoothThermal.isBluetoothEnabled;
      if (status) {
        List<BluetoothInfo> devices = await PrintBluetoothThermal.pairedBluetooths;
        setState(() => _devices = devices);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pehle mobile ka Bluetooth on karein!')));
        }
      }
    } catch (e) {
      // Error handling
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _connectDevice(String macAddress) async {
    setState(() => _isLoading = true);
    try {
      final bool result = await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
      if (result) {
        setState(() {
          _isConnected = true;
          _selectedMac = macAddress;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Printer connect ho gaya!')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connection error: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _printReceipt() async {
    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pehle printer connect karein!')));
      return;
    }

    await PrintBluetoothThermal.writeText("KHAN BABA GENERAL STORE\n");
    await PrintBluetoothThermal.writeText("Sanawan, Kot Addu\n");
    await PrintBluetoothThermal.writeText("Customer: ${widget.customerName}\n");
    await PrintBluetoothThermal.writeText("Date: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}\n");
    await PrintBluetoothThermal.writeText("--------------------------------\n");

    for (var item in widget.cartItems) {
      await PrintBluetoothThermal.writeText("${item['name']}\n${item['quantity']} x ${item['salePrice']} = Rs.${item['quantity'] * item['salePrice']}\n");
    }

    await PrintBluetoothThermal.writeText("--------------------------------\n");
    await PrintBluetoothThermal.writeText("TOTAL: Rs. ${widget.totalAmount}\n");
    await PrintBluetoothThermal.writeText("--------------------------------\n");
    await PrintBluetoothThermal.writeText("Thank you for shopping!\n\n\n");

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rasid kamyabi se print ho gayi!')));
    }
  }

  String _buildBillText() {
    String text = "*KHAN BABA GENERAL STORE*\n";
    text += "Grahak: ${widget.customerName}\n";
    text += "Tareekh: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}\n";
    text += "--------------------------------\n";
    for (var item in widget.cartItems) {
      text += "${item['name']} - ${item['quantity']} x ${item['salePrice']} = Rs.${item['quantity'] * item['salePrice']}\n";
    }
    text += "--------------------------------\n";
    text += "*Kul Raqam: Rs. ${widget.totalAmount}*\n";
    text += "Kharidari ka shukriya!";
    return text;
  }

  void _shareOnWhatsApp() {
    Share.share(_buildBillText());
  }

  void _sendSMSAlert() async {
    final Uri smsUri = Uri(
      scheme: 'sms',
      path: widget.customerPhone,
      queryParameters: <String, String>{'body': _buildBillText()},
    );
    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
    } else {
      Share.share(_buildBillText());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bluetooth Thermal Printer & Bill'), backgroundColor: Colors.teal, foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
              onPressed: _getBluetoothDevices,
              icon: const Icon(Icons.refresh),
              label: const Text('Paired devices talash karein'),
            ),
            const SizedBox(height: 15),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Expanded(
                    flex: 1,
                    child: ListView.builder(
                      itemCount: _devices.length,
                      itemBuilder: (context, index) {
                        final device = _devices[index];
                        return Card(
                          child: ListTile(
                            title: Text(device.name),
                            subtitle: Text(device.macAdress),
                            trailing: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _selectedMac == device.macAdress ? Colors.green : Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => _connectDevice(device.macAdress),
                              child: Text(_selectedMac == device.macAdress ? 'Connected' : 'Connect'),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
            const Divider(thickness: 2),
            Expanded(
              flex: 1,
              child: ListView.builder(
                itemCount: widget.cartItems.length,
                itemBuilder: (context, index) {
                  final item = widget.cartItems[index];
                  return ListTile(
                    title: Text(item['name']),
                    subtitle: Text('${item['quantity']} x Rs. ${item['salePrice']}'),
                    trailing: Text('Rs. ${item['quantity'] * item['salePrice']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Kul Raqam:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('Rs. ${widget.totalAmount}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal)),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: _printReceipt,
                    icon: const Icon(Icons.print),
                    label: const Text('Rasid Print Karein', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: _shareOnWhatsApp,
                    icon: const Icon(Icons.share),
                    label: const Text('WhatsApp Par Bhein', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}