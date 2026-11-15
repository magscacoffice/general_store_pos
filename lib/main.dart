import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'auth_gate.dart';
import 'drive_sync_service.dart';
import 'update_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  try {
    await DriveSyncService.initialize();
  } catch (error) {
    debugPrint('Cloud sync initialization deferred: $error');
  }
  runApp(const KhanBabaPOSApp());
}

class KhanBabaPOSApp extends StatelessWidget {
  const KhanBabaPOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Khan Baba General Store',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const UpdateAwareHome(child: AuthGate()),
    );
  }
}
