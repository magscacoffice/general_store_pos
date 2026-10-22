import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:file_picker/file_picker.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _isExporting = false;

  // Local Backup Export (Download folder / Selected location mein save karna)
  Future<void> _exportLocalBackup() async {
    setState(() => _isExporting = true);
    try {
      final dbPath = join(await getDatabasesPath(), 'khan_baba_pos.db');
      final dbFile = File(dbPath);

      if (!await dbFile.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Database file nahi mili!')),
          );
        }
        return;
      }

      // Folder select karne ke liye file picker
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory != null) {
        final now = DateTime.now();
        final fileName = 'khan_baba_pos_backup_${now.millisecondsSinceEpoch}.db';
        final newPath = p.join(selectedDirectory, fileName);

        await dbFile.copy(newPath);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Local Backup save ho gaya:\n$newPath')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup mein masla aya: $e')),
        );
      }
    } finally {
      setState(() => _isExporting = false);
    }
  }

  // Local Backup Restore (Purana backup file select karke data wapas lana)
  Future<void> _restoreLocalBackup() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();

      if (result != null && result.files.single.path != null) {
        final selectedFile = File(result.files.single.path!);

        if (!selectedFile.path.endsWith('.db')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Kripya sahi database (.db) file select karein!')),
            );
          }
          return;
        }

        final dbPath = join(await getDatabasesPath(), 'khan_baba_pos.db');

        // Existing db file ko replace karna
        await selectedFile.copy(dbPath);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Data kamyabi se Restore ho gaya! App restart karein.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore mein masla aya: $e')),
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
                    Icon(Icons.storage, size: 50, color: Colors.teal),
                    SizedBox(height: 10),
                    Text(
                      'Local Storage Backup',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Apne mobile me database ki backup file save karein ya purani file se data restore karein.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _isExporting ? null : _exportLocalBackup,
              icon: const Icon(Icons.download),
              label: const Text('Local Backup Banaein (Export)', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _restoreLocalBackup,
              icon: const Icon(Icons.upload),
              label: const Text('Local Backup Restore Karein (Import)', style: TextStyle(fontSize: 16)),
            ),
            const Divider(height: 40),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Icon(Icons.cloud_upload, size: 50, color: Colors.blue),
                    SizedBox(height: 10),
                    Text(
                      'Google Drive Backup',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Google Drive integration ke liye Google Cloud Console se API Key aur OAuth Config configure karna zaroori hota hai.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}