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
public sealed record PrinterPreferences(string? PreferredPrinter=null,int PaperWidthMm=80,int HeaderSize=2,int TotalSize=2,int MarginMm=2);
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
 static readonly Encoding Ascii=Encoding.ASCII;
 public static string BuildText(SaleHistoryRecord? sale,IReadOnlyList<SaleHistoryItem> items,PrinterPreferences prefs)
 {
  if(sale is null)return "KHAN BABA GENERAL STORE\nPrinter configured. Select an invoice to preview its receipt.";
  var width=Math.Clamp((576-prefs.MarginMm*16)/12,40,48);string line=new('-',width);
  string Center(string v){v=v.Length>width?v[..width]:v;return v.PadLeft((width+v.Length)/2).PadRight(width);}
  string Pair(string l,string r){if(l.Length+r.Length+1>=width){l=l[..Math.Min(l.Length,width-r.Length-1)];}return l+new string(' ',Math.Max(1,width-l.Length-r.Length))+r;}
  var b=new StringBuilder();b.AppendLine(Center("KHAN BABA"));b.AppendLine(Center("GENERAL STORE"));b.AppendLine(Center("G.T ROAD SANAWAN"));b.AppendLine(Center("PH#03451444325"));b.AppendLine();
  var date=DateTime.TryParse(sale.Date,out var parsed)?parsed:DateTime.Now;
  b.AppendLine(sale.SaleId <= 0 ? Pair("DRAFT PREVIEW",$"Date: {date:dd/MM/yy}") : Pair($"Bill# {sale.SaleId:D6}",$"Date: {date:dd/MM/yy}"));b.AppendLine(Pair($"Cashier: {sale.Cashier}",$"Time: {date:hh:mm:ss tt}"));b.AppendLine(Pair($"Type: {sale.CustomerType}",""));b.AppendLine(Pair($"Customer: {sale.CustomerName}",""));b.AppendLine(line);
  b.AppendLine(" Qty Description       Rate       Amount");
  b.AppendLine(line);
  foreach(var item in items){var q=item.Quantity.ToString(CultureInfo.InvariantCulture).PadLeft(4);var rate=item.SalePrice.ToString("0.00",CultureInfo.InvariantCulture).PadLeft(10);var amount=item.LineTotal.ToString("0.00",CultureInfo.InvariantCulture).PadLeft(11);var desc=item.ProductName.Length>17?item.ProductName[..17]:item.ProductName;b.AppendLine(q+" "+desc.PadRight(17)+" "+rate+" "+amount);}
  b.AppendLine(line);b.AppendLine(Pair($"Items: {items.Count}",$"Gross: {sale.Subtotal:0.00}"));b.AppendLine(Pair("Discount",sale.Discount.ToString("0.00",CultureInfo.InvariantCulture)));b.AppendLine(line);b.AppendLine(Center($"NET AMOUNT: Rs. {sale.FinalAmount:0.00}"));b.AppendLine(line);b.AppendLine(Pair($"Payment: {sale.PaymentType}",""));b.AppendLine(Pair("Received",sale.Received.ToString("0.00",CultureInfo.InvariantCulture)));if(sale.BalanceDue>0)b.AppendLine(Pair("Balance Due",sale.BalanceDue.ToString("0.00",CultureInfo.InvariantCulture)));var change=sale.Received-sale.FinalAmount;if(change>0)b.AppendLine(Pair("Change",change.ToString("0.00",CultureInfo.InvariantCulture)));if(sale.ReturnedAmount>0)b.AppendLine(Pair("Returned",sale.ReturnedAmount.ToString("0.00",CultureInfo.InvariantCulture)));b.AppendLine(line);b.AppendLine(Center("THANK YOU - VISIT AGAIN"));b.AppendLine(Center("KHAN BABA GENERAL STORE"));return b.ToString();
 }
 public static byte[] BuildBytes(string text,PrinterPreferences p)
 {
  using var ms=new MemoryStream();void B(params byte[] v)=>ms.Write(v,0,v.Length);
  B(0x1B,0x40);var margin=p.MarginMm*8;var printWidth=576-margin*2;B(0x1D,0x4C,(byte)(margin&255),(byte)((margin>>8)&255),0x1D,0x57,(byte)(printWidth&255),(byte)((printWidth>>8)&255));
  var lines=text.Split('\n');foreach(var line in lines){if(line.Trim()=="KHAN BABA"||line.Trim()=="GENERAL STORE"){B(0x1B,0x61,0x01,0x1B,0x45,0x01,0x1D,0x21,(byte)(p.HeaderSize switch{1=>0x10,3=>0x22,_=>0x11}));B(Ascii.GetBytes(line));B(0x1D,0x21,0x00,0x1B,0x45,0x00,0x1B,0x61,0x00);}else if(line.TrimStart().StartsWith("NET AMOUNT",StringComparison.Ordinal)){B(0x1B,0x61,0x01,0x1B,0x45,0x01,0x1D,0x21,(byte)(p.TotalSize switch{1=>0x10,3=>0x22,_=>0x11}));B(Ascii.GetBytes(line));B(0x1D,0x21,0x00,0x1B,0x45,0x00,0x1B,0x61,0x00);}else B(Ascii.GetBytes(line));B(0x0A);}
  B(0x0A,0x0A,0x1D,0x56,0x00);return ms.ToArray();
 }
}

public static class PdfReceiptBuilder
{
 public static byte[] Build(string text)
 {
  var lines=(text??string.Empty).Replace("\r",string.Empty).Split('\n');
  var pages=lines.Chunk(55).ToList();if(pages.Count==0)pages.Add(Array.Empty<string>());
  var count=pages.Count;var contentStart=3+count;var fontId=3+(2*count);
  var objects=new List<byte[]>();
  objects.Add(Encoding.ASCII.GetBytes("<< /Type /Catalog /Pages 2 0 R >>"));
  var kids=string.Join(" ",Enumerable.Range(0,count).Select(i=>$"{3+i} 0 R"));
  objects.Add(Encoding.ASCII.GetBytes($"<< /Type /Pages /Kids [{kids}] /Count {count} >>"));
  for(var i=0;i<count;i++)objects.Add(Encoding.ASCII.GetBytes($"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 {fontId} 0 R >> >> /Contents {contentStart+i} 0 R >>"));
  foreach(var page in pages)
  {
   var body=new StringBuilder("BT\n/F1 9 Tf\n42 800 Td\n12 TL\n");
   foreach(var line in page){var safe=line.Replace("\\","\\\\").Replace("(","\\(").Replace(")","\\)").Replace("\t"," ");body.Append('(').Append(safe).Append(") Tj T*\n");}
   body.Append("ET\n");var bytes=Encoding.ASCII.GetBytes(body.ToString());
   using var stream=new MemoryStream();stream.Write(Encoding.ASCII.GetBytes($"<< /Length {bytes.Length} >>\nstream\n"));stream.Write(bytes);stream.Write(Encoding.ASCII.GetBytes("endstream"));objects.Add(stream.ToArray());
  }
  objects.Add(Encoding.ASCII.GetBytes("<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>"));
  using var output=new MemoryStream();output.Write(Encoding.ASCII.GetBytes("%PDF-1.4\n"));var offsets=new List<long>{0};
  for(var i=0;i<objects.Count;i++){offsets.Add(output.Position);output.Write(Encoding.ASCII.GetBytes($"{i+1} 0 obj\n"));output.Write(objects[i]);output.Write(Encoding.ASCII.GetBytes("\nendobj\n"));}
  var xref=output.Position;output.Write(Encoding.ASCII.GetBytes($"xref\n0 {objects.Count+1}\n0000000000 65535 f \n"));
  foreach(var offset in offsets.Skip(1))output.Write(Encoding.ASCII.GetBytes($"{offset:0000000000} 00000 n \n"));
  output.Write(Encoding.ASCII.GetBytes($"trailer\n<< /Size {objects.Count+1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF"));
  return output.ToArray();
 }
}
