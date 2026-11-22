using System.Text;
using System.Text.Json;
using KhanBabaPos.Wpf.Services;
using Xunit;

namespace KhanBabaPos.Wpf.Tests;

public sealed class EscPosReceiptBuilderTests
{
    private static SaleHistoryRecord SampleSale(string customerName = "Test Customer",
        string customerPhone = "03001234567", double received = 500, double due = 600,
        double subtotal = 1200, double discount = 100, double finalAmount = 1100) =>
        new(42, "2026-11-18 08:30:00", customerName, "Khata", "Partial",
            subtotal, discount, finalAmount, received, due, "Cashier One", 0, 0, 7, "cashier-uid", customerPhone);

    private static IReadOnlyList<SaleHistoryItem> SampleItems(string name = "Milk 1L") =>
        [new SaleHistoryItem(1, "123", name, 2, "pcs", 100, 70, 200, 140)];

    [Fact]
    public void ReceiptTextMatchesAndroidMasterOrderAndIncludesCustomerPhone()
    {
        var text = EscPosReceiptBuilder.BuildText(SampleSale(), SampleItems(), new PrinterPreferences());
        var expected = new[]
        {
            "KHAN BABA", "GENERAL STORE", "G.T ROAD SANAWAN", "PH#03451444325",
            "Bill# 000042", "Cashier: Cashier One", "Type: Khata", "Customer: Test Customer",
            "Qty", "Description", "Rate", "Amount", "Total Items: 1", "Gross: 1200",
            "Discount", "NET AMOUNT: Rs. 1100", "Payment: Partial", "Received",
            "Balance Due", "Phone: 03001234567", "THANK YOU - VISIT AGAIN"
        };
        var cursor = -1;
        foreach (var term in expected)
        {
            var next = text.IndexOf(term, cursor + 1, StringComparison.Ordinal);
            Assert.True(next >= 0, $"Missing or out-of-order receipt content: {term}");
            cursor = next;
        }
    }

    [Fact]
    public void ReceiptRemovesWholeNumberDecimalsAndKeepsMeaningfulFractions()
    {
        var sale = SampleSale(received: 125, due: 0, subtotal: 125.5, discount: 0.5, finalAmount: 125);
        var items = new[] { new SaleHistoryItem(1, "123", "Milk", 1, "pcs", 125.5, 100, 125.5, 100) };
        var text = EscPosReceiptBuilder.BuildText(sale, items, new PrinterPreferences());
        Assert.Contains("Gross: 125.5", text);
        Assert.Contains("NET AMOUNT: Rs. 125", text);
        Assert.DoesNotContain("125.50", text);
        Assert.DoesNotContain("125.00", text);
    }

    [Fact]
    public void ReceiptUsesFortyFiveColumnsAndTruncatesLongCustomerAndProductLabels()
    {
        var text = EscPosReceiptBuilder.BuildText(SampleSale(new string('C', 90)),
            SampleItems(new string('P', 90)), new PrinterPreferences());
        var visibleLines = text.Replace("\r", string.Empty).Split('\n').Where(line => line.Length > 0);
        Assert.All(visibleLines, line => Assert.True(line.Length <= 45, $"Line exceeded 80mm width: {line}"));
        Assert.Contains("PPPPPPPPPPPPPPP..", text);
        Assert.Contains("Customer: " + new string('C', 32) + "..", text);
    }

    [Fact]
    public void EscPosBytesSetEightyMillimeterWidthMarginsEmphasisAndCutter()
    {
        var prefs = new PrinterPreferences();
        var bytes = EscPosReceiptBuilder.BuildBytes(
            EscPosReceiptBuilder.BuildText(SampleSale(), SampleItems(), prefs), prefs);
        Assert.True(Contains(bytes, 0x1D, 0x4C, 16, 0, 0x1D, 0x57, 32, 2));
        Assert.Equal(2, CountSequence(bytes, 0x1B, 0x4A, 16));
        Assert.False(Contains(bytes, 0x1B, 0x4A, 24));
        Assert.False(Contains(bytes, 0x1B, 0x4A, 32));
        Assert.True(Contains(bytes, 0x1B, 0x61, 1, 0x1B, 0x45, 1, 0x1D, 0x21, 0x11));
        Assert.True(Contains(bytes, 0x1D, 0x21, 0x10));
        Assert.Equal(new byte[] { 0x1D, 0x56, 0x00 }, bytes[^3..]);
    }

    [Fact]
    public void CashChangeIsHandledWithoutInventingTax()
    {
        var sale = SampleSale(received: 1200, due: 0);
        var prefs = new PrinterPreferences();
        var text = EscPosReceiptBuilder.BuildText(sale, SampleItems(), prefs);
        Assert.Contains("Change", text);
        Assert.DoesNotContain("Balance Due", text);
        Assert.DoesNotContain("Tax (GST)", text);
        Assert.Equal(2, CountSequence(EscPosReceiptBuilder.BuildBytes(text, prefs), 0x1B, 0x4A, 16));
    }

    [Fact]
    public void PdfUsesReceiptRollWidthAndIncludesBoldHeaderAndNetTotal()
    {
        var text = EscPosReceiptBuilder.BuildText(SampleSale(), SampleItems(), new PrinterPreferences());
        var pdf = Encoding.ASCII.GetString(PdfReceiptBuilder.Build(text, new PrinterPreferences()));
        Assert.StartsWith("%PDF-1.4", pdf);
        Assert.Contains("/MediaBox [0 0 226.77", pdf);
        Assert.Contains("/BaseFont /Courier-Bold", pdf);
        Assert.Contains("NET AMOUNT: Rs. 1100", pdf);
    }

    [Fact]
    public void LegacyPrinterMarginValuesAreIgnoredAndCannotChangeReceiptOutput()
    {
        const string legacyJson = """{"PreferredPrinter":"Black Copper BC-86AC","PaperWidthMm":80,"TopMarginMm":9,"BottomMarginMm":7,"HeaderSize":3,"TotalSize":2}""";
        var legacy = JsonSerializer.Deserialize<PrinterPreferences>(legacyJson);
        Assert.Equal("Black Copper BC-86AC", legacy?.PreferredPrinter);

        var current = new PrinterPreferences("Black Copper BC-86AC");
        var text = EscPosReceiptBuilder.BuildText(SampleSale(), SampleItems(), current);
        Assert.Equal(
            EscPosReceiptBuilder.BuildBytes(text, current),
            EscPosReceiptBuilder.BuildBytes(text, legacy ?? new PrinterPreferences()));
        var savedJson = JsonSerializer.Serialize(legacy);
        Assert.DoesNotContain("TopMarginMm", savedJson, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("BottomMarginMm", savedJson, StringComparison.OrdinalIgnoreCase);
    }

    private static int CountSequence(byte[] source, params byte[] value)
    {
        var count = 0;
        for (var i = 0; i <= source.Length - value.Length; i++)
        {
            var match = true;
            for (var j = 0; j < value.Length; j++)
                if (source[i + j] != value[j]) { match = false; break; }
            if (match) count++;
        }
        return count;
    }

    private static bool Contains(byte[] source, params byte[] value)
    {
        for (var i = 0; i <= source.Length - value.Length; i++)
        {
            var match = true;
            for (var j = 0; j < value.Length; j++)
                if (source[i + j] != value[j]) { match = false; break; }
            if (match) return true;
        }
        return false;
    }
}
