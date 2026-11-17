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
    tempDirectory = await Directory.systemTemp.createTemp('khan_baba_recall_');
    DBHelper.localOnlyMode = true;
    DBHelper.drivePrimaryMode = false;
    DBHelper.databasePathOverrideForTests = p.join(tempDirectory.path, 'recall.db');
    await DBHelper.closeDatabase();
  });

  tearDown(() async {
    await DBHelper.closeDatabase();
    DBHelper.databasePathOverrideForTests = null;
    DBHelper.localOnlyMode = false;
    DBHelper.drivePrimaryMode = false;
    if (await tempDirectory.exists()) await tempDirectory.delete(recursive: true);
  });

  test('edited bill recalculates totals and reconciles stock and Khata atomically', () async {
    final customerId = await _seedCustomer();
    await _seedProduct();
    final saleId = await _createPartialSale(customerId, quantity: 2);
    await DBHelper.updateSaleFromRecall(
      saleId: saleId,
      sale: {'customer_id': customerId, 'customer_type': 'Khata', 'payment_type': 'Partial', 'discount': 5.4, 'received_amount': 20.0},
      items: [{'barcode': 'RECALL-TEA-1', 'name': 'Recall Tea', 'quantity': 3, 'salePrice': 18.0, 'purchasePrice': 10.0, 'stockUnit': 'pcs'}],
    );
    final db = await DBHelper.database;
    final sale = (await db.query('sales', where: 'id = ?', whereArgs: [saleId])).single;
    expect((sale['total_amount'] as num).toDouble(), 54.0);
    expect((sale['discount'] as num).toDouble(), 5.4);
    expect((sale['final_amount'] as num).toDouble(), 48.6);
    expect((sale['received_amount'] as num).toDouble(), 20.0);
    expect((sale['balance_due'] as num).toDouble(), 28.6);
    final product = (await db.query('products', where: 'barcode = ?', whereArgs: ['RECALL-TEA-1'])).single;
    expect(product['quantity'], 7);
    final party = (await db.query('parties', columns: ['balance'], where: 'id = ?', whereArgs: [customerId])).single;
    expect((party['balance'] as num).toDouble(), 28.6);
    final ledger = await db.query('khata_transactions', where: 'party_id = ?', whereArgs: [customerId]);
    expect(ledger, hasLength(2));
    expect(ledger.where((x) => x['type'] == 'credit').single['amount'], 48.6);
    expect(ledger.where((x) => x['type'] == 'receipt').single['amount'], 20.0);
  });

  test('receipt before original sale does not block safe overwrite', () async {
    final customerId = await _seedCustomer();
    await _seedProduct();
    final db = await DBHelper.database;
    final party = (await db.query('parties', columns: ['sync_id'], where: 'id = ?', whereArgs: [customerId])).single;
    await db.insert('khata_transactions', {'party_id': customerId, 'party_sync_id': party['sync_id'], 'sync_id': 'recall-prior-receipt', 'type': 'receipt', 'amount': 2.0, 'note': 'Receipt before sale', 'date': '2026-11-16 09:00:00'});
    final saleId = await _createPartialSale(customerId, quantity: 1, date: '2026-11-16 10:00:00', received: 5.0);
    await DBHelper.updateSaleFromRecall(
      saleId: saleId,
      sale: {'customer_id': customerId, 'customer_type': 'Khata', 'payment_type': 'Partial', 'discount': 0.0, 'received_amount': 5.0},
      items: [{'barcode': 'RECALL-TEA-1', 'name': 'Recall Tea', 'quantity': 1, 'salePrice': 18.0, 'purchasePrice': 10.0}],
    );
    expect(await db.query('khata_transactions', where: 'sync_id = ?', whereArgs: ['recall-prior-receipt']), hasLength(1));
  });

  test('receipt after original sale blocks overwrite and leaves stock and bill unchanged', () async {
    final customerId = await _seedCustomer();
    await _seedProduct();
    final saleId = await _createPartialSale(customerId, quantity: 1, date: '2026-11-16 10:00:00', received: 5.0);
    final db = await DBHelper.database;
    final party = (await db.query('parties', columns: ['sync_id'], where: 'id = ?', whereArgs: [customerId])).single;
    await db.insert('khata_transactions', {'party_id': customerId, 'party_sync_id': party['sync_id'], 'sync_id': 'recall-later-receipt', 'type': 'receipt', 'amount': 1.0, 'note': 'Later receipt', 'date': '2026-11-16 11:00:00'});
    await expectLater(
      DBHelper.updateSaleFromRecall(
        saleId: saleId,
        sale: {'customer_id': customerId, 'customer_type': 'Khata', 'payment_type': 'Partial', 'discount': 0.0, 'received_amount': 5.0},
        items: [{'barcode': 'RECALL-TEA-1', 'name': 'Recall Tea', 'quantity': 2, 'salePrice': 18.0, 'purchasePrice': 10.0}],
      ),
      throwsA(isA<Exception>()),
    );
    final product = (await db.query('products', where: 'barcode = ?', whereArgs: ['RECALL-TEA-1'])).single;
    expect(product['quantity'], 9);
    final original = (await db.query('sales', where: 'id = ?', whereArgs: [saleId])).single;
    expect((original['final_amount'] as num).toDouble(), 18.0);
  });

  test('bill with a return record cannot be overwritten', () async {
    final customerId = await _seedCustomer();
    await _seedProduct();
    final saleId = await _createPartialSale(customerId, quantity: 1);
    final db = await DBHelper.database;
    await db.insert('sale_returns', {'sale_id': saleId, 'customer_id': customerId, 'reason': 'Test return', 'refund_method': 'Cash', 'refund_amount': 1.0, 'date': '2026-11-16 11:00:00'});
    await expectLater(
      DBHelper.updateSaleFromRecall(
        saleId: saleId,
        sale: {'customer_id': customerId, 'customer_type': 'Khata', 'payment_type': 'Partial', 'discount': 0.0, 'received_amount': 5.0},
        items: [{'barcode': 'RECALL-TEA-1', 'name': 'Recall Tea', 'quantity': 1, 'salePrice': 18.0, 'purchasePrice': 10.0}],
      ),
      throwsA(isA<Exception>()),
    );
    final product = (await db.query('products', where: 'barcode = ?', whereArgs: ['RECALL-TEA-1'])).single;
    expect(product['quantity'], 9);
  });
}

Future<int> _seedCustomer() => DBHelper.insertParty({
  'name': 'Recall Test Customer', 'phone': '03000000000', 'type': 'customer',
  'customer_type': 'Khata', 'balance': 0.0,
});

Future<int> _seedProduct() => DBHelper.insertProduct({
  'name': 'Recall Tea', 'barcode': 'RECALL-TEA-1', 'price': 18.0,
  'purchasePrice': 10.0, 'quantity': 10, 'stock_unit': 'pcs',
});

Future<int> _createPartialSale(int customerId, {
  required int quantity,
  String date = '2026-11-16 10:00:00',
  double received = 10.0,
}) => DBHelper.completeSale(
  sale: {
    'total_amount': quantity * 18.0, 'discount': 0.0,
    'final_amount': quantity * 18.0, 'payment_type': 'Partial',
    'customer_id': customerId, 'customer_type': 'Khata',
    'received_amount': received, 'balance_due': quantity * 18.0 - received,
    'date': date,
  },
  items: [{
    'barcode': 'RECALL-TEA-1', 'name': 'Recall Tea', 'quantity': quantity,
    'salePrice': 18.0, 'purchasePrice': 10.0, 'stockUnit': 'pcs',
  }],
);
