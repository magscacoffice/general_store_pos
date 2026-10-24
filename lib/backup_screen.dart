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
  bool _isWorking = false;

  // 1. Download folder mein backup save karna
  Future<void> _createBackup() async {
    setState(() => _isWorking = true);
    try {
      final dbPath = p.join(await getDatabasesPath(), 'khan_baba_pos.db');
      final dbFile = File(dbPath);

      if (!await dbFile.exists()) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Database file nahi mili!')));
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isWorking = false);
    }
  }

  // 2. Download folder se database restore karna
  Future<void> _restoreBackup() async {
    setState(() => _isWorking = true);
    try {
      final targetDir = Directory('/storage/emulated/0/Download');
      if (!await targetDir.exists()) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download folder nahi mila!')));
        return;
      }

      // Download folder ki .db files dhundna
      List<FileSystemEntity> files = targetDir.listSync();
      List<File> backupFiles = files.where((element) => element.path.endsWith('.db')).map((e) => File(e.path)).toList();

      if (backupFiles.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Downloads mein koi backup file nahi mili!')));
        return;
      }

      // Sab se latest backup file select karna (Syntax fixed here)
      backupFiles.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      File latestBackup = backupFiles.first;

      String dbPath = p.join(await getDatabasesPath(), 'khan_baba_pos.db');
      await latestBackup.copy(dbPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup kamyabi se restore ho gaya! App restart karein.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restore Error: $e')));
    } finally {
      setState(() => _isWorking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore'), backgroundColor: Colors.teal, foregroundColor: Colors.white),
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
                    Text('Database Backup & Restore', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    SizedBox(height: 10),
                    Text(
                      'Apna sara data phone ke Download folder mein save karein ya wahin se restore karein.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _isWorking ? null : _createBackup,
              icon: const Icon(Icons.download, size: 24),
              label: const Text('Backup Download Karein', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 15),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), foregroundColor: Colors.teal),
              onPressed: _isWorking ? null : _restoreBackup,
              icon: const Icon(Icons.restore, size: 24),
              label: const Text('Downloads Se Restore Karein', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}