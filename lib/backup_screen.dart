import 'windows/desktop_app_bar.dart';
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

      // Close SQLite before touching the live database or its sidecar files.
      await DBHelper.closeDatabase();
      databaseClosed = true;

      // Keep a uniquely named safety copy before replacing the live database.
      if (await currentDb.exists()) {
        final safetyFile = File(safetyPath);
        if (await safetyFile.exists()) await safetyFile.delete();
        await currentDb.copy(safetyPath);
      }

      // A stale WAL/SHM file must never be applied to the restored database.
      for (final suffix in ['-wal', '-shm', '-journal']) {
        final sidecar = File('$dbPath$suffix');
        if (await sidecar.exists()) await sidecar.delete();
      }

      try {
        // Rename the validated staging file into place instead of copying
        // over an existing destination (which can fail with Windows errno 183).
        if (await currentDb.exists()) await currentDb.delete();
        await tempDb.rename(dbPath);
        tempPath = null;
      } catch (_) {
        // Restore the safety copy if the replacement did not complete.
        final safetyFile = File(safetyPath);
        if (await safetyFile.exists()) {
          if (await currentDb.exists()) await currentDb.delete();
          await safetyFile.copy(dbPath);
        }
        rethrow;
      }

      // Re-open and verify the restored database through the normal helper.
      try {
        await DBHelper.database;
        databaseClosed = false;
      } catch (_) {
        await DBHelper.closeDatabase();
        final safetyFile = File(safetyPath);
        if (await safetyFile.exists()) {
          if (await currentDb.exists()) await currentDb.delete();
          await safetyFile.copy(dbPath);
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
      if (mounted) setState(() => _isWorking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !Platform.isWindows,
        leading: desktopWorkspaceButton(),
        title: const Text('Backup & Restore'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Padding(
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
