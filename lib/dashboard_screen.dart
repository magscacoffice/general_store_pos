import 'package:firebase_auth/firebase_auth.dart';
import 'salesmen_management_screen.dart';

import 'package:flutter/material.dart';
import 'db_helper.dart';
import 'cloud_sync_screen.dart';

import 'sales_screen.dart';
import 'inventory_screen.dart';
import 'history_screen.dart';
import 'sales_report_screen.dart';
import 'backup_screen.dart';
import 'purchase_screen.dart';
import 'expense_screen.dart';
import 'customer_khata_screen.dart';
import 'profit_loss_screen.dart';
import 'party_screen.dart';
import 'reminders_screen.dart';
import 'update_manager.dart';

class DashboardScreen extends StatefulWidget {
  final String role;

  const DashboardScreen({super.key, required this.role});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final GlobalKey<SalesScreenState> _dashboardSaleKey = GlobalKey<SalesScreenState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('خان بابا جنرل سٹور'),
        centerTitle: false,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 56,
        actions: [
          IconButton(
              tooltip: 'Check for Android updates',
              icon: const Icon(Icons.system_update_alt),
              onPressed: () => PosUpdateService.checkAndPrompt(
                context,
                manual: true,
              ),
            ),
          IconButton(
            tooltip: 'Google Drive Cloud Sync',
            icon: const Icon(Icons.cloud_sync_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CloudSyncScreen()),
            ),
          ),
          if (!DBHelper.localOnlyMode) ...[
            IconButton(
              tooltip: 'Sync store data',
              icon: const Icon(Icons.sync),
              onPressed: () async {
                await DBHelper.syncAllData();
                final pending = await DBHelper.getPendingSyncCount();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Sync check complete. Pending uploads: $pending')),
                  );
                }
              },
            ),
            IconButton(
              tooltip: 'Logout',
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
            ),
          ],
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 950) {
            return _buildCompactDashboard(context, constraints.maxWidth);
          }
          return Row(
            children: [
              SizedBox(
                width: 218,
                child: ColoredBox(
                  color: const Color(0xFFF0F5F4),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(14, 18, 14, 14),
                          child: Column(
                            children: [
                              Icon(Icons.store_outlined, size: 30, color: Colors.teal),
                              SizedBox(height: 10),
                              Text(
                                'KHAN BABA POS',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                              Text('General Store G.T Road Sanawan',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 11, color: Colors.black54)),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: Scrollbar(
                            thumbVisibility: true,
                            child: ListView(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                            children: [
                              _desktopNavItem(context, 'New Sale / Billing', Icons.point_of_sale, const SalesScreen()),
                              _desktopNavItem(context, 'Inventory / Stock', Icons.inventory_2, const InventoryScreen()),
                              _desktopNavItem(context, 'Sales History', Icons.receipt_long, const HistoryScreen()),
                              _desktopNavItem(context, 'Sales Reports', Icons.bar_chart, const SalesReportScreen()),
                              _desktopNavItem(context, 'Purchases', Icons.add_shopping_cart, const PurchaseScreen()),
                              _desktopNavItem(context, 'Expenses', Icons.money_off, const ExpenseScreen()),
                              _desktopNavItem(context, 'Customers / Parties', Icons.people, const PartyScreen(type: 'customer')),
                              _desktopNavItem(context, 'Suppliers', Icons.local_shipping_outlined, const PartyScreen(type: 'supplier')),
                              _desktopNavItem(context, 'Customer Khata', Icons.menu_book, const CustomerKhataScreen()),
                              _desktopNavItem(context, 'Reminders / Due Alerts', Icons.notifications_active, const RemindersScreen()),
                              _desktopNavItem(context, 'Profit / Loss', Icons.trending_up, const ProfitLossScreen()),
                              if (widget.role == 'admin' && !DBHelper.localOnlyMode)
                                _desktopNavItem(context, 'Salesmen / Staff', Icons.manage_accounts, const SalesmenManagementScreen()),
                              _desktopNavItem(context, 'Cloud Sync', Icons.cloud_sync_outlined, const CloudSyncScreen()),
                              _desktopNavItem(context, 'Settings / Backup', Icons.settings, const BackupScreen()),
                              ],
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Offline-first Point of Sale',
                            style: TextStyle(color: Colors.black54, fontSize: 11)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: SalesScreen(
                    key: _dashboardSaleKey,
                    embeddedInDashboard: true,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCompactDashboard(BuildContext context, double width) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Icon(Icons.store, size: 60, color: Colors.teal),
          const SizedBox(height: 8),
          const Text(
            'Khan Baba General Store POS',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.count(
              crossAxisCount: width >= 650 ? 3 : 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              children: _desktopCards(context),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _desktopCards(BuildContext context) => [
    _buildMenuCard(context, 'New Sale / Billing', Icons.point_of_sale, Colors.green, const SalesScreen()),
    _buildMenuCard(context, 'Inventory / Stock', Icons.inventory_2, Colors.orange, const InventoryScreen()),
    _buildMenuCard(context, 'Sales History', Icons.receipt_long, Colors.purple, const HistoryScreen()),
    _buildMenuCard(context, 'Sales Reports', Icons.bar_chart, Colors.blue, const SalesReportScreen()),
    _buildMenuCard(context, 'Purchases / Stock Entry', Icons.add_shopping_cart, Colors.brown, const PurchaseScreen()),
    _buildMenuCard(context, 'Expenses', Icons.money_off, Colors.red, const ExpenseScreen()),
    _buildMenuCard(context, 'Customers / Parties', Icons.people, Colors.deepOrange, const PartyScreen(type: 'customer')),
    _buildMenuCard(context, 'Suppliers', Icons.local_shipping_outlined, Colors.blueGrey, const PartyScreen(type: 'supplier')),
    _buildMenuCard(context, 'Customer Khata', Icons.menu_book, Colors.indigo, const CustomerKhataScreen()),
    _buildMenuCard(context, 'Reminders / Due Alerts', Icons.notifications_active, Colors.red, const RemindersScreen()),
    _buildMenuCard(context, 'Profit / Loss', Icons.trending_up, Colors.deepPurple, const ProfitLossScreen()),
    if (widget.role == 'admin' && !DBHelper.localOnlyMode)
      _buildMenuCard(context, 'Salesmen / Staff', Icons.manage_accounts, Colors.cyan, const SalesmenManagementScreen()),
    _buildMenuCard(context, 'Cloud Sync', Icons.cloud_sync_outlined, Colors.lightBlue, const CloudSyncScreen()),
    _buildMenuCard(context, 'Settings / Backup', Icons.settings, Colors.teal, const BackupScreen()),
  ];

  Widget _desktopNavItem(
    BuildContext context,
    String title,
    IconData icon,
    Widget targetScreen, {
    bool selected = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: ListTile(
        selected: selected,
        selectedTileColor: Colors.teal.withValues(alpha: 0.09),
        dense: false,
        minTileHeight: 48,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        leading: Icon(icon, size: 24, color: selected ? Colors.teal : Colors.blueGrey),
        title: Text(title, style: TextStyle(
          fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          fontSize: 13,
        )),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => targetScreen),
          );
        },
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    Widget targetScreen,
  ) {
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => targetScreen),
          );
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 38, color: color),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
