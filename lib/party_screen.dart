import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import 'db_helper.dart';

class PartyScreen extends StatefulWidget {
  final String type; // 'customer' ya 'supplier'
  const PartyScreen({super.key, required this.type});

  @override
  State<PartyScreen> createState() => _PartyScreenState();
}

class _PartyScreenState extends State<PartyScreen> {
  List<Map<String, dynamic>> _parties = [];

  @override
  void initState() {
    super.initState();
    _loadParties();
  }

  void _loadParties() async {
    final data = await DBHelper.getParties(widget.type);
    setState(() {
      _parties = data;
    });
  }

  void _showAddPartyDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

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
                      'customer_type': 'Khata',
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

  @override
  Widget build(BuildContext context) {
    bool isCustomer = widget.type == 'customer';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isCustomer ? 'Customers (Gahak Khata)' : 'Suppliers (Samaan Waly)',
        ),
        backgroundColor: isCustomer ? Colors.orange : Colors.indigo,
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
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isCustomer
                          ? Colors.orange
                          : Colors.indigo,
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
                    subtitle: Text(widget.type == 'customer'
                        ? 'Phone: ${party['phone']}  |  Khata Customer'
                        : 'Phone: ${party['phone']}'),
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
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.grey),
                          onPressed: () async {
                            try {
                              await DBHelper.deleteParty((party['id'] as num).toInt());
                              _loadParties();
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account delete ho gaya.')));
                            } catch (e) {
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
                            }
                          },
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
