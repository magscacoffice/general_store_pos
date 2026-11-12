import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'db_helper.dart';
import 'drive_sync_service.dart';
import 'windows/desktop_app_bar.dart';

class CloudSyncScreen extends StatefulWidget {
  const CloudSyncScreen({super.key});

  @override
  State<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends State<CloudSyncScreen> {
  bool _busy = false;
  List<Map<String, dynamic>> _conflicts = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      await DriveSyncService.restoreStatus();
    } catch (_) {}
    final conflicts = Platform.isWindows
        ? await DBHelper.getDriveSyncConflicts()
        : <Map<String, dynamic>>[];
    if (!mounted) return;
    setState(() => _conflicts = conflicts);
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

  Future<void> _resolve(Map<String, dynamic> conflict, bool useRemote) async {
    if (useRemote) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirm reconciliation'),
          content: Text(
            conflict['entity_type'].toString().endsWith('_delete')
                ? 'This will delete this product or party from the Windows master. Existing stock, balances or transaction history may prevent deletion. Continue?'
                : conflict['entity_type'].toString().endsWith('_readd')
                    ? 'This will restore the product or party that was deleted on Windows, using the other device record. Continue?'
                    : 'This will replace the Windows product stock/prices or customer account details with the other device values. This is a manual choice and cannot be undone automatically. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                conflict['entity_type'].toString().endsWith('_delete')
                    ? 'Delete on Windows'
                    : conflict['entity_type'].toString().endsWith('_readd')
                        ? 'Restore Other Device'
                        : 'Use Other Device',
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _busy = true);
    try {
      await DBHelper.resolveDriveSyncConflict(
        (conflict['id'] as num).toInt(),
        useRemote: useRemote,
      );
      await DriveSyncService.syncNow();
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Conflict resolve nahi ho saka: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _decode(String? value) {
    try {
      final decoded = jsonDecode(value ?? '{}');
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  Widget _conflictCard(Map<String, dynamic> conflict) {
    final local = _decode(conflict['local_payload']?.toString());
    final remote = _decode(conflict['remote_payload']?.toString());
    final entityType = conflict['entity_type']?.toString() ?? '';
    final isProduct = entityType.startsWith('product');
    final isDelete = entityType.endsWith('_delete');
    final isReadd = entityType.endsWith('_readd');
    final key = conflict['entity_key']?.toString() ?? '';
    final title = isDelete
        ? (isProduct ? 'Product deletion conflict' : 'Party deletion conflict')
        : isReadd
            ? (isProduct ? 'Product restore conflict' : 'Party restore conflict')
            : (isProduct ? 'Product stock / details conflict' : 'Customer / party details conflict');
    final localSummary = isReadd
        ? 'Deleted on Windows master'
        : isProduct
            ? '${local['name'] ?? ''}\nWindows stock: ${local['quantity'] ?? 0}  |  Damaged: ${local['damaged_quantity'] ?? 0}\nSale price: Rs. ${local['price'] ?? 0}'
            : '${local['name'] ?? ''}  •  ${local['phone'] ?? ''}\nWindows balance: Rs. ${local['balance'] ?? 0}';
    final remoteSummary = isDelete
        ? 'Deleted on the other device'
        : isProduct
            ? '${remote['name'] ?? ''}\nOther device stock: ${remote['quantity'] ?? 0}  |  Damaged: ${remote['damaged_quantity'] ?? 0}\nSale price: Rs. ${remote['price'] ?? 0}'
            : '${remote['name'] ?? ''}  •  ${remote['phone'] ?? ''}\nOther device balance: Rs. ${remote['balance'] ?? 0}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(isProduct ? 'Barcode: $key' : 'Account: $key', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F4F7),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('WINDOWS MASTER', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
                        const SizedBox(height: 6),
                        Text(localSummary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7E8),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('OTHER DEVICE', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
                        const SizedBox(height: 6),
                        Text(remoteSummary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : () => _resolve(conflict, false),
                  child: const Text('Keep Windows'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : () => _resolve(conflict, true),
                  child: Text(isDelete ? 'Delete on Windows' : isReadd ? 'Restore Other Device' : 'Use Other Device'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWindows = Platform.isWindows;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !isWindows,
        leading: desktopWorkspaceButton(),
        title: const Text('Cloud Sync'),
        backgroundColor: isWindows ? const Color(0xFFF7F9FB) : Colors.teal,
        foregroundColor: isWindows ? const Color(0xFF263442) : Colors.white,
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
                    'Pending bills and local reminder-log entries remain on their own device. Both apps continue working offline; cloud changes wait until internet is available. Firebase/Firestore ka existing Android sync is testing ke dauran active rahega; Drive sync us ke saath alag Windows-master channel ke taur par chalega. Firebase data ya rules ko remove/disable nahi kiya jayega.',
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
          if (isWindows) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text('Reconciliation required', style: Theme.of(context).textTheme.titleLarge)),
                Text('${_conflicts.length} pending', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            if (_conflicts.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('No pending conflicts. Windows can publish the approved master data.'),
                ),
              )
            else
              ..._conflicts.map(_conflictCard),
          ] else ...[
            const SizedBox(height: 12),
            const Text(
              'Android device data is safely uploaded first. Windows must process and approve the snapshot before its stock and account balances replace local values.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }
}
