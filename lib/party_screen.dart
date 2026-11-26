import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'db_helper.dart';

class PartyScreen extends StatefulWidget {
  final String type; // 'customer' ya 'supplier'
  const PartyScreen({super.key, required this.type});

  @override
  State<PartyScreen> createState() => _PartyScreenState();
}

class _PartyScreenState extends State<PartyScreen> {
  List<Map<String, dynamic>> _parties = [];
  Map<int, Map<String, dynamic>> _overdueByParty = {};

  @override
  void initState() {
    super.initState();
    _loadParties();
  }

  Future<void> _loadParties() async {
    final data = await DBHelper.getParties(widget.type);
    final overdue = widget.type == 'customer'
        ? await DBHelper.getOverdueKhataCustomers(overdueDays: 30)
        : <Map<String, dynamic>>[];
    if (!mounted) return;
    setState(() {
      _parties = data;
      _overdueByParty = {
        for (final item in overdue)
          (item['id'] as num).toInt(): item,
      };
    });
  }

  Future<void> _deleteParty(Map<String, dynamic> party) async {
    final id = (party['id'] as num).toInt();
    final isCustomer = widget.type == 'customer';
    final balance = (party['balance'] as num?)?.toDouble() ?? 0;
    if (isCustomer && balance.abs() > 0.000001) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete / archive account?'),
        content: Text(isCustomer
            ? 'Balance zero hai. Agar purani sales ya Khata history mojood hui to account archive hoga taa-ke history mehfooz rahe; warna delete hoga. Continue?'
            : 'Is supplier account ko delete karna hai?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Continue')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await DBHelper.deleteParty(id);
      await _loadParties();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isCustomer
              ? 'Customer active list se remove ho gaya; historical records mehfooz hain.'
              : 'Supplier account delete ho gaya.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _sendKhataReminder(Map<String, dynamic> party) async {
    final rawPhone = (party['phone'] ?? '').toString();
    var phone = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.startsWith('0')) phone = '92${phone.substring(1)}';
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Is customer ka phone number mojood nahi.')),
      );
      return;
    }
    final overdue = _overdueByParty[(party['id'] as num).toInt()];
    final balance = (party['balance'] as num?)?.toDouble() ?? 0;
    final message = 'Assalam-o-Alaikum ${party['name']}, '
        'aap ke Khan Baba General Store Khata mein Rs. '
        '${balance.toStringAsFixed(2)} baqi hain. '
        'Sab se purani unpaid raqam ki tareekh '
        '${overdue?['oldest_due_date'] ?? 'available'} hai. '
        'Meharbani farma kar payment ka intizam karein. Shukriya.';
    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(message)}',
    );
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp link open nahi ho saka.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('WhatsApp open nahi ho saka: $error')),
        );
      }
    }
  }

  void _showAddPartyDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    String newCustomerType = 'Khata';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              widget.type == 'customer'
                  ? 'Add New Customer'
                  : 'Add New Supplier',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Naam *'),
                ),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone Number'),
                ),
                if (widget.type == 'customer') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: newCustomerType,
                    decoration: const InputDecoration(labelText: 'Customer Type'),
                    items: const [
                      DropdownMenuItem(value: 'Khata', child: Text('Khata Customer')),
                      DropdownMenuItem(value: 'Wholesale', child: Text('Wholesale Customer')),
                    ],
                    onChanged: (value) => setDialogState(() {
                      if (value != null) newCustomerType = value;
                    }),
                  ),
                ],
                const SizedBox(height: 15),
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final permission = await FlutterContacts.permissions
                          .request(PermissionType.read);
                      if (permission != PermissionStatus.granted) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Contacts permission allow karein.')),
                          );
                        }
                        return;
                      }
                      final contact = await FlutterContacts.native.showPicker(
                        properties: {ContactProperty.phone},
                      );
                      if (contact != null && context.mounted) {
                        nameController.text = contact.displayName ?? '';
                        if (contact.phones.isNotEmpty) {
                          phoneController.text = contact.phones.first.number;
                        }
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Contact open nahi ho saka: $e')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.contacts),
                  label: const Text('Phone Contacts Se Chunein'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.isNotEmpty) {
                    await DBHelper.insertParty({
                      'name': nameController.text.trim(),
                      'phone': phoneController.text.trim(),
                      'type': widget.type,
                      if (widget.type == 'customer') 'customer_type': newCustomerType,
                      'balance': 0.0,
                    });
                    _loadParties();
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _changeCustomerType(Map<String, dynamic> party) async {
    final id = (party['id'] as num).toInt();
    final current = party['customer_type']?.toString() ?? 'Khata';
    String selected = current;
    final choice = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Customer Type: ${party['name']}'),
          content: DropdownButtonFormField<String>(
            value: selected,
            items: const [
              DropdownMenuItem(value: 'Khata', child: Text('Khata Customer')),
              DropdownMenuItem(value: 'Wholesale', child: Text('Wholesale Customer')),
            ],
            onChanged: (value) => setDialogState(() {
              if (value != null) selected = value;
            }),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (choice != true || selected == current) return;
    try {
      await DBHelper.updateCustomerType(id, selected);
      await _loadParties();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Customer type changed to $selected.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Widget _buildDesktopParties(bool isCustomer) {
    if (_parties.isEmpty) {
      return Center(child: Text(isCustomer ? 'No customers found.' : 'No suppliers found.'));
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(child: Text(isCustomer ? 'Customer Accounts' : 'Supplier Accounts', style: Theme.of(context).textTheme.titleLarge)),
                  Text('${_parties.length} accounts', style: Theme.of(context).textTheme.bodySmall),
                  IconButton(tooltip: 'Refresh', onPressed: _loadParties, icon: const Icon(Icons.refresh)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Scrollbar(
                    thumbVisibility: true,
                    notificationPredicate: (notification) => notification.metrics.axis == Axis.vertical,
                    child: SingleChildScrollView(
                      child: DataTable(
                      headingRowHeight: 42,
                      dataRowMinHeight: 42,
                      dataRowMaxHeight: 54,
                      columns: [
                        const DataColumn(label: Text('Name')),
                        const DataColumn(label: Text('Phone')),
                        if (isCustomer) const DataColumn(label: Text('Customer Type / Status')),
                        const DataColumn(label: Text('Outstanding'), numeric: true),
                        const DataColumn(label: Text('Actions')),
                      ],
                      rows: _parties.map((party) {
                        final id = (party['id'] as num).toInt();
                        final overdue = _overdueByParty[id];
                        final balance = (party['balance'] as num?)?.toDouble() ?? 0;
                        return DataRow(cells: [
                          DataCell(SizedBox(
                            width: 220,
                            child: Text(
                              party['name']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          )),
                          DataCell(Text(party['phone']?.toString() ?? '—')),
                          if (isCustomer)
                            DataCell(Text(
                              '${party['customer_type'] ?? 'Khata'} • ${overdue == null ? 'Regular' : 'OVERDUE ${overdue['overdue_days']} days'}',
                              style: TextStyle(
                                color: overdue == null ? null : Colors.red.shade700,
                                fontWeight: overdue == null ? FontWeight.normal : FontWeight.w600,
                              ),
                            )),
                          DataCell(Text('Rs. ${balance.toStringAsFixed(2)}')),
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isCustomer)
                                IconButton(
                                  tooltip: 'Change customer type',
                                  icon: const Icon(Icons.swap_horiz, color: Colors.blueGrey),
                                  onPressed: () => _changeCustomerType(party),
                                ),
                              if (isCustomer && overdue != null)
                                IconButton(
                                  tooltip: 'WhatsApp overdue reminder',
                                  icon: const Icon(Icons.message_outlined, color: Colors.green),
                                  onPressed: () => _sendKhataReminder(party),
                                ),
                              if (!isCustomer || balance.abs() <= 0.000001)
                                IconButton(
                                tooltip: 'Delete / archive account',
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => _deleteParty(party),
                              ),
                            ],
                          )),
                        ]);
                      }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isCustomer = widget.type == 'customer';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isCustomer ? 'Customers (Gahak Khata)' : 'Suppliers (Samaan Waly)',
        ),
        backgroundColor: (isCustomer ? Colors.orange : Colors.indigo),
        foregroundColor: Colors.white,
      ),
      body: _parties.isEmpty
          ? Center(
              child: Text(
                isCustomer ? 'No customers found.' : 'No suppliers found.',
              ),
            )
          : ListView.builder(
              itemCount: _parties.length,
              itemBuilder: (context, index) {
                final party = _parties[index];
                final partyId = (party['id'] as num).toInt();
                final balance = (party['balance'] as num?)?.toDouble() ?? 0;
                final overdue = _overdueByParty[partyId];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  color: overdue != null ? Colors.red.shade50 : null,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: overdue != null
                          ? Colors.red
                          : (isCustomer ? Colors.orange : Colors.indigo),
                      child: Text(
                        party['name'].isNotEmpty
                            ? party['name'][0].toUpperCase()
                            : '?',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(
                      party['name'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      widget.type == 'customer'
                          ? overdue == null
                              ? 'Phone: ${party['phone']}  |  ${party['customer_type'] ?? 'Khata'} Customer'
                              : '${party['customer_type'] ?? 'Khata'} | OVERDUE ${overdue['overdue_days']} days | Oldest unpaid: ${overdue['oldest_due_date']} | Phone: ${party['phone']}'
                          : 'Phone: ${party['phone']}',
                      style: TextStyle(
                        color: overdue != null ? Colors.red.shade900 : null,
                        fontWeight: overdue != null ? FontWeight.w600 : null,
                      ),
                    ),
                    onTap: isCustomer ? () => _changeCustomerType(party) : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Rs. ${party['balance']}',
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (overdue != null)
                          IconButton(
                            tooltip: 'WhatsApp overdue reminder',
                            icon: const Icon(Icons.message, color: Colors.green),
                            onPressed: () => _sendKhataReminder(party),
                          ),
                        if (widget.type != 'customer' || balance.abs() <= 0.000001)
                          IconButton(
                          tooltip: 'Delete / archive account',
                          icon: const Icon(Icons.delete, color: Colors.grey),
                          onPressed: () => _deleteParty(party),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddPartyDialog,
        backgroundColor: isCustomer ? Colors.orange : Colors.indigo,
        child: const Icon(Icons.person_add),
      ),
    );
  }
}
