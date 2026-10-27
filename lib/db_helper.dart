import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await initDB();
    return _db!;
  }

  static Future<Database> initDB() async {
    String path = join(await getDatabasesPath(), 'khan_baba_pos.db');
    return await openDatabase(
      path,
      version: 3, // Version ko 3 kar diya hai taaki naye tables aur columns upgrade ho sakein
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
          // Purane products table mein agar purchasePrice nahi hai toh add kar do
          try {
            await db.execute('ALTER TABLE products ADD COLUMN purchasePrice REAL DEFAULT 0.0');
          } catch (_) {}
          
          // Sales table mein discount aur final_amount ke columns add karna
          try {
            await db.execute('ALTER TABLE sales ADD COLUMN discount REAL DEFAULT 0.0');
            await db.execute('ALTER TABLE sales ADD COLUMN final_amount REAL DEFAULT 0.0');
            await db.execute('ALTER TABLE sales ADD COLUMN payment_type TEXT DEFAULT "Cash"');
            await db.execute('ALTER TABLE sales ADD COLUMN customer_id INTEGER');
          } catch (_) {}

          // Reminders table create karna agar na ho
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
      },
    );
  }

  // Product Operations
  static Future<int> insertProduct(Map<String, dynamic> product) async {
    final db = await database;
    return await db.insert('products', product, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Map<String, dynamic>>> getProducts() async {
    final db = await database;
    return await db.query('products', orderBy: 'id DESC');
  }

  static Future<int> deleteProduct(int id) async {
    final db = await database;
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  // Sales Operations
  static Future<int> insertSale(Map<String, dynamic> sale) async {
    final db = await database;
    return await db.insert('sales', sale);
  }

  static Future<List<Map<String, dynamic>>> getSales() async {
    final db = await database;
    return await db.query('sales', orderBy: 'id DESC');
  }

  // Party Operations (Customers & Suppliers)
  static Future<int> insertParty(Map<String, dynamic> party) async {
    final db = await database;
    return await db.insert('parties', party);
  }

  static Future<List<Map<String, dynamic>>> getParties(String type) async {
    final db = await database;
    return await db.query('parties', where: 'type = ?', whereArgs: [type], orderBy: 'id DESC');
  }

  static Future<int> deleteParty(int id) async {
    final db = await database;
    return await db.delete('parties', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> updatePartyBalance(int id, double amount) async {
    final db = await database;
    await db.rawUpdate('UPDATE parties SET balance = balance + ? WHERE id = ?', [amount, id]);
  }

  // Expense Operations (Kharcha)
  static Future<int> insertExpense(Map<String, dynamic> expense) async {
    final db = await database;
    return await db.insert('expenses', expense);
  }

  static Future<List<Map<String, dynamic>>> getExpenses() async {
    final db = await database;
    return await db.query('expenses', orderBy: 'id DESC');
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