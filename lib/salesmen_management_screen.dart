import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'auth_gate.dart';

class SalesmenManagementScreen extends StatefulWidget {
  const SalesmenManagementScreen({super.key});

  @override
  State<SalesmenManagementScreen> createState() =>
      _SalesmenManagementScreenState();
}

class _SalesmenManagementScreenState extends State<SalesmenManagementScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _creating = false;
  bool _hidePassword = true;

  CollectionReference<Map<String, dynamic>> get _members => FirebaseFirestore
      .instance
      .collection('stores')
      .doc(storeId)
      .collection('members');

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _createSalesman() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (name.isEmpty || !email.contains('@') || password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Name, valid email aur kam az kam 8 character password enter karein.'),
        ),
      );
      return;
    }

    setState(() => _creating = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('createSalesman');
      await callable.call({
        'name': name,
        'email': email,
        'password': password,
      });
      _nameController.clear();
      _emailController.clear();
      _passwordController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Salesman account create ho gaya.'),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Account create nahi ho saka.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _setActive(
    DocumentReference<Map<String, dynamic>> ref,
    bool active,
  ) async {
    try {
      await ref.update({'active': active});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(active
              ? 'Salesman account dobara active kar diya gaya.'
              : 'Salesman account deactivate kar diya gaya.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status update nahi ho saka: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Salesmen Management'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Naya Salesman Account',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Salesman ka naam',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _passwordController,
                    obscureText: _hidePassword,
                    decoration: InputDecoration(
                      labelText: 'Temporary password (minimum 8 characters)',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _hidePassword = !_hidePassword),
                        icon: Icon(_hidePassword
                            ? Icons.visibility
                            : Icons.visibility_off),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _creating ? null : _createSalesman,
                    icon: _creating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_add),
                    label: Text(_creating ? 'Creating...' : 'Create Salesman'),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Account banne ke baad salesman isi email aur password se login karega.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Store Staff',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _members.orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Staff list load nahi hui: ${snapshot.error}');
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final staff = snapshot.data!.docs
                  .where((doc) => doc.data()['role'] == 'salesman')
                  .toList();
              if (staff.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Abhi koi salesman account nahi bana.'),
                  ),
                );
              }
              return Column(
                children: staff.map((doc) {
                  final data = doc.data();
                  final active = data['active'] == true;
                  final name = (data['name'] ?? 'Salesman').toString();
                  final email = (data['email'] ?? '').toString();
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(active ? Icons.person : Icons.person_off),
                      ),
                      title: Text(name),
                      subtitle: Text(
                        '$email\n${active ? 'Active' : 'Deactivated'}',
                      ),
                      isThreeLine: true,
                      trailing: Switch(
                        value: active,
                        onChanged: (value) => _setActive(doc.reference, value),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
