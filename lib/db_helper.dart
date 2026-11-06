import 'dart:convert';
import 'dart:math' as math;
import 'dart:developer' as developer;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DBHelper {
  static Database? _db;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _storeId = 'khan-baba-general-store';

  static CollectionReference<Map<String, dynamic>> _storeCollection(
    String name,
  ) {
    return _firestore.collection('stores').doc(_storeId).collection(name);
  }

  static bool _isPullingProducts = false;

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
        final customerType = customerId == null
            ? 'Walk-in'
            : (row['customer_type']?.toString() == 'Wholesale'
                ? 'Wholesale'
                : 'Khata');
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
        values['customer_type'] ??= 'Khata';
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
    if (_isSyncingAll) return;
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
    }
  }

  static Future<void> syncProductsFromCloud() => syncAllData();

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

  static Future<Database> initDB() async {
    final path = join(await getDatabasesPath(), 'khan_baba_pos.db');

    return await openDatabase(
      path,
      version: 8,
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
            quantity INTEGER NOT NULL
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
          date TEXT NOT NULL
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
      },
      onUpgrade: (db, oldVersion, newVersion) async {
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
          await ref.delete();
        } else {
          final decoded = jsonDecode(row['payload'].toString());
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('Invalid sync payload.');
          }
          await ref.set(decoded, SetOptions(merge: true));
        }
        await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
      } catch (e) {
        await db.rawUpdate(
          'UPDATE sync_queue SET attempts = attempts + 1, last_error = ? WHERE id = ?',
          [e.toString(), id],
        );
      }
    }
  }

  // Product Operations + Firebase Sync

  static Future<int> insertProduct(Map<String, dynamic> product) async {
    final db = await database;

    final result = await db.transaction<int>((txn) async {
      final inserted = await txn.insert(
        'products',
        product,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _queueSync(
        txn,
        collection: 'products',
        documentId: product['barcode'].toString(),
        payload: product,
      );
      return inserted;
    });
    await syncPendingChanges();
    return result;
  }

  static Future<int> updateProduct(
    int id,
    Map<String, dynamic> product,
  ) async {
    final db = await database;

    final result = await db.transaction<int>((txn) async {
      final updated = await txn.update(
        'products',
        product,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (updated == 0) {
        throw Exception('Product not found. Please refresh and try again.');
      }
      await _queueSync(
        txn,
        collection: 'products',
        documentId: product['barcode'].toString(),
        payload: product,
      );
      return updated;
    });
    await syncPendingChanges();
    return result;
  }

  static Future<List<Map<String, dynamic>>> getProducts() async {
    final db = await database;
    return await db.query('products', orderBy: 'id DESC');
  }

  static Future<int> deleteProduct(int id) async {
    final db = await database;
    final deleted = await db.transaction<int>((txn) async {
      final rows = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return 0;
      final barcode = rows.first['barcode'].toString();
      await _queueSync(
        txn,
        collection: 'products',
        documentId: barcode,
        payload: {'barcode': barcode, '_deleted': true},
      );
      return txn.delete('products', where: 'id = ?', whereArgs: [id]);
    });
    await syncPendingChanges();
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
    final customerType = (saleData['customer_type'] ??
            (customerId == null ? 'Walk-in' : 'Khata'))
        .toString();
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

        // Newly arrived goods may be sold before the stock entry is recorded.
        // Add only the shortage, then the normal sale deduction consumes it.
        if (stock < requestedQuantity) {
          final shortage = requestedQuantity - stock;
          await txn.rawUpdate(
            'UPDATE products SET quantity = quantity + ? WHERE barcode = ?',
            [shortage, barcode],
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

    await syncPendingChanges();
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
    await syncPendingChanges();
    return result;
  }

  static Future<List<Map<String, dynamic>>> getSales() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT s.*,
        COALESCE((SELECT SUM(refund_amount) FROM sale_returns r WHERE r.sale_id = s.id), 0) AS returned_amount
      FROM sales s ORDER BY s.id DESC
    ''');
    return rows.map((row) {
      final sale = Map<String, dynamic>.from(row);
      sale['effective_amount'] = _effectiveSaleAmount(sale);
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
        final received = (sale['received_amount'] as num?)?.toDouble() ??
            ((sale['payment_type']?.toString() ?? 'Khata') == 'Cash'
                ? _effectiveSaleAmount(sale)
                : 0.0);
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
    await syncPendingChanges();
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
    final data = Map<String, dynamic>.from(party)
      ..['sync_id'] = _newSyncId()
      ..['customer_type'] ??= 'Khata';
    final result = await db.transaction<int>((txn) async {
      final id = await txn.insert('parties', data);
      await _queueRow(txn, 'parties', data);
      return id;
    });
    await syncPendingChanges();
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

  static Future<int> deleteParty(int id) async {
    final db = await database;
    final deleted = await db.transaction<int>((txn) async {
      final rows = await txn.query('parties', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return 0;
      final row = Map<String, dynamic>.from(rows.first);
      final syncId = row['sync_id']?.toString();
      if (syncId != null && syncId.isNotEmpty) {
        await _queueSync(txn, collection: 'parties', documentId: syncId,
            payload: {'sync_id': syncId, '_deleted': true});
      }
      return txn.delete('parties', where: 'id = ?', whereArgs: [id]);
    });
    await syncPendingChanges();
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
    await syncPendingChanges();
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
    await syncPendingChanges();
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
    int? supplierId,
  }) async {
    if (quantity <= 0 || unitCost < 0) {
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
      await txn.rawUpdate(
        'UPDATE products SET quantity = quantity + ?, purchasePrice = ? WHERE id = ?',
        [quantity, unitCost, productId],
      );
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
    await syncPendingChanges();
    return purchaseId;
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
    await syncPendingChanges();
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
    await syncPendingChanges();
    return id;
  }

  static Future<List<Map<String, dynamic>>> getReminders() async {
    final db = await database;
    return await db.query('reminders', orderBy: 'id DESC');
  }
}
