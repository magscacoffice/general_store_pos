import 'package:flutter_test/flutter_test.dart';
import 'package:khan_baba_general_store/printer_screen.dart';

void main() {
  test('receipt money removes insignificant zeroes and preserves fractions', () {
    expect(formatReceiptMoney(125.0), '125');
    expect(formatReceiptMoney(0.0), '0');
    expect(formatReceiptMoney(125.5), '125.5');
    expect(formatReceiptMoney(125.25), '125.25');
    expect(formatReceiptMoney(0.1), '0.1');
  });
}
