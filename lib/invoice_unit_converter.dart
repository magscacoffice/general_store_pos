/// Converts supplier invoice pack quantities into the product's integer stock unit.
class InvoiceUnitConverter {
  InvoiceUnitConverter._();

  static String normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z]'), '');

  static String canonicalUnit(String value) {
    final unit = normalize(value);
    if (const ['pc', 'pcs', 'piece', 'pieces', 'unit', 'units'].contains(unit)) {
      return 'pcs';
    }
    if (const ['kg', 'kgs', 'kilogram', 'kilograms'].contains(unit)) return 'kg';
    if (const ['g', 'gm', 'gram', 'grams'].contains(unit)) return 'g';
    if (const ['l', 'ltr', 'litre', 'litres', 'liter', 'liters'].contains(unit)) {
      return 'l';
    }
    if (const ['ml', 'millilitre', 'millilitres', 'milliliter', 'milliliters']
        .contains(unit)) return 'ml';
    if (const ['dz', 'dozen', 'dozens'].contains(unit)) return 'dozen';
    return unit;
  }

  /// Returns invoice units per stock unit, or null when the pack size is unknown.
  static double? suggestedFactor({
    required String invoiceUnit,
    required String stockUnit,
  }) {
    final invoice = canonicalUnit(invoiceUnit);
    final stock = canonicalUnit(stockUnit);
    if (invoice.isEmpty || stock.isEmpty) return null;
    if (invoice == stock) return 1;
    if (invoice == 'dozen' && stock == 'pcs') return 12;
    if (invoice == 'kg' && stock == 'g') return 1000;
    if (invoice == 'g' && stock == 'kg') return 0.001;
    if (invoice == 'l' && stock == 'ml') return 1000;
    if (invoice == 'ml' && stock == 'l') return 0.001;
    return null;
  }

  /// Converts invoice quantity to the integer stock quantity used by the POS.
  /// For example, 1.5 cartons x 12 pieces = 18 pieces.
  static int toStockQuantity({
    required double invoiceQuantity,
    required double conversionFactor,
  }) {
    if (!invoiceQuantity.isFinite || invoiceQuantity <= 0) {
      throw ArgumentError.value(invoiceQuantity, 'invoiceQuantity',
          'Invoice quantity must be a positive number.');
    }
    if (!conversionFactor.isFinite || conversionFactor <= 0) {
      throw ArgumentError.value(conversionFactor, 'conversionFactor',
          'Pack conversion factor must be a positive number.');
    }
    final converted = invoiceQuantity * conversionFactor;
    if (!converted.isFinite || converted > 2147483647) {
      throw RangeError('Converted stock quantity is outside the supported range.');
    }
    final rounded = converted.round();
    if ((converted - rounded).abs() > 0.000001 || rounded <= 0) {
      throw ArgumentError(
        'Converted stock quantity must be a whole number. Use a smaller stock unit, such as grams instead of kilograms.',
      );
    }
    return rounded;
  }

  static double baseUnitCost({
    required double lineTotal,
    required int stockQuantity,
  }) {
    if (!lineTotal.isFinite || lineTotal < 0 || stockQuantity <= 0) {
      throw ArgumentError('Line total and converted stock quantity are invalid.');
    }
    return lineTotal / stockQuantity;
  }
}
