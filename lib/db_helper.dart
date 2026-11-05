import 'dart:convert';
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
      version: 6,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            barcode TEXT UNIQUE NOT NULL,
            price REAL NOT NULL,
            purchasePrice REAL DEFAULT 0.0,
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
            date TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE parties(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT NOT NULL,
            type TEXT NOT NULL,
            balance REAL DEFAULT 0.0
          )
        ''');

        await db.execute('''
          CREATE TABLE expenses(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            amount REAL NOT NULL,
            date TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE reminders(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            details TEXT,
            date TEXT NOT NULL,
            is_done INTEGER DEFAULT 0
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
          cost_total REAL NOT NULL
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
          date TEXT NOT NULL
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
      final id = await txn.insert('sales', sale);

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

      // Record credit sale in the ledger; balance update remains in this transaction.
      final customerIdForLedger = sale['customer_id'];
      if (customerIdForLedger != null) {
        await txn.insert('khata_transactions', {
          'party_id': customerIdForLedger,
          'type': 'credit',
          'amount': (sale['final_amount'] as num?)?.toDouble() ?? 0.0,
          'note': 'Credit sale #$id',
          'date': sale['date'].toString(),
        });
      }

      // Update customer balance for credit/Khata sales.
      final customerId = sale['customer_id'];

      if (customerId != null) {
        final finalAmount = (sale['final_amount'] as num?)?.toDouble() ?? 0.0;

        await txn.rawUpdate(
          'UPDATE parties '
          'SET balance = balance + ? WHERE id = ?',
          [finalAmount, customerId],
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
    return await db.query('sales', orderBy: 'id DESC');
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
      )
      ORDER BY date DESC, entry_id DESC
    ''', [partyId, partyId]);
  }

  static Future<Map<String, double>> getProfitLossSummary() async {
    final db = await database;
    final sales = await db.rawQuery(
      "SELECT COALESCE(SUM(final_amount), SUM(total_amount), 0) AS revenue FROM sales",
    );
    final costs = await db.rawQuery(
      'SELECT COALESCE(SUM(cost_total), 0) AS cost FROM sale_items',
    );
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
