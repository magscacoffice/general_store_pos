
import 'package:flutter/material.dart';

import 'drive_sync_service.dart';

class CloudSyncScreen extends StatefulWidget {
  const CloudSyncScreen({super.key});

  @override
  State<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends State<CloudSyncScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      await DriveSyncService.restoreStatus();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      await DriveSyncService.connectAndSync();
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DriveSyncService.status)),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google Drive connection failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect Google account?'),
        content: const Text('POS data local device par rahega aur verified local backup banega. Is database ke saath pehle se paired Gmail hi dobara connect ho sakta hai; disconnect karne se pairing remove nahi hoti. Isi store ke Android aur Windows devices par same Gmail use karein. Har doosray business ke liye separate clean POS database aur separate Gmail lazmi hai.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Backup & Disconnect')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await DriveSyncService.disconnect();
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Account disconnect nahi hua: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() async {
    setState(() => _busy = true);
    try {
      await DriveSyncService.syncNow();
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DriveSyncService.status)),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cloud sync could not complete: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud Sync'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh status',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.cloud_sync_outlined, size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Google Drive store sync', style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 4),
                            Text(DriveSyncService.status, style: Theme.of(context).textTheme.bodyMedium),
                            if (DriveSyncService.connectedAccountEmail != null)
                              Text('Connected Gmail: ${DriveSyncService.connectedAccountEmail}', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      if (_busy || DriveSyncService.isSyncing)
                        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ),
                  if (DriveSyncService.lastSyncAt != null) ...[
                    const SizedBox(height: 8),
                    Text('Last successful sync: ${DriveSyncService.lastSyncAt}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                  if (DriveSyncService.lastError != null) ...[
                    const SizedBox(height: 8),
                    Text(DriveSyncService.lastError!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : _connect,
                        icon: const Icon(Icons.link),
                        label: const Text('Connect Google Drive'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _sync,
                        icon: const Icon(Icons.sync),
                        label: const Text('Sync Now'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _disconnect,
                        icon: const Icon(Icons.link_off),
                        label: const Text('Disconnect / Switch Gmail'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How this sync works', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                    'Use the same Google account on Windows and Android. Windows is the master copy. Android first uploads its existing records for reconciliation; Windows imports missing sales, purchases, parties, receipts, expenses and returns by stable IDs. Before importing a new Android device snapshot, Windows automatically saves a separate local database safety copy. Product stock or customer-balance differences are held for review instead of being added together or silently overwritten. Once Windows approves the device snapshot, Android downloads the master copy.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Pending bills and local reminder-log entries remain on their own device. Both apps continue working offline; cloud changes wait until internet is available. On first Android pairing, existing Firebase business data is synchronized and its pending upload queue must be empty. After the first successful Google Drive sync, Drive becomes the only Android business-data sync provider. Firebase remains in use for sign-in/access checks and update notifications, not inventory, sales, purchases or Khata data. Android aur Windows dono par latest app version install karke sync karein; older sync-schema versions newer stock-unit data merge nahi kar sakte.',
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Android device data is safely uploaded first. Windows must process and approve the snapshot before its stock and account balances replace local values.',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
