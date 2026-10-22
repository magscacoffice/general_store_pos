import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _isExporting = false;

  // Direct Internal/Public Download Folder mein Backup save karna
  Future<void> _createBackup() async {
    setState(() => _isExporting = true);
    try {
      final dbPath = p.join(await getDatabasesPath(), 'khan_baba_pos.db');
      final dbFile = File(dbPath);

      if (!await dbFile.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Database file nahi mili!')),
          );
        }
        return;
      }

      // Android ke public download directory ka rasta
      final targetDir = Directory('/storage/emulated/0/Download');
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final now = DateTime.now();
      final fileName = 'khan_baba_backup_${now.year}${now.month}${now.day}_${now.hour}${now.minute}.db';
      final savedPath = p.join(targetDir.path, fileName);

      await dbFile.copy(savedPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup Downloads folder mein save ho gaya!\nPath: $savedPath')),
        );
      }
    } catch (e) {
      // Agar direct path mein masla ho toh app ke apne documents folder mein save kar lein
      try {
        final dbPath = p.join(await getDatabasesPath(), 'khan_baba_pos.db');
        final dbFile = File(dbPath);
        
        final backupDir = Directory('/storage/emulated/0/Android/data/com.example.khan_baba_general_store/files');
        if (!await backupDir.exists()) {
          await backupDir.create(recursive: true);
        }
        
        final savedPath = p.join(backupDir.path, 'khan_baba_pos.db');
        await dbFile.copy(savedPath);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Backup save ho gaya:\n$savedPath')),
          );
        }
      } catch (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Backup error: $err')),
          );
        }
      }
    } finally {
      setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Backup'),
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
                      'One-Click Database Backup',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Neeche diye gaye button par click karke apne dukan ka sara data (Sales, Inventory, Customers, Expenses) apne phone ke Download folder mein mehfooz kar lein.',
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
              onPressed: _isExporting ? null : _createBackup,
              icon: const Icon(Icons.download, size: 24),
              label: const Text('Backup Download Karein', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}