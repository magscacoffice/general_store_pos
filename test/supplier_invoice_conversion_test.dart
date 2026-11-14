import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:khan_baba_general_store/db_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDirectory = await Directory.systemTemp.createTemp('khan_baba_invoice_units_');
    DBHelper.localOnlyMode = true;
    DBHelper.drivePrimaryMode = false;
    DBHelper.databasePathOverrideForTests =
        p.join(tempDirectory.path, 'invoice-units.db');
    await DBHelper.closeDatabase();
  });

  tearDown(() async {
    await DBHelper.closeDatabase();
    DBHelper.databasePathOverrideForTests = null;
    DBHelper.localOnlyMode = false;
    DBHelper.drivePrimaryMode = false;
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('posts carton quantity as base pieces and preserves invoice-unit details', () async {
    final supplierId = await DBHelper.insertParty({
      'name': 'Unit Test Supplier',
      'phone': '03000000000',
      'type': 'supplier',
      'balance': 0.0,
    });

    await DBHelper.recordPurchaseInvoice(
      supplierId: supplierId,
      invoiceNumber: 'CTN-100',
      invoiceDate: '2026-11-14',
      invoiceTotal: 2400,
      paidAmount: 1000,
      items: [
        {
          'product_id': null,
          'new_product_name': 'Tea',
          'new_product_barcode': 'UNIT-TEA-1',
          'quantity': 24,
          'invoice_quantity': 2,
          'conversion_factor': 12,
          'base_unit': 'pcs',
          'unit_label': 'carton',
          'unit_cost': 1200,
          'line_total': 2400,
          'sale_price': 150,
        },
      ],
    );

    final product = (await DBHelper.getProducts()).single;
    final purchase = (await DBHelper.getPurchases()).single;
    final supplier = (await DBHelper.getParties('supplier')).single;

    expect(product['quantity'], 24);
    expect(product['stock_unit'], 'pcs');
    expect(product['purchasePrice'], 100.0);
    expect(product['price'], 150.0);
    expect(purchase['quantity'], 24);
    expect(purchase['invoice_quantity'], 2.0);
    expect(purchase['conversion_factor'], 12.0);
    expect(purchase['unit_label'], 'carton');
    expect(purchase['base_unit'], 'pcs');
    expect(purchase['unit_cost'], 100.0);
    expect(purchase['invoice_unit_cost'], 1200.0);
    expect(purchase['total_cost'], 2400.0);
    expect(supplier['balance'], 1400.0);
  });

  test('rejects a retail price below the converted base-unit purchase cost', () async {
    final supplierId = await DBHelper.insertParty({
      'name': 'Cost Test Supplier',
      'phone': '03111111111',
      'type': 'supplier',
      'balance': 0.0,
    });

    await expectLater(
      DBHelper.recordPurchaseInvoice(
        supplierId: supplierId,
        invoiceNumber: 'COST-100',
        invoiceDate: '2026-11-14',
        invoiceTotal: 2400,
        paidAmount: 0,
        items: [
          {
            'product_id': null,
            'new_product_name': 'Tea',
            'new_product_barcode': 'UNIT-TEA-2',
            'quantity': 24,
            'invoice_quantity': 2,
            'conversion_factor': 12,
            'base_unit': 'pcs',
            'unit_label': 'carton',
            'unit_cost': 1200,
            'line_total': 2400,
            'sale_price': 90,
          },
        ],
      ),
      throwsA(isA<Exception>()),
    );

    expect(await DBHelper.getProducts(), isEmpty);
    expect(await DBHelper.getPurchases(), isEmpty);
  });

  test('blocks posting the same supplier invoice twice', () async {
    final supplierId = await DBHelper.insertParty({
      'name': 'Duplicate Test Supplier',
      'phone': '03222222222',
      'type': 'supplier',
      'balance': 0.0,
    });
    final items = [
      {
        'product_id': null,
        'new_product_name': 'Rice',
        'new_product_barcode': 'UNIT-RICE-1',
        'quantity': 10,
        'invoice_quantity': 1,
        'conversion_factor': 10,
        'base_unit': 'pcs',
        'unit_label': 'bag',
        'unit_cost': 100,
        'line_total': 1000,
        'sale_price': 120,
      },
    ];

    Future<void> post() => DBHelper.recordPurchaseInvoice(
      supplierId: supplierId,
      invoiceNumber: 'DUP-100',
      invoiceDate: '2026-11-14',
      invoiceTotal: 1000,
      paidAmount: 0,
      items: items,
    );

    await post();
    await expectLater(post(), throwsA(isA<Exception>()));
    expect((await DBHelper.getProducts()).length, 1);
    expect((await DBHelper.getPurchases()).length, 1);
  });
  test('upgrades an existing version-16 database without losing stock or purchase history', () async {
    await DBHelper.closeDatabase();
    final legacyPath = p.join(tempDirectory.path, 'legacy-v16.db');
    final legacy = await openDatabase(
      legacyPath,
      version: 16,
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE products(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          barcode TEXT UNIQUE NOT NULL,
          price REAL NOT NULL,
          purchasePrice REAL DEFAULT 0,
          wholesalePrice REAL DEFAULT 0,
          damaged_quantity INTEGER DEFAULT 0,
          quantity INTEGER NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1
        )''');
        await db.execute('''CREATE TABLE purchases(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER NOT NULL,
          product_name TEXT NOT NULL,
          barcode TEXT NOT NULL,
          quantity INTEGER NOT NULL,
          unit_cost REAL NOT NULL,
          total_cost REAL NOT NULL,
          supplier_id INTEGER,
          sync_id TEXT,
          supplier_sync_id TEXT,
          date TEXT NOT NULL,
          invoice_group_id TEXT,
          invoice_number TEXT,
          invoice_date TEXT,
          invoice_total REAL,
          invoice_discount REAL,
          invoice_tax REAL,
          invoice_paid_amount REAL,
          invoice_balance_due REAL,
          invoice_image_path TEXT,
          unit_label TEXT
        )''');
        await db.execute('''CREATE TABLE sale_items(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sale_id INTEGER NOT NULL,
          product_id INTEGER,
          barcode TEXT NOT NULL,
          product_name TEXT NOT NULL,
          quantity INTEGER NOT NULL,
          sale_price REAL NOT NULL,
          purchase_price REAL NOT NULL,
          line_total REAL NOT NULL,
          cost_total REAL NOT NULL,
          sync_id TEXT,
          sale_sync_id TEXT
        )''');
        await db.execute('''CREATE TABLE sale_return_items(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          return_id INTEGER NOT NULL,
          sale_item_id INTEGER NOT NULL,
          product_id INTEGER,
          barcode TEXT NOT NULL,
          product_name TEXT NOT NULL,
          quantity INTEGER NOT NULL,
          sale_price REAL NOT NULL,
          purchase_price REAL NOT NULL,
          line_total REAL NOT NULL,
          cost_total REAL NOT NULL,
          condition TEXT NOT NULL DEFAULT 'saleable',
          sync_id TEXT,
          return_sync_id TEXT,
          sale_item_sync_id TEXT
        )''');
        await db.insert('products', {
          'name': 'Legacy Sugar',
          'barcode': 'LEGACY-1',
          'price': 100,
          'purchasePrice': 70,
          'quantity': 25,
        });
        await db.insert('purchases', {
          'product_id': 1,
          'product_name': 'Legacy Sugar',
          'barcode': 'LEGACY-1',
          'quantity': 25,
          'unit_cost': 70,
          'total_cost': 1750,
          'date': '2026-11-01',
          'invoice_number': 'OLD-1',
          'unit_label': 'pcs',
        });
      },
    );
    await legacy.close();

    DBHelper.databasePathOverrideForTests = legacyPath;
    final upgraded = await DBHelper.database;
    final products = await upgraded.query('products');
    final purchases = await upgraded.query('purchases');
    final productColumns = await upgraded.rawQuery('PRAGMA table_info(products)');
    final purchaseColumns = await upgraded.rawQuery('PRAGMA table_info(purchases)');
    final saleItemColumns = await upgraded.rawQuery('PRAGMA table_info(sale_items)');
    final returnItemColumns = await upgraded.rawQuery('PRAGMA table_info(sale_return_items)');

    expect(products.single['quantity'], 25);
    expect(products.single['name'], 'Legacy Sugar');
    expect(productColumns.map((row) => row['name']), contains('stock_unit'));
    expect(purchases.single['invoice_number'], 'OLD-1');
    expect(purchases.single['quantity'], 25);
    expect(purchaseColumns.map((row) => row['name']), containsAll([
      'invoice_quantity',
      'conversion_factor',
      'base_unit',
      'invoice_unit_cost',
    ]));
    expect(saleItemColumns.map((row) => row['name']), contains('stock_unit'));
    expect(returnItemColumns.map((row) => row['name']), contains('stock_unit'));
  });

}
