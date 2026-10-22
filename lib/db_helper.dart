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
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            barcode TEXT UNIQUE NOT NULL,
            price REAL NOT NULL,
            quantity INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE sales(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            total_amount REAL NOT NULL,
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

  // Expense Operations (Kharcha)
  static Future<int> insertExpense(Map<String, dynamic> expense) async {
    final db = await database;
    return await db.insert('expenses', expense);
  }

  static Future<List<Map<String, dynamic>>> getExpenses() async {
    final db = await database;
    return await db.query('expenses', orderBy: 'id DESC');
  }
}