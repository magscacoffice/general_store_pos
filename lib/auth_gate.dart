import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'dashboard_screen.dart';
import 'login_screen.dart';

const String storeId = 'khan-baba-general-store';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<DocumentSnapshot<Map<String, dynamic>>> _membership(User user) {
    return FirebaseFirestore.instance
        .collection('stores')
        .doc(storeId)
        .collection('members')
        .doc(user.uid)
        .get();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const _StatusScreen(message: 'Account check ho raha hai...');
        }
        final user = authSnapshot.data;
        if (user == null) return const LoginScreen();

        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: _membership(user),
          builder: (context, memberSnapshot) {
            if (memberSnapshot.connectionState == ConnectionState.waiting) {
              return const _StatusScreen(message: 'Store permission check ho rahi hai...');
            }
            if (memberSnapshot.hasError) {
              return _StatusScreen(
                message: 'Permission check nahi ho saki. Internet aur Firestore Rules check karein.\n${memberSnapshot.error}',
                showSignOut: true,
              );
            }
            final data = memberSnapshot.data?.data();
            if (data == null || data['active'] != true ||
                !['admin', 'salesman'].contains(data['role'])) {
              return const _StatusScreen(
                message: 'Aapka account is store ke liye active nahi hai. Admin se rabta karein.',
                showSignOut: true,
              );
            }
            return const DashboardScreen();
          },
        );
      },
    );
  }
}

class _StatusScreen extends StatelessWidget {
  final String message;
  final bool showSignOut;
  const _StatusScreen({required this.message, this.showSignOut = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.store, size: 56, color: Colors.teal),
              const SizedBox(height: 18),
              Text(message, textAlign: TextAlign.center),
              if (showSignOut) ...[
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
