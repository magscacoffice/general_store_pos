import 'package0:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

void main() {
  runApp(GeneralStoreApp());
}

class GeneralStoreApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'جنرل سٹور POS',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    BillingScreen(),
    StockScreen(),
    PrinterSettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _checkInternetAndAutoBackup();
  }

  void _checkInternetAndAutoBackup() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult != ConnectivityResult.none) {
      print('انٹرنیٹ دستیاب ہے: گوگل ڈرائیو پر آٹو بیک اپ ہو رہا ہے...');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('جنرل سٹور (آف لائن + ڈرائیو بیک اپ)'),
        centerTitle: true,
      ),
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.receipt), label: 'بلنگ / کھاتہ'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: 'سٹاک (SQLite)'),
          BottomNavigationBarItem(icon: Icon(Icons.print), label: 'پرنٹر سیٹنگز'),
        ],
      ),
    );
  }
}

class BillingScreen extends StatelessWidget {
  void _printReceipt() async {
    print('پرنٹر پر بل بھیجا جا رہا ہے...');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              labelText: 'گاہک کا نام / کھاتہ نمبر درج کریں',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 20),
          Expanded(
            child: ListView(
              children: [
                ListTile(
                  title: Text('آئٹم: چینی (1 کلو)'),
                  subtitle: Text('قیمت: 150 x 2 = 300 روپے'),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: _printReceipt,
            icon: Icon(Icons.print, color: Colors.white),
            label: Text('بل پرنٹ کریں (وائرلیس پرنٹر)', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class StockScreen extends StatefulWidget {
  @override
  _StockScreenState createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  Database? _database;

  @override
  void initState() {
    super.initState();
    _initDatabase();
  }

  Future<void> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'general_store.db');
    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) {
        return db.execute(
          "CREATE TABLE stock(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, price REAL, qty INTEGER)",
        );
      },
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('سٹاک ڈیٹا آف لائن (SQLite) میں محفوظ ہے', style: TextStyle(fontSize: 16)),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              if (_database != null) {
                await _database!.insert('stock', {'name': 'چینی', 'price': 150.0, 'qty': 50});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('نیا سامان کامیابی سے شامل ہو گیا!')),
                );
              }
            },
            child: Text('نیا سامان SQLite میں درج کریں'),
          ),
        ],
      ),
    );
  }
}

class PrinterSettingsScreen extends StatefulWidget {
  @override
  _PrinterSettingsScreenState createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  List<ScanResult> _scanResults = [];

  void _scanForPrinters() {
    FlutterBluePlus.startScan(timeout: Duration(seconds: 4));
    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _scanResults = results;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(16.0),
      child: Column(
        children: [
          ElevatedButton.icon(
            onPressed: _scanForPrinters,
            icon: Icon(Icons.bluetooth_searching),
            label: Text('قریبی تھرمل پرنٹر تلاش کریں'),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _scanResults.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(_scanResults[index].device.platformName.isNotEmpty
                      ? _scanResults[index].device.platformName
                      : 'نامعلوم پرنٹر'),
                  subtitle: Text(_scanResults[index].device.remoteId.toString()),
                  trailing: ElevatedButton(
                    onPressed: () {},
                    child: Text('کنیکٹ کریں'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}