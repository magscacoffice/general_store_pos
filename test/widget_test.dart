import 'package:flutter_test/flutter_test.dart';
import 'package:khan_baba_general_store/main.dart';

void main() {
  testWidgets('Khan Baba POS app launches', (WidgetTester tester) async {
    await tester.pumpWidget(const KhanBabaPOSApp());
    await tester.pump();
  });
}
