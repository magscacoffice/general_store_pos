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
