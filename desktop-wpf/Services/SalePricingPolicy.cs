namespace KhanBabaPos.Wpf.Services;

public static class SalePricingPolicy
{
    public static double DefaultPrice(
        string customerType,
        double retailPrice,
        double wholesalePrice,
        double purchasePrice)
    {
        var requestedPrice = customerType == "Wholesale" && wholesalePrice > 0
            ? wholesalePrice
            : retailPrice;
        return Math.Max(requestedPrice, purchasePrice);
    }
}

// Authorized main-branch test artifact build trigger: 2026-11-26.
