import 'windows/desktop_app_bar.dart';
import 'dart:io';
import 'package:flutter/material.dart';

import 'db_helper.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  List<Map<String, dynamic>> reminders = [];

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    final data = await DBHelper.getReminders();
    setState(() => reminders = data);
  }

  void _addReminderDialog() {
    TextEditingController titleController = TextEditingController();
    TextEditingController detailsController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('نیا ریمائنڈر شامل کریں'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'عنوان (مثلاً ادھار وصولی)',
                ),
              ),
              TextField(
                controller: detailsController,
                decoration: const InputDecoration(labelText: 'تفصیلات'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('منسوخ کریں'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.isNotEmpty) {
                  await DBHelper.insertReminder({
                    'title': titleController.text,
                    'details': detailsController.text,
                    'date': DateTime.now().toString().substring(0, 10),
                    'is_done': 0,
                  });
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                  _loadReminders();
                }
              },
              child: const Text('محفوظ کریں'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !Platform.isWindows,
        leading: desktopWorkspaceButton(),
        title: const Text('وصولی اور ریمائنڈرز'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.teal,
        onPressed: _addReminderDialog,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: reminders.isEmpty
          ? const Center(child: Text('کوئی ریمائنڈر موجود نہیں ہے۔'))
          : ListView.builder(
              itemCount: reminders.length,
              itemBuilder: (context, index) {
                final item = reminders[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.alarm, color: Colors.teal),
                    title: Text(
                      item['title'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${item['details']}\nتاریخ: ${item['date']}',
                    ),
                  ),
                );
              },
            ),
    );
  }
}
