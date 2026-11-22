import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:khan_baba_general_store/db_helper.dart';

Map<String, dynamic> envelope(
  Map<String, dynamic> data, {
  required String deviceId,
  required String hash,
}) => {
  'schemaVersion': 2,
  'deviceId': deviceId,
  'snapshotHash': hash,
  'data': data,
};

Future<void> useDatabase(String path) async {
  await DBHelper.closeDatabase();
  DBHelper.databasePathOverrideForTests = path;
  await DBHelper.database;
}

Future<void> resolveAllConflicts({required bool useRemote}) async {
  final conflicts = await DBHelper.getDriveSyncConflicts();
  for (final conflict in conflicts) {
    await DBHelper.resolveDriveSyncConflict(
      (conflict['id'] as num).toInt(),
      useRemote: useRemote,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late String androidPath;
  late String windowsPath;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDirectory = await Directory.systemTemp.createTemp('khan_baba_drive_sync_');
    androidPath = p.join(tempDirectory.path, 'android.db');
    windowsPath = p.join(tempDirectory.path, 'windows.db');
    DBHelper.localOnlyMode = true;
    DBHelper.drivePrimaryMode = false;
    DBHelper.databasePathOverrideForTests = androidPath;
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

  test('Android and Windows exchange sales, purchases, receipts and master data without duplicates', () async {
    // Seed Android's existing inventory and customer/supplier accounts.
    await DBHelper.insertProduct({
      'name': 'Sugar',
      'barcode': 'KB-1001',
      'price': 20.0,
      'purchasePrice': 10.0,
      'wholesalePrice': 18.0,
      'damaged_quantity': 0,
      'quantity': 10,
      'is_active': 1,
      'stock_unit': 'pcs',
    });
    await DBHelper.insertParty({
      'name': 'Test Customer',
      'phone': '03000000000',
      'type': 'customer',
      'balance': 0.0,
    });
    await DBHelper.insertParty({
      'name': 'Test Supplier',
      'phone': '03111111111',
      'type': 'supplier',
      'balance': 0.0,
    });
    final androidBase = await DBHelper.exportDriveSnapshot();

    // First Android -> Windows transfer.
    await useDatabase(windowsPath);
    expect(
      await DBHelper.mergeDriveSnapshot(
        envelope(androidBase, deviceId: 'android-device', hash: 'android-base'),
        sourceDeviceId: 'android-device',
        snapshotHash: 'android-base',
      ),
      isTrue,
    );
    var windowsProduct = (await DBHelper.getProducts()).single;
    var windowsCustomer = (await DBHelper.getParties('customer')).single;
    var windowsSupplier = (await DBHelper.getParties('supplier')).single;

    // Windows creates a sale. Android must receive its invoice, items and ledger.
    await DBHelper.completeSale(
      sale: {
        'total_amount': 20.0,
        'final_amount': 20.0,
        'discount': 0.0,
        'payment_type': 'Partial',
        'customer_id': windowsCustomer['id'],
        'received_amount': 5.0,
        'date': '2026-11-14T08:00:00',
      },
      items: [
        {
          'barcode': 'KB-1001',
          'name': 'Sugar',
          'quantity': 1,
          'salePrice': 20.0,
          'purchasePrice': 10.0,
        },
      ],
    );
    final windowsAfterSale = await DBHelper.exportDriveSnapshot();
    await useDatabase(androidPath);
    expect(
      await DBHelper.mergeDriveSnapshot(
        envelope(windowsAfterSale, deviceId: 'windows-master', hash: 'master-sale-1'),
        sourceDeviceId: 'windows-master',
        snapshotHash: 'master-sale-1',
        applyMasterState: true,
        detectConflicts: false,
      ),
      isTrue,
    );
    expect((await DBHelper.getSales()).length, 1);
    final importedSale = (await DBHelper.getSales()).single;
    final importedItems = await DBHelper.getSaleItems((importedSale['id'] as num).toInt());
    expect(importedItems.single['stock_unit'], 'pcs');
    expect((await DBHelper.getProducts()).single['quantity'], 9);
    expect((await DBHelper.getParties('customer')).single['balance'], 15.0);

    // Android creates another sale while Windows still has the previous stock.
    final androidCustomer = (await DBHelper.getParties('customer')).single;
    await DBHelper.completeSale(
      sale: {
        'total_amount': 20.0,
        'final_amount': 20.0,
        'discount': 0.0,
        'payment_type': 'Khata',
        'customer_id': androidCustomer['id'],
        'received_amount': 0.0,
        'date': '2026-11-14T08:10:00',
      },
      items: [
        {
          'barcode': 'KB-1001',
          'name': 'Sugar',
          'quantity': 1,
          'salePrice': 20.0,
          'purchasePrice': 10.0,
        },
      ],
    );
    final androidAfterSale = await DBHelper.exportDriveSnapshot();
    final androidSaleEnvelope = envelope(
      androidAfterSale,
      deviceId: 'android-device',
      hash: 'android-sale-2',
    );

    // Windows also creates a newer sale after Android's last download.
    // The incoming Android snapshot is now stale for stock and Khata balance.
    await useDatabase(windowsPath);
    windowsProduct = (await DBHelper.getProducts()).single;
    windowsCustomer = (await DBHelper.getParties('customer')).single;
    await DBHelper.completeSale(
      sale: {
        'total_amount': 40.0,
        'final_amount': 40.0,
        'discount': 0.0,
        'payment_type': 'Khata',
        'customer_id': windowsCustomer['id'],
        'received_amount': 0.0,
        'date': '2026-11-14T08:15:00',
      },
      items: [
        {
          'barcode': 'KB-1001',
          'name': 'Sugar',
          'quantity': 2,
          'salePrice': 20.0,
          'purchasePrice': 10.0,
        },
      ],
    );

    // Windows imports Android's sale but holds the stale stock/balance
    // differences for reconciliation. Keeping Windows must preserve its newer sale.
    expect(
      await DBHelper.mergeDriveSnapshot(
        androidSaleEnvelope,
        sourceDeviceId: 'android-device',
        snapshotHash: 'android-sale-2',
      ),
      isFalse,
    );
    expect((await DBHelper.getSales()).length, 3);
    expect((await DBHelper.getDriveSyncConflicts()).length, greaterThanOrEqualTo(2));
    await resolveAllConflicts(useRemote: false);
    expect(
      await DBHelper.mergeDriveSnapshot(
        androidSaleEnvelope,
        sourceDeviceId: 'android-device',
        snapshotHash: 'android-sale-2',
      ),
      isTrue,
    );
    expect((await DBHelper.getSales()).length, 3);
    expect((await DBHelper.getProducts()).single['quantity'], 7);
    expect((await DBHelper.getParties('customer')).single['balance'], 55.0);

    // The approved Windows master returns to Android; replay is idempotent.
    var masterData = await DBHelper.exportDriveSnapshot();
    await useDatabase(androidPath);
    final masterEnvelope1 = envelope(masterData, deviceId: 'windows-master', hash: 'master-after-android-sale');
    expect(
      await DBHelper.mergeDriveSnapshot(
        masterEnvelope1,
        sourceDeviceId: 'windows-master',
        snapshotHash: 'master-after-android-sale',
        applyMasterState: true,
        detectConflicts: false,
      ),
      isTrue,
    );
    expect((await DBHelper.getSales()).length, 3);
    expect((await DBHelper.getProducts()).single['quantity'], 7);
    expect((await DBHelper.getParties('customer')).single['balance'], 55.0);

    // Windows purchase travels back to Android.
    await useDatabase(windowsPath);
    windowsProduct = (await DBHelper.getProducts()).single;
    windowsSupplier = (await DBHelper.getParties('supplier')).single;
    await DBHelper.recordPurchase(
      productId: (windowsProduct['id'] as num).toInt(),
      quantity: 3,
      unitCost: 10,
      supplierId: (windowsSupplier['id'] as num).toInt(),
    );
    masterData = await DBHelper.exportDriveSnapshot();
    await useDatabase(androidPath);
    final masterEnvelope2 = envelope(masterData, deviceId: 'windows-master', hash: 'master-after-windows-purchase');
    await DBHelper.mergeDriveSnapshot(
      masterEnvelope2,
      sourceDeviceId: 'windows-master',
      snapshotHash: 'master-after-windows-purchase',
      applyMasterState: true,
      detectConflicts: false,
    );
    expect((await DBHelper.getPurchases()).length, 1);
    // Stock is 7 after three sales; the Windows purchase adds 3 units.
    expect((await DBHelper.getProducts()).single['quantity'], 10);

    // Android purchase and customer receipt travel back to Windows.
    final androidProduct = (await DBHelper.getProducts()).single;
    final androidSupplier = (await DBHelper.getParties('supplier')).single;
    await DBHelper.recordPurchase(
      productId: (androidProduct['id'] as num).toInt(),
      quantity: 2,
      unitCost: 10,
      supplierId: (androidSupplier['id'] as num).toInt(),
    );
    final customer = (await DBHelper.getParties('customer')).single;
    await DBHelper.recordKhataReceipt(
      partyId: (customer['id'] as num).toInt(),
      amount: 2,
      note: 'Drive sync integration test',
    );
    final androidFinal = await DBHelper.exportDriveSnapshot();
    final androidFinalEnvelope = envelope(
      androidFinal,
      deviceId: 'android-device',
      hash: 'android-final',
    );

    await useDatabase(windowsPath);
    expect(
      await DBHelper.mergeDriveSnapshot(
        androidFinalEnvelope,
        sourceDeviceId: 'android-device',
        snapshotHash: 'android-final',
      ),
      isFalse,
    );
    expect((await DBHelper.getPurchases()).length, 2);
    expect((await DBHelper.getKhataTransactions(
      ((await DBHelper.getParties('customer')).single['id'] as num).toInt(),
    )).length, 5);
    await resolveAllConflicts(useRemote: true);
    expect(
      await DBHelper.mergeDriveSnapshot(
        androidFinalEnvelope,
        sourceDeviceId: 'android-device',
        snapshotHash: 'android-final',
      ),
      isTrue,
    );
    expect((await DBHelper.getPurchases()).length, 2);

    masterData = await DBHelper.exportDriveSnapshot();
    await useDatabase(androidPath);
    final finalMaster = envelope(masterData, deviceId: 'windows-master', hash: 'master-final');
    await DBHelper.mergeDriveSnapshot(
      finalMaster,
      sourceDeviceId: 'windows-master',
      snapshotHash: 'master-final',
      applyMasterState: true,
      detectConflicts: false,
    );
    final finalSales = await DBHelper.getSales();
    expect(finalSales.length, 3);
    var totalSaleItems = 0;
    for (final sale in finalSales) {
      totalSaleItems += (await DBHelper.getSaleItems((sale['id'] as num).toInt())).length;
    }
    expect(totalSaleItems, 3);
    expect((await DBHelper.getPurchases()).length, 2);
    expect((await DBHelper.getProducts()).single['quantity'], 12);
    expect((await DBHelper.getParties('customer')).single['balance'], 53.0);

    // Reapplying the same master cannot duplicate any invoice or ledger entry.
    await DBHelper.mergeDriveSnapshot(
      finalMaster,
      sourceDeviceId: 'windows-master',
      snapshotHash: 'master-final',
      applyMasterState: true,
      detectConflicts: false,
    );
    expect((await DBHelper.getSales()).length, 3);
    expect((await DBHelper.getPurchases()).length, 2);
  });

  test('Windows master sale revision replaces Android invoice items and ledger without duplicates', () async {
    await DBHelper.insertProduct({
      'name': 'Revision Sugar',
      'barcode': 'KB-REV-1',
      'price': 20.0,
      'purchasePrice': 10.0,
      'wholesalePrice': 18.0,
      'damaged_quantity': 0,
      'quantity': 10,
      'is_active': 1,
      'stock_unit': 'pcs',
    });
    await DBHelper.insertParty({
      'name': 'Revision Customer',
      'phone': '03000000009',
      'type': 'customer',
      'customer_type': 'Khata',
      'balance': 0.0,
    });
    final androidCustomer = (await DBHelper.getParties('customer')).single;
    await DBHelper.completeSale(
      sale: {
        'total_amount': 20.0,
        'final_amount': 20.0,
        'discount': 0.0,
        'payment_type': 'Partial',
        'customer_type': 'Khata',
        'customer_id': androidCustomer['id'],
        'received_amount': 5.0,
        'date': '2026-11-22 11:00:00',
      },
      items: [
        {
          'barcode': 'KB-REV-1',
          'name': 'Revision Sugar',
          'quantity': 1,
          'salePrice': 20.0,
          'purchasePrice': 10.0,
        },
      ],
    );

    final initial = await DBHelper.exportDriveSnapshot();
    await useDatabase(windowsPath);
    expect(
      await DBHelper.mergeDriveSnapshot(
        envelope(initial, deviceId: 'android-device', hash: 'revision-initial'),
        sourceDeviceId: 'android-device',
        snapshotHash: 'revision-initial',
      ),
      isTrue,
    );
    final windowsSale = (await DBHelper.getSales()).single;
    final windowsCustomer = (await DBHelper.getParties('customer')).single;
    await DBHelper.updateSaleFromRecall(
      saleId: (windowsSale['id'] as num).toInt(),
      sale: {
        'customer_id': windowsCustomer['id'],
        'customer_type': 'Khata',
        'discount': 5.0,
        'received_amount': 5.0,
        'payment_type': 'Partial',
      },
      items: [
        {
          'barcode': 'KB-REV-1',
          'name': 'Revision Sugar',
          'quantity': 2,
          'salePrice': 25.0,
          'purchasePrice': 10.0,
          'stockUnit': 'pcs',
        },
      ],
    );

    final master = await DBHelper.exportDriveSnapshot();
    await useDatabase(androidPath);
    final masterEnvelope = envelope(master, deviceId: 'windows-master', hash: 'revision-master-1');
    expect(
      await DBHelper.mergeDriveSnapshot(
        masterEnvelope,
        sourceDeviceId: 'windows-master',
        snapshotHash: 'revision-master-1',
        applyMasterState: true,
        detectConflicts: false,
      ),
      isTrue,
    );

    final sale = (await DBHelper.getSales()).single;
    expect(sale['final_amount'], 45.0);
    expect(sale['balance_due'], 40.0);
    final items = await DBHelper.getSaleItems((sale['id'] as num).toInt());
    expect(items.length, 1);
    expect(items.single['quantity'], 2);
    expect(items.single['sale_price'], 25.0);
    expect((await DBHelper.getProducts()).single['quantity'], 7);
    final customer = (await DBHelper.getParties('customer')).single;
    expect(customer['balance'], 40.0);
    final ledger = await DBHelper.getKhataTransactions((customer['id'] as num).toInt());
    expect(ledger.length, 2);
    expect(ledger.where((row) => row['type'] == 'credit').single['amount'], 45.0);
    expect(ledger.where((row) => row['type'] == 'receipt').single['amount'], 5.0);

    await DBHelper.mergeDriveSnapshot(
      masterEnvelope,
      sourceDeviceId: 'windows-master',
      snapshotHash: 'revision-master-1',
      applyMasterState: true,
      detectConflicts: false,
    );
    expect((await DBHelper.getSaleItems((sale['id'] as num).toInt())).length, 1);
    expect((await DBHelper.getKhataTransactions((customer['id'] as num).toInt())).length, 2);
  });

  test('Khata cash and partial sales preserve customer type and post same-account receipts', () async {
    await DBHelper.insertProduct({
      'name': 'Wholesale Sugar',
      'barcode': 'KB-WH-100',
      'price': 22.0,
      'purchasePrice': 10.0,
      'wholesalePrice': 18.0,
      'damaged_quantity': 0,
      'quantity': 10,
      'is_active': 1,
      'stock_unit': 'pcs',
    });
    final customerId = await DBHelper.insertParty({
      'name': 'Khata Test Account',
      'phone': '03000000001',
      'type': 'customer',
      'customer_type': 'Khata',
      'balance': 0.0,
    });
    await DBHelper.updateCustomerType(customerId, 'Khata');

    await DBHelper.completeSale(
      sale: {
        'total_amount': 36.0,
        'final_amount': 36.0,
        'discount': 0.0,
        'payment_type': 'Partial',
        'customer_type': 'Khata',
        'customer_id': customerId,
        'received_amount': 10.0,
        'date': '2026-11-15 10:00:00',
      },
      items: [
        {
          'barcode': 'KB-WH-100',
          'name': 'Wholesale Sugar',
          'quantity': 2,
          'salePrice': 18.0,
          'purchasePrice': 10.0,
        },
      ],
    );

    await DBHelper.completeSale(
      sale: {
        'total_amount': 18.0,
        'final_amount': 18.0,
        'discount': 0.0,
        'payment_type': 'Cash',
        'customer_type': 'Khata',
        'customer_id': customerId,
        'received_amount': 18.0,
        'date': '2026-11-15 10:05:00',
      },
      items: [
        {
          'barcode': 'KB-WH-100',
          'name': 'Wholesale Sugar',
          'quantity': 1,
          'salePrice': 18.0,
          'purchasePrice': 10.0,
        },
      ],
    );

    final customer = (await DBHelper.getParties('customer')).single;
    expect(customer['customer_type'], 'Khata');
    expect(customer['balance'], 26.0);

    final sales = await DBHelper.getSales();
    expect(sales.length, 2);
    expect(sales.every((sale) => sale['customer_type'] == 'Khata'), isTrue);
    expect(sales.any((sale) => sale['payment_type'] == 'Partial' && sale['received_amount'] == 10.0), isTrue);
    expect(sales.any((sale) => sale['payment_type'] == 'Cash' && sale['received_amount'] == 18.0), isTrue);

    final ledger = await DBHelper.getKhataTransactions(customerId);
    expect(ledger.length, 4);
    expect(ledger.where((entry) => entry['type'] == 'credit').length, 2);
    expect(ledger.where((entry) => entry['type'] == 'receipt').length, 2);
    expect(
      ledger.where((entry) => entry['type'] == 'receipt')
          .fold<double>(0, (sum, entry) => sum + (entry['amount'] as num).toDouble()),
      28.0,
    );
    expect((await DBHelper.getProducts()).single['quantity'], 7);

    final snapshot = await DBHelper.exportDriveSnapshot();
    final syncedParty = (snapshot['parties'] as List)
        .cast<Map>()
        .singleWhere((party) => party['sync_id'] == customer['sync_id']);
    expect(syncedParty['customer_type'], 'Khata');

    await useDatabase(windowsPath);
    expect(
      await DBHelper.mergeDriveSnapshot(
        envelope(snapshot, deviceId: 'android-device', hash: 'wholesale-roundtrip'),
        sourceDeviceId: 'android-device',
        snapshotHash: 'wholesale-roundtrip',
        applyMasterState: true,
        detectConflicts: false,
      ),
      isTrue,
    );
    expect((await DBHelper.getParties('customer')).single['customer_type'], 'Khata');
    expect(
      (await DBHelper.getSales()).every((sale) => sale['customer_type'] == 'Khata'),
      isTrue,
    );
  });

  test('Retired Wholesale sale type is rejected and leaves stock unchanged', () async {
    await DBHelper.insertProduct({
      'name': 'Rate Check Item',
      'barcode': 'KB-WH-101',
      'price': 20.0,
      'purchasePrice': 10.0,
      'wholesalePrice': 16.0,
      'damaged_quantity': 0,
      'quantity': 5,
      'is_active': 1,
      'stock_unit': 'pcs',
    });
    final customerId = await DBHelper.insertParty({
      'name': 'Khata Only Account',
      'phone': '03000000002',
      'type': 'customer',
      'customer_type': 'Wholesale',
      'balance': 0.0,
    });

    await expectLater(
      DBHelper.completeSale(
        sale: {
          'total_amount': 16.0,
          'final_amount': 16.0,
          'discount': 0.0,
          'payment_type': 'Cash',
          'customer_type': 'Khata',
          'customer_id': customerId,
          'received_amount': 16.0,
          'date': '2026-11-15 10:10:00',
        },
        items: [
          {
            'barcode': 'KB-WH-101',
            'name': 'Rate Check Item',
            'quantity': 1,
            'salePrice': 16.0,
            'purchasePrice': 10.0,
          },
        ],
      ),
      throwsException,
    );
    expect((await DBHelper.getProducts()).single['quantity'], 5);
    expect((await DBHelper.getSales()), isEmpty);
  });

  test('zero-balance Khata with history is archived and non-zero balance is protected', () async {
    await DBHelper.insertProduct({
      'name': 'Archive Test Item',
      'barcode': 'KB-ARCHIVE-1',
      'price': 10.0,
      'purchasePrice': 5.0,
      'wholesalePrice': 0.0,
      'damaged_quantity': 0,
      'quantity': 5,
      'is_active': 1,
      'stock_unit': 'pcs',
    });
    final customerId = await DBHelper.insertParty({
      'name': 'Zero Balance Customer',
      'phone': '03000000003',
      'type': 'customer',
      'customer_type': 'Khata',
      'balance': 0.0,
    });
    await DBHelper.completeSale(
      sale: {
        'total_amount': 10.0,
        'final_amount': 10.0,
        'discount': 0.0,
        'payment_type': 'Cash',
        'customer_type': 'Khata',
        'customer_id': customerId,
        'received_amount': 10.0,
        'date': '2026-11-22 10:10:00',
      },
      items: [
        {
          'barcode': 'KB-ARCHIVE-1',
          'name': 'Archive Test Item',
          'quantity': 1,
          'salePrice': 10.0,
          'purchasePrice': 5.0,
        },
      ],
    );

    await DBHelper.deleteParty(customerId);
    expect(await DBHelper.getParties('customer'), isEmpty);
    final archived = await DBHelper.getParties('archived_customer');
    expect(archived.single['id'], customerId);

    final owingCustomerId = await DBHelper.insertParty({
      'name': 'Customer With Balance',
      'phone': '03000000004',
      'type': 'customer',
      'customer_type': 'Khata',
      'balance': 5.0,
    });
    await expectLater(DBHelper.deleteParty(owingCustomerId), throwsException);
    expect((await DBHelper.getParties('customer')).single['id'], owingCustomerId);
  });

  test('Drive-primary mode prevents new Firestore outbox writes', () async {
    DBHelper.localOnlyMode = false;
    DBHelper.drivePrimaryMode = true;
    await DBHelper.insertProduct({
      'name': 'Local Only Product',
      'barcode': 'LOCAL-ONLY-1',
      'price': 10.0,
      'purchasePrice': 5.0,
      'wholesalePrice': 0.0,
      'damaged_quantity': 0,
      'quantity': 1,
      'is_active': 1,
      'stock_unit': 'pcs',
    });
    await DBHelper.syncPendingChanges();
    expect(await DBHelper.getPendingSyncCount(), 0);
  });
  test('imports legacy schema-v1 snapshots without clearing a configured stock unit', () async {
    await DBHelper.insertProduct({
      'name': 'Legacy-compatible Tea',
      'barcode': 'KB-OLD-1',
      'price': 20.0,
      'purchasePrice': 10.0,
      'wholesalePrice': 18.0,
      'damaged_quantity': 0,
      'quantity': 12,
      'is_active': 1,
      'stock_unit': 'pcs',
    });
    final data = await DBHelper.exportDriveSnapshot();
    final oldProducts = (data['products'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map)..remove('stock_unit'))
        .toList();
    data['products'] = oldProducts;
    await DBHelper.mergeDriveSnapshot(
      {
        'schemaVersion': 1,
        'deviceId': 'old-android',
        'snapshotHash': 'legacy-v1',
        'data': data,
      },
      sourceDeviceId: 'old-android',
      snapshotHash: 'legacy-v1',
    );
    expect((await DBHelper.getProducts()).single['stock_unit'], 'pcs');
    expect(await DBHelper.getDriveSyncConflictCount(), 0);
  });



}
