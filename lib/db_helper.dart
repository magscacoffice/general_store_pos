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

  /// Pull shared inventory without replacing device-local SQLite primary keys
  /// or overwriting local product changes waiting in the sync outbox.
  static Future<void> syncProductsFromCloud() async {
    if (_isPullingProducts) return;
    _isPullingProducts = true;
    try {
      await syncPendingChanges();
      final snapshot = await _storeCollection('products').get();
      final db = await database;
      final pendingRows = await db.query(
        'sync_queue',
        columns: ['document_id'],
        where: 'collection_name = ?',
        whereArgs: ['products'],
      );
      final pendingBarcodes = pendingRows
          .map((row) => row['document_id'].toString())
          .toSet();

      await db.transaction((txn) async {
        for (final document in snapshot.docs) {
          final data = document.data();
          final barcode = (data['barcode'] ?? document.id).toString().trim();
          final name = (data['name'] ?? '').toString().trim();
          if (barcode.isEmpty || name.isEmpty ||
              pendingBarcodes.contains(barcode)) {
            continue;
          }

          // Never import a remote SQLite id; it is local to another device.
          final product = <String, dynamic>{
            'barcode': barcode,
            'name': name,
            'price': _numberAsDouble(data['price']),
            'purchasePrice': _numberAsDouble(data['purchasePrice']),
            'quantity': _numberAsInt(data['quantity']),
          };
          final existing = await txn.query(
            'products',
            columns: ['id'],
            where: 'barcode = ?',
            whereArgs: [barcode],
            limit: 1,
          );
          if (existing.isEmpty) {
            await txn.insert('products', product);
          } else {
            await txn.update(
              'products',
              product,
              where: 'barcode = ?',
              whereArgs: [barcode],
            );
          }
        }
      });
    } catch (e) {
      // Keep the app usable offline; retry at the next authenticated startup.
      developer.log('Firebase Inventory Pull Error',
          name: 'DBHelper', error: e);
    } finally {
      _isPullingProducts = false;
    }
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

        if (oldVersion < 7) {
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
    await executor.insert(
      'sync_queue',
      {
        'collection_name': collection,
        'document_id': documentId,
        'operation': operation,
        'payload': jsonEncode(payload),
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
        payload: {'barcode': barcode},
        operation: 'delete',
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

      // Save the sale in the same transaction.
      final id = await txn.insert('sales', saleData);

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
        await txn.insert('sale_items', {
          'sale_id': id,
          'product_id': product['id'],
          'barcode': barcode,
          'product_name': name,
          'quantity': qty,
          'sale_price': salePrice,
          'purchase_price': purchasePrice,
          'line_total': salePrice * qty,
          'cost_total': purchasePrice * qty,
        });
      }

      // Named-customer sales enter the ledger as a debit. Any cash collected
      // at checkout is recorded as a receipt so only the unpaid amount remains.
      final customerIdForLedger = saleData['customer_id'];
      if (customerIdForLedger != null) {
        await txn.insert('khata_transactions', {
          'party_id': customerIdForLedger,
          'type': 'credit',
          'amount': saleFinalAmount,
          'note': 'Sale #$id',
          'date': saleData['date'].toString(),
        });
        if (receivedAmount > 0) {
          await txn.insert('khata_transactions', {
            'party_id': customerIdForLedger,
            'type': 'receipt',
            'amount': receivedAmount,
            'note': 'Cash received at sale #$id',
            'date': saleData['date'].toString(),
          });
        }
        await txn.rawUpdate(
          'UPDATE parties SET balance = balance + ? WHERE id = ?',
          [balanceDue, customerIdForLedger],
        );
      }

      return id;
    });

    // Stock changes were queued atomically with the local sale.
    await syncPendingChanges();

    // Sync the sale to Firebase.
    try {
      await _storeCollection('sales').add(sale);
    } catch (e) {
      developer.log('Firebase Sales Sync Error', name: 'DBHelper', error: e);
    }

    return saleId;
  }

  // Sales Operations + Firebase Sync

  static Future<int> insertSale(Map<String, dynamic> sale) async {
    final db = await database;
    final result = await db.insert('sales', sale);

    try {
      await _storeCollection('sales').add(sale);
    } catch (e) {
      developer.log('Firebase Sales Sync Error', name: 'DBHelper', error: e);
    }

    return result;
  }

  static Future<List<Map<String, dynamic>>> getSales() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT s.*,
        COALESCE((SELECT SUM(refund_amount) FROM sale_returns r WHERE r.sale_id = s.id), 0) AS returned_amount
      FROM sales s ORDER BY s.id DESC
    ''');
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
    final db = await database;
    return db.transaction<int>((txn) async {
      final saleRows = await txn.query('sales', where: 'id = ?', whereArgs: [saleId], limit: 1);
      if (saleRows.isEmpty) throw Exception('Original invoice nahi mila.');
      final sale = saleRows.first;
      final customerId = sale['customer_id'] as int?;
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
          throw Exception('Return quantity sold quantity se zyada hai: ${item['product_name']}');
        }
        final salePrice = (item['sale_price'] as num).toDouble();
        final purchasePrice = (item['purchase_price'] as num).toDouble();
        final condition = request['condition'] == 'damaged' ? 'damaged' : 'saleable';
        final lineTotal = salePrice * quantity;
        grossTotal += lineTotal;
        selected.add({
          'sale_item_id': saleItemId,
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
                ? ((sale['final_amount'] as num?)?.toDouble() ?? 0.0)
                : 0.0);
        if (alreadyRefunded + refundAmount > received) {
          throw Exception('Cash refund received cash se zyada hai. Khata adjustment select karein.');
        }
      }
      final date = DateTime.now().toIso8601String().substring(0, 19);
      final id = await txn.insert('sale_returns', {
        'sale_id': saleId,
        'customer_id': customerId,
        'reason': reason.trim(),
        'refund_method': refundMethod,
        'refund_amount': refundAmount,
        'date': date,
      });
      for (final item in selected) {
        await txn.insert('sale_return_items', {'return_id': id, ...item});
        final productId = item['product_id'];
        if (productId != null) {
          if (item['condition'] == 'saleable') {
            await txn.rawUpdate('UPDATE products SET quantity = quantity + ? WHERE id = ?', [item['quantity'], productId]);
          } else {
            await txn.rawUpdate('UPDATE products SET damaged_quantity = COALESCE(damaged_quantity, 0) + ? WHERE id = ?', [item['quantity'], productId]);
          }
        }
      }
      if (refundMethod == 'Khata' && customerId != null && refundAmount > 0) {
        await txn.rawUpdate('UPDATE parties SET balance = balance - ? WHERE id = ?', [refundAmount, customerId]);
        await txn.insert('khata_transactions', {
          'party_id': customerId,
          'type': 'return_adjustment',
          'amount': refundAmount,
          'note': 'Return #$id against Bill #$saleId',
          'date': date,
        });
      }
      return id;
    });
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
    final result = await db.insert('parties', party);

    try {
      await _storeCollection('parties').add(party);
    } catch (e) {
      developer.log('Firebase Party Sync Error', name: 'DBHelper', error: e);
    }

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

    return await db.delete('parties', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> updatePartyBalance(int id, double amount) async {
    final db = await database;

    await db.rawUpdate(
      'UPDATE parties SET balance = balance + ? WHERE id = ?',
      [amount, id],
    );
  }

  // Expense Operations

  static Future<int> insertExpense(Map<String, dynamic> expense) async {
    final db = await database;
    return await db.insert('expenses', expense);
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
      return txn.insert('purchases', {
        'product_id': productId,
        'product_name': name,
        'barcode': barcode,
        'quantity': quantity,
        'unit_cost': unitCost,
        'total_cost': quantity * unitCost,
        'supplier_id': supplierId,
        'date': DateTime.now().toIso8601String().substring(0, 19),
      });
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
      await txn.rawUpdate(
        'UPDATE parties SET balance = balance - ? WHERE id = ?',
        [amount, partyId],
      );
      await txn.insert('khata_transactions', {
        'party_id': partyId,
        'type': 'receipt',
        'amount': amount,
        'note': note,
        'date': DateTime.now().toIso8601String().substring(0, 19),
      });
    });
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
          COALESCE(s.final_amount, s.total_amount, 0) AS amount,
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
        WHERE k.party_id = ?
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
        COALESCE((SELECT SUM(CASE WHEN final_amount > 0 THEN final_amount ELSE total_amount END) FROM sales), 0)
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
    return await db.insert('reminders', reminder);
  }

  static Future<List<Map<String, dynamic>>> getReminders() async {
    final db = await database;
    return await db.query('reminders', orderBy: 'id DESC');
  }
}
