import 'package:flutter/material.dart';
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
      builder: (_) => AlertDialog(
        title: Text('Naya ${widget.type == 'customer' ? 'Customer' : 'Supplier'} Add Karein'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Naam')),
            TextField(controller: phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                await DBHelper.insertParty({
                  'name': nameController.text,
                  'phone': phoneController.text,
                  'type': widget.type,
                  'balance': 0.0,
                });
                _loadParties();
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.type == 'customer' ? 'Customers Khata' : 'Suppliers Khata'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        itemCount: _parties.length,
        itemBuilder: (context, index) {
          final party = _parties[index];
          return Card(
            child: ListTile(
              title: Text(party['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Phone: ${party['phone']}'),
              trailing: Text('Rs. ${party['balance']}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddPartyDialog,
        backgroundColor: Colors.orange,
        child: const Icon(Icons.person_add),
      ),
    );
  }
}