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
    if (!mounted) return;
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
        backgroundColor: Platform.isWindows ? const Color(0xFFF7F9FB) : Colors.teal,
        foregroundColor: Platform.isWindows ? const Color(0xFF263442) : Colors.white,
      ),
      floatingActionButton: Platform.isWindows ? FloatingActionButton.extended(
        onPressed: _addReminderDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Reminder'),
      ) : FloatingActionButton(
        backgroundColor: Colors.teal,
        onPressed: _addReminderDialog,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Platform.isWindows
          ? reminders.isEmpty
              ? const Center(child: Text('کوئی ریمائنڈر موجود نہیں ہے۔'))
              : Padding(
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
                              Expanded(child: Text('Reminder Register', style: Theme.of(context).textTheme.titleLarge)),
                              Text('${reminders.length} reminders', style: Theme.of(context).textTheme.bodySmall),
                              IconButton(tooltip: 'Refresh', onPressed: _loadReminders, icon: const Icon(Icons.refresh)),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: SingleChildScrollView(
                            child: DataTable(
                              headingRowHeight: 42,
                              dataRowMinHeight: 40,
                              dataRowMaxHeight: 52,
                              columns: const [
                                DataColumn(label: Text('Reminder')),
                                DataColumn(label: Text('Details')),
                                DataColumn(label: Text('Date')),
                                DataColumn(label: Text('Status')),
                              ],
                              rows: reminders.map((item) => DataRow(cells: [
                                DataCell(SizedBox(width: 220, child: Text('${item['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis))),
                                DataCell(SizedBox(width: 360, child: Text('${item['details'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis))),
                                DataCell(Text('${item['date'] ?? ''}')),
                                DataCell(Text(item['is_done'] == 1 || item['is_done'] == true ? 'Completed' : 'Pending')),
                              ])).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
          : reminders.isEmpty
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
