/// Compatibility shim for shared restore/sync code while the Windows client
/// is migrated to the separate native WPF application. This class deliberately
/// does not create or control Flutter desktop windows.
class PosWindows {
  static const String sale = 'sale';
  static const String dashboard = 'dashboard';

  static String newBillId() => DateTime.now().microsecondsSinceEpoch.toString();

  static Future<Map<String, dynamic>> currentArguments() async =>
      <String, dynamic>{};

  static Future<void> openSale({String? billId}) async {}

  static Future<List<String>> closeSaleWindowsForRestore() async =>
      <String>[];

  static Future<void> openDashboard() async {}
}
