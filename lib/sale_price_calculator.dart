class SalePriceCalculator {
  const SalePriceCalculator._();

  static double defaultPrice({
    required String customerType,
    required double retailPrice,
    required double wholesalePrice,
    required double purchasePrice,
  }) {
    final requestedPrice = customerType == 'Wholesale' && wholesalePrice > 0
        ? wholesalePrice
        : retailPrice;
    return requestedPrice < purchasePrice ? purchasePrice : requestedPrice;
  }
}
