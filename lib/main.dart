import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'auth_gate.dart';
import 'dashboard_screen.dart';
import 'db_helper.dart';

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

Future<void> main() async {
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
    runApp(const KhanBabaPOSApp(windowsLocalMode: true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_writeWindowsStartupLog('First Dart frame rendered.'));
    });
    return;
  }

  await Firebase.initializeApp();
  runApp(const KhanBabaPOSApp());
}

class KhanBabaPOSApp extends StatelessWidget {
  final bool windowsLocalMode;

  const KhanBabaPOSApp({super.key, this.windowsLocalMode = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Khan Baba General Store',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: windowsLocalMode ? const WindowsStartupGate() : const AuthGate(),
    );
  }
}

class WindowsStartupGate extends StatefulWidget {
  const WindowsStartupGate({super.key});

  @override
  State<WindowsStartupGate> createState() => _WindowsStartupGateState();
}

class _WindowsStartupGateState extends State<WindowsStartupGate> {
  bool _loading = true;
  bool _ready = false;
  Object? _error;
  String? _logPath;

  @override
  void initState() {
    super.initState();
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
      unawaited(_writeWindowsStartupLog('Local database opened successfully.'));

      if (!mounted) return;
      setState(() {
        _ready = true;
        _loading = false;
        _error = null;
      });
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
    if (_ready) return const WindowsRenderDiagnosticScreen();

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


/// Temporary Windows-only rendering probe.
///
/// This deliberately starts with a very small, high-contrast Flutter screen.
/// If this screen is visible, the Windows Flutter renderer is working and the
/// Dashboard can be opened separately to isolate any dashboard-specific issue.
class WindowsRenderDiagnosticScreen extends StatefulWidget {
  const WindowsRenderDiagnosticScreen({super.key});

  @override
  State<WindowsRenderDiagnosticScreen> createState() =>
      _WindowsRenderDiagnosticScreenState();
}

class _WindowsRenderDiagnosticScreenState
    extends State<WindowsRenderDiagnosticScreen> {
  bool _showDashboard = false;
  bool _dashboardFrameLogged = false;

  @override
  Widget build(BuildContext context) {
    if (_showDashboard) {
      if (!_dashboardFrameLogged) {
        _dashboardFrameLogged = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_writeWindowsStartupLog(
              'Dashboard screen first frame completed after diagnostic probe.'));
        });
      }
      return const DashboardScreen(role: 'admin');
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B6E69),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Card(
              color: Colors.white,
              margin: const EdgeInsets.all(28),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.desktop_windows,
                        size: 72, color: Color(0xFF0B6E69)),
                    const SizedBox(height: 20),
                    const Text(
                      'KHAN BABA POS',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF164B48),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Windows display test passed',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Agar yeh screen nazar aa rahi hai to Flutter ki basic '
                      'screen rendering kaam kar rahi hai. Ab Dashboard ko '
                      'alag se test karne ke liye neeche button dabayen.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.black87),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          unawaited(_writeWindowsStartupLog(
                              'User opened Dashboard from Windows rendering probe.'));
                          setState(() => _showDashboard = true);
                        },
                        icon: const Icon(Icons.dashboard),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Open POS Dashboard',
                              style: TextStyle(fontSize: 17)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
