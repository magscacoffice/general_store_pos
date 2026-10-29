import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'dashboard_screen.dart';

void main() async {
  // 1. App ko crash hone se bachane ke liye zaroori initialization
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Firebase aur Local Database initialization
  try {
    await Firebase.initializeApp();
    debugPrint("Firebase initialized successfully...");
  } catch (e) {
    debugPrint("Firebase initialization error: $e");
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
      // Direct DashboardScreen ko home screen set kar diya hai
      home: const DashboardScreen(),
    );
  }
}
