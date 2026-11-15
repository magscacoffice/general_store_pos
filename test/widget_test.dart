import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khan_baba_general_store/main.dart';

void main() {
  testWidgets('Khan Baba POS MaterialApp shell launches', (WidgetTester tester) async {
    await tester.pumpWidget(
      const KhanBabaPOSApp(
        home: Scaffold(
          body: Center(child: Text('Khan Baba POS test shell')),
        ),
      ),
    );

    expect(find.text('Khan Baba POS test shell'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
