import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:developer' as developer;
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class DBHelper {
  static Database? _db;
  // Windows portable mode runs locally without Firebase/cloud synchronization.
  static bool localOnlyMode = false;
  // Once Google Drive is paired, pause Android Firestore data sync so two cloud
  // providers cannot overwrite each other's inventory or account balances.
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _storeId = 'khan-baba-general-store';

  static CollectionReference<Map<String, dynamic>> _storeCollection(
    String name,
  ) {
    return _firestore.collection('stores').doc(_storeId).collection(name);
  }

  static bool _isPullingProducts = false;
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  static bool _isSyncingPending = false;
  static bool _syncPendingAgain = false;
  static bool _syncAllAgain = false;

  static void startAutoSync() {
    if (localOnlyMode || _connectivitySubscription != null) return;
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        unawaited(syncAllData());
      }
    });
    unawaited(() async {
      try {
        final results = await Connectivity().checkConnectivity();
        if (results.any((result) => result != ConnectivityResult.none)) {
          await syncAllData();
        }
      } catch (error) {
        developer.log('Connectivity check failed', name: 'DBHelper', error: error);
      }
    }());
  }

  static Future<void> stopAutoSync() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  static String _newSyncId() {
    final random = math.Random.secure();
    return '${DateTime.now().microsecondsSinceEpoch}_${random.nextInt(1 << 32)}';
  }

  static Future<void> _ensureColumn(
    DatabaseExecutor executor,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await executor.rawQuery('PRAGMA table_info($table)');
    if (!columns.any((row) => row['name'] == column)) {
      await executor.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  static double _numberAsDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static int _numberAsInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  // Legacy sales may have final_amount=0 because older app versions used
  // the column default. Reconstruct their net amount from the stored discount,
  // while preserving a genuine 100% discounted sale as zero.
  static double _effectiveSaleAmount(Map<String, dynamic> sale) {
    final total = _numberAsDouble(sale['total_amount']);
    final finalValue = sale['final_amount'];
    final finalAmount = _numberAsDouble(finalValue);
    if (finalValue != null && (finalAmount > 0 || total <= 0)) {
      return finalAmount;
    }
    final discount = _numberAsDouble(sale['discount']);
    if (discount > 0) {
      return (total - discount).clamp(0.0, double.infinity).toDouble();
    }
    return total;
  }

  static double _effectiveReceivedAmount(Map<String, dynamic> sale) {
    final received = _numberAsDouble(sale['received_amount']);
    if (received > 0) return received;
    if (sale['payment_type']?.toString() == 'Cash') {
      return _effectiveSaleAmount(sale);
    }
    return received;
  }

  static double _effectiveBalanceDue(Map<String, dynamic> sale) {
    final balance = _numberAsDouble(sale['balance_due']);
    if (balance > 0) return balance;
    final paymentType = sale['payment_type']?.toString() ?? 'Cash';
    if (paymentType == 'Khata' || paymentType == 'Partial') {
      return (_effectiveSaleAmount(sale) - _effectiveReceivedAmount(sale))
          .clamp(0.0, double.infinity)
          .toDouble();
    }
    return balance;
  }

  static bool _isSyncingAll = false;

  static Map<String, dynamic> _cloudRow(
    Map<String, dynamic> row, {
    List<String> remove = const [],
  }) {
    final payload = Map<String, dynamic>.from(row);
    payload.remove('id');
    for (final key in remove) {
      payload.remove(key);
    }
    payload['updated_at'] = DateTime.now().toIso8601String();
    return payload;
  }

  static Future<void> _queueRow(
    DatabaseExecutor txn,
    String collection,
    Map<String, dynamic> row, {
    List<String> remove = const [],
  }) async {
    final syncId = row['sync_id']?.toString();
    if (syncId == null || syncId.isEmpty) return;
    await _queueSync(
      txn,
      collection: collection,
      documentId: syncId,
      payload: _cloudRow(row, remove: remove),
    );
  }

  static Future<int?> _localIdBySyncId(
    DatabaseExecutor txn,
    String table,
    String syncId,
  ) async {
    final rows = await txn.query(
      table,
      columns: ['id'],
      where: 'sync_id = ?',
      whereArgs: [syncId],
      limit: 1,
    );
    return rows.isEmpty ? null : (rows.first['id'] as num).toInt();
  }

  static Future<void> _upsertSyncRecord(
    DatabaseExecutor txn,
    String table,
    String syncId,
    Map<String, dynamic> values,
  ) async {
    final existing = await txn.query(
      table,
      columns: ['id'],
      where: 'sync_id = ?',
      whereArgs: [syncId],
      limit: 1,
    );
    if (existing.isEmpty) {
      await txn.insert(table, {...values, 'sync_id': syncId});
    } else {
      await txn.update(
        table,
        values,
        where: 'sync_id = ?',
        whereArgs: [syncId],
      );
    }
  }

  static Future<Set<String>> _pendingIds(String collection) async {
    final db = await database;
    final rows = await db.query(
      'sync_queue',
      columns: ['document_id'],
      where: 'collection_name = ?',
      whereArgs: [collection],
    );
    return rows.map((row) => row['document_id'].toString()).toSet();
  }

  // Assign stable cloud IDs to data created before multi-device sync was added.
  // The first device that signs in uploads its existing local history; other
  // devices then download the same records without relying on SQLite row IDs.
  static Future<void> _ensureLegacySyncIds() async {
    final db = await database;
    await db.transaction((txn) async {
      final partyIds = <int, String>{};
      final partyRows = await txn.query('parties');
      for (final original in partyRows) {
        final row = Map<String, dynamic>.from(original);
        final localId = (row['id'] as num).toInt();
        final existingSyncId = row['sync_id']?.toString();
        final needsQueue = existingSyncId == null || existingSyncId.isEmpty;
        final syncId = needsQueue ? _newSyncId() : existingSyncId!;
        partyIds[localId] = syncId;
        if (needsQueue) {
          await txn.update('parties', {'sync_id': syncId}, where: 'id = ?', whereArgs: [localId]);
          row['sync_id'] = syncId;
          await _queueRow(txn, 'parties', row);
        }
      }

      final saleIds = <int, String>{};
      final saleRows = await txn.query('sales');
      for (final original in saleRows) {
        final row = Map<String, dynamic>.from(original);
        final localId = (row['id'] as num).toInt();
        final existingSyncId = row['sync_id']?.toString();
        final newId = existingSyncId == null || existingSyncId.isEmpty;
        final syncId = newId ? _newSyncId() : existingSyncId!;
        saleIds[localId] = syncId;
        final customerId = (row['customer_id'] as num?)?.toInt();
        final customerSyncId = customerId == null ? null : partyIds[customerId];
        final customerType = customerId == null ? 'Walk-in' : 'Khata';
        if (newId || row['customer_sync_id'] != customerSyncId ||
            row['customer_type'] != customerType) {
          await txn.update('sales', {
            'sync_id': syncId,
            'customer_sync_id': customerSyncId,
            'customer_type': customerType,
          }, where: 'id = ?', whereArgs: [localId]);
          row['sync_id'] = syncId;
          row['customer_sync_id'] = customerSyncId;
          row['customer_type'] = customerType;
          await _queueRow(txn, 'sales', row, remove: ['customer_id']);
        }
      }

      final saleItemIds = <int, String>{};
      final itemRows = await txn.query('sale_items');
      for (final original in itemRows) {
        final row = Map<String, dynamic>.from(original);
        final localId = (row['id'] as num).toInt();
        final existingSyncId = row['sync_id']?.toString();
        final newId = existingSyncId == null || existingSyncId.isEmpty;
        final syncId = newId ? _newSyncId() : existingSyncId!;
        saleItemIds[localId] = syncId;
        final saleId = (row['sale_id'] as num).toInt();
        final saleSyncId = saleIds[saleId];
        if (newId || row['sale_sync_id'] != saleSyncId) {
          await txn.update('sale_items', {
            'sync_id': syncId,
            'sale_sync_id': saleSyncId,
          }, where: 'id = ?', whereArgs: [localId]);
          row['sync_id'] = syncId;
          row['sale_sync_id'] = saleSyncId;
          await _queueRow(txn, 'sale_items', row, remove: ['sale_id', 'product_id']);
        }
      }

      final purchaseRows = await txn.query('purchases');
      for (final original in purchaseRows) {
        final row = Map<String, dynamic>.from(original);
        final localId = (row['id'] as num).toInt();
        final existingSyncId = row['sync_id']?.toString();
        final newId = existingSyncId == null || existingSyncId.isEmpty;
        final syncId = newId ? _newSyncId() : existingSyncId!;
        final supplierId = (row['supplier_id'] as num?)?.toInt();
        final supplierSyncId = supplierId == null ? null : partyIds[supplierId];
        if (newId || row['supplier_sync_id'] != supplierSyncId) {
          await txn.update('purchases', {
            'sync_id': syncId,
            'supplier_sync_id': supplierSyncId,
          }, where: 'id = ?', whereArgs: [localId]);
          row['sync_id'] = syncId;
          row['supplier_sync_id'] = supplierSyncId;
          await _queueRow(txn, 'purchases', row, remove: ['product_id', 'supplier_id']);
        }
      }

      final transactionRows = await txn.query('khata_transactions');
      for (final original in transactionRows) {
        final row = Map<String, dynamic>.from(original);
        final localId = (row['id'] as num).toInt();
        final existingSyncId = row['sync_id']?.toString();
        final newId = existingSyncId == null || existingSyncId.isEmpty;
        final syncId = newId ? _newSyncId() : existingSyncId!;
        final partyId = (row['party_id'] as num).toInt();
        final partySyncId = partyIds[partyId];
        if (newId || row['party_sync_id'] != partySyncId) {
          await txn.update('khata_transactions', {
            'sync_id': syncId,
            'party_sync_id': partySyncId,
          }, where: 'id = ?', whereArgs: [localId]);
          row['sync_id'] = syncId;
          row['party_sync_id'] = partySyncId;
          await _queueRow(txn, 'khata_transactions', row, remove: ['party_id']);
        }
      }

      for (final table in ['expenses', 'reminders']) {
        final rows = await txn.query(table);
        for (final original in rows) {
          final row = Map<String, dynamic>.from(original);
          final localId = (row['id'] as num).toInt();
          var syncId = row['sync_id']?.toString();
          if (syncId == null || syncId.isEmpty) {
            syncId = _newSyncId();
            await txn.update(table, {'sync_id': syncId}, where: 'id = ?', whereArgs: [localId]);
            row['sync_id'] = syncId;
            await _queueRow(txn, table, row);
          }
        }
      }

      final returnIds = <int, String>{};
      final returnRows = await txn.query('sale_returns');
      for (final original in returnRows) {
        final row = Map<String, dynamic>.from(original);
        final localId = (row['id'] as num).toInt();
        final existingSyncId = row['sync_id']?.toString();
        final newId = existingSyncId == null || existingSyncId.isEmpty;
        final syncId = newId ? _newSyncId() : existingSyncId!;
        returnIds[localId] = syncId;
        final saleId = (row['sale_id'] as num).toInt();
        final customerId = (row['customer_id'] as num?)?.toInt();
        final saleSyncId = saleIds[saleId];
        final partySyncId = customerId == null ? null : partyIds[customerId];
        if (newId || row['sale_sync_id'] != saleSyncId || row['party_sync_id'] != partySyncId) {
          await txn.update('sale_returns', {
            'sync_id': syncId,
            'sale_sync_id': saleSyncId,
            'party_sync_id': partySyncId,
          }, where: 'id = ?', whereArgs: [localId]);
          row['sync_id'] = syncId;
          row['sale_sync_id'] = saleSyncId;
          row['party_sync_id'] = partySyncId;
          await _queueRow(txn, 'sale_returns', row, remove: ['sale_id', 'customer_id']);
        }
      }

      final returnItemRows = await txn.query('sale_return_items');
      for (final original in returnItemRows) {
        final row = Map<String, dynamic>.from(original);
        final localId = (row['id'] as num).toInt();
        final existingSyncId = row['sync_id']?.toString();
        final newId = existingSyncId == null || existingSyncId.isEmpty;
        final syncId = newId ? _newSyncId() : existingSyncId!;
        final returnId = (row['return_id'] as num).toInt();
        final saleItemId = (row['sale_item_id'] as num).toInt();
        final returnSyncId = returnIds[returnId];
        final saleItemSyncId = saleItemIds[saleItemId];
        if (newId || row['return_sync_id'] != returnSyncId ||
            row['sale_item_sync_id'] != saleItemSyncId) {
          await txn.update('sale_return_items', {
            'sync_id': syncId,
            'return_sync_id': returnSyncId,
            'sale_item_sync_id': saleItemSyncId,
          }, where: 'id = ?', whereArgs: [localId]);
          row['sync_id'] = syncId;
          row['return_sync_id'] = returnSyncId;
          row['sale_item_sync_id'] = saleItemSyncId;
          await _queueRow(txn, 'sale_return_items', row, remove: ['return_id', 'sale_item_id', 'product_id']);
        }
      }
    });
  }

  static Future<void> _queueMissingProducts() async {
    final db = await database;
    final products = await db.query('products');
    final remote = await _storeCollection('products').get();
    final remoteBarcodes = remote.docs.map((doc) => doc.id).toSet();
    for (final product in products) {
      final barcode = product['barcode']?.toString() ?? '';
      if (barcode.isEmpty || remoteBarcodes.contains(barcode)) continue;
      final payload = Map<String, dynamic>.from(product)..remove('id');
      await db.transaction((txn) => _queueSync(
        txn,
        collection: 'products',
        documentId: barcode,
        payload: payload,
      ));
    }
  }

  static Future<void> _pullProductsFromCloud() async {
    final snapshot = await _storeCollection('products').get();
    final db = await database;
    final pending = await _pendingIds('products');
    await db.transaction((txn) async {
      for (final document in snapshot.docs) {
        final data = document.data();
        final barcode = (data['barcode'] ?? document.id).toString().trim();
        if (barcode.isEmpty || pending.contains(barcode)) continue;
        if (data['_deleted'] == true) {
          await txn.delete('products', where: 'barcode = ?', whereArgs: [barcode]);
          continue;
        }
        final name = (data['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final product = <String, dynamic>{
          'barcode': barcode,
          'name': name,
          'price': _numberAsDouble(data['price']),
          'purchasePrice': _numberAsDouble(data['purchasePrice']),
          'wholesalePrice': _numberAsDouble(data['wholesalePrice']),
          'damaged_quantity': _numberAsInt(data['damaged_quantity']),
          'quantity': _numberAsInt(data['quantity']),
        };
        final existing = await txn.query('products', columns: ['id'], where: 'barcode = ?', whereArgs: [barcode], limit: 1);
        if (existing.isEmpty) {
          await txn.insert('products', product);
        } else {
          await txn.update('products', product, where: 'barcode = ?', whereArgs: [barcode]);
        }
      }
    });
  }

  static Future<void> _pullParties() async {
    final snapshot = await _storeCollection('parties').get();
    final pending = await _pendingIds('parties');
    final db = await database;
    await db.transaction((txn) async {
      for (final doc in snapshot.docs) {
        if (pending.contains(doc.id)) continue;
        final data = doc.data();
        if (data['sync_id'] == null) continue;
        if (data['_deleted'] == true) {
          await txn.delete('parties', where: 'sync_id = ?', whereArgs: [doc.id]);
          continue;
        }
        final values = Map<String, dynamic>.from(data)
          ..remove('id')
          ..remove('_deleted')
          ..remove('updated_at')
          ..['sync_id'] = doc.id;
        values['customer_type'] = 'Khata';
        values['balance'] ??= 0.0;
        await _upsertSyncRecord(txn, 'parties', doc.id, values);
      }
    });
  }

  static Future<void> _pullSales() async {
    final snapshot = await _storeCollection('sales').get();
    final pending = await _pendingIds('sales');
    final db = await database;
    await db.transaction((txn) async {
      for (final doc in snapshot.docs) {
        if (pending.contains(doc.id)) continue;
        final data = doc.data();
        if (data['sync_id'] == null) continue;
        if (data['_deleted'] == true) {
          await txn.delete('sales', where: 'sync_id = ?', whereArgs: [doc.id]);
          continue;
        }
        final customerSyncId = data['customer_sync_id']?.toString();
        final customerId = customerSyncId == null
            ? null
            : await _localIdBySyncId(txn, 'parties', customerSyncId);
        if (customerSyncId != null && customerId == null) continue;
        final values = Map<String, dynamic>.from(data)
          ..remove('id')
          ..remove('customer_id')
          ..remove('_deleted')
          ..remove('updated_at')
          ..['sync_id'] = doc.id
          ..['customer_id'] = customerId;
        await _upsertSyncRecord(txn, 'sales', doc.id, values);
      }
    });
  }

  static Future<void> _pullSaleItems() async {
    final snapshot = await _storeCollection('sale_items').get();
    final pending = await _pendingIds('sale_items');
    final db = await database;
    await db.transaction((txn) async {
      for (final doc in snapshot.docs) {
        if (pending.contains(doc.id)) continue;
        final data = doc.data();
        if (data['sync_id'] == null) continue;
        if (data['_deleted'] == true) {
          await txn.delete('sale_items', where: 'sync_id = ?', whereArgs: [doc.id]);
          continue;
        }
        final saleSyncId = data['sale_sync_id']?.toString();
        final saleId = saleSyncId == null ? null : await _localIdBySyncId(txn, 'sales', saleSyncId);
        if (saleId == null) continue;
        final barcode = data['barcode']?.toString() ?? data['product_barcode']?.toString() ?? '';
        final productRows = barcode.isEmpty ? [] : await txn.query('products', columns: ['id'], where: 'barcode = ?', whereArgs: [barcode], limit: 1);
        final values = Map<String, dynamic>.from(data)
          ..remove('id')
          ..remove('sale_id')
          ..remove('product_id')
          ..remove('_deleted')
          ..remove('updated_at')
          ..['sync_id'] = doc.id
          ..['sale_id'] = saleId
          ..['product_id'] = productRows.isEmpty ? null : productRows.first['id'];
        await _upsertSyncRecord(txn, 'sale_items', doc.id, values);
      }
    });
  }

  static Future<void> _pullPurchases() async {
    final snapshot = await _storeCollection('purchases').get();
    final pending = await _pendingIds('purchases');
    final db = await database;
    await db.transaction((txn) async {
      for (final doc in snapshot.docs) {
        if (pending.contains(doc.id)) continue;
        final data = doc.data();
        if (data['sync_id'] == null) continue;
        if (data['_deleted'] == true) {
          await txn.delete('purchases', where: 'sync_id = ?', whereArgs: [doc.id]);
          continue;
        }
        final barcode = data['barcode']?.toString() ?? data['product_barcode']?.toString() ?? '';
        final productRows = barcode.isEmpty ? [] : await txn.query('products', columns: ['id'], where: 'barcode = ?', whereArgs: [barcode], limit: 1);
        final supplierSyncId = data['supplier_sync_id']?.toString();
        final supplierId = supplierSyncId == null ? null : await _localIdBySyncId(txn, 'parties', supplierSyncId);
        final values = Map<String, dynamic>.from(data)
          ..remove('id')
          ..remove('product_id')
          ..remove('supplier_id')
          ..remove('_deleted')
          ..remove('updated_at')
          ..['sync_id'] = doc.id
          ..['product_id'] = productRows.isEmpty ? 0 : productRows.first['id']
          ..['supplier_id'] = supplierId;
        await _upsertSyncRecord(txn, 'purchases', doc.id, values);
      }
    });
  }

  static Future<void> _pullKhataTransactions() async {
    final snapshot = await _storeCollection('khata_transactions').get();
    final pending = await _pendingIds('khata_transactions');
    final db = await database;
    await db.transaction((txn) async {
      for (final doc in snapshot.docs) {
        if (pending.contains(doc.id)) continue;
        final data = doc.data();
        if (data['sync_id'] == null) continue;
        if (data['_deleted'] == true) {
          await txn.delete('khata_transactions', where: 'sync_id = ?', whereArgs: [doc.id]);
          continue;
        }
        final partySyncId = data['party_sync_id']?.toString();
        final partyId = partySyncId == null ? null : await _localIdBySyncId(txn, 'parties', partySyncId);
        if (partyId == null) continue;
        final values = Map<String, dynamic>.from(data)
          ..remove('id')
          ..remove('party_id')
          ..remove('_deleted')
          ..remove('updated_at')
          ..['sync_id'] = doc.id
          ..['party_id'] = partyId;
        await _upsertSyncRecord(txn, 'khata_transactions', doc.id, values);
      }
    });
  }

  static Future<void> _pullSimpleCollection(String collection, String table) async {
    final snapshot = await _storeCollection(collection).get();
    final pending = await _pendingIds(collection);
    final db = await database;
    await db.transaction((txn) async {
      for (final doc in snapshot.docs) {
        if (pending.contains(doc.id)) continue;
        final data = doc.data();
        if (data['sync_id'] == null) continue;
        if (data['_deleted'] == true) {
          await txn.delete(table, where: 'sync_id = ?', whereArgs: [doc.id]);
          continue;
        }
        final values = Map<String, dynamic>.from(data)
          ..remove('id')
          ..remove('_deleted')
          ..remove('updated_at')
          ..['sync_id'] = doc.id;
        await _upsertSyncRecord(txn, table, doc.id, values);
      }
    });
  }

  static Future<void> _pullReturns() async {
    final snapshot = await _storeCollection('sale_returns').get();
    final pending = await _pendingIds('sale_returns');
    final db = await database;
    await db.transaction((txn) async {
      for (final doc in snapshot.docs) {
        if (pending.contains(doc.id)) continue;
        final data = doc.data();
        if (data['sync_id'] == null) continue;
        if (data['_deleted'] == true) {
          await txn.delete('sale_returns', where: 'sync_id = ?', whereArgs: [doc.id]);
          continue;
        }
        final saleSyncId = data['sale_sync_id']?.toString();
        final saleId = saleSyncId == null ? null : await _localIdBySyncId(txn, 'sales', saleSyncId);
        if (saleId == null) continue;
        final partySyncId = data['party_sync_id']?.toString();
        final customerId = partySyncId == null ? null : await _localIdBySyncId(txn, 'parties', partySyncId);
        final values = Map<String, dynamic>.from(data)
          ..remove('id')
          ..remove('sale_id')
          ..remove('customer_id')
          ..remove('_deleted')
          ..remove('updated_at')
          ..['sync_id'] = doc.id
          ..['sale_id'] = saleId
          ..['customer_id'] = customerId;
        await _upsertSyncRecord(txn, 'sale_returns', doc.id, values);
      }
    });
  }

  static Future<void> _pullReturnItems() async {
    final snapshot = await _storeCollection('sale_return_items').get();
    final pending = await _pendingIds('sale_return_items');
    final db = await database;
    await db.transaction((txn) async {
      for (final doc in snapshot.docs) {
        if (pending.contains(doc.id)) continue;
        final data = doc.data();
        if (data['sync_id'] == null) continue;
        if (data['_deleted'] == true) {
          await txn.delete('sale_return_items', where: 'sync_id = ?', whereArgs: [doc.id]);
          continue;
        }
        final returnSyncId = data['return_sync_id']?.toString();
        final returnId = returnSyncId == null ? null : await _localIdBySyncId(txn, 'sale_returns', returnSyncId);
        final saleItemSyncId = data['sale_item_sync_id']?.toString();
        final saleItemId = saleItemSyncId == null ? null : await _localIdBySyncId(txn, 'sale_items', saleItemSyncId);
        if (returnId == null || saleItemId == null) continue;
        final barcode = data['barcode']?.toString() ?? data['product_barcode']?.toString() ?? '';
        final productRows = barcode.isEmpty ? [] : await txn.query('products', columns: ['id'], where: 'barcode = ?', whereArgs: [barcode], limit: 1);
        final values = Map<String, dynamic>.from(data)
          ..remove('id')
          ..remove('return_id')
          ..remove('sale_item_id')
          ..remove('product_id')
          ..remove('_deleted')
          ..remove('updated_at')
          ..['sync_id'] = doc.id
          ..['return_id'] = returnId
          ..['sale_item_id'] = saleItemId
          ..['product_id'] = productRows.isEmpty ? null : productRows.first['id'];
        await _upsertSyncRecord(txn, 'sale_return_items', doc.id, values);
      }
    });
  }

  static Future<void> syncAllData() async {
    if (localOnlyMode) return;
    if (_isSyncingAll) {
      _syncAllAgain = true;
      return;
    }
    _isSyncingAll = true;
    try {
      await _ensureLegacySyncIds();
      await _queueMissingProducts();
      for (var i = 0; i < 5; i++) {
        final before = await getPendingSyncCount();
        if (before == 0) break;
        await syncPendingChanges(batchSize: 100);
        final after = await getPendingSyncCount();
        if (after >= before) break;
      }
      await _pullProductsFromCloud();
      await _pullParties();
      await _pullSales();
      await _pullSaleItems();
      await _pullPurchases();
      await _pullKhataTransactions();
      await _pullSimpleCollection('expenses', 'expenses');
      await _pullSimpleCollection('reminders', 'reminders');
      await _pullReturns();
      await _pullReturnItems();
    } catch (e) {
      developer.log('Firebase Full Sync Error', name: 'DBHelper', error: e);
    } finally {
      _isSyncingAll = false;
      if (_syncAllAgain) {
        _syncAllAgain = false;
        unawaited(syncAllData());
      }
    }
  }

  static Future<void> syncProductsFromCloud() => syncAllData();


  static Future<void> _recordDriveTombstone(
    DatabaseExecutor txn,
    String entityType,
    String entityKey, {
    String sourceDeviceId = 'local',
  }) async {
    await txn.insert(
      'drive_sync_tombstones',
      {
        'entity_type': entityType,
        'entity_key': entityKey,
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'source_device_id': sourceDeviceId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await txn.delete(
      'drive_sync_ignored_tombstones',
      where: 'entity_type = ? AND entity_key = ?',
      whereArgs: [entityType, entityKey],
    );
  }

  /// Export relational data without SQLite row IDs. Cloud references use stable sync IDs.
  static Future<Map<String, dynamic>> exportDriveSnapshot() async {
    await _ensureLegacySyncIds();
    final db = await database;
    Future<List<Map<String, dynamic>>> rows(
      String table, {
      List<String> remove = const ['id'],
    }) async {
      final result = await db.query(table, orderBy: 'id ASC');
      return result.map((row) {
        final value = Map<String, dynamic>.from(row);
        for (final key in remove) {
          value.remove(key);
        }
        return value;
      }).toList();
    }

    return {
      'schemaVersion': 1,
      'products': await rows('products'),
      'parties': await rows('parties'),
      'sales': await rows('sales', remove: const ['id', 'customer_id']),
      'sale_items': await rows('sale_items', remove: const ['id', 'sale_id', 'product_id']),
      'purchases': await rows('purchases', remove: const ['id', 'product_id', 'supplier_id']),
      'khata_transactions': await rows('khata_transactions', remove: const ['id', 'party_id']),
      'expenses': await rows('expenses'),
      'reminders': await rows('reminders'),
      'sale_returns': await rows('sale_returns', remove: const ['id', 'sale_id', 'customer_id']),
      'sale_return_items': await rows('sale_return_items', remove: const ['id', 'return_id', 'sale_item_id', 'product_id']),
      'tombstones': await rows('drive_sync_tombstones'),
    };
  }

  static Future<List<Map<String, dynamic>>> getDriveSyncConflicts() async {
    final db = await database;
    return db.query(
      'drive_sync_conflicts',
      where: "status = 'pending'",
      orderBy: 'created_at ASC',
    );
  }

  static Future<int> getDriveSyncConflictCount() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS total FROM drive_sync_conflicts WHERE status = 'pending'",
    );
    return (result.first['total'] as num?)?.toInt() ?? 0;
  }

  static Future<void> resolveDriveSyncConflict(
    int conflictId, {
    required bool useRemote,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'drive_sync_conflicts',
        where: "id = ? AND status = 'pending'",
        whereArgs: [conflictId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final conflict = rows.first;
      final remote = jsonDecode(conflict['remote_payload'].toString());
      if (remote is! Map) throw const FormatException('Invalid cloud conflict payload.');
      final payload = Map<String, dynamic>.from(remote);
      final entityType = conflict['entity_type'].toString();
      final sourceDeviceId = conflict['source_device_id'].toString();
      if (entityType == 'product_readd' || entityType == 'party_readd') {
        final baseType = entityType == 'product_readd' ? 'product_readd' : 'party_readd';
        final remoteKey = entityType == 'product_readd'
            ? (payload['barcode'] ?? conflict['entity_key']).toString()
            : (payload['sync_id'] ?? conflict['entity_key']).toString();
        if (!useRemote && payload['_has_related_records'] == true) {
          throw Exception('Doosre device par is record se linked transactions mojood hain. History bachane ke liye record restore karna zaroori hai.');
        }
        if (useRemote) {
          if (entityType == 'product_readd') {
            final values = <String, dynamic>{
              'name': payload['name']?.toString() ?? '',
              'barcode': remoteKey,
              'price': _numberAsDouble(payload['price']),
              'purchasePrice': _numberAsDouble(payload['purchasePrice']),
              'wholesalePrice': _numberAsDouble(payload['wholesalePrice']),
              'quantity': _numberAsInt(payload['quantity']),
              'damaged_quantity': _numberAsInt(payload['damaged_quantity']),
              'is_active': _numberAsInt(payload['is_active'] ?? 1),
            };
            await txn.insert('products', values, conflictAlgorithm: ConflictAlgorithm.replace);
            await txn.delete('drive_sync_tombstones', where: 'entity_type = ? AND entity_key = ?', whereArgs: ['product', remoteKey]);
          } else {
            final values = Map<String, dynamic>.from(payload)
              ..remove('id')
              ..remove('_has_related_records')
              ..['sync_id'] = remoteKey
              ..['balance'] = _numberAsDouble(payload['balance']);
            await txn.insert('parties', values, conflictAlgorithm: ConflictAlgorithm.replace);
            await txn.delete('drive_sync_tombstones', where: 'entity_type = ? AND entity_key = ?', whereArgs: ['party', remoteKey]);
            final aliases = await txn.query(
              'drive_sync_aliases',
              columns: ['local_sync_id'],
              where: 'source_device_id = ? AND remote_sync_id = ?',
              whereArgs: [sourceDeviceId, remoteKey],
            );
            for (final alias in aliases) {
              await txn.delete(
                'drive_sync_tombstones',
                where: 'entity_type = ? AND entity_key = ?',
                whereArgs: ['party', alias['local_sync_id']],
              );
            }
          }
          await txn.delete(
            'drive_sync_ignored_tombstones',
            where: 'source_device_id = ? AND entity_type = ? AND entity_key = ?',
            whereArgs: [sourceDeviceId, baseType, remoteKey],
          );
        } else {
          await txn.insert(
            'drive_sync_ignored_tombstones',
            {
              'source_device_id': sourceDeviceId,
              'entity_type': baseType,
              'entity_key': remoteKey,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      } else if (entityType == 'product_delete' || entityType == 'party_delete') {
        final baseType = entityType == 'product_delete' ? 'product' : 'party';
        final remoteKey = entityType == 'product_delete'
            ? (payload['barcode'] ?? conflict['entity_key']).toString()
            : (payload['sync_id'] ?? conflict['entity_key']).toString();
        if (useRemote) {
          if (entityType == 'product_delete') {
            final barcode = remoteKey;
            final productRows = await txn.query('products', where: 'barcode = ?', whereArgs: [barcode], limit: 1);
            if (productRows.isNotEmpty) {
              final product = productRows.first;
              final stock = _numberAsInt(product['quantity']);
              final damaged = _numberAsInt(product['damaged_quantity']);
              final sales = await txn.rawQuery('SELECT COUNT(*) AS total FROM sale_items WHERE barcode = ?', [barcode]);
              final purchases = await txn.rawQuery('SELECT COUNT(*) AS total FROM purchases WHERE barcode = ?', [barcode]);
              if (stock != 0 || damaged != 0 ||
                  (sales.first['total'] as num).toInt() > 0 ||
                  (purchases.first['total'] as num).toInt() > 0) {
                throw Exception('Is product par stock ya transaction history mojood hai. Pehle Windows master ko preserve karein.');
              }
              await txn.delete('products', where: 'barcode = ?', whereArgs: [barcode]);
            }
            await _recordDriveTombstone(txn, 'product', barcode, sourceDeviceId: sourceDeviceId);
          } else {
            final localSyncId = conflict['entity_key'].toString();
            final partyRows = await txn.query('parties', where: 'sync_id = ?', whereArgs: [localSyncId], limit: 1);
            if (partyRows.isNotEmpty) {
              final partyId = (partyRows.first['id'] as num).toInt();
              final refs = await txn.rawQuery(
                '''SELECT (SELECT COUNT(*) FROM sales WHERE customer_id = ?) +
                          (SELECT COUNT(*) FROM khata_transactions WHERE party_id = ?) +
                          (SELECT COUNT(*) FROM purchases WHERE supplier_id = ?) +
                          (SELECT COUNT(*) FROM sale_returns WHERE customer_id = ?) AS total''',
                [partyId, partyId, partyId, partyId],
              );
              final balance = _numberAsDouble(partyRows.first['balance']);
              if ((refs.first['total'] as num).toInt() > 0 || balance.abs() > 0.000001) {
                throw Exception('Is party ki transaction history ya outstanding balance mojood hai. Windows master record preserve karein.');
              }
              await txn.delete('parties', where: 'id = ?', whereArgs: [partyId]);
            }
            await _recordDriveTombstone(txn, 'party', localSyncId, sourceDeviceId: sourceDeviceId);
            if (remoteKey != localSyncId) {
              await _recordDriveTombstone(txn, 'party', remoteKey, sourceDeviceId: sourceDeviceId);
            }
          }
        } else {
          await txn.insert(
            'drive_sync_ignored_tombstones',
            {
              'source_device_id': sourceDeviceId,
              'entity_type': baseType,
              'entity_key': remoteKey,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      } else if (useRemote) {
        if (entityType == 'product') {
          final barcode = conflict['entity_key'].toString();
          final values = <String, dynamic>{
            'name': payload['name'],
            'price': _numberAsDouble(payload['price']),
            'purchasePrice': _numberAsDouble(payload['purchasePrice']),
            'wholesalePrice': _numberAsDouble(payload['wholesalePrice']),
            'quantity': _numberAsInt(payload['quantity']),
            'damaged_quantity': _numberAsInt(payload['damaged_quantity']),
            'is_active': _numberAsInt(payload['is_active'] ?? 1),
          };
          await txn.update('products', values, where: 'barcode = ?', whereArgs: [barcode]);
        } else if (entityType == 'party') {
          final localSyncId = conflict['entity_key'].toString();
          final values = Map<String, dynamic>.from(payload)
            ..remove('sync_id')
            ..remove('updated_at');
          await txn.update('parties', values, where: 'sync_id = ?', whereArgs: [localSyncId]);
        }
      }
      await txn.update(
        'drive_sync_conflicts',
        {
          'status': 'resolved',
          'resolution': useRemote ? 'use_remote' : 'keep_local',
          'resolved_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [conflictId],
      );
    });
  }

  static Future<bool> mergeDriveSnapshot(
    Map<String, dynamic> snapshot, {
    required String sourceDeviceId,
    required String snapshotHash,
    bool applyMasterState = false,
    bool detectConflicts = true,
  }) async {
    final data = snapshot['data'];
    if (snapshot['schemaVersion'] != 1 || data is! Map) {
      throw const FormatException('Cloud snapshot version or data is invalid.');
    }
    const requiredCollections = [
      'products',
      'parties',
      'sales',
      'sale_items',
      'purchases',
      'khata_transactions',
      'expenses',
      'reminders',
      'sale_returns',
      'sale_return_items',
      'tombstones',
    ];
    for (final name in requiredCollections) {
      if (data[name] is! List) {
        throw FormatException('Cloud snapshot collection is missing: $name');
      }
    }
    final db = await database;
    Future<void> addConflict(
      DatabaseExecutor txn, {
      required String type,
      required String key,
      required Map<String, dynamic> local,
      required Map<String, dynamic> remote,
    }) async {
      final existing = await txn.query(
        'drive_sync_conflicts',
        columns: ['status'],
        where: 'source_device_id = ? AND snapshot_hash = ? AND entity_type = ? AND entity_key = ?',
        whereArgs: [sourceDeviceId, snapshotHash, type, key],
        limit: 1,
      );
      if (existing.isNotEmpty && existing.first['status'] == 'resolved') return;
      final priorKeepLocal = await txn.query(
        'drive_sync_conflicts',
        columns: ['remote_payload'],
        where: "source_device_id = ? AND entity_type = ? AND entity_key = ? AND status = 'resolved' AND resolution = 'keep_local'",
        whereArgs: [sourceDeviceId, type, key],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (priorKeepLocal.isNotEmpty &&
          priorKeepLocal.first['remote_payload']?.toString() == jsonEncode(remote)) {
        return;
      }
      await txn.insert(
        'drive_sync_conflicts',
        {
          'source_device_id': sourceDeviceId,
          'snapshot_hash': snapshotHash,
          'entity_type': type,
          'entity_key': key,
          'local_payload': jsonEncode(local),
          'remote_payload': jsonEncode(remote),
          'status': 'pending',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    List<Map<String, dynamic>> collection(String name) {
      final value = data[name];
      if (value is! List) return [];
      return value.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
    }

    await db.transaction((txn) async {
      await txn.update(
        'drive_sync_conflicts',
        {'status': 'superseded'},
        where: "source_device_id = ? AND snapshot_hash != ? AND status = 'pending'",
        whereArgs: [sourceDeviceId, snapshotHash],
      );
      // Products use barcode as their stable identity. The Windows master never
      // silently replaces stock or pricing with a remote device's snapshot.
      for (final remote in collection('products')) {
        final barcode = remote['barcode']?.toString().trim() ?? '';
        if (barcode.isEmpty) continue;
        final deletedLocally = await txn.query(
          'drive_sync_tombstones',
          columns: ['entity_key'],
          where: 'entity_type = ? AND entity_key = ?',
          whereArgs: ['product', barcode],
          limit: 1,
        );
        if (deletedLocally.isNotEmpty && !applyMasterState) {
          final ignoredReadd = await txn.query(
            'drive_sync_ignored_tombstones',
            columns: ['entity_key'],
            where: 'source_device_id = ? AND entity_type = ? AND entity_key = ?',
            whereArgs: [sourceDeviceId, 'product_readd', barcode],
            limit: 1,
          );
          if (ignoredReadd.isEmpty && detectConflicts) {
            await addConflict(
              txn,
              type: 'product_readd',
              key: barcode,
              local: {'_deleted': true, 'barcode': barcode},
              remote: {
                'name': remote['name']?.toString() ?? '',
                'barcode': barcode,
                'price': _numberAsDouble(remote['price']),
                'purchasePrice': _numberAsDouble(remote['purchasePrice']),
                'wholesalePrice': _numberAsDouble(remote['wholesalePrice']),
                'damaged_quantity': _numberAsInt(remote['damaged_quantity']),
                'quantity': _numberAsInt(remote['quantity']),
                'is_active': _numberAsInt(remote['is_active'] ?? 1),
                '_has_related_records': collection('sale_items').any((item) => item['barcode']?.toString() == barcode) ||
                    collection('purchases').any((item) => item['barcode']?.toString() == barcode),
              },
            );
          }
          continue;
        }
        await txn.delete('drive_sync_tombstones', where: 'entity_type = ? AND entity_key = ?', whereArgs: ['product', barcode]);
        await txn.delete('drive_sync_ignored_tombstones', where: 'entity_type = ? AND entity_key = ?', whereArgs: ['product', barcode]);
        final existing = await txn.query('products', where: 'barcode = ?', whereArgs: [barcode], limit: 1);
        final values = <String, dynamic>{
          'name': remote['name']?.toString() ?? '',
          'barcode': barcode,
          'price': _numberAsDouble(remote['price']),
          'purchasePrice': _numberAsDouble(remote['purchasePrice']),
          'wholesalePrice': _numberAsDouble(remote['wholesalePrice']),
          'damaged_quantity': _numberAsInt(remote['damaged_quantity']),
          'quantity': _numberAsInt(remote['quantity']),
          'is_active': _numberAsInt(remote['is_active'] ?? 1),
        };
        if (existing.isEmpty) {
          await txn.insert('products', values);
        } else if (applyMasterState) {
          await txn.update('products', values, where: 'barcode = ?', whereArgs: [barcode]);
        } else {
          final local = existing.first;
          final different = ['name', 'price', 'purchasePrice', 'wholesalePrice', 'damaged_quantity', 'quantity', 'is_active']
              .any((key) => (local[key] ?? 0).toString() != (values[key] ?? 0).toString());
          if (different && detectConflicts) {
            await addConflict(
              txn,
              type: 'product',
              key: barcode,
              local: Map<String, dynamic>.from(local)..remove('id'),
              remote: values,
            );
          }
        }
      }

      final partyIds = <String, int>{};
      for (final remote in collection('parties')) {
        final syncId = remote['sync_id']?.toString() ?? '';
        if (syncId.isEmpty) continue;
        var deletedPartyKeys = <String>[syncId];
        final previousAlias = await txn.query(
          'drive_sync_aliases',
          columns: ['local_sync_id'],
          where: 'source_device_id = ? AND remote_sync_id = ?',
          whereArgs: [sourceDeviceId, syncId],
          limit: 1,
        );
        if (previousAlias.isNotEmpty) deletedPartyKeys.add(previousAlias.first['local_sync_id'].toString());
        var deletedPartyRows = <Map<String, Object?>>[];
        for (final deletedKey in deletedPartyKeys) {
          deletedPartyRows = await txn.query(
            'drive_sync_tombstones',
            columns: ['entity_key'],
            where: 'entity_type = ? AND entity_key = ?',
            whereArgs: ['party', deletedKey],
            limit: 1,
          );
          if (deletedPartyRows.isNotEmpty) break;
        }
        if (deletedPartyRows.isNotEmpty && !applyMasterState) {
          final ignoredReadd = await txn.query(
            'drive_sync_ignored_tombstones',
            columns: ['entity_key'],
            where: 'source_device_id = ? AND entity_type = ? AND entity_key = ?',
            whereArgs: [sourceDeviceId, 'party_readd', syncId],
            limit: 1,
          );
          if (ignoredReadd.isEmpty && detectConflicts) {
            final remotePartyPayload = Map<String, dynamic>.from(remote)..remove('id');
            remotePartyPayload['_has_related_records'] =
                collection('sales').any((sale) => sale['customer_sync_id']?.toString() == syncId) ||
                collection('khata_transactions').any((entry) => entry['party_sync_id']?.toString() == syncId) ||
                collection('purchases').any((purchase) => purchase['supplier_sync_id']?.toString() == syncId) ||
                collection('sale_returns').any((saleReturn) => saleReturn['party_sync_id']?.toString() == syncId);
            await addConflict(
              txn,
              type: 'party_readd',
              key: syncId,
              local: {'_deleted': true, 'sync_id': syncId},
              remote: remotePartyPayload,
            );
          }
          continue;
        }
        await txn.delete(
          'drive_sync_tombstones',
          where: 'entity_type = ? AND entity_key IN (?, ?)',
          whereArgs: ['party', syncId, deletedPartyKeys.last],
        );
        var localRows = await txn.query('parties', where: 'sync_id = ?', whereArgs: [syncId], limit: 1);
        if (localRows.isEmpty) {
          final alias = await txn.query(
            'drive_sync_aliases',
            columns: ['local_sync_id'],
            where: 'source_device_id = ? AND remote_sync_id = ?',
            whereArgs: [sourceDeviceId, syncId],
            limit: 1,
          );
          if (alias.isNotEmpty) {
            localRows = await txn.query('parties', where: 'sync_id = ?', whereArgs: [alias.first['local_sync_id']], limit: 1);
          }
        }
        if (localRows.isEmpty) {
          final name = (remote['name'] ?? '').toString().trim().toLowerCase();
          final phone = (remote['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
          final matches = await txn.query('parties');
          final exact = phone.isEmpty ? <Map<String, Object?>>[] : matches.where((row) =>
            (row['name'] ?? '').toString().trim().toLowerCase() == name &&
            (row['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '') == phone &&
            row['type'] == remote['type']).toList();
          if (exact.length == 1) localRows = [exact.first];
        }
        if (localRows.isEmpty) {
          final values = Map<String, dynamic>.from(remote)
            ..remove('id')
            ..['sync_id'] = syncId
            ..['customer_type'] = remote['customer_type'] ?? 'Khata'
            ..['balance'] = _numberAsDouble(remote['balance']);
          final id = await txn.insert('parties', values);
          partyIds[syncId] = id;
          await txn.delete('drive_sync_tombstones', where: 'entity_type = ? AND entity_key = ?', whereArgs: ['party', syncId]);
          await txn.delete('drive_sync_ignored_tombstones', where: 'source_device_id = ? AND entity_type = ? AND entity_key = ?', whereArgs: [sourceDeviceId, 'party', syncId]);
          continue;
        }
        final local = localRows.first;
        final localId = (local['id'] as num).toInt();
        final localSyncId = local['sync_id']?.toString() ?? syncId;
        partyIds[syncId] = localId;
        await txn.delete('drive_sync_tombstones', where: 'entity_type = ? AND entity_key IN (?, ?)', whereArgs: ['party', syncId, localSyncId]);
        final oldAliases = await txn.query(
          'drive_sync_aliases',
          columns: ['remote_sync_id'],
          where: 'source_device_id = ? AND local_sync_id = ?',
          whereArgs: [sourceDeviceId, localSyncId],
        );
        for (final oldAlias in oldAliases) {
          await txn.delete(
            'drive_sync_tombstones',
            where: 'entity_type = ? AND entity_key = ?',
            whereArgs: ['party', oldAlias['remote_sync_id']],
          );
        }
        await txn.delete('drive_sync_ignored_tombstones', where: 'source_device_id = ? AND entity_type = ? AND entity_key = ?', whereArgs: [sourceDeviceId, 'party', syncId]);
        if (localSyncId != syncId) {
          await txn.insert(
            'drive_sync_aliases',
            {
              'source_device_id': sourceDeviceId,
              'remote_sync_id': syncId,
              'local_sync_id': localSyncId,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        final remoteBalance = _numberAsDouble(remote['balance']);
        final localBalance = _numberAsDouble(local['balance']);
        final fieldsDiffer = local['name'] != remote['name'] ||
            local['phone'] != remote['phone'] ||
            local['type'] != remote['type'] ||
            local['customer_type'] != (remote['customer_type'] ?? 'Khata') ||
            localBalance != remoteBalance;
        if (applyMasterState) {
          await txn.update(
            'parties',
            {
              'name': remote['name'],
              'phone': remote['phone'],
              'type': remote['type'],
              'customer_type': remote['customer_type'] ?? 'Khata',
              'balance': remoteBalance,
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
        } else if (fieldsDiffer && detectConflicts) {
          await addConflict(
            txn,
            type: 'party',
            key: localSyncId,
            local: Map<String, dynamic>.from(local)..remove('id'),
            remote: {
              'name': remote['name'],
              'phone': remote['phone'],
              'type': remote['type'],
              'customer_type': remote['customer_type'] ?? 'Khata',
              'balance': remoteBalance,
            },
          );
        }
      }

      Future<int?> partyIdFor(String? syncId) async {
        if (syncId == null || syncId.isEmpty) return null;
        if (partyIds.containsKey(syncId)) return partyIds[syncId];
        final direct = await _localIdBySyncId(txn, 'parties', syncId);
        if (direct != null) return direct;
        final alias = await txn.query(
          'drive_sync_aliases',
          columns: ['local_sync_id'],
          where: 'source_device_id = ? AND remote_sync_id = ?',
          whereArgs: [sourceDeviceId, syncId],
          limit: 1,
        );
        if (alias.isEmpty) return null;
        return _localIdBySyncId(txn, 'parties', alias.first['local_sync_id'].toString());
      }

      Future<int?> localBySync(String table, String? syncId) async {
        if (syncId == null || syncId.isEmpty) return null;
        return _localIdBySyncId(txn, table, syncId);
      }

      Future<String?> canonicalPartySyncId(String? remoteSyncId) async {
        final id = await partyIdFor(remoteSyncId);
        if (id == null) return null;
        final rows = await txn.query('parties', columns: ['sync_id'], where: 'id = ?', whereArgs: [id], limit: 1);
        return rows.isEmpty ? null : rows.first['sync_id']?.toString();
      }

      Future<int?> productIdFor(String? barcode) async {
        if (barcode == null || barcode.isEmpty) return null;
        final rows = await txn.query('products', columns: ['id'], where: 'barcode = ?', whereArgs: [barcode], limit: 1);
        return rows.isEmpty ? null : (rows.first['id'] as num).toInt();
      }

      // Append-only business records are imported by stable sync ID and never
      // replace an existing sale, purchase, receipt, or return.
      for (final remote in collection('sales')) {
        final syncId = remote['sync_id']?.toString() ?? '';
        if (syncId.isEmpty || await localBySync('sales', syncId) != null) continue;
        final customerSyncId = remote['customer_sync_id']?.toString();
        final customerId = await partyIdFor(customerSyncId);
        if (customerSyncId != null && customerId == null) continue;
        final canonicalCustomerSyncId = await canonicalPartySyncId(customerSyncId);
        final values = Map<String, dynamic>.from(remote)
          ..remove('id')
          ..remove('customer_id')
          ..['sync_id'] = syncId
          ..['customer_sync_id'] = canonicalCustomerSyncId
          ..['customer_id'] = customerId;
        await txn.insert('sales', values);
      }

      for (final remote in collection('sale_items')) {
        final syncId = remote['sync_id']?.toString() ?? '';
        if (syncId.isEmpty || await localBySync('sale_items', syncId) != null) continue;
        final saleId = await localBySync('sales', remote['sale_sync_id']?.toString());
        if (saleId == null) continue;
        final productId = await productIdFor(remote['barcode']?.toString());
        final values = Map<String, dynamic>.from(remote)
          ..remove('id')
          ..remove('sale_id')
          ..remove('product_id')
          ..['sale_id'] = saleId
          ..['product_id'] = productId
          ..['sync_id'] = syncId;
        await txn.insert('sale_items', values);
      }

      for (final remote in collection('purchases')) {
        final syncId = remote['sync_id']?.toString() ?? '';
        if (syncId.isEmpty || await localBySync('purchases', syncId) != null) continue;
        final productId = await productIdFor(remote['barcode']?.toString());
        if (productId == null) continue;
        final remoteSupplierSyncId = remote['supplier_sync_id']?.toString();
        final supplierId = await partyIdFor(remoteSupplierSyncId);
        final canonicalSupplierSyncId = await canonicalPartySyncId(remoteSupplierSyncId);
        final values = Map<String, dynamic>.from(remote)
          ..remove('id')
          ..remove('product_id')
          ..remove('supplier_id')
          ..['product_id'] = productId
          ..['supplier_id'] = supplierId
          ..['supplier_sync_id'] = canonicalSupplierSyncId
          ..['sync_id'] = syncId;
        await txn.insert('purchases', values);
      }

      for (final remote in collection('khata_transactions')) {
        final syncId = remote['sync_id']?.toString() ?? '';
        if (syncId.isEmpty || await localBySync('khata_transactions', syncId) != null) continue;
        final remotePartySyncId = remote['party_sync_id']?.toString();
        final partyId = await partyIdFor(remotePartySyncId);
        if (partyId == null) continue;
        final canonicalSyncId = await canonicalPartySyncId(remotePartySyncId);
        final values = Map<String, dynamic>.from(remote)
          ..remove('id')
          ..remove('party_id')
          ..['party_id'] = partyId
          ..['party_sync_id'] = canonicalSyncId
          ..['sync_id'] = syncId;
        await txn.insert('khata_transactions', values);
      }

      for (final table in ['expenses', 'reminders']) {
        for (final remote in collection(table)) {
          final syncId = remote['sync_id']?.toString() ?? '';
          if (syncId.isEmpty || await localBySync(table, syncId) != null) continue;
          final values = Map<String, dynamic>.from(remote)..remove('id')..['sync_id'] = syncId;
          await txn.insert(table, values);
        }
      }

      for (final remote in collection('sale_returns')) {
        final syncId = remote['sync_id']?.toString() ?? '';
        if (syncId.isEmpty || await localBySync('sale_returns', syncId) != null) continue;
        final saleId = await localBySync('sales', remote['sale_sync_id']?.toString());
        if (saleId == null) continue;
        final remotePartySyncId = remote['party_sync_id']?.toString();
        final customerId = await partyIdFor(remotePartySyncId);
        final canonicalSyncId = await canonicalPartySyncId(remotePartySyncId);
        final values = Map<String, dynamic>.from(remote)
          ..remove('id')
          ..remove('sale_id')
          ..remove('customer_id')
          ..['sale_id'] = saleId
          ..['customer_id'] = customerId
          ..['party_sync_id'] = canonicalSyncId
          ..['sync_id'] = syncId;
        await txn.insert('sale_returns', values);
      }

      for (final remote in collection('sale_return_items')) {
        final syncId = remote['sync_id']?.toString() ?? '';
        if (syncId.isEmpty || await localBySync('sale_return_items', syncId) != null) continue;
        final returnId = await localBySync('sale_returns', remote['return_sync_id']?.toString());
        final saleItemId = await localBySync('sale_items', remote['sale_item_sync_id']?.toString());
        if (returnId == null || saleItemId == null) continue;
        final productId = await productIdFor(remote['barcode']?.toString());
        final values = Map<String, dynamic>.from(remote)
          ..remove('id')
          ..remove('return_id')
          ..remove('sale_item_id')
          ..remove('product_id')
          ..['return_id'] = returnId
          ..['sale_item_id'] = saleItemId
          ..['product_id'] = productId
          ..['sync_id'] = syncId;
        await txn.insert('sale_return_items', values);
      }

      // Apply explicit deletion markers only when the other device has no
      // local stock/history that would be lost. Otherwise require a decision.
      for (final tombstone in collection('tombstones')) {
        final type = tombstone['entity_type']?.toString() ?? '';
        final key = tombstone['entity_key']?.toString() ?? '';
        if (key.isEmpty || !['product', 'party'].contains(type)) continue;
        if (type == 'product' &&
            collection('products').any((product) => product['barcode']?.toString() == key)) {
          continue;
        }
        if (type == 'party' &&
            collection('parties').any((party) => party['sync_id']?.toString() == key)) {
          continue;
        }
        final ignored = await txn.query(
          'drive_sync_ignored_tombstones',
          columns: ['entity_key'],
          where: 'source_device_id = ? AND entity_type = ? AND entity_key = ?',
          whereArgs: [sourceDeviceId, type, key],
          limit: 1,
        );
        if (ignored.isNotEmpty) continue;

        if (type == 'product') {
          final productRows = await txn.query('products', where: 'barcode = ?', whereArgs: [key], limit: 1);
          if (productRows.isEmpty) {
            await _recordDriveTombstone(txn, 'product', key, sourceDeviceId: sourceDeviceId);
            continue;
          }
          final product = productRows.first;
          final stock = _numberAsInt(product['quantity']);
          final damaged = _numberAsInt(product['damaged_quantity']);
          final sales = await txn.rawQuery('SELECT COUNT(*) AS total FROM sale_items WHERE barcode = ?', [key]);
          final purchases = await txn.rawQuery('SELECT COUNT(*) AS total FROM purchases WHERE barcode = ?', [key]);
          final hasHistory = (sales.first['total'] as num).toInt() > 0 ||
              (purchases.first['total'] as num).toInt() > 0;
          if (sourceDeviceId == 'windows-master' &&
              applyMasterState &&
              stock == 0 &&
              damaged == 0 &&
              !hasHistory) {
            await txn.delete('products', where: 'barcode = ?', whereArgs: [key]);
            await _recordDriveTombstone(txn, 'product', key, sourceDeviceId: sourceDeviceId);
          } else if (detectConflicts) {
            // Android-originated deletion is never applied silently on the
            // Windows master, even when the current stock appears to be zero.
            await addConflict(
              txn,
              type: 'product_delete',
              key: key,
              local: Map<String, dynamic>.from(product)..remove('id'),
              remote: {'_deleted': true, 'barcode': key, 'deleted_at': tombstone['deleted_at']},
            );
          }
        } else {
          final localPartyId = await partyIdFor(key);
          if (localPartyId == null) {
            await _recordDriveTombstone(txn, 'party', key, sourceDeviceId: sourceDeviceId);
            continue;
          }
          final partyRows = await txn.query('parties', where: 'id = ?', whereArgs: [localPartyId], limit: 1);
          if (partyRows.isEmpty) {
            await _recordDriveTombstone(txn, 'party', key, sourceDeviceId: sourceDeviceId);
            continue;
          }
          final party = partyRows.first;
          final localSyncId = party['sync_id']?.toString() ?? key;
          final refs = await txn.rawQuery(
            '''SELECT (SELECT COUNT(*) FROM sales WHERE customer_id = ?) +
                      (SELECT COUNT(*) FROM khata_transactions WHERE party_id = ?) +
                      (SELECT COUNT(*) FROM purchases WHERE supplier_id = ?) +
                      (SELECT COUNT(*) FROM sale_returns WHERE customer_id = ?) AS total''',
            [localPartyId, localPartyId, localPartyId, localPartyId],
          );
          final balance = _numberAsDouble(party['balance']);
          if (sourceDeviceId == 'windows-master' &&
              applyMasterState &&
              (refs.first['total'] as num).toInt() == 0 &&
              balance.abs() < 0.000001) {
            await txn.delete('parties', where: 'id = ?', whereArgs: [localPartyId]);
            await _recordDriveTombstone(txn, 'party', localSyncId, sourceDeviceId: sourceDeviceId);
            if (key != localSyncId) {
              await _recordDriveTombstone(txn, 'party', key, sourceDeviceId: sourceDeviceId);
            }
          } else if (detectConflicts) {
            // Require explicit Windows approval before applying an Android
            // party deletion; never silently remove a Khata/customer account.
            await addConflict(
              txn,
              type: 'party_delete',
              key: localSyncId,
              local: Map<String, dynamic>.from(party)..remove('id'),
              remote: {'_deleted': true, 'sync_id': key, 'deleted_at': tombstone['deleted_at']},
            );
          }
        }
      }
    });

    final pending = await db.rawQuery(
      "SELECT COUNT(*) AS total FROM drive_sync_conflicts WHERE source_device_id = ? AND snapshot_hash = ? AND status = 'pending'",
      [sourceDeviceId, snapshotHash],
    );
    return (pending.first['total'] as num?)?.toInt() == 0;
  }

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await initDB();
    return _db!;
  }

  // Close the active SQLite handle before replacing the database during restore.
  static Future<void> closeDatabase() async {
    final current = _db;
    _db = null;
    if (current != null && current.isOpen) {
      await current.close();
    }
  }

  // Keep Windows data in the user's profile, outside the extracted app folder.
  static Future<String> getDatabaseDirectory() async {
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      final candidates = <String?>[
        Platform.environment['LOCALAPPDATA'],
        Platform.environment['APPDATA'],
        if (userProfile != null && userProfile.isNotEmpty)
          join(userProfile, 'AppData', 'Local'),
      ];
      final failures = <String>[];
      for (final base in candidates.whereType<String>().where((value) => value.isNotEmpty).toSet()) {
        final directory = Directory(join(base, 'KhanBabaPOS', 'Data'));
        try {
          await directory.create(recursive: true);
          final probe = File(join(directory.path, '.write_test_${pid}'));
          await probe.writeAsString('ok', flush: true);
          await probe.delete();
          return directory.path;
        } catch (error) {
          failures.add('${directory.path}: $error');
        }
      }
      throw FileSystemException(
        'Khan Baba POS could not find a writable Windows user-data folder. '
        'The app does not need administrator rights. Check your Windows profile permissions. '
        '${failures.join(' | ')}',
      );
    }

    final directory = await getDatabasesPath();
    await Directory(directory).create(recursive: true);
    return directory;
  }

  // Resolve the active database without requiring Windows to delete or rename
  // the live SQLite file. A restored database is staged under a new filename and
  // this small pointer selects it for subsequent app starts.
  static Future<String> getDatabaseFilePath() async {
    final directory = await getDatabaseDirectory();
    final marker = File(join(directory, '.active_database'));
    if (!await marker.exists()) {
      return join(directory, 'khan_baba_pos.db');
    }

    final fileName = (await marker.readAsString()).trim();
    if (fileName.isEmpty ||
        basename(fileName) != fileName ||
        !fileName.startsWith('khan_baba_pos_') ||
        !fileName.toLowerCase().endsWith('.db')) {
      throw FileSystemException(
        'The active database pointer is invalid. Your existing database has not been changed.',
        marker.path,
      );
    }

    final activePath = join(directory, fileName);
    if (!await File(activePath).exists()) {
      throw FileSystemException(
        'The selected active database file is missing. Your original database has been preserved.',
        activePath,
      );
    }
    return activePath;
  }

  // Switch databases by updating a tiny metadata file, never by deleting the
  // active SQLite file (which Windows may still have open in another process).
  static Future<void> setActiveDatabaseFilePath(String filePath) async {
    final directory = await getDatabaseDirectory();
    final normalizedDirectory = normalize(absolute(directory));
    final normalizedPath = normalize(absolute(filePath));
    if (dirname(normalizedPath).toLowerCase() !=
        normalizedDirectory.toLowerCase()) {
      throw ArgumentError('Restore database must remain inside the POS data folder.');
    }

    final fileName = basename(normalizedPath);
    if (!fileName.startsWith('khan_baba_pos_') ||
        !fileName.toLowerCase().endsWith('.db')) {
      throw ArgumentError('Restore database filename is not valid.');
    }

    final marker = File(join(directory, '.active_database'));
    if (fileName == 'khan_baba_pos.db') {
      if (await marker.exists()) await marker.delete();
      return;
    }

    await marker.writeAsString(fileName, flush: true);
  }

  static Future<Database> initDB() async {
    final path = await getDatabaseFilePath();

    return await openDatabase(
      path,
      version: 16,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            barcode TEXT UNIQUE NOT NULL,
            price REAL NOT NULL,
            purchasePrice REAL DEFAULT 0.0,
            wholesalePrice REAL DEFAULT 0.0,
            damaged_quantity INTEGER DEFAULT 0,
            quantity INTEGER NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1
          )
        ''');

        await db.execute('''
          CREATE TABLE sales(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            total_amount REAL NOT NULL,
            discount REAL DEFAULT 0.0,
            final_amount REAL DEFAULT 0.0,
            payment_type TEXT DEFAULT 'Cash',
            customer_id INTEGER,
            salesman_uid TEXT,
            salesman_name TEXT,
            customer_type TEXT DEFAULT 'Walk-in',
            received_amount REAL DEFAULT 0.0,
            balance_due REAL DEFAULT 0.0,
            sync_id TEXT,
            customer_sync_id TEXT,
            date TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE parties(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT NOT NULL,
            type TEXT NOT NULL,
            customer_type TEXT DEFAULT 'Khata',
            sync_id TEXT,
            balance REAL DEFAULT 0.0
          )
        ''');

        await db.execute('''
          CREATE TABLE expenses(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            amount REAL NOT NULL,
            date TEXT NOT NULL,
            sync_id TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE reminders(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            details TEXT,
            date TEXT NOT NULL,
            is_done INTEGER DEFAULT 0,
            sync_id TEXT
          )
        ''');

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
        await db.execute('''CREATE TABLE sync_queue(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          collection_name TEXT NOT NULL,
          document_id TEXT NOT NULL,
          operation TEXT NOT NULL DEFAULT 'set',
          payload TEXT,
          created_at TEXT NOT NULL,
          attempts INTEGER NOT NULL DEFAULT 0,
          last_error TEXT,
          UNIQUE(collection_name, document_id)
        )''');
        await db.execute('''CREATE TABLE khata_transactions(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          party_id INTEGER NOT NULL,
          type TEXT NOT NULL,
          amount REAL NOT NULL,
          note TEXT,
          date TEXT NOT NULL,
          sync_id TEXT,
          party_sync_id TEXT
        )''');
        await db.execute('''CREATE TABLE sale_returns(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sale_id INTEGER NOT NULL,
          customer_id INTEGER,
          reason TEXT NOT NULL,
          refund_method TEXT NOT NULL,
          refund_amount REAL NOT NULL,
          date TEXT NOT NULL,
          sync_id TEXT,
          sale_sync_id TEXT,
          party_sync_id TEXT
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
        await db.execute('''CREATE TABLE khata_reminder_log(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          party_id INTEGER NOT NULL,
          oldest_due_date TEXT NOT NULL,
          created_at TEXT NOT NULL,
          UNIQUE(party_id, oldest_due_date)
        )''');
        await db.execute('''CREATE TABLE pending_bills(
          bill_id TEXT PRIMARY KEY,
          label TEXT NOT NULL,
          payload TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )''');
        await db.execute('''CREATE TABLE drive_sync_conflicts(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          source_device_id TEXT NOT NULL,
          snapshot_hash TEXT NOT NULL,
          entity_type TEXT NOT NULL,
          entity_key TEXT NOT NULL,
          local_payload TEXT NOT NULL,
          remote_payload TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending',
          resolution TEXT,
          created_at TEXT NOT NULL,
          resolved_at TEXT,
          UNIQUE(source_device_id, snapshot_hash, entity_type, entity_key)
        )''');
        await db.execute('''CREATE TABLE drive_sync_aliases(
          source_device_id TEXT NOT NULL,
          remote_sync_id TEXT NOT NULL,
          local_sync_id TEXT NOT NULL,
          PRIMARY KEY(source_device_id, remote_sync_id)
        )''');
        await db.execute('''CREATE TABLE drive_sync_tombstones(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          entity_type TEXT NOT NULL,
          entity_key TEXT NOT NULL,
          deleted_at TEXT NOT NULL,
          source_device_id TEXT NOT NULL DEFAULT 'local',
          UNIQUE(entity_type, entity_key)
        )''');
        await db.execute('''CREATE TABLE drive_sync_ignored_tombstones(
          source_device_id TEXT NOT NULL,
          entity_type TEXT NOT NULL,
          entity_key TEXT NOT NULL,
          PRIMARY KEY(source_device_id, entity_type, entity_key)
        )''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 15) {
          await db.execute('''CREATE TABLE IF NOT EXISTS purchases(
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
            date TEXT NOT NULL
          )''');
          await _ensureColumn(db, 'purchases', 'invoice_group_id', 'TEXT');
          await _ensureColumn(db, 'purchases', 'invoice_number', 'TEXT');
          await _ensureColumn(db, 'purchases', 'invoice_date', 'TEXT');
          await _ensureColumn(db, 'purchases', 'invoice_total', 'REAL');
          await _ensureColumn(db, 'purchases', 'invoice_discount', 'REAL');
          await _ensureColumn(db, 'purchases', 'invoice_tax', 'REAL');
          await _ensureColumn(db, 'purchases', 'invoice_paid_amount', 'REAL');
          await _ensureColumn(db, 'purchases', 'invoice_balance_due', 'REAL');
          await _ensureColumn(db, 'purchases', 'invoice_image_path', 'TEXT');
        }
        if (oldVersion < 16) {
          await _ensureColumn(db, 'purchases', 'unit_label', 'TEXT');
        }
        if (oldVersion < 10) {
          await _ensureColumn(db, 'products', 'is_active', 'INTEGER NOT NULL DEFAULT 1');
        }
        if (oldVersion < 11) {
          await db.execute('''CREATE TABLE IF NOT EXISTS khata_reminder_log(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            party_id INTEGER NOT NULL,
            oldest_due_date TEXT NOT NULL,
            created_at TEXT NOT NULL,
            UNIQUE(party_id, oldest_due_date)
          )''');
        }
        if (oldVersion < 12) {
          await db.execute('''CREATE TABLE IF NOT EXISTS pending_bills(
            bill_id TEXT PRIMARY KEY,
            label TEXT NOT NULL,
            payload TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )''');
        }
        if (oldVersion < 13) {
          await db.execute('''CREATE TABLE IF NOT EXISTS drive_sync_conflicts(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_device_id TEXT NOT NULL,
            snapshot_hash TEXT NOT NULL,
            entity_type TEXT NOT NULL,
            entity_key TEXT NOT NULL,
            local_payload TEXT NOT NULL,
            remote_payload TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            resolution TEXT,
            created_at TEXT NOT NULL,
            resolved_at TEXT,
            UNIQUE(source_device_id, snapshot_hash, entity_type, entity_key)
          )''');
          await db.execute('''CREATE TABLE IF NOT EXISTS drive_sync_aliases(
            source_device_id TEXT NOT NULL,
            remote_sync_id TEXT NOT NULL,
            local_sync_id TEXT NOT NULL,
            PRIMARY KEY(source_device_id, remote_sync_id)
          )''');
        }
        if (oldVersion < 14) {
          await db.execute('''CREATE TABLE IF NOT EXISTS drive_sync_tombstones(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity_type TEXT NOT NULL,
            entity_key TEXT NOT NULL,
            deleted_at TEXT NOT NULL,
            source_device_id TEXT NOT NULL DEFAULT 'local',
            UNIQUE(entity_type, entity_key)
          )''');
          await db.execute('''CREATE TABLE IF NOT EXISTS drive_sync_ignored_tombstones(
            source_device_id TEXT NOT NULL,
            entity_type TEXT NOT NULL,
            entity_key TEXT NOT NULL,
            PRIMARY KEY(source_device_id, entity_type, entity_key)
          )''');
        }
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS expenses(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              amount REAL NOT NULL,
              date TEXT NOT NULL
            )
          ''');
        }

        if (oldVersion < 3) {
          try {
            await db.execute(
              'ALTER TABLE products '
              'ADD COLUMN purchasePrice REAL DEFAULT 0.0',
            );
          } catch (_) {}

          try {
            await db.execute(
              'ALTER TABLE sales '
              'ADD COLUMN discount REAL DEFAULT 0.0',
            );
            await db.execute(
              'ALTER TABLE sales '
              'ADD COLUMN final_amount REAL DEFAULT 0.0',
            );
            await db.execute(
              'ALTER TABLE sales '
              'ADD COLUMN payment_type TEXT DEFAULT "Cash"',
            );
            await db.execute(
              'ALTER TABLE sales ADD COLUMN customer_id INTEGER',
            );
          } catch (_) {}

          await db.execute('''
            CREATE TABLE IF NOT EXISTS reminders(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              details TEXT,
              date TEXT NOT NULL,
              is_done INTEGER DEFAULT 0
            )
          ''');
        }

        if (oldVersion < 6) {
          await db.execute('''CREATE TABLE IF NOT EXISTS sync_queue(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            collection_name TEXT NOT NULL,
            document_id TEXT NOT NULL,
            operation TEXT NOT NULL DEFAULT 'set',
            payload TEXT,
            created_at TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            UNIQUE(collection_name, document_id)
          )''');
        }

        if (oldVersion < 5) {
          await db.execute('ALTER TABLE sales ADD COLUMN salesman_uid TEXT');
          await db.execute('ALTER TABLE sales ADD COLUMN salesman_name TEXT');
        }

        if (oldVersion < 4) {
          await db.execute('''CREATE TABLE IF NOT EXISTS purchases(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            product_id INTEGER NOT NULL,
            product_name TEXT NOT NULL,
            barcode TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            unit_cost REAL NOT NULL,
            total_cost REAL NOT NULL,
            supplier_id INTEGER,
            date TEXT NOT NULL
          )''');
          await db.execute('''CREATE TABLE IF NOT EXISTS sale_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sale_id INTEGER NOT NULL,
            product_id INTEGER,
            barcode TEXT NOT NULL,
            product_name TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            sale_price REAL NOT NULL,
            purchase_price REAL NOT NULL,
            line_total REAL NOT NULL,
            cost_total REAL NOT NULL
          )''');
          await db.execute('''CREATE TABLE IF NOT EXISTS khata_transactions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            party_id INTEGER NOT NULL,
            type TEXT NOT NULL,
            amount REAL NOT NULL,
            note TEXT,
            date TEXT NOT NULL
          )''');
        }

        if (oldVersion < 7) {
          await db.execute('''CREATE TABLE IF NOT EXISTS parties(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT NOT NULL,
            type TEXT NOT NULL,
            balance REAL DEFAULT 0.0
          )''');
          await _ensureColumn(db, 'products', 'wholesalePrice', 'REAL DEFAULT 0.0');
          await _ensureColumn(db, 'products', 'damaged_quantity', 'INTEGER DEFAULT 0');
          await _ensureColumn(db, 'parties', 'customer_type', "TEXT DEFAULT 'Khata'");
          await _ensureColumn(db, 'sales', 'customer_type', "TEXT DEFAULT 'Walk-in'");
          await _ensureColumn(db, 'sales', 'received_amount', 'REAL DEFAULT 0.0');
          await _ensureColumn(db, 'sales', 'balance_due', 'REAL DEFAULT 0.0');
          await db.execute('''CREATE TABLE IF NOT EXISTS sale_returns(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sale_id INTEGER NOT NULL,
            customer_id INTEGER,
            reason TEXT NOT NULL,
            refund_method TEXT NOT NULL,
            refund_amount REAL NOT NULL,
            date TEXT NOT NULL
          )''');
          await db.execute('''CREATE TABLE IF NOT EXISTS sale_return_items(
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
            condition TEXT NOT NULL DEFAULT 'saleable'
          )''');
        }

        if (oldVersion < 8) {
          await _ensureColumn(db, 'parties', 'sync_id', 'TEXT');
          await _ensureColumn(db, 'sales', 'sync_id', 'TEXT');
          await _ensureColumn(db, 'sales', 'customer_sync_id', 'TEXT');
          await _ensureColumn(db, 'sale_items', 'sync_id', 'TEXT');
          await _ensureColumn(db, 'sale_items', 'sale_sync_id', 'TEXT');
          await _ensureColumn(db, 'purchases', 'sync_id', 'TEXT');
          await _ensureColumn(db, 'purchases', 'supplier_sync_id', 'TEXT');
          await _ensureColumn(db, 'khata_transactions', 'sync_id', 'TEXT');
          await _ensureColumn(db, 'khata_transactions', 'party_sync_id', 'TEXT');
          await _ensureColumn(db, 'expenses', 'sync_id', 'TEXT');
          await _ensureColumn(db, 'reminders', 'sync_id', 'TEXT');
          await _ensureColumn(db, 'sale_returns', 'sync_id', 'TEXT');
          await _ensureColumn(db, 'sale_returns', 'sale_sync_id', 'TEXT');
          await _ensureColumn(db, 'sale_returns', 'party_sync_id', 'TEXT');
          await _ensureColumn(db, 'sale_return_items', 'sync_id', 'TEXT');
          await _ensureColumn(db, 'sale_return_items', 'return_sync_id', 'TEXT');
          await _ensureColumn(db, 'sale_return_items', 'sale_item_sync_id', 'TEXT');
        }
        if (oldVersion < 9) {
          // Preserve existing customers, balances and ledger entries while
          // removing the separate Wholesale customer classification.
          await db.execute("UPDATE parties SET customer_type = 'Khata' WHERE type = 'customer' AND customer_type = 'Wholesale'");
        }
      },
    );
  }


  // Durable offline-first outbox. Local changes are queued before network sync.
  static Future<void> _queueSync(
    DatabaseExecutor executor, {
    required String collection,
    required String documentId,
    required Map<String, dynamic> payload,
    String operation = 'set',
  }) async {
    if (localOnlyMode) return;
    final syncPayload = Map<String, dynamic>.from(payload);
    if (collection == 'products' && syncPayload['_deleted'] != true) {
      syncPayload['_deleted'] = false;
    }
    await executor.insert(
      'sync_queue',
      {
        'collection_name': collection,
        'document_id': documentId,
        'operation': operation,
        'payload': jsonEncode(syncPayload),
        'created_at': DateTime.now().toIso8601String(),
        'attempts': 0,
        'last_error': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<int> getPendingSyncCount() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM sync_queue');
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  static Future<void> syncPendingChanges({int batchSize = 50}) async {
    if (localOnlyMode) return;
    if (_isSyncingPending) {
      _syncPendingAgain = true;
      return;
    }
    _isSyncingPending = true;
    try {
      do {
        _syncPendingAgain = false;
        final db = await database;
        final pending = await db.query(
          'sync_queue',
          orderBy: 'id ASC',
          limit: batchSize,
        );

        for (final row in pending) {
          final id = row['id'] as int;
          final collection = row['collection_name'].toString();
          final documentId = row['document_id'].toString();
          final operation = row['operation'].toString();
          try {
            final ref = _storeCollection(collection).doc(documentId);
            if (operation == 'delete') {
              await ref.delete().timeout(const Duration(seconds: 8));
            } else {
              final decoded = jsonDecode(row['payload'].toString());
              if (decoded is! Map<String, dynamic>) {
                throw const FormatException('Invalid sync payload.');
              }
              await ref.set(decoded, SetOptions(merge: true))
                  .timeout(const Duration(seconds: 8));
            }
            await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
          } catch (e) {
            await db.rawUpdate(
              'UPDATE sync_queue SET attempts = attempts + 1, last_error = ? WHERE id = ?',
              [e.toString(), id],
            );
            // Stop on the first network/permission error. Keep the remaining
            // outbox rows for the next successful connection.
            break;
          }
        }
      } while (_syncPendingAgain);
    } finally {
      _isSyncingPending = false;
    }
  }

  // Product Operations + Firebase Sync

  static Future<int> insertProduct(Map<String, dynamic> product) async {
    final db = await database;
    final data = Map<String, dynamic>.from(product);
    final barcode = (data['barcode'] ?? '').toString().trim();
    if (barcode.isEmpty) throw Exception('Product barcode zaroori hai.');
    data['barcode'] = barcode;

    final result = await db.transaction<int>((txn) async {
      final existing = await txn.query(
        'products',
        columns: ['id'],
        where: 'barcode = ?',
        whereArgs: [barcode],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw Exception('Is barcode ka product pehle se inventory mein mojood hai. Existing product ko edit karein.');
      }
      final inserted = await txn.insert(
        'products',
        data,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await txn.delete('drive_sync_tombstones', where: 'entity_type = ? AND entity_key = ?', whereArgs: ['product', barcode]);
      await txn.delete('drive_sync_ignored_tombstones', where: 'entity_type = ? AND entity_key = ?', whereArgs: ['product', barcode]);
      await _queueSync(
        txn,
        collection: 'products',
        documentId: barcode,
        payload: data,
      );
      return inserted;
    });
    unawaited(syncPendingChanges());
    return result;
  }

  static Future<int> updateProduct(
    int id,
    Map<String, dynamic> product,
  ) async {
    final db = await database;

    final result = await db.transaction<int>((txn) async {
      final oldRows = await txn.query('products', where: 'id = ?', whereArgs: [id], limit: 1);
      if (oldRows.isEmpty) throw Exception('Product not found. Please refresh and try again.');
      final oldBarcode = oldRows.first['barcode'].toString();
      final newBarcode = product['barcode'].toString();
      final updated = await txn.update('products', product, where: 'id = ?', whereArgs: [id]);
      if (updated == 0) throw Exception('Product not found. Please refresh and try again.');
      if (oldBarcode != newBarcode) {
        await _recordDriveTombstone(txn, 'product', oldBarcode);
        await _queueSync(txn, collection: 'products', documentId: oldBarcode,
            payload: {'barcode': oldBarcode, '_deleted': true});
      }
      await _queueSync(txn, collection: 'products', documentId: newBarcode, payload: product);
      return updated;
    });
    unawaited(syncPendingChanges());
    return result;
  }

  static Future<List<Map<String, dynamic>>> getProducts() async {
    final db = await database;
    return await db.query('products', orderBy: 'id DESC');
  }

  static Future<int> deleteProduct(int id) async {
    final db = await database;
    final deleted = await db.transaction<int>((txn) async {
      final rows = await txn.query('products', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return 0;
      final barcode = rows.first['barcode'].toString();
      final availableStock = (rows.first['quantity'] as num?)?.toInt() ?? 0;
      final damagedStock = (rows.first['damaged_quantity'] as num?)?.toInt() ?? 0;
      if (availableStock > 0 || damagedStock > 0) {
        throw Exception('Pehle is product ka saleable aur damaged stock zero karein; stock mojood honay par delete nahi kar sakte.');
      }
      final saleHistory = await txn.rawQuery('SELECT COUNT(*) AS count FROM sale_items WHERE barcode = ?', [barcode]);
      final purchaseHistory = await txn.rawQuery('SELECT COUNT(*) AS count FROM purchases WHERE product_id = ? OR barcode = ?', [id, barcode]);
      final salesCount = (saleHistory.first['count'] as num).toInt();
      final purchasesCount = (purchaseHistory.first['count'] as num).toInt();
      if (salesCount > 0 || purchasesCount > 0) {
        throw Exception('Is product ki $salesCount sale aur $purchasesCount purchase history mojood hai. Purana record mehfooz rakhne ke liye delete nahi kar sakte; Edit se stock zero ya details update karein.');
      }
      await _recordDriveTombstone(txn, 'product', barcode);
      await _queueSync(txn, collection: 'products', documentId: barcode, payload: {'barcode': barcode, '_deleted': true});
      return txn.delete('products', where: 'id = ?', whereArgs: [id]);
    });
    unawaited(syncPendingChanges());
    return deleted;
  }

  // Safely complete a sale and reduce stock in one transaction.

  static Future<int> completeSale({
    required Map<String, dynamic> sale,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) {
      throw Exception('Cart is empty.');
    }

    final db = await database;
    final saleData = Map<String, dynamic>.from(sale);
    final customerId = saleData['customer_id'];
    final customerType = customerId == null ? 'Walk-in' : 'Khata';
    final saleFinalAmount = (saleData['final_amount'] as num?)?.toDouble() ??
        (saleData['total_amount'] as num?)?.toDouble() ?? 0.0;
    final receivedAmount = customerId == null
        ? saleFinalAmount
        : ((saleData['received_amount'] as num?)?.toDouble() ?? 0.0);
    if (!receivedAmount.isFinite || receivedAmount < 0 || receivedAmount > saleFinalAmount) {
      throw Exception('Received amount must be between zero and the bill total.');
    }
    final balanceDue = customerId == null ? 0.0 : saleFinalAmount - receivedAmount;
    saleData['customer_type'] = customerType;
    saleData['received_amount'] = receivedAmount;
    saleData['balance_due'] = balanceDue;

    // Combine quantities for repeated barcodes.
    final quantitiesByBarcode = <String, int>{};

    for (final item in items) {
      final barcode = item['barcode']?.toString();
      final quantity = (item['quantity'] as num?)?.toInt() ?? 0;

      if (barcode == null || barcode.isEmpty || quantity <= 0) {
        throw Exception('Invalid product barcode or quantity.');
      }

      quantitiesByBarcode[barcode] =
          (quantitiesByBarcode[barcode] ?? 0) + quantity;
    }

    // Check stock and save the sale atomically.
    final saleId = await db.transaction<int>((txn) async {
      // Validate every product before changing any stock.
      for (final entry in quantitiesByBarcode.entries) {
        final barcode = entry.key;
        final requestedQuantity = entry.value;

        final products = await txn.query(
          'products',
          where: 'barcode = ?',
          whereArgs: [barcode],
          limit: 1,
        );

        if (products.isEmpty) {
          throw Exception('Product not found: $barcode');
        }

        final product = products.first;
        final stock = (product['quantity'] as num?)?.toInt() ?? 0;

        if (stock < requestedQuantity) {
          throw Exception(
            'Insufficient stock. Available: $stock, required: $requestedQuantity.',
          );
        }
      }

      // Reduce stock only after all products pass validation.
      for (final entry in quantitiesByBarcode.entries) {
        final barcode = entry.key;
        final requestedQuantity = entry.value;

        final changed = await txn.rawUpdate(
          'UPDATE products '
          'SET quantity = quantity - ? '
          'WHERE barcode = ? AND quantity >= ?',
          [requestedQuantity, barcode, requestedQuantity],
        );

        if (changed != 1) {
          throw Exception(
            'Stock update failed for barcode $barcode. '
            'Please try again.',
          );
        }
        final updatedRows = await txn.query(
          'products',
          where: 'barcode = ?',
          whereArgs: [barcode],
          limit: 1,
        );
        if (updatedRows.isNotEmpty) {
          final updatedProduct = Map<String, dynamic>.from(updatedRows.first)
            ..remove('id');
          await _queueSync(
            txn,
            collection: 'products',
            documentId: barcode,
            payload: updatedProduct,
          );
        }
      }

      // Save the sale with a stable Firestore document ID.
      final customerSyncRows = customerId == null
          ? <Map<String, Object?>>[]
          : await txn.query('parties', columns: ['sync_id'], where: 'id = ?', whereArgs: [customerId], limit: 1);
      final saleSyncId = _newSyncId();
      saleData['sync_id'] = saleSyncId;
      saleData['customer_sync_id'] = customerSyncRows.isEmpty ? null : customerSyncRows.first['sync_id'];
      final id = await txn.insert('sales', saleData);
      await _queueRow(txn, 'sales', saleData, remove: ['customer_id']);

      // Snapshot item prices/costs for future profit reports.
      for (final item in items) {
        final barcode = item['barcode'].toString();
        final productRows = await txn.query(
          'products',
          where: 'barcode = ?',
          whereArgs: [barcode],
          limit: 1,
        );
        final product = productRows.isEmpty
            ? <String, dynamic>{}
            : productRows.first;
        final qty = (item['quantity'] as num).toInt();
        final salePrice =
            ((item['salePrice'] ?? item['price'] ?? product['price'] ?? 0)
                    as num)
                .toDouble();
        final purchasePrice =
            ((item['purchasePrice'] ?? product['purchasePrice'] ?? 0) as num)
                .toDouble();
        final name = (item['name'] ?? product['name'] ?? barcode).toString();
        if (!salePrice.isFinite || !purchasePrice.isFinite ||
            salePrice < purchasePrice) {
          throw Exception(
            'Sale price for $name must not be below purchase cost '
            '(Rs. ${purchasePrice.toStringAsFixed(2)}).',
          );
        }
        final saleItem = <String, dynamic>{
          'sale_id': id,
          'product_id': product['id'],
          'barcode': barcode,
          'product_name': name,
          'quantity': qty,
          'sale_price': salePrice,
          'purchase_price': purchasePrice,
          'line_total': salePrice * qty,
          'cost_total': purchasePrice * qty,
          'sync_id': _newSyncId(),
          'sale_sync_id': saleSyncId,
        };
        await txn.insert('sale_items', saleItem);
        await _queueRow(txn, 'sale_items', saleItem, remove: ['sale_id', 'product_id']);
      }

      // Named-customer sales enter the ledger as a debit. Any cash collected
      // at checkout is recorded as a receipt so only the unpaid amount remains.
      final customerIdForLedger = saleData['customer_id'];
      if (customerIdForLedger != null) {
        final partySyncId = saleData['customer_sync_id']?.toString();
        final creditEntry = <String, dynamic>{
          'party_id': customerIdForLedger,
          'party_sync_id': partySyncId,
          'sync_id': _newSyncId(),
          'type': 'credit',
          'amount': saleFinalAmount,
          'note': 'Sale #$id',
          'date': saleData['date'].toString(),
        };
        await txn.insert('khata_transactions', creditEntry);
        await _queueRow(txn, 'khata_transactions', creditEntry, remove: ['party_id']);
        if (receivedAmount > 0) {
          final receiptEntry = <String, dynamic>{
            'party_id': customerIdForLedger,
            'party_sync_id': partySyncId,
            'sync_id': _newSyncId(),
            'type': 'receipt',
            'amount': receivedAmount,
            'note': 'Cash received at sale #$id',
            'date': saleData['date'].toString(),
          };
          await txn.insert('khata_transactions', receiptEntry);
          await _queueRow(txn, 'khata_transactions', receiptEntry, remove: ['party_id']);
        }
        await txn.rawUpdate(
          'UPDATE parties SET balance = balance + ? WHERE id = ?',
          [balanceDue, customerIdForLedger],
        );
        final updatedParty = await txn.query('parties', where: 'id = ?', whereArgs: [customerIdForLedger], limit: 1);
        if (updatedParty.isNotEmpty) await _queueRow(txn, 'parties', Map<String, dynamic>.from(updatedParty.first));
      }

      return id;
    });

    unawaited(syncPendingChanges());
    return saleId;
  }

  // Sales Operations + Firebase Sync

  static Future<int> insertSale(Map<String, dynamic> sale) async {
    final db = await database;
    final data = Map<String, dynamic>.from(sale);
    data['sync_id'] ??= _newSyncId();
    final customerId = (data['customer_id'] as num?)?.toInt();
    if (customerId != null) {
      final party = await db.query('parties', columns: ['sync_id'], where: 'id = ?', whereArgs: [customerId], limit: 1);
      data['customer_sync_id'] = party.isEmpty ? null : party.first['sync_id'];
    }
    final result = await db.transaction<int>((txn) async {
      final id = await txn.insert('sales', data);
      await _queueRow(txn, 'sales', data, remove: ['customer_id']);
      return id;
    });
    unawaited(syncPendingChanges());
    return result;
  }

  static Future<List<Map<String, dynamic>>> getSales() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT s.*,
        COALESCE((SELECT SUM(refund_amount) FROM sale_returns r WHERE r.sale_id = s.id), 0) AS returned_amount,
        (SELECT COUNT(*) FROM sale_returns r WHERE r.sale_id = s.id) AS returned_count
      FROM sales s ORDER BY s.id DESC
    ''');
    return rows.map((row) {
      final sale = Map<String, dynamic>.from(row);
      sale['effective_amount'] = _effectiveSaleAmount(sale);
      sale['effective_received_amount'] = _effectiveReceivedAmount(sale);
      sale['effective_balance_due'] = _effectiveBalanceDue(sale);
      return sale;
    }).toList();
  }

  static Future<Map<String, dynamic>?> getPartyById(int id) async {
    final db = await database;
    final rows = await db.query('parties', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  static Future<List<Map<String, dynamic>>> getSaleItems(int saleId) async {
    final db = await database;
    return db.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId], orderBy: 'id ASC');
  }

  static Future<List<Map<String, dynamic>>> getReturnableSaleItems(int saleId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT si.*,
        COALESCE((SELECT SUM(ri.quantity) FROM sale_return_items ri WHERE ri.sale_item_id = si.id), 0) AS returned_quantity,
        si.quantity - COALESCE((SELECT SUM(ri.quantity) FROM sale_return_items ri WHERE ri.sale_item_id = si.id), 0) AS returnable_quantity
      FROM sale_items si WHERE si.sale_id = ? ORDER BY si.id ASC
    ''', [saleId]);
  }

  static Future<int> recordSaleReturn({
    required int saleId,
    required String reason,
    required String refundMethod,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) throw Exception('Return ke liye kam az kam aik item select karein.');
    if (reason.trim().isEmpty) throw Exception('Return reason likhna zaroori hai.');
    await _ensureLegacySyncIds();
    final db = await database;
    final returnId = await db.transaction<int>((txn) async {
      final saleRows = await txn.query('sales', where: 'id = ?', whereArgs: [saleId], limit: 1);
      if (saleRows.isEmpty) throw Exception('Original invoice nahi mila.');
      final sale = saleRows.first;
      final customerId = (sale['customer_id'] as num?)?.toInt();
      final saleSyncId = sale['sync_id']?.toString();
      if (saleSyncId == null || saleSyncId.isEmpty) throw Exception('Original invoice sync ID missing hai.');
      final partyRows = customerId == null
          ? <Map<String, Object?>>[]
          : await txn.query('parties', columns: ['sync_id'], where: 'id = ?', whereArgs: [customerId], limit: 1);
      final partySyncId = partyRows.isEmpty ? null : partyRows.first['sync_id']?.toString();
      if (refundMethod == 'Khata' && customerId == null) {
        throw Exception('Walk-in sale ka refund Khata mein adjust nahi ho sakta.');
      }
      final selected = <Map<String, dynamic>>[];
      var grossTotal = 0.0;
      for (final request in items) {
        final saleItemId = (request['sale_item_id'] as num?)?.toInt();
        final quantity = (request['quantity'] as num?)?.toInt() ?? 0;
        if (saleItemId == null || quantity <= 0) throw Exception('Return quantity valid honi chahiye.');
        final rows = await txn.query('sale_items', where: 'id = ? AND sale_id = ?', whereArgs: [saleItemId, saleId], limit: 1);
        if (rows.isEmpty) throw Exception('Selected item original invoice ka hissa nahi hai.');
        final item = rows.first;
        final returnedRows = await txn.rawQuery('SELECT COALESCE(SUM(quantity), 0) AS qty FROM sale_return_items WHERE sale_item_id = ?', [saleItemId]);
        final alreadyReturned = (returnedRows.first['qty'] as num?)?.toInt() ?? 0;
        final soldQuantity = (item['quantity'] as num).toInt();
        if (quantity > soldQuantity - alreadyReturned) {
          throw Exception('Return quantity sold quantity se zyada hai: ' + item['product_name'].toString());
        }
        final salePrice = (item['sale_price'] as num).toDouble();
        final purchasePrice = (item['purchase_price'] as num).toDouble();
        final condition = request['condition'] == 'damaged' ? 'damaged' : 'saleable';
        final lineTotal = salePrice * quantity;
        grossTotal += lineTotal;
        selected.add({
          'sale_item_id': saleItemId,
          'sale_item_sync_id': item['sync_id'],
          'product_id': item['product_id'],
          'barcode': item['barcode'].toString(),
          'product_name': item['product_name'].toString(),
          'quantity': quantity,
          'sale_price': salePrice,
          'purchase_price': purchasePrice,
          'line_total': lineTotal,
          'cost_total': purchasePrice * quantity,
          'condition': condition,
        });
      }
      final subtotal = (sale['total_amount'] as num?)?.toDouble() ?? grossTotal;
      final discount = (sale['discount'] as num?)?.toDouble() ?? 0.0;
      final discountShare = subtotal > 0 ? (discount * grossTotal / subtotal).clamp(0.0, grossTotal).toDouble() : 0.0;
      final refundAmount = (grossTotal - discountShare).clamp(0.0, double.infinity).toDouble();
      if (refundMethod == 'Cash' && customerId != null) {
        final priorCashRefunds = await txn.rawQuery(
          "SELECT COALESCE(SUM(refund_amount), 0) AS amount FROM sale_returns WHERE sale_id = ? AND refund_method = 'Cash'",
          [saleId],
        );
        final alreadyRefunded = (priorCashRefunds.first['amount'] as num?)?.toDouble() ?? 0.0;
        final received = _effectiveReceivedAmount(sale);
        if (alreadyRefunded + refundAmount > received) {
          throw Exception('Cash refund received cash se zyada hai. Khata adjustment select karein.');
        }
      }
      final date = DateTime.now().toIso8601String().substring(0, 19);
      final returnSyncId = _newSyncId();
      final returnRow = <String, dynamic>{
        'sale_id': saleId,
        'sale_sync_id': saleSyncId,
        'customer_id': customerId,
        'party_sync_id': partySyncId,
        'reason': reason.trim(),
        'refund_method': refundMethod,
        'refund_amount': refundAmount,
        'date': date,
        'sync_id': returnSyncId,
      };
      final id = await txn.insert('sale_returns', returnRow);
      await _queueRow(txn, 'sale_returns', returnRow, remove: ['sale_id', 'customer_id']);
      for (final item in selected) {
        final returnItem = <String, dynamic>{
          'return_id': id,
          'return_sync_id': returnSyncId,
          ...item,
          'sync_id': _newSyncId(),
        };
        await txn.insert('sale_return_items', returnItem);
        await _queueRow(txn, 'sale_return_items', returnItem,
            remove: ['return_id', 'sale_item_id', 'product_id']);
        final productId = item['product_id'];
        if (productId != null) {
          if (item['condition'] == 'saleable') {
            await txn.rawUpdate('UPDATE products SET quantity = quantity + ? WHERE id = ?', [item['quantity'], productId]);
          } else {
            await txn.rawUpdate('UPDATE products SET damaged_quantity = COALESCE(damaged_quantity, 0) + ? WHERE id = ?', [item['quantity'], productId]);
          }
          final productRows = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
          if (productRows.isNotEmpty) {
            final product = Map<String, dynamic>.from(productRows.first)..remove('id');
            await _queueSync(txn, collection: 'products',
                documentId: product['barcode'].toString(), payload: product);
          }
        }
      }
      if (refundMethod == 'Khata' && customerId != null && refundAmount > 0) {
        await txn.rawUpdate('UPDATE parties SET balance = balance - ? WHERE id = ?', [refundAmount, customerId]);
        final transaction = <String, dynamic>{
          'party_id': customerId,
          'party_sync_id': partySyncId,
          'sync_id': _newSyncId(),
          'type': 'return_adjustment',
          'amount': refundAmount,
          'note': 'Return #' + id.toString() + ' against Bill #' + saleId.toString(),
          'date': date,
        };
        await txn.insert('khata_transactions', transaction);
        await _queueRow(txn, 'khata_transactions', transaction, remove: ['party_id']);
        final updatedParty = await txn.query('parties', where: 'id = ?', whereArgs: [customerId], limit: 1);
        if (updatedParty.isNotEmpty) await _queueRow(txn, 'parties', Map<String, dynamic>.from(updatedParty.first));
      }
      return id;
    });
    unawaited(syncPendingChanges());
    return returnId;
  }

  static Future<List<Map<String, dynamic>>> getSaleReturns() async {
    final db = await database;
    return db.rawQuery('''
      SELECT r.*, s.date AS sale_date, p.name AS customer_name
      FROM sale_returns r JOIN sales s ON s.id = r.sale_id
      LEFT JOIN parties p ON p.id = r.customer_id
      ORDER BY r.id DESC
    ''');
  }

  static Future<List<Map<String, dynamic>>> getSaleReturnItems(int returnId) async {
    final db = await database;
    return db.query('sale_return_items', where: 'return_id = ?', whereArgs: [returnId], orderBy: 'id ASC');
  }

  // Party Operations (Customers & Suppliers) + Firebase Sync

  static Future<int> insertParty(Map<String, dynamic> party) async {
    final db = await database;
    final data = Map<String, dynamic>.from(party)..['sync_id'] = _newSyncId();
    if (data['type'] == 'customer') data['customer_type'] = 'Khata';
    final result = await db.transaction<int>((txn) async {
      final id = await txn.insert('parties', data);
      await _queueRow(txn, 'parties', data);
      return id;
    });
    unawaited(syncPendingChanges());
    return result;
  }

  static Future<List<Map<String, dynamic>>> getParties(String type) async {
    final db = await database;

    return await db.query(
      'parties',
      where: 'type = ?',
      whereArgs: [type],
      orderBy: 'id DESC',
    );
  }

  // Identify the oldest still-unpaid credit using FIFO receipt allocation.
  // Unmatched legacy balance is treated as current rather than falsely aged.
  static Future<List<Map<String, dynamic>>> getOverdueKhataCustomers({
    int overdueDays = 30,
  }) async {
    final db = await database;
    final parties = await db.query(
      'parties',
      where: "type = 'customer' AND balance > 0",
      orderBy: 'name COLLATE NOCASE',
    );
    final cutoff = DateTime.now().subtract(Duration(days: overdueDays));
    final results = <Map<String, dynamic>>[];

    for (final party in parties) {
      final partyId = (party['id'] as num).toInt();
      final balance = _numberAsDouble(party['balance']);
      final sales = await db.query(
        'sales',
        where: 'customer_id = ?',
        whereArgs: [partyId],
        columns: ['id', 'date', 'total_amount', 'discount', 'final_amount'],
        orderBy: 'date ASC, id ASC',
      );
      final receipts = await db.query(
        'khata_transactions',
        where: "party_id = ? AND type = 'receipt'",
        whereArgs: [partyId],
        columns: ['date', 'amount', 'id'],
        orderBy: 'date ASC, id ASC',
      );
      final returns = await db.query(
        'sale_returns',
        where: "customer_id = ? AND refund_method = 'Khata'",
        whereArgs: [partyId],
        columns: ['date', 'refund_amount', 'id'],
        orderBy: 'date ASC, id ASC',
      );
      final events = <Map<String, dynamic>>[];
      for (final sale in sales) {
        events.add({
          'date': sale['date']?.toString() ?? '',
          'kind': 'credit',
          'amount': _effectiveSaleAmount(sale),
          'id': (sale['id'] as num?)?.toInt() ?? 0,
        });
      }
      for (final receipt in receipts) {
        events.add({
          'date': receipt['date']?.toString() ?? '',
          'kind': 'payment',
          'amount': _numberAsDouble(receipt['amount']),
          'id': (receipt['id'] as num?)?.toInt() ?? 0,
        });
      }
      for (final saleReturn in returns) {
        events.add({
          'date': saleReturn['date']?.toString() ?? '',
          'kind': 'payment',
          'amount': _numberAsDouble(saleReturn['refund_amount']),
          'id': (saleReturn['id'] as num?)?.toInt() ?? 0,
        });
      }
      events.sort((a, b) {
        final ad = DateTime.tryParse(a['date'].toString()) ?? DateTime.now();
        final bd = DateTime.tryParse(b['date'].toString()) ?? DateTime(1970);
        final byDate = ad.compareTo(bd);
        if (byDate != 0) return byDate;
        final kindOrder = (a['kind'] == 'credit' ? 0 : 1)
            .compareTo(b['kind'] == 'credit' ? 0 : 1);
        return kindOrder != 0
            ? kindOrder
            : (a['id'] as int).compareTo(b['id'] as int);
      });
      final unpaid = <Map<String, dynamic>>[];
      for (final event in events) {
        final amount = _numberAsDouble(event['amount']);
        if (amount <= 0) continue;
        if (event['kind'] == 'credit') {
          unpaid.add({'date': event['date'], 'remaining': amount});
        } else {
          var payment = amount;
          for (final debt in unpaid) {
            if (payment <= 0) break;
            final remaining = _numberAsDouble(debt['remaining']);
            final applied = remaining < payment ? remaining : payment;
            debt['remaining'] = remaining - applied;
            payment -= applied;
          }
        }
      }
      var ledgerOpen = unpaid.fold<double>(
        0,
        (sum, debt) => sum + _numberAsDouble(debt['remaining']),
      );
      if (ledgerOpen < balance) {
        unpaid.add({
          'date': DateTime.now().toIso8601String(),
          'remaining': balance - ledgerOpen,
        });
      } else if (ledgerOpen > balance) {
        var excess = ledgerOpen - balance;
        for (final debt in unpaid) {
          if (excess <= 0) break;
          final remaining = _numberAsDouble(debt['remaining']);
          final applied = remaining < excess ? remaining : excess;
          debt['remaining'] = remaining - applied;
          excess -= applied;
        }
      }
      unpaid.removeWhere((debt) => _numberAsDouble(debt['remaining']) <= 0.000001);
      unpaid.sort((a, b) {
        final ad = DateTime.tryParse(a['date'].toString()) ?? DateTime.now();
        final bd = DateTime.tryParse(b['date'].toString()) ?? DateTime.now();
        return ad.compareTo(bd);
      });
      if (unpaid.isEmpty) continue;
      final oldestDate = DateTime.tryParse(unpaid.first['date'].toString());
      if (oldestDate == null || oldestDate.isAfter(cutoff)) continue;
      final dueDate = DateTime(oldestDate.year, oldestDate.month, oldestDate.day);
      final ageDays = DateTime.now().difference(dueDate).inDays;
      final overdue = <String, dynamic>{
        ...party,
        'oldest_due_date': dueDate.toIso8601String().substring(0, 10),
        'overdue_days': ageDays,
      };
      results.add(overdue);
      await db.transaction((txn) async {
        final inserted = await txn.insert(
          'khata_reminder_log',
          {
            'party_id': partyId,
            'oldest_due_date': overdue['oldest_due_date'],
            'created_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (inserted <= 0) return;
        final reminder = <String, dynamic>{
          'title': 'Khata overdue: ${party['name']}',
          'details': 'Outstanding Rs. ${balance.toStringAsFixed(2)} | '
              'Oldest unpaid credit: ${overdue['oldest_due_date']} | '
              '${ageDays} days overdue | Party ID: $partyId',
          'date': DateTime.now().toIso8601String().substring(0, 10),
          'is_done': 0,
          'sync_id': _newSyncId(),
        };
        await txn.insert('reminders', reminder);
        await _queueRow(txn, 'reminders', reminder);
      });
    }
    if (results.isNotEmpty) unawaited(syncPendingChanges());
    return results;
  }

  static Future<int> deleteParty(int id) async {
    final db = await database;
    final deleted = await db.transaction<int>((txn) async {
      final rows = await txn.query('parties', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return 0;
      final row = Map<String, dynamic>.from(rows.first);
      final partyType = row['type']?.toString();
      final references = partyType == 'customer'
          ? await txn.rawQuery(
              '''SELECT (SELECT COUNT(*) FROM sales WHERE customer_id = ?) +
                        (SELECT COUNT(*) FROM khata_transactions WHERE party_id = ?) AS count''',
              [id, id])
          : await txn.rawQuery('SELECT COUNT(*) AS count FROM purchases WHERE supplier_id = ?', [id]);
      final referenceCount = (references.first['count'] as num).toInt();
      final balance = (row['balance'] as num?)?.toDouble() ?? 0.0;
      if (referenceCount > 0 || balance.abs() > 0.000001) {
        throw Exception('Is account ki transaction history ya outstanding balance mojood hai. Ledger aur purane records mehfooz rakhne ke liye delete nahi kar sakte.');
      }
      final syncId = row['sync_id']?.toString();
      if (syncId != null && syncId.isNotEmpty) {
        await _recordDriveTombstone(txn, 'party', syncId);
        await _queueSync(txn, collection: 'parties', documentId: syncId, payload: {'sync_id': syncId, '_deleted': true});
      }
      return txn.delete('parties', where: 'id = ?', whereArgs: [id]);
    });
    unawaited(syncPendingChanges());
    return deleted;
  }

  static Future<void> updatePartyBalance(int id, double amount) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE parties SET balance = balance + ? WHERE id = ?',
        [amount, id],
      );
      final rows = await txn.query('parties', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isNotEmpty) await _queueRow(txn, 'parties', Map<String, dynamic>.from(rows.first));
    });
    unawaited(syncPendingChanges());
  }

  // Expense Operations

  static Future<int> insertExpense(Map<String, dynamic> expense) async {
    final db = await database;
    final data = Map<String, dynamic>.from(expense)..['sync_id'] = _newSyncId();
    final id = await db.transaction<int>((txn) async {
      final inserted = await txn.insert('expenses', data);
      await _queueRow(txn, 'expenses', data);
      return inserted;
    });
    unawaited(syncPendingChanges());
    return id;
  }

  static Future<List<Map<String, dynamic>>> getExpenses() async {
    final db = await database;
    return await db.query('expenses', orderBy: 'id DESC');
  }

  // Purchase / stock entry. Product stock and purchase history update atomically.
  static Future<int> recordPurchase({
    required int productId,
    required int quantity,
    required double unitCost,
    double? salePrice,
    int? supplierId,
  }) async {
    if (quantity <= 0 || unitCost < 0 || (salePrice != null && (!salePrice.isFinite || salePrice < 0))) {
      throw Exception('Quantity and cost must be valid.');
    }
    final db = await database;
    final purchaseId = await db.transaction<int>((txn) async {
      final rows = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      if (rows.isEmpty) throw Exception('Product not found.');
      final p = rows.first;
      final name = p['name'].toString();
      final barcode = p['barcode'].toString();
      if (salePrice == null) {
        await txn.rawUpdate(
          'UPDATE products SET quantity = quantity + ?, purchasePrice = ? WHERE id = ?',
          [quantity, unitCost, productId],
        );
      } else {
        await txn.rawUpdate(
          'UPDATE products SET quantity = quantity + ?, purchasePrice = ?, price = ? WHERE id = ?',
          [quantity, unitCost, salePrice, productId],
        );
      }
      final updatedRows = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      if (updatedRows.isNotEmpty) {
        final updatedProduct = Map<String, dynamic>.from(updatedRows.first)
          ..remove('id');
        await _queueSync(
          txn,
          collection: 'products',
          documentId: barcode,
          payload: updatedProduct,
        );
      }
      final supplierRows = supplierId == null
          ? <Map<String, Object?>>[]
          : await txn.query('parties', columns: ['sync_id'], where: 'id = ?', whereArgs: [supplierId], limit: 1);
      final purchase = <String, dynamic>{
        'product_id': productId,
        'product_name': name,
        'barcode': barcode,
        'quantity': quantity,
        'unit_cost': unitCost,
        'total_cost': quantity * unitCost,
        'supplier_id': supplierId,
        'supplier_sync_id': supplierRows.isEmpty ? null : supplierRows.first['sync_id'],
        'sync_id': _newSyncId(),
        'date': DateTime.now().toIso8601String().substring(0, 19),
      };
      final id = await txn.insert('purchases', purchase);
      await _queueRow(txn, 'purchases', purchase, remove: ['product_id', 'supplier_id']);
      return id;
    });
    unawaited(syncPendingChanges());
    return purchaseId;
  }

  // Atomically post a supplier invoice: stock, purchase rows and supplier
  // payable/payment ledger entries either all succeed or none are applied.
  static Future<String> recordPurchaseInvoice({
    required int supplierId,
    required String invoiceNumber,
    required String invoiceDate,
    required double invoiceTotal,
    double invoiceDiscount = 0,
    double invoiceTax = 0,
    required double paidAmount,
    required List<Map<String, dynamic>> items,
    String? invoiceImagePath,
  }) async {
    final normalizedInvoice = invoiceNumber.trim().toUpperCase();
    if (normalizedInvoice.isEmpty) throw Exception('Supplier invoice number zaroori hai.');
    if (!invoiceTotal.isFinite || invoiceTotal <= 0 ||
        !invoiceDiscount.isFinite || invoiceDiscount < 0 ||
        !invoiceTax.isFinite || invoiceTax < 0 ||
        !paidAmount.isFinite || paidAmount < 0 || paidAmount > invoiceTotal) {
      throw Exception('Invoice total aur paid amount valid enter karein.');
    }
    if (items.isEmpty) throw Exception('Invoice mein kam az kam aik item zaroori hai.');
    for (final item in items) {
      final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
      final unitCost = (item['unit_cost'] as num?)?.toDouble() ?? -1;
      if (quantity <= 0 || !unitCost.isFinite || unitCost < 0) {
        throw Exception('Har invoice item ki quantity aur purchase rate valid honi chahiye.');
      }
    }

    final rawLineTotals = items.map((item) {
      final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
      final unitCost = (item['unit_cost'] as num?)?.toDouble() ?? 0;
      return (item['line_total'] as num?)?.toDouble() ?? quantity * unitCost;
    }).toList();
    if (rawLineTotals.any((value) => !value.isFinite || value < 0)) {
      throw Exception('Invoice item amount valid nahi.');
    }
    final rawItemsTotal = rawLineTotals.fold<double>(0, (sum, value) => sum + value);
    final db = await database;
    final invoiceGroupId = _newSyncId();
    await db.transaction((txn) async {
      final supplierRows = await txn.query(
        'parties',
        where: "id = ? AND type = 'supplier'",
        whereArgs: [supplierId],
        limit: 1,
      );
      if (supplierRows.isEmpty) throw Exception('Selected supplier nahi mila.');
      final duplicate = await txn.query(
        'purchases',
        columns: ['id'],
        where: 'supplier_id = ? AND invoice_number = ?',
        whereArgs: [supplierId, normalizedInvoice],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw Exception('Ye supplier invoice pehle hi stock mein post ho chuka hai.');
      }

      final supplierSyncId = supplierRows.first['sync_id']?.toString();
      final now = DateTime.now().toIso8601String().substring(0, 19);
      final payable = invoiceTotal - paidAmount;

      for (var itemIndex = 0; itemIndex < items.length; itemIndex++) {
        final item = items[itemIndex];
        var productId = (item['product_id'] as num?)?.toInt();
        final quantity = (item['quantity'] as num).toInt();
        final unitCost = (item['unit_cost'] as num).toDouble();
        final salePrice = (item['sale_price'] as num?)?.toDouble();
        if (productId == null) {
          final newName = item['new_product_name']?.toString().trim() ?? '';
          final newBarcode = item['new_product_barcode']?.toString().trim() ?? '';
          if (newName.isEmpty || newBarcode.isEmpty) {
            throw Exception('Naye product ke liye name aur barcode dono zaroori hain.');
          }
          final duplicateBarcode = await txn.query(
            'products', columns: ['id'], where: 'barcode = ?', whereArgs: [newBarcode], limit: 1,
          );
          if (duplicateBarcode.isNotEmpty) {
            throw Exception('New product barcode $newBarcode pehle se inventory mein mojood hai.');
          }
          productId = await txn.insert('products', {
            'name': newName,
            'barcode': newBarcode,
            'price': salePrice ?? 0,
            'purchasePrice': unitCost,
            'wholesalePrice': 0,
            'damaged_quantity': 0,
            'quantity': 0,
            'is_active': 1,
          });
        }
        final productRows = await txn.query(
          'products', where: 'id = ?', whereArgs: [productId], limit: 1,
        );
        if (productRows.isEmpty) throw Exception('Invoice ka selected product inventory mein nahi mila.');
        final product = productRows.first;
        if (salePrice != null && (!salePrice.isFinite || salePrice < 0)) {
          throw Exception('Retail sale price valid nahi.');
        }
        final barcode = product['barcode']?.toString() ?? '';
        final rawLineTotal = rawLineTotals[itemIndex];
        final adjustedLineTotal = rawItemsTotal > 0
            ? rawLineTotal * invoiceTotal / rawItemsTotal
            : invoiceTotal / items.length;
        final effectiveUnitCost = adjustedLineTotal / quantity;
        if (salePrice == null) {
          await txn.rawUpdate(
            'UPDATE products SET quantity = quantity + ?, purchasePrice = ? WHERE id = ?',
            [quantity, effectiveUnitCost, productId],
          );
        } else {
          await txn.rawUpdate(
            'UPDATE products SET quantity = quantity + ?, purchasePrice = ?, price = ? WHERE id = ?',
            [quantity, effectiveUnitCost, salePrice, productId],
          );
        }
        final updated = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
        if (updated.isNotEmpty) {
          final payload = Map<String, dynamic>.from(updated.first)..remove('id');
          await _queueSync(txn, collection: 'products', documentId: barcode, payload: payload);
        }

        if (!adjustedLineTotal.isFinite || adjustedLineTotal < 0) {
          throw Exception('Invoice item total valid nahi.');
        }
        final purchase = <String, dynamic>{
          'product_id': productId,
          'product_name': product['name']?.toString() ?? 'Product',
          'barcode': barcode,
          'quantity': quantity,
          'unit_cost': unitCost,
          'total_cost': adjustedLineTotal,
          'supplier_id': supplierId,
          'supplier_sync_id': supplierSyncId,
          'sync_id': _newSyncId(),
          'date': now,
          'invoice_group_id': invoiceGroupId,
          'invoice_number': normalizedInvoice,
          'invoice_date': invoiceDate,
          'invoice_total': invoiceTotal,
          'invoice_discount': invoiceDiscount,
          'invoice_tax': invoiceTax,
          'invoice_paid_amount': paidAmount,
          'invoice_balance_due': payable,
          'invoice_image_path': invoiceImagePath,
          'unit_label': item['unit_label']?.toString().trim(),
        };
        await txn.insert('purchases', purchase);
        await _queueRow(txn, 'purchases', purchase,
          remove: ['product_id', 'supplier_id', 'invoice_image_path']);
      }

      await txn.rawUpdate(
        'UPDATE parties SET balance = COALESCE(balance, 0) + ? WHERE id = ?',
        [payable, supplierId],
      );
      final purchaseEntry = <String, dynamic>{
        'party_id': supplierId,
        'party_sync_id': supplierSyncId,
        'sync_id': _newSyncId(),
        'type': 'supplier_purchase',
        'amount': invoiceTotal,
        'note': 'Supplier invoice $normalizedInvoice',
        'date': now,
      };
      await txn.insert('khata_transactions', purchaseEntry);
      await _queueRow(txn, 'khata_transactions', purchaseEntry, remove: ['party_id']);

      if (paidAmount > 0) {
        final paymentEntry = <String, dynamic>{
          'party_id': supplierId,
          'party_sync_id': supplierSyncId,
          'sync_id': _newSyncId(),
          'type': 'supplier_payment',
          'amount': paidAmount,
          'note': 'Payment against supplier invoice $normalizedInvoice',
          'date': now,
        };
        await txn.insert('khata_transactions', paymentEntry);
        await _queueRow(txn, 'khata_transactions', paymentEntry, remove: ['party_id']);
      }
      final updatedSupplier = await txn.query('parties', where: 'id = ?', whereArgs: [supplierId], limit: 1);
      if (updatedSupplier.isNotEmpty) {
        await _queueRow(txn, 'parties', Map<String, dynamic>.from(updatedSupplier.first));
      }
    });
    unawaited(syncPendingChanges());
    return invoiceGroupId;
  }

  static Future<List<Map<String, dynamic>>> getPurchases() async {
    final db = await database;
    return db.query('purchases', orderBy: 'id DESC');
  }

  // A receipt reduces the customer balance exactly once and records the ledger entry.
  static Future<void> recordKhataReceipt({
    required int partyId,
    required double amount,
    String note = '',
  }) async {
    if (amount <= 0) {
      throw Exception('Receipt amount must be greater than zero.');
    }
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'parties',
        where: 'id = ? AND type = ?',
        whereArgs: [partyId, 'customer'],
        limit: 1,
      );
      if (rows.isEmpty) throw Exception('Customer not found.');
      final currentBalance = (rows.first['balance'] as num?)?.toDouble() ?? 0.0;
      if (currentBalance <= 0) {
        throw Exception('Is customer ke khate mein koi baqi raqam mojood nahi.');
      }
      if (amount > currentBalance + 0.000001) {
        throw Exception('Receipt baqi Khata balance (Rs. ${currentBalance.toStringAsFixed(2)}) se zyada nahi ho sakti.');
      }
      final partySyncId = rows.first['sync_id']?.toString();
      await txn.rawUpdate(
        'UPDATE parties SET balance = balance - ? WHERE id = ?',
        [amount, partyId],
      );
      final transaction = <String, dynamic>{
        'party_id': partyId,
        'party_sync_id': partySyncId,
        'sync_id': _newSyncId(),
        'type': 'receipt',
        'amount': amount,
        'note': note,
        'date': DateTime.now().toIso8601String().substring(0, 19),
      };
      await txn.insert('khata_transactions', transaction);
      await _queueRow(txn, 'khata_transactions', transaction, remove: ['party_id']);
      final updatedParty = await txn.query('parties', where: 'id = ?', whereArgs: [partyId], limit: 1);
      if (updatedParty.isNotEmpty) await _queueRow(txn, 'parties', Map<String, dynamic>.from(updatedParty.first));
    });
    unawaited(syncPendingChanges());
  }

  static Future<List<Map<String, dynamic>>> getKhataTransactions(
    int partyId,
  ) async {
    final db = await database;
    return db.query(
      'khata_transactions',
      where: 'party_id = ?',
      whereArgs: [partyId],
      orderBy: 'id DESC',
    );
  }

  // Complete customer ledger: credit purchases and cash receipts in one timeline.
  static Future<List<Map<String, dynamic>>> getCustomerHistory(int partyId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT * FROM (
        SELECT s.id AS entry_id, s.date AS date, 'sale' AS entry_type,
          CASE
            WHEN COALESCE(s.final_amount, 0) > 0 OR COALESCE(s.total_amount, 0) <= 0
              THEN COALESCE(s.final_amount, 0)
            WHEN COALESCE(s.discount, 0) > 0
              THEN MAX(s.total_amount - s.discount, 0)
            ELSE COALESCE(s.total_amount, 0)
          END AS amount,
          ('Bill #' || s.id || ' - ' || COALESCE((
            SELECT GROUP_CONCAT(product_name || ' x' || quantity, ', ')
            FROM sale_items WHERE sale_id = s.id
          ), 'Items unavailable')) AS description
        FROM sales s
        WHERE s.customer_id = ?
        UNION ALL
        SELECT k.id AS entry_id, k.date AS date, k.type AS entry_type,
          k.amount AS amount,
          CASE WHEN k.type = 'receipt'
            THEN 'Cash received' || CASE WHEN COALESCE(k.note, '') = '' THEN '' ELSE ' - ' || k.note END
            ELSE COALESCE(k.note, k.type) END AS description
        FROM khata_transactions k
        WHERE k.party_id = ? AND k.type NOT IN ('credit', 'return_adjustment')
        UNION ALL
        SELECT r.id AS entry_id, r.date AS date, 'return_adjustment' AS entry_type,
          r.refund_amount AS amount,
          ('Return against Bill #' || r.sale_id || ' - ' || r.reason) AS description
        FROM sale_returns r WHERE r.customer_id = ? AND r.refund_method = 'Khata'
      )
      ORDER BY date DESC, entry_id DESC
    ''', [partyId, partyId, partyId]);
  }

  static Future<Map<String, double>> getProfitLossSummary() async {
    final db = await database;
    final sales = await db.rawQuery('''
      SELECT
        COALESCE((SELECT SUM(
          CASE
            WHEN COALESCE(final_amount, 0) > 0 OR COALESCE(total_amount, 0) <= 0
              THEN COALESCE(final_amount, 0)
            WHEN COALESCE(discount, 0) > 0
              THEN MAX(total_amount - discount, 0)
            ELSE COALESCE(total_amount, 0)
          END
        ) FROM sales), 0)
        - COALESCE((SELECT SUM(refund_amount) FROM sale_returns), 0) AS revenue
    ''');
    final costs = await db.rawQuery('''
      SELECT
        COALESCE((SELECT SUM(cost_total) FROM sale_items), 0)
        - COALESCE((SELECT SUM(cost_total) FROM sale_return_items WHERE condition = 'saleable'), 0) AS cost
    ''');
    final expenses = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS expenses FROM expenses',
    );
    final revenue = (sales.first['revenue'] as num?)?.toDouble() ?? 0;
    final cost = (costs.first['cost'] as num?)?.toDouble() ?? 0;
    final expense = (expenses.first['expenses'] as num?)?.toDouble() ?? 0;
    return {
      'revenue': revenue,
      'cost': cost,
      'expenses': expense,
      'profit': revenue - cost - expense,
    };
  }

  // Reminder Operations

  static Future<int> insertReminder(Map<String, dynamic> reminder) async {
    final db = await database;
    final data = Map<String, dynamic>.from(reminder)..['sync_id'] = _newSyncId();
    final id = await db.transaction<int>((txn) async {
      final inserted = await txn.insert('reminders', data);
      await _queueRow(txn, 'reminders', data);
      return inserted;
    });
    unawaited(syncPendingChanges());
    return id;
  }

  // Draft bills are local working documents and never enter cloud sales sync.
  static Future<void> savePendingBill(Map<String, dynamic> bill) async {
    final billId = bill['bill_id']?.toString() ?? '';
    if (billId.isEmpty) throw Exception('Pending bill ID is missing.');
    final payload = Map<String, dynamic>.from(bill)
      ..remove('bill_id')
      ..remove('label');
    final db = await database;
    await db.insert(
      'pending_bills',
      {
        'bill_id': billId,
        'label': bill['label']?.toString() ?? 'Pending Bill',
        'payload': jsonEncode(payload),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getPendingBills() async {
    final db = await database;
    final rows = await db.query('pending_bills', orderBy: 'updated_at DESC');
    final bills = <Map<String, dynamic>>[];
    for (final row in rows) {
      try {
        final payload = jsonDecode(row['payload']?.toString() ?? '{}');
        if (payload is! Map) continue;
        bills.add({
          ...Map<String, dynamic>.from(payload),
          'bill_id': row['bill_id'].toString(),
          'label': row['label']?.toString() ?? 'Pending Bill',
          'updated_at': row['updated_at']?.toString(),
        });
      } catch (error) {
        developer.log('Skipping unreadable pending bill', name: 'DBHelper', error: error);
      }
    }
    return bills;
  }

  static Future<void> deletePendingBill(String billId) async {
    final db = await database;
    await db.delete('pending_bills', where: 'bill_id = ?', whereArgs: [billId]);
  }

  static Future<List<Map<String, dynamic>>> getReminders() async {
    final db = await database;
    return await db.query('reminders', orderBy: 'id DESC');
  }
}
