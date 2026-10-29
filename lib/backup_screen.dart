import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:file_picker/file_picker.dart';

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
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Backup kahan save karna hai?',
        fileName: fileName,
      );

      if (outputFile != null) {
        await dbFile.copy(outputFile);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Backup saved successfully!\nPath: $outputFile'),
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
      setState(() => _isWorking = false);
    }
  }

  // 2. File Picker ke zariye database restore karna
  Future<void> _restoreBackup() async {
    setState(() => _isWorking = true);
    try {
      // User se .db file select karwana
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        String filePath = result.files.single.path!;
        if (!filePath.endsWith('.db')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please select a valid .db backup file!'),
              ),
            );
          }
          return;
        }

        File selectedFile = File(filePath);
        String dbPath = p.join(await getDatabasesPath(), 'khan_baba_pos.db');
        await selectedFile.copy(dbPath);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Backup restored successfully! Please restart the app.',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Restore Error: $e')));
      }
    } finally {
      setState(() => _isWorking = false);
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
