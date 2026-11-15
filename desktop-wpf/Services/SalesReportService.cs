using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;
namespace KhanBabaPos.Wpf.Services;
public sealed class SalesReportService
{
 public async Task<SalesReportSnapshot> GetAsync(DateTime from,DateTime to,CancellationToken ct=default)
 {
  if(from.Date>to.Date)throw new InvalidOperationException("From date cannot be later than To date.");
  var path=PosDatabasePath.Resolve(requireExisting:true);await PosDatabaseSchemaVerifier.VerifyAsync(path,ct);
  await using var db=new SqliteConnection(new SqliteConnectionStringBuilder{DataSource=path,Mode=SqliteOpenMode.ReadOnly,Pooling=false}.ToString());await db.OpenAsync(ct);
  var days=new SortedDictionary<string,DailySalesReport>(StringComparer.Ordinal);
  await using(var cmd=db.CreateCommand())
  {
   cmd.CommandText="""
    SELECT substr(s.date,1,10),
      SUM(MAX(0, (CASE WHEN s.final_amount IS NOT NULL AND (s.final_amount>0 OR s.total_amount<=0) THEN s.final_amount
        WHEN COALESCE(s.discount,0)>0 THEN MAX(s.total_amount-s.discount,0) ELSE s.total_amount END)
        - COALESCE((SELECT SUM(r.refund_amount) FROM sale_returns r WHERE r.sale_id=s.id),0))),
      SUM(COALESCE(s.discount,0)),
      SUM(COALESCE((SELECT SUM(r.refund_amount) FROM sale_returns r WHERE r.sale_id=s.id),0)),COUNT(*)
    FROM sales s WHERE substr(s.date,1,10) BETWEEN $from AND $to GROUP BY substr(s.date,1,10);
    """;
   cmd.Parameters.AddWithValue("$from",from.ToString("yyyy-MM-dd"));cmd.Parameters.AddWithValue("$to",to.ToString("yyyy-MM-dd"));
   await using var rd=await cmd.ExecuteReaderAsync(ct);
   while(await rd.ReadAsync(ct)){var key=rd.GetString(0);days[key]=new DailySalesReport(key,rd.GetDouble(1),0,0,rd.GetDouble(2),rd.GetDouble(3),rd.GetInt32(4));}
  }
  await using(var cmd=db.CreateCommand())
  {
   cmd.CommandText="""
    SELECT CASE WHEN COALESCE(invoice_date,'')<>'' THEN substr(invoice_date,1,10) ELSE substr(date,1,10) END,
      SUM(COALESCE(total_cost,0))
    FROM purchases
    WHERE (CASE WHEN COALESCE(invoice_date,'')<>'' THEN substr(invoice_date,1,10) ELSE substr(date,1,10) END) BETWEEN $from AND $to
    GROUP BY 1;
    """;
   cmd.Parameters.AddWithValue("$from",from.ToString("yyyy-MM-dd"));cmd.Parameters.AddWithValue("$to",to.ToString("yyyy-MM-dd"));
   await using var rd=await cmd.ExecuteReaderAsync(ct);
   while(await rd.ReadAsync(ct)){var key=rd.GetString(0);days.TryGetValue(key,out var old);days[key]=(old??new DailySalesReport(key,0,0,0,0,0,0)) with{Purchases=rd.GetDouble(1)};}
  }
  await using(var cmd=db.CreateCommand())
  {
   cmd.CommandText="SELECT substr(date,1,10),SUM(COALESCE(amount,0)) FROM expenses WHERE substr(date,1,10) BETWEEN $from AND $to GROUP BY substr(date,1,10);";
   cmd.Parameters.AddWithValue("$from",from.ToString("yyyy-MM-dd"));cmd.Parameters.AddWithValue("$to",to.ToString("yyyy-MM-dd"));
   await using var rd=await cmd.ExecuteReaderAsync(ct);
   while(await rd.ReadAsync(ct)){var key=rd.GetString(0);days.TryGetValue(key,out var old);days[key]=(old??new DailySalesReport(key,0,0,0,0,0,0)) with{Expenses=rd.GetDouble(1)};}
  }
  var rows=days.Values.Select(x=>x with{NetActivity=x.Sales-x.Purchases-x.Expenses}).ToList();
  return new SalesReportSnapshot(from.Date,to.Date,rows.Sum(x=>x.Sales),rows.Sum(x=>x.Purchases),rows.Sum(x=>x.Expenses),rows.Sum(x=>x.Discount),rows.Sum(x=>x.Returned),rows.Sum(x=>x.SalesCount),rows);
 }
}
public sealed record DailySalesReport(string Date,double Sales,double Purchases,double Expenses,double Discount,double Returned,int SalesCount,double NetActivity=0);
public sealed record SalesReportSnapshot(DateTime From,DateTime To,double Sales,double Purchases,double Expenses,double Discount,double Returned,int SalesCount,IReadOnlyList<DailySalesReport> Days)
{public double NetActivity=>Sales-Purchases-Expenses;}
