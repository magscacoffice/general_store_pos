import 'package:flutter_test/flutter_test.dart';
import 'package:khan_baba_general_store/invoice_unit_converter.dart';

void main() {
  group('InvoiceUnitConverter', () {
    test('converts fractional cartons into whole stock pieces', () {
      expect(
        InvoiceUnitConverter.toStockQuantity(
          invoiceQuantity: 1.5,
          conversionFactor: 12,
        ),
        18,
      );
    });

    test('suggests common dozen, weight and volume conversions', () {
      expect(InvoiceUnitConverter.suggestedFactor(invoiceUnit: 'dozen', stockUnit: 'pcs'), 12);
      expect(InvoiceUnitConverter.suggestedFactor(invoiceUnit: 'kgs', stockUnit: 'g'), 1000);
      expect(InvoiceUnitConverter.suggestedFactor(invoiceUnit: 'litre', stockUnit: 'ml'), 1000);
    });

    test('requires a user-defined factor for carton and box units', () {
      expect(InvoiceUnitConverter.suggestedFactor(invoiceUnit: 'carton', stockUnit: 'pcs'), isNull);
      expect(InvoiceUnitConverter.suggestedFactor(invoiceUnit: 'box', stockUnit: 'pcs'), isNull);
    });

    test('rejects converted quantities that cannot be represented in integer stock', () {
      expect(
        () => InvoiceUnitConverter.toStockQuantity(
          invoiceQuantity: 0.5,
          conversionFactor: 1,
        ),
        throwsArgumentError,
      );
    });

    test('calculates the base-unit purchase cost', () {
      expect(
        InvoiceUnitConverter.baseUnitCost(lineTotal: 2400, stockQuantity: 24),
        100,
      );
    });
  });
}
