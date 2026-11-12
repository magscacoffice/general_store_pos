import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';

class PosWindows {
  static const String sale = 'sale';
  static const String dashboard = 'dashboard';

  static String newBillId() => DateTime.now().microsecondsSinceEpoch.toString();

  static Future<Map<String, dynamic>> currentArguments() async {
    final controller = await WindowController.fromCurrentEngine();
    final raw = controller.arguments;
    if (raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Older launches have no JSON window arguments.
    }
    return <String, dynamic>{};
  }

  static Future<void> openSale({String? billId}) async {
    final id = billId ?? newBillId();
    final windows = await WindowController.getAll();
    for (final existing in windows) {
      try {
        final decoded = jsonDecode(existing.arguments);
        if (decoded is Map &&
            decoded['type'] == sale &&
            decoded['billId']?.toString() == id) {
          await existing.show();
          return;
        }
      } catch (_) {
        // Ignore windows without POS arguments.
      }
    }
    final controller = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: jsonEncode({'type': sale, 'billId': id}),
      ),
    );
    await controller.show();
  }

  // Release resident cashier windows before replacing the shared SQLite file.
  static Future<List<String>> closeSaleWindowsForRestore() async {
    final billIds = <String>[];
    final windows = await WindowController.getAll();
    try {
      for (final controller in windows) {
        Map<String, dynamic> arguments;
        try {
          final decoded = jsonDecode(controller.arguments);
          if (decoded is! Map) continue;
          arguments = Map<String, dynamic>.from(decoded);
        } catch (_) {
          continue;
        }
        if (arguments['type'] != sale) continue;
        final billId = arguments['billId']?.toString();
        if (billId == null || billId.isEmpty) {
          throw Exception('New Sale window ka bill ID nahi mil saka; restore rok diya gaya hai.');
        }
        final closed = await controller.invokeMethod<bool>('prepare_for_restore');
        if (closed != true) {
          throw Exception('New Sale window database release nahi kar saki. Restore cancel kar diya gaya hai.');
        }
        billIds.add(billId);
      }
      return billIds;
    } catch (_) {
      for (final billId in billIds) {
        try {
          await openSale(billId: billId);
        } catch (_) {}
      }
      rethrow;
    }
  }

  static Future<void> openDashboard() async {
    final windows = await WindowController.getAll();
    for (final controller in windows) {
      if (controller.arguments.isEmpty) {
        await controller.show();
        return;
      }
      try {
        final decoded = jsonDecode(controller.arguments);
        if (decoded is Map && (decoded.isEmpty || decoded['type'] == dashboard)) {
          await controller.show();
          return;
        }
      } catch (_) {
        // Ignore a window that has no POS window arguments.
      }
    }
    final controller = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: jsonEncode({'type': dashboard}),
      ),
    );
    await controller.show();
  }
}
