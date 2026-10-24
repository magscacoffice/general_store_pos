import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _isWorking = false;

  // 1. Google Drive / External Apps par Backup Share karna
  Future<void> _backupAndShare() async {
    setState(() => _isWorking = true);
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

      // System share sheet khule gi jahan se Google Drive par direct save kar sakte hain
      await Share.shareXFiles(
        [XFile(dbFile.path)],
        text: 'Khan Baba POS Database Backup (.db)',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup Error: $e')),
        );
      }
    } finally {
      setState(() => _isWorking = false);
    }
  }

  // 2. Mobile ke Downloads folder mein local backup save karna
  Future<void> _createLocalBackup() async {
    setState(() => _isWorking = true);
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Local Backup Error: $e')),
        );
      }
    } finally {
      setState(() => _isWorking = false);
    }
  }

  // 3. Purana Backup File Chun Kar Restore Karna
  Future<void> _restoreDatabase() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        File backupFile = File(result.files.single.path!);
        String dbPath = p.join(await getDatabasesPath(), 'khan_baba_pos.db');

        // Current database ko backup file se replace karna
        await backupFile.copy(dbPath);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Database kamyabi se restore ho gaya! App restart karein.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Backup & Restore'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Card(
              elevation: 3,
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Icon(Icons.cloud_sync, size: 60, color: Colors.teal),
                    SizedBox(height: 15),
                    Text(
                      'Cloud Backup & Data Restore',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Apne dukan ka sara data (Sales, Stock, Khata) Google Drive par mehfooz karein ya purana data wapas restore karein.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 25),

            // Option 1: Google Drive / Share Sheet
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _isWorking ? null : _backupAndShare,
              icon: const Icon(Icons.add_to_drive, size: 24),
              label: const Text('Google Drive Par Backup Save Karein', style: TextStyle(fontSize: 16)),
            ),

            const SizedBox(height: 12),

            // Option 2: Mobile Download Folder
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                foregroundColor: Colors.teal,
              ),
              onPressed: _isWorking ? null : _createLocalBackup,
              icon: const Icon(Icons.download_for_offline, size: 24),
              label: const Text('Mobile Download Folder Mein Save Karein', style: TextStyle(fontSize: 16)),
            ),

            const SizedBox(height: 25),
            const Divider(),
            const SizedBox(height: 15),

            // Option 3: Restore Database
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[800],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _isWorking ? null : _restoreDatabase,
              icon: const Icon(Icons.settings_backup_restore, size: 24),
              label: const Text('Purana Backup Restore Karein', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}