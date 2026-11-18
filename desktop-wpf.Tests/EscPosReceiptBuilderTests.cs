using System.Text;
using KhanBabaPos.Wpf.Services;
using Xunit;

namespace KhanBabaPos.Wpf.Tests;

public sealed class EscPosReceiptBuilderTests
{
    private static SaleHistoryRecord SampleSale(string customerName = "Test Customer",
        string customerPhone = "03001234567", double received = 500, double due = 600) =>
        new(42, "2026-11-18 08:30:00", customerName, "Khata", "Partial",
            1200, 100, 1100, received, due, "Cashier One", 0, 0, 7, "cashier-uid", customerPhone);

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
            "Qty", "Description", "Rate", "Amount", "Total Items: 1", "Gross: 1200.00",
            "Discount", "NET AMOUNT: Rs. 1100.00", "Payment: Partial", "Received",
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
        var prefs = new PrinterPreferences(TopMarginMm: 3, BottomMarginMm: 4);
        var bytes = EscPosReceiptBuilder.BuildBytes(
            EscPosReceiptBuilder.BuildText(SampleSale(), SampleItems(), prefs), prefs);
        Assert.True(Contains(bytes, 0x1D, 0x4C, 16, 0, 0x1D, 0x57, 32, 2));
        Assert.True(Contains(bytes, 0x1B, 0x4A, 24));
        Assert.True(Contains(bytes, 0x1B, 0x4A, 32));
        Assert.True(Contains(bytes, 0x1B, 0x61, 1, 0x1B, 0x45, 1, 0x1D, 0x21, 0x11));
        Assert.True(Contains(bytes, 0x1D, 0x21, 0x10));
        Assert.Equal(new byte[] { 0x1D, 0x56, 0x00 }, bytes[^3..]);
    }

    [Fact]
    public void ZeroMarginsAndCashChangeAreHandledWithoutInventingTax()
    {
        var sale = SampleSale(received: 1200, due: 0);
        var prefs = new PrinterPreferences(TopMarginMm: 0, BottomMarginMm: 0);
        var text = EscPosReceiptBuilder.BuildText(sale, SampleItems(), prefs);
        Assert.Contains("Change", text);
        Assert.DoesNotContain("Balance Due", text);
        Assert.DoesNotContain("Tax (GST)", text);
        Assert.False(Contains(EscPosReceiptBuilder.BuildBytes(text, prefs), 0x1B, 0x4A));
    }

    [Fact]
    public void PdfUsesReceiptRollWidthAndIncludesBoldHeaderAndNetTotal()
    {
        var text = EscPosReceiptBuilder.BuildText(SampleSale(), SampleItems(), new PrinterPreferences());
        var pdf = Encoding.ASCII.GetString(PdfReceiptBuilder.Build(text, new PrinterPreferences()));
        Assert.StartsWith("%PDF-1.4", pdf);
        Assert.Contains("/MediaBox [0 0 226.77", pdf);
        Assert.Contains("/BaseFont /Courier-Bold", pdf);
        Assert.Contains("NET AMOUNT: Rs. 1100.00", pdf);
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
