import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'auth_gate.dart';
import 'dashboard_screen.dart';
import 'sales_screen.dart';
import 'windows/pos_windows.dart';
import 'windows/desktop_theme.dart';
import 'db_helper.dart';
import 'drive_sync_service.dart';
import 'update_manager.dart';

Future<void> _writeWindowsStartupLog(String message,
    [Object? error, StackTrace? stackTrace]) async {
  if (!Platform.isWindows) return;
  final bases = <String?>[
    Platform.environment['LOCALAPPDATA'],
    Platform.environment['TEMP'],
    Directory.systemTemp.path,
  ];
  for (final base in bases.whereType<String>().where((value) => value.isNotEmpty).toSet()) {
    try {
      final directory = Directory(p.join(base, 'KhanBabaPOS', 'Logs'));
      await directory.create(recursive: true);
      final file = File(p.join(directory.path, 'startup.log'));
      final entry = StringBuffer()
        ..writeln('--- ${DateTime.now().toIso8601String()} ---')
        ..writeln(message);
      if (error != null) entry.writeln(error);
      if (stackTrace != null) entry.writeln(stackTrace);
      await file.writeAsString(entry.toString(), mode: FileMode.append, flush: true);
      return;
    } catch (_) {
      // Try another writable per-user temporary location.
    }
  }
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    unawaited(_writeWindowsStartupLog('Dart main() entered.'));
    FlutterError.onError = (details) {
      unawaited(_writeWindowsStartupLog(
          'Flutter framework error.', details.exception, details.stack));
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      unawaited(_writeWindowsStartupLog(
          'Uncaught Dart platform error.', error, stackTrace));
      return false;
    };

    // The portable Windows edition is local/offline-only.
    DBHelper.localOnlyMode = true;
    Map<String, dynamic> windowArguments = <String, dynamic>{};
    try {
      windowArguments = await PosWindows.currentArguments();
    } catch (error, stackTrace) {
      unawaited(_writeWindowsStartupLog(
        'Could not read native window arguments; opening Dashboard with a New Sale window.',
        error,
        stackTrace,
      ));
    }
    final windowType = windowArguments['type']?.toString() ?? PosWindows.dashboard;
    // The primary native window is the Dashboard; open a separate cashier window on launch.
    final openSaleOnStart = windowArguments.isEmpty && windowType == PosWindows.dashboard;
    final billId = windowArguments['billId']?.toString();
    runApp(KhanBabaPOSApp(
      windowsLocalMode: true,
      windowsWindowType: windowType,
      windowsBillId: billId,
      windowsOpenSaleOnStart: openSaleOnStart,
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_writeWindowsStartupLog('First Dart frame rendered.'));
    });
    return;
  }

  await Firebase.initializeApp();
  try {
    await DriveSyncService.initialize();
  } catch (error) {
    debugPrint('Cloud sync initialization deferred: $error');
  }
  runApp(const KhanBabaPOSApp());
}

class KhanBabaPOSApp extends StatelessWidget {
  final bool windowsLocalMode;
  final String windowsWindowType;
  final String? windowsBillId;
  final bool windowsOpenSaleOnStart;

  const KhanBabaPOSApp({
    super.key,
    this.windowsLocalMode = false,
    this.windowsWindowType = PosWindows.dashboard,
    this.windowsBillId,
    this.windowsOpenSaleOnStart = false,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Khan Baba General Store',
      debugShowCheckedModeBanner: false,
      theme: windowsLocalMode ? buildWindowsTheme() : ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: windowsLocalMode
          ? WindowsStartupGate(
              windowType: windowsWindowType,
              billId: windowsBillId,
              openSaleOnStart: windowsOpenSaleOnStart,
            )
          : const UpdateAwareHome(child: AuthGate()),
    );
  }
}

class WindowsStartupGate extends StatefulWidget {
  final String windowType;
  final String? billId;
  final bool openSaleOnStart;

  const WindowsStartupGate({
    super.key,
    required this.windowType,
    this.billId,
    this.openSaleOnStart = false,
  });

  @override
  State<WindowsStartupGate> createState() => _WindowsStartupGateState();
}

class _WindowsStartupGateState extends State<WindowsStartupGate> {
  String? _billId;
  bool _loading = true;
  bool _ready = false;
  Object? _error;
  String? _logPath;
  bool _allowCloseForRestore = false;

  @override
  void initState() {
    super.initState();
    _billId = widget.billId;
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    setState(() {
      _loading = true;
      _ready = false;
      _error = null;
      _logPath = null;
    });

    try {
      unawaited(_writeWindowsStartupLog('Initializing SQLite FFI.'));
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      DBHelper.localOnlyMode = true;
      unawaited(_writeWindowsStartupLog('Opening local database.'));
      await DBHelper.database;
      try {
        await DriveSyncService.initialize();
        await DriveSyncService.restoreStatus();
        DriveSyncService.startAutoSync();
      } catch (error, stackTrace) {
        unawaited(_writeWindowsStartupLog(
          'Cloud sync initialization deferred; local POS will continue offline.',
          error,
          stackTrace,
        ));
      }
      unawaited(_writeWindowsStartupLog('Local database opened successfully.'));

      if (widget.windowType == PosWindows.sale && (_billId == null || _billId!.isEmpty)) {
        final pending = await DBHelper.getPendingBills();
        _billId = pending.isNotEmpty
            ? pending.first['bill_id']?.toString()
            : PosWindows.newBillId();
      }

      try {
        final windowController = await WindowController.fromCurrentEngine();
        await windowController.setWindowMethodHandler((call) async {
          if (call.method != 'prepare_for_restore' || widget.windowType != PosWindows.sale) {
            throw MissingPluginException('Unsupported window command: ${call.method}');
          }
          try {
            await windowsBeforeDatabaseRestore?.call();
            await DBHelper.closeDatabase();
            _allowCloseForRestore = true;
            final restoreWindow = WindowManager.instance.getCurrent();
            if (restoreWindow != null) {
              await restoreWindow.close();
            }
            return true;
          } catch (_) {
            _allowCloseForRestore = false;
            rethrow;
          }
        });
        final nativeWindow = WindowManager.instance.getCurrent();
        if (nativeWindow != null) {
          final isDashboard = widget.windowType == PosWindows.dashboard;
          nativeWindow.title = isDashboard
              ? 'Khan Baba POS - Dashboard'
              : 'Khan Baba POS - New Sale';
          nativeWindow.minimumSize = const Size(980, 650).toNative();
          nativeWindow.setSize(const Size(1240, 740).toNative(), false);
          nativeWindow.center();
          if (!isDashboard) {
            nativeWindow.addListener((event) {
              if (event is WindowCloseRequestedEvent && !_allowCloseForRestore) {
                // Keep the cashier window resident in the Windows taskbar during normal use.
                event.request.cancel();
                nativeWindow.minimize();
              }
            });
          }
          nativeWindow.show();
        }
      } catch (error, stackTrace) {
        unawaited(_writeWindowsStartupLog(
          'Native window styling could not be applied; continuing with default window.',
          error,
          stackTrace,
        ));
      }

      if (!mounted) return;
      setState(() {
        _ready = true;
        _loading = false;
        _error = null;
      });

      if (widget.openSaleOnStart) {
        try {
          final pending = await DBHelper.getPendingBills();
          final initialBillId = pending.isNotEmpty
              ? pending.first['bill_id']?.toString()
              : PosWindows.newBillId();
          await PosWindows.openSale(billId: initialBillId);
        } catch (error, stackTrace) {
          unawaited(_writeWindowsStartupLog(
            'Automatic New Sale window could not be opened.',
            error,
            stackTrace,
          ));
        }
      }
    } catch (error, stackTrace) {
      final logPath = await _writeStartupLog(error, stackTrace);
      await _writeWindowsStartupLog(
          'Windows startup database initialization failed.', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _ready = false;
        _loading = false;
        _error = error;
        _logPath = logPath;
      });
    }
  }

  Future<String?> _writeStartupLog(Object error, StackTrace stackTrace) async {
    final bases = <String?>[
      Platform.environment['LOCALAPPDATA'],
      Platform.environment['APPDATA'],
      Platform.environment['TEMP'],
      Directory.systemTemp.path,
    ];

    for (final base in bases.whereType<String>().where((value) => value.isNotEmpty).toSet()) {
      try {
        final directory = Directory(p.join(base, 'KhanBabaPOS', 'Logs'));
        await directory.create(recursive: true);
        final file = File(p.join(directory.path, 'startup.log'));
        final entry = StringBuffer()
          ..writeln('--- ${DateTime.now().toIso8601String()} ---')
          ..writeln('Windows portable startup failed')
          ..writeln(error)
          ..writeln(stackTrace)
          ..writeln();
        await file.writeAsString(entry.toString(), mode: FileMode.append, flush: true);
        return file.path;
      } catch (_) {
        // Try the next per-user writable location.
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      if (widget.windowType == PosWindows.dashboard) {
        return const DashboardScreen(role: 'admin');
      }
      return SalesScreen(billId: _billId);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F8),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: _loading
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 18),
                        Text(
                          'Khan Baba POS is preparing your local database...',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 8),
                        Text('First startup may take a little longer.'),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 52),
                        const SizedBox(height: 12),
                        const Text(
                          'Khan Baba POS could not start',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'The app could not initialize its local database. No administrator access is required. '
                          'Check that the Windows user profile is writable and that office security software has not blocked the app.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        SelectableText(
                          _error?.toString() ?? 'Unknown startup error',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                        if (_logPath != null) ...[
                          const SizedBox(height: 12),
                          const Text('Diagnostic log:'),
                          SelectableText(_logPath!, style: const TextStyle(fontSize: 12)),
                        ] else ...[
                          const SizedBox(height: 12),
                          const Text(
                            'A diagnostic log could not be saved. Please check the Windows user profile folder permissions.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _loading ? null : _initialize,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry startup'),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
