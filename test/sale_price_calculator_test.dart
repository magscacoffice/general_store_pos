import 'package:flutter_test/flutter_test.dart';
import '../lib/sale_price_calculator.dart';

void main() {
  group('SalePriceCalculator', () {
    test('uses positive wholesale rate for Wholesale customer', () {
      expect(
        SalePriceCalculator.defaultPrice(
          customerType: 'Wholesale',
          retailPrice: 22,
          wholesalePrice: 18,
          purchasePrice: 10,
        ),
        18,
      );
    });

    test('falls back to retail rate when wholesale rate is zero', () {
      expect(
        SalePriceCalculator.defaultPrice(
          customerType: 'Wholesale',
          retailPrice: 22,
          wholesalePrice: 0,
          purchasePrice: 10,
        ),
        22,
      );
    });

    test('never returns a sale price below purchase cost', () {
      expect(
        SalePriceCalculator.defaultPrice(
          customerType: 'Wholesale',
          retailPrice: 22,
          wholesalePrice: 15,
          purchasePrice: 20,
        ),
        20,
      );
    });
  });
}
