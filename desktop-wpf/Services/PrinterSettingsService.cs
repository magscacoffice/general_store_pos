using System.ComponentModel;
using System.IO;
using System.Globalization;
using System.Printing;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using KhanBabaPos.Wpf.Services;
namespace KhanBabaPos.Wpf.Services;
public sealed class PrinterSettingsService
{
 static string SettingsPath=>Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"KhanBabaPOS","printer-settings.json");
 public async Task<PrinterPreferences> LoadAsync(CancellationToken ct=default){try{if(!File.Exists(SettingsPath))return new PrinterPreferences();var json=await File.ReadAllTextAsync(SettingsPath,ct);return JsonSerializer.Deserialize<PrinterPreferences>(json)??new PrinterPreferences();}catch{return new PrinterPreferences();}}
 public async Task SaveAsync(PrinterPreferences value,CancellationToken ct=default){
        // Administrative settings mutation remains restricted to Admin.
        AccessService.RequireCurrentAdmin();
        await WritePreferencesAsync(value,ct);
    }
 public async Task SaveWorkstationAsync(PrinterPreferences value,CancellationToken ct=default){
        // Selecting a local printer and tuning receipt output are workstation
        // preferences, not business-data mutations. Both staff roles may use them.
        AccessService.RequireCurrentRole(AccessRole.Admin,AccessRole.Salesman);
        await WritePreferencesAsync(value,ct);
    }
 async Task WritePreferencesAsync(PrinterPreferences value,CancellationToken ct){
        var dir=Path.GetDirectoryName(SettingsPath)!;
        Directory.CreateDirectory(dir);
        await File.WriteAllTextAsync(SettingsPath,JsonSerializer.Serialize(value,new JsonSerializerOptions{WriteIndented=true}),ct);
    }
 public Task<IReadOnlyList<PrinterQueueInfo>> GetInstalledAsync(CancellationToken ct=default)=>Task.Run<IReadOnlyList<PrinterQueueInfo>>(()=>{using var server=new LocalPrintServer();var rows=new List<PrinterQueueInfo>();foreach(var q in server.GetPrintQueues()){q.Refresh();var status=q.QueueStatus;var unavailable=PrintQueueStatus.Offline|PrintQueueStatus.NotAvailable|PrintQueueStatus.Error|PrintQueueStatus.PaperOut|PrintQueueStatus.PaperProblem|PrintQueueStatus.Paused|PrintQueueStatus.DoorOpen|PrintQueueStatus.UserIntervention|PrintQueueStatus.PendingDeletion;var ready=(status&unavailable)==0;rows.Add(new PrinterQueueInfo(q.Name,ready,status.ToString()));q.Dispose();}return rows.OrderBy(x=>x.Name,StringComparer.OrdinalIgnoreCase).ToList();},ct);
 public async Task PrintRawAsync(string printerName,byte[] bytes,CancellationToken ct=default){
        AccessService.RequireCurrentRole(AccessRole.Admin, AccessRole.Salesman);if(string.IsNullOrWhiteSpace(printerName))throw new InvalidOperationException("Select a printer first.");await Task.Run(()=>RawPrinter.Send(printerName,bytes),ct);}
}
public sealed record PrinterQueueInfo(string Name,bool IsAvailable,string Status){public string DisplayStatus=>IsAvailable?"Available":"Unavailable";}
public sealed record PrinterPreferences(string? PreferredPrinter=null,int PaperWidthMm=80,int TopMarginMm=2,int BottomMarginMm=2);
internal static class RawPrinter
{
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]struct DocInfo{[MarshalAs(UnmanagedType.LPWStr)]public string DocumentName;[MarshalAs(UnmanagedType.LPWStr)]public string OutputFile;[MarshalAs(UnmanagedType.LPWStr)]public string DataType;}
 [DllImport("winspool.drv",SetLastError=true,CharSet=CharSet.Unicode)]static extern bool OpenPrinter(string name,out IntPtr handle,IntPtr defaults);
 [DllImport("winspool.drv",SetLastError=true)]static extern bool ClosePrinter(IntPtr handle);
 [DllImport("winspool.drv",SetLastError=true,CharSet=CharSet.Unicode)]static extern int StartDocPrinter(IntPtr handle,int level,ref DocInfo info);
 [DllImport("winspool.drv",SetLastError=true)]static extern bool EndDocPrinter(IntPtr handle);
 [DllImport("winspool.drv",SetLastError=true)]static extern bool StartPagePrinter(IntPtr handle);
 [DllImport("winspool.drv",SetLastError=true)]static extern bool EndPagePrinter(IntPtr handle);
 [DllImport("winspool.drv",SetLastError=true)]static extern bool WritePrinter(IntPtr handle,IntPtr buffer,int count,out int written);
 public static void Send(string printer,byte[] data){if(!OpenPrinter(printer,out var h,IntPtr.Zero))throw new Win32Exception(Marshal.GetLastWin32Error(),"Windows printer queue open nahi ho saki.");try{var doc=new DocInfo{DocumentName="Khan Baba POS Receipt",OutputFile=string.Empty,DataType="RAW"};if(StartDocPrinter(h,1,ref doc)==0)throw new Win32Exception(Marshal.GetLastWin32Error(),"Printer document start nahi hua.");try{if(!StartPagePrinter(h))throw new Win32Exception(Marshal.GetLastWin32Error(),"Printer page start nahi hua.");var ptr=Marshal.AllocHGlobal(data.Length);try{Marshal.Copy(data,0,ptr,data.Length);if(!WritePrinter(h,ptr,data.Length,out var written)||written!=data.Length)throw new Win32Exception(Marshal.GetLastWin32Error(),"Receipt data printer ko complete send nahi hui.");}finally{Marshal.FreeHGlobal(ptr);}if(!EndPagePrinter(h))throw new Win32Exception(Marshal.GetLastWin32Error(),"Printer page finish nahi hua.");}finally{EndDocPrinter(h);}}finally{ClosePrinter(h);}}
}
public static class EscPosReceiptBuilder
{
    private const int PaperDots = 576;
    private const int HorizontalMarginDots = 16;
    private const int Columns = 45;
    private static readonly Encoding Ascii = Encoding.ASCII;

    public static string BuildText(SaleHistoryRecord? sale, IReadOnlyList<SaleHistoryItem> items, PrinterPreferences prefs)
    {
        if (sale is null)
            return "KHAN BABA GENERAL STORE\nPrinter configured. Select an invoice to preview its receipt.";

        var separator = new string('-', Columns);
        var date = DateTime.TryParse(sale.Date, CultureInfo.InvariantCulture, DateTimeStyles.AssumeLocal, out var parsed)
            ? parsed : DateTime.Now;
        var b = new StringBuilder();

        b.AppendLine(Center("KHAN BABA"));
        b.AppendLine(Center("GENERAL STORE"));
        b.AppendLine(Center("G.T ROAD SANAWAN"));
        b.AppendLine(Center("PH#03451444325"));
        b.AppendLine();
        b.AppendLine(sale.SaleId <= 0
            ? Pair("DRAFT PREVIEW", $"Date: {date:dd/MM/yy}")
            : Pair($"Bill# {sale.SaleId:D6}", $"Date: {date:dd/MM/yy}"));
        b.AppendLine(Pair($"Cashier: {sale.Cashier}", $"Time: {date:hh:mm:ss tt}"));
        b.AppendLine(Pair($"Type: {sale.CustomerType}", string.Empty));
        b.AppendLine(Pair($"Customer: {sale.CustomerName}", string.Empty));
        b.AppendLine(separator);
        b.AppendLine(ItemHeader());
        b.AppendLine(separator);
        foreach (var item in items)
            b.AppendLine(ItemRow(item));
        b.AppendLine(separator);
        b.AppendLine(Pair($"Total Items: {items.Count}", $"Gross: {Money(sale.Subtotal)}"));
        b.AppendLine(Pair("Discount", Money(sale.Discount)));
        b.AppendLine(separator);
        b.AppendLine(Center($"NET AMOUNT: Rs. {Money(sale.FinalAmount)}"));
        b.AppendLine(separator);
        b.AppendLine(Pair($"Payment: {sale.PaymentType}", string.Empty));
        b.AppendLine(Pair("Received", Money(sale.Received)));
        if (sale.BalanceDue > 0)
            b.AppendLine(Pair("Balance Due", Money(sale.BalanceDue)));
        var change = Math.Max(0d, sale.Received - sale.FinalAmount);
        if (change > 0)
            b.AppendLine(Pair("Change", Money(change)));
        if (sale.ReturnedAmount > 0)
            b.AppendLine(Pair("Returned", Money(sale.ReturnedAmount)));
        if (!string.IsNullOrWhiteSpace(sale.CustomerPhone))
            b.AppendLine(Pair($"Phone: {sale.CustomerPhone}", string.Empty));
        b.AppendLine(separator);
        b.AppendLine(Center("THANK YOU - VISIT AGAIN"));
        b.AppendLine(Center("KHAN BABA GENERAL STORE"));
        b.AppendLine();
        b.AppendLine();
        return b.ToString();
    }

    public static byte[] BuildBytes(string text, PrinterPreferences prefs)
    {
        using var ms = new MemoryStream();
        void B(params byte[] bytes) => ms.Write(bytes, 0, bytes.Length);

        B(0x1B, 0x40);
        var left = HorizontalMarginDots;
        var width = PaperDots - (HorizontalMarginDots * 2);
        B(0x1D, 0x4C, (byte)(left & 0xFF), (byte)((left >> 8) & 0xFF));
        B(0x1D, 0x57, (byte)(width & 0xFF), (byte)((width >> 8) & 0xFF));

        var topDots = Math.Clamp(prefs.TopMarginMm, 0, 10) * 8;
        var bottomDots = Math.Clamp(prefs.BottomMarginMm, 0, 10) * 8;
        if (topDots > 0)
            B(0x1B, 0x4A, (byte)topDots);

        foreach (var line in (text ?? string.Empty).Replace("\r", string.Empty).Split('\n'))
        {
            var trimmed = line.Trim();
            if (trimmed.Length == 0)
            {
                B(0x0A);
                continue;
            }

            if (trimmed == "KHAN BABA")
                WriteStyledLine(B, trimmed, centered: true, bold: true, size: 0x11);
            else if (trimmed == "GENERAL STORE")
                WriteStyledLine(B, trimmed, centered: true, bold: true, size: 0x00);
            else if (trimmed is "G.T ROAD SANAWAN" or "PH#03451444325" or "THANK YOU - VISIT AGAIN" or "KHAN BABA GENERAL STORE")
                WriteStyledLine(B, trimmed, centered: true, bold: false, size: 0x00);
            else if (trimmed.StartsWith("NET AMOUNT:", StringComparison.Ordinal))
                WriteStyledLine(B, trimmed, centered: true, bold: true, size: 0x10);
            else
            {
                B(0x1B, 0x61, 0x00, 0x1B, 0x45, 0x00, 0x1D, 0x21, 0x00);
                B(Ascii.GetBytes(line));
                B(0x0A);
            }
        }

        if (bottomDots > 0)
            B(0x1B, 0x4A, (byte)bottomDots);
        B(0x1D, 0x56, 0x00);
        return ms.ToArray();
    }

    private static void WriteStyledLine(Action<byte[]> write, string value, bool centered, bool bold, byte size)
    {
        write([0x1B, 0x61, centered ? (byte)0x01 : (byte)0x00]);
        write([0x1B, 0x45, bold ? (byte)0x01 : (byte)0x00]);
        write([0x1D, 0x21, size]);
        write(Ascii.GetBytes(value));
        write([0x1D, 0x21, 0x00, 0x1B, 0x45, 0x00, 0x1B, 0x61, 0x00, 0x0A]);
    }

    private static string ItemHeader() =>
        "Qty".PadLeft(4) + " " + "Description".PadRight(17) +
        " " + "Rate".PadLeft(10) + " " + "Amount".PadLeft(11);

    private static string ItemRow(SaleHistoryItem item)
    {
        var qty = item.Quantity.ToString(CultureInfo.InvariantCulture);
        var rate = Money(item.SalePrice);
        var amount = Money(item.LineTotal);
        var qtyWidth = Math.Max(4, qty.Length);
        var rateWidth = Math.Max(10, rate.Length);
        var amountWidth = Math.Max(11, amount.Length);
        var descriptionWidth = Math.Clamp(Columns - qtyWidth - rateWidth - amountWidth - 3, 1, 17);
        var name = SingleLine(item.ProductName, descriptionWidth);
        var row = qty.PadLeft(qtyWidth) + " " + name.PadRight(descriptionWidth) +
                  " " + rate.PadLeft(rateWidth) + " " + amount.PadLeft(amountWidth);
        return row.Length <= Columns ? row : row[^Columns..];
    }

    private static string Money(double value) => value.ToString("0.00", CultureInfo.InvariantCulture);

    private static string SingleLine(string value, int maxWidth)
    {
        var safe = string.Join(' ', (value ?? string.Empty)
            .Replace('\r', ' ').Replace('\n', ' ').Replace('\t', ' ')
            .Split(' ', StringSplitOptions.RemoveEmptyEntries));
        if (safe.Length <= maxWidth)
            return safe;
        if (maxWidth <= 2)
            return safe[..maxWidth];
        return safe[..(maxWidth - 2)] + "..";
    }

    private static string Center(string value)
    {
        var safe = SingleLine(value, Columns);
        return safe.PadLeft((Columns + safe.Length) / 2).PadRight(Columns);
    }

    private static string Pair(string left, string right)
    {
        var safeRight = SingleLine(right, Columns);
        var safeLeft = SingleLine(left, Math.Max(0, Columns - safeRight.Length - 1));
        return safeLeft + new string(' ', Math.Max(1, Columns - safeLeft.Length - safeRight.Length)) + safeRight;
    }
}

public static class PdfReceiptBuilder
{
    private const double MmToPoints = 72d / 25.4d;
    private const double PageWidth = 80d * MmToPoints;

    public static byte[] Build(string text, PrinterPreferences? preferences = null)
    {
        preferences ??= new PrinterPreferences();
        var lines = (text ?? string.Empty).Replace("\r", string.Empty).Split('\n');
        var top = Math.Clamp(preferences.TopMarginMm, 0, 10) * MmToPoints;
        var bottom = Math.Clamp(preferences.BottomMarginMm, 0, 10) * MmToPoints;
        var side = 2d * MmToPoints;
        var pageHeight = top + bottom + 34d + Math.Max(1, lines.Length) * 10.5d;
        var body = new StringBuilder("BT\n");
        var y = pageHeight - top - 16d;

        foreach (var sourceLine in lines)
        {
            var line = sourceLine.TrimEnd();
            var trimmed = line.Trim();
            if (trimmed.Length == 0) { y -= 5d; continue; }

            var header = trimmed == "KHAN BABA";
            var store = trimmed == "GENERAL STORE";
            var total = trimmed.StartsWith("NET AMOUNT:", StringComparison.Ordinal);
            var centered = header || store || total || trimmed == "G.T ROAD SANAWAN" ||
                           trimmed == "PH#03451444325" || trimmed == "THANK YOU - VISIT AGAIN" ||
                           trimmed == "KHAN BABA GENERAL STORE";
            var bold = header || store || total;
            var size = header ? 14d : total ? 10.5d : store ? 8.5d : 7d;
            var value = centered ? trimmed : line;
            var width = value.Length * size * 0.6d;
            var x = centered ? Math.Max(side, (PageWidth - width) / 2d) : side;

            body.Append('/').Append(bold ? "F2" : "F1").Append(' ')
                .Append(size.ToString("0.##", CultureInfo.InvariantCulture)).Append(" Tf\n");
            body.Append("1 0 0 1 ")
                .Append(x.ToString("0.##", CultureInfo.InvariantCulture)).Append(' ')
                .Append(y.ToString("0.##", CultureInfo.InvariantCulture)).Append(" Tm\n");
            body.Append('(').Append(PdfEscape(Encoding.ASCII.GetString(Encoding.ASCII.GetBytes(value)))).Append(") Tj\n");
            y -= header ? 16d : total ? 14d : store ? 12d : 10.5d;
        }
        body.Append("ET\n");

        var streamBytes = Encoding.ASCII.GetBytes(body.ToString());
        var objects = new List<byte[]>
        {
            Encoding.ASCII.GetBytes("<< /Type /Catalog /Pages 2 0 R >>"),
            Encoding.ASCII.GetBytes("<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
            Encoding.ASCII.GetBytes($"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {PageWidth.ToString("0.##", CultureInfo.InvariantCulture)} {pageHeight.ToString("0.##", CultureInfo.InvariantCulture)}] /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> /Contents 4 0 R >>"),
            BuildStreamObject(streamBytes),
            Encoding.ASCII.GetBytes("<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>"),
            Encoding.ASCII.GetBytes("<< /Type /Font /Subtype /Type1 /BaseFont /Courier-Bold >>")
        };

        using var output = new MemoryStream();
        output.Write(Encoding.ASCII.GetBytes("%PDF-1.4\n"));
        var offsets = new List<long> { 0 };
        for (var i = 0; i < objects.Count; i++)
        {
            offsets.Add(output.Position);
            output.Write(Encoding.ASCII.GetBytes($"{i + 1} 0 obj\n"));
            output.Write(objects[i]);
            output.Write(Encoding.ASCII.GetBytes("\nendobj\n"));
        }

        var xref = output.Position;
        output.Write(Encoding.ASCII.GetBytes($"xref\n0 {objects.Count + 1}\n0000000000 65535 f \n"));
        foreach (var offset in offsets.Skip(1))
            output.Write(Encoding.ASCII.GetBytes($"{offset:0000000000} 00000 n \n"));
        output.Write(Encoding.ASCII.GetBytes($"trailer\n<< /Size {objects.Count + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF"));
        return output.ToArray();
    }

    private static byte[] BuildStreamObject(byte[] bytes)
    {
        using var stream = new MemoryStream();
        stream.Write(Encoding.ASCII.GetBytes($"<< /Length {bytes.Length} >>\nstream\n"));
        stream.Write(bytes);
        stream.Write(Encoding.ASCII.GetBytes("endstream"));
        return stream.ToArray();
    }

    private static string PdfEscape(string value) =>
        value.Replace("\\", "\\\\", StringComparison.Ordinal)
             .Replace("(", "\\(", StringComparison.Ordinal)
             .Replace(")", "\\)", StringComparison.Ordinal);
}
