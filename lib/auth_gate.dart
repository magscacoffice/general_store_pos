import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'dashboard_screen.dart';
import 'login_screen.dart';
import 'db_helper.dart';

const String storeId = 'khan-baba-general-store';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  User? _lastUser;
  Future<Map<String, dynamic>?>? _membershipFuture;
  bool _membershipRevoked = false;

  DocumentReference<Map<String, dynamic>> _membershipRef(User user) =>
      FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('members')
          .doc(user.uid);

  bool _isAllowed(Map<String, dynamic>? data) =>
      data != null &&
      data['active'] == true &&
      ['admin', 'salesman'].contains(data['role']);

  Future<Map<String, dynamic>?> _membership(User user) async {
    final ref = _membershipRef(user);

    // Firestore's local cache lets an already-authorized device open POS
    // without waiting for a network permission check.
    try {
      final cached = await ref
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 3));
      final cachedData = cached.data();
      if (_isAllowed(cachedData)) {
        DBHelper.startAutoSync();
        unawaited(DBHelper.syncAllData());
        unawaited(_verifyMembershipOnline(user));
        return cachedData;
      }
    } catch (_) {
      // No cached membership is normal on a first login/device.
    }

    final serverSnapshot = await ref
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 8));
    final serverData = serverSnapshot.data();
    if (_isAllowed(serverData)) {
      DBHelper.startAutoSync();
      unawaited(DBHelper.syncAllData());
      return serverData;
    }
    return serverData;
  }

  Future<void> _verifyMembershipOnline(User user) async {
    try {
      final snapshot = await _membershipRef(user)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      if (!_isAllowed(snapshot.data())) {
        await DBHelper.stopAutoSync();
        if (mounted && _lastUser?.uid == user.uid) {
          setState(() => _membershipRevoked = true);
        }
      }
    } catch (_) {
      // Keep cached access during temporary network loss.
    }
  }

  Future<Map<String, dynamic>?> _membershipFor(User user) {
    if (_lastUser?.uid != user.uid || _membershipFuture == null) {
      _lastUser = user;
      _membershipRevoked = false;
      _membershipFuture = _membership(user);
    }
    return _membershipFuture!;
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
        if (user == null) {
          _lastUser = null;
          _membershipFuture = null;
          _membershipRevoked = false;
          DBHelper.stopAutoSync();
          return const LoginScreen();
        }

        return FutureBuilder<Map<String, dynamic>?>(
          future: _membershipFor(user),
          builder: (context, memberSnapshot) {
            if (_membershipRevoked) {
              return const _StatusScreen(
                message: 'Aapka store access admin ne band kar diya hai.',
                showSignOut: true,
              );
            }
            if (memberSnapshot.connectionState == ConnectionState.waiting) {
              return const _StatusScreen(message: 'Store permission check ho rahi hai...');
            }
            if (memberSnapshot.hasError) {
              return _StatusScreen(
                message: 'Pehli dafa store permission check karne ke liye internet zaroori hai.\n${memberSnapshot.error}',
                showSignOut: true,
              );
            }
            final data = memberSnapshot.data;
            if (!_isAllowed(data)) {
              return const _StatusScreen(
                message: 'Aapka account is store ke liye active nahi hai. Admin se rabta karein.',
                showSignOut: true,
              );
            }
            return DashboardScreen(role: data!['role'] as String);
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
