import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:file_picker/file_picker.dart';
import 'db_helper.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _isWorking = false;

  // 1. Backup file save karna (File Picker ke zariye user ki marzi ki jagah par)
  Future<void> _createBackup() async {
    setState(() => _isWorking = true);
    try {
      final dbPath = p.join(await getDatabasesPath(), 'khan_baba_pos.db');
      final dbFile = File(dbPath);

      if (!await dbFile.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Database file not found!')),
          );
        }
        return;
      }

      final now = DateTime.now();
      final fileName =
          'khan_baba_backup_${now.year}${now.month}${now.day}_${now.hour}${now.minute}.db';

      // User ko folder choose karne ki ijazat dena
      // Android/iOS par saveFile ko bytes dena zaroori hota hai.
      final backupBytes = await dbFile.readAsBytes();
      final outputFile = await FilePicker.saveFile(
        dialogTitle: 'Backup kahan save karna hai?',
        fileName: fileName,
        bytes: backupBytes,
      );

      if (outputFile != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Backup saved successfully!\nPath: $outputFile'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  // Restore only a verified database, keeping a safety copy of current data.
  Future<void> _restoreBackup() async {
    setState(() => _isWorking = true);
    try {
      // Android document providers may reject custom filters for .db files.
      // Let the user choose any file, then validate the extension and SQLite
      // database contents below before touching the live database.
      final result = await FilePicker.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result.isEmpty) return;
      final selectedPath = result.single.path;
      if (selectedPath == null) {
        throw Exception('Selected backup file ka path nahi mil saka.');
      }

      final selectedFile = File(selectedPath);
      if (!await selectedFile.exists() ||
          !selectedFile.path.toLowerCase().endsWith('.db')) {
        throw Exception('Please select a valid .db backup file.');
      }

      final dbDirectory = await getDatabasesPath();
      final dbPath = p.join(dbDirectory, 'khan_baba_pos.db');
      final currentDb = File(dbPath);
      final tempPath = p.join(
        dbDirectory,
        'restore_validation_${DateTime.now().microsecondsSinceEpoch}.db',
      );
      final tempDb = File(tempPath);

      // Copy first and validate the selected file without touching live data.
      await selectedFile.copy(tempPath);
      Database? validationDb;
      try {
        validationDb = await openDatabase(tempPath, readOnly: true);
        final integrity = await validationDb.rawQuery('PRAGMA integrity_check');
        final integrityResult = integrity.isNotEmpty
            ? integrity.first.values.first.toString().toLowerCase()
            : '';
        if (integrityResult != 'ok') {
          throw Exception('Backup file database integrity check failed.');
        }

        final tables = await validationDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        );
        final tableNames = tables.map((row) => row['name'].toString()).toSet();
        const requiredTables = {
          'products',
          'sales',
          'parties',
          'expenses',
          'purchases',
          'sale_items',
          'khata_transactions',
        };
        if (!tableNames.containsAll(requiredTables)) {
          throw Exception('Selected file is not a valid app backup.');
        }
      } finally {
        await validationDb?.close();
      }

      // Preserve the current database before replacing it.
      final now = DateTime.now();
      final safetyPath = p.join(
        dbDirectory,
        'before_restore_${now.millisecondsSinceEpoch}.db',
      );
      if (await currentDb.exists()) {
        await DBHelper.closeDatabase();
        await currentDb.copy(safetyPath);
      } else {
        await DBHelper.closeDatabase();
      }

      try {
        await tempDb.copy(dbPath);
      } catch (_) {
        // Roll back automatically if replacing the database fails.
        final safetyFile = File(safetyPath);
        if (await safetyFile.exists()) {
          await safetyFile.copy(dbPath);
        }
        rethrow;
      } finally {
        if (await tempDb.exists()) await tempDb.delete();
      }

      // Re-open using the app's normal database helper and confirm it is readable.
      await DBHelper.database;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Restore successful. Previous data backup: ${p.basename(safetyPath)}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup & Restore'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Icon(Icons.backup, size: 60, color: Colors.teal),
                    SizedBox(height: 15),
                    Text(
                      'Database Backup & Restore',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Back up all your data and restore it whenever needed.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _isWorking ? null : _createBackup,
              icon: const Icon(Icons.download, size: 24),
              label: const Text('Save Backup', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 15),
            OutlinedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                foregroundColor: Colors.teal,
              ),
              onPressed: _isWorking ? null : _restoreBackup,
              icon: const Icon(Icons.restore, size: 24),
              label: const Text(
                'Restore from File',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
