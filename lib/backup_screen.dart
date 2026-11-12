import 'windows/desktop_app_bar.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:file_picker/file_picker.dart';
import 'db_helper.dart';
import 'windows/pos_windows.dart';

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
      final dbPath = await DBHelper.getDatabaseFilePath();
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
    String? tempPath;
    String? safetyPath;
    var databaseClosed = false;
    var cashierBillIds = <String>[];
    try {
      final pickedFile = await FilePicker.pickFile(type: FileType.any);
      if (pickedFile == null) return;
      final selectedPath = pickedFile.path;
      if (selectedPath == null) {
        throw Exception('Selected backup file ka path nahi mil saka.');
      }

      final selectedFile = File(selectedPath);
      if (!await selectedFile.exists() ||
          !selectedFile.path.toLowerCase().endsWith('.db')) {
        throw Exception('Please select a valid .db backup file.');
      }

      final dbDirectory = await DBHelper.getDatabaseDirectory();
      final dbPath = await DBHelper.getDatabaseFilePath();
      final currentDb = File(dbPath);
      final restoreId = '${DateTime.now().microsecondsSinceEpoch}_$pid';
      tempPath = p.join(dbDirectory, 'restore_validation_$restoreId.db');
      safetyPath = p.join(dbDirectory, 'before_restore_$restoreId.db');
      final tempDb = File(tempPath);

      // Always start with a new staging file; Windows rejects some copies
      // when the destination already exists.
      if (await tempDb.exists()) await tempDb.delete();
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

      // Ask every resident cashier window to close its SQLite connection first.
      // The dashboard then closes its own connection before replacing the file.
      if (Platform.isWindows) {
        cashierBillIds = await PosWindows.closeSaleWindowsForRestore();
      }
      await DBHelper.closeDatabase();
      databaseClosed = true;

      // Keep a uniquely named safety copy before replacing the live database.
      if (await currentDb.exists()) {
        final safetyFile = File(safetyPath);
        if (await safetyFile.exists()) await safetyFile.delete();
        await currentDb.copy(safetyPath);
      }

      // Never delete or rename the live database on Windows. Even after
      // closing our own SQLite handle, another process can retain a file lock.
      // Copy the verified backup to a fresh filename and atomically switch the
      // app's small active-database pointer instead.
      final restoredPath =
          p.join(dbDirectory, 'khan_baba_pos_restored_$restoreId.db');
      final restoredFile = File(restoredPath);
      if (await restoredFile.exists()) {
        throw FileSystemException('Restore destination already exists.', restoredPath);
      }
      await tempDb.copy(restoredPath);

      try {
        await DBHelper.setActiveDatabaseFilePath(restoredPath);
        await DBHelper.database;
        databaseClosed = false;
      } catch (_) {
        // Roll back to the original database pointer before surfacing the error.
        await DBHelper.closeDatabase();
        await DBHelper.setActiveDatabaseFilePath(dbPath);
        await DBHelper.database;
        databaseClosed = false;
        try {
          if (await restoredFile.exists()) await restoredFile.delete();
        } catch (_) {
          // A leftover, inactive restore candidate is harmless and can be
          // removed later; never risk the original database to clean it up.
        }
        rethrow;
      }

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
      // If validation or replacement failed after closing SQLite, make sure
      // the existing database is available again when possible.
      if (databaseClosed) {
        try {
          await DBHelper.database;
          databaseClosed = false;
        } catch (_) {
          // Preserve the original restore error for the user.
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Restore Error: $e')));
      }
    } finally {
      if (tempPath != null) {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
          try {
            await tempFile.delete();
          } catch (_) {}
        }
      }
      if (Platform.isWindows && cashierBillIds.isNotEmpty) {
        try {
          for (final billId in cashierBillIds) {
            await PosWindows.openSale(billId: billId);
          }
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Restore ke baad New Sale window dobara open nahi ho saki: $error')),
            );
          }
        }
      }
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Widget _buildWindowsBackupPanel() {
    Widget actionCard({
      required IconData icon,
      required String title,
      required String description,
      required VoidCallback onPressed,
      required bool restore,
    }) {
      return Expanded(
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 30, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 14),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Expanded(child: Text(description, style: Theme.of(context).textTheme.bodyMedium)),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: restore
                      ? OutlinedButton.icon(
                          onPressed: _isWorking ? null : onPressed,
                          icon: const Icon(Icons.restore),
                          label: const Text('Restore from File'),
                        )
                      : FilledButton.icon(
                          onPressed: _isWorking ? null : onPressed,
                          icon: const Icon(Icons.save_alt),
                          label: const Text('Save Backup'),
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Data Protection & Recovery', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Create a separate copy of your store database or restore a previously saved backup. The current database is preserved as a safety copy during restore.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                actionCard(
                  icon: Icons.backup_outlined,
                  title: 'Create Database Backup',
                  description: 'Save products, stock, sales, purchases, customers, khata transactions and expenses into a .db backup file. Keep the file on a separate drive or secure location.',
                  onPressed: _createBackup,
                  restore: false,
                ),
                const SizedBox(width: 14),
                actionCard(
                  icon: Icons.settings_backup_restore,
                  title: 'Restore Database Backup',
                  description: 'Select a valid Khan Baba POS .db backup. The file is checked before use and the current database is retained as a safety copy.',
                  onPressed: _restoreBackup,
                  restore: true,
                ),
              ],
            ),
          ),
          if (_isWorking) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 6),
            const Text('Please wait. Do not close the application while this operation is running.'),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !Platform.isWindows,
        leading: desktopWorkspaceButton(),
        title: const Text('Backup & Restore'),
        backgroundColor: Platform.isWindows ? const Color(0xFFF7F9FB) : Colors.teal,
        foregroundColor: Platform.isWindows ? const Color(0xFF263442) : Colors.white,
      ),
      body: Platform.isWindows
          ? _buildWindowsBackupPanel()
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Icon(Icons.backup, size: Platform.isWindows ? 24 : 60, color: Colors.teal),
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
