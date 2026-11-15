using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;
namespace KhanBabaPos.Wpf.Services;
public sealed class ProfitLossService
{
 public async Task<ProfitLossSnapshot> GetAsync(CancellationToken ct=default)
 {
  var path=PosDatabasePath.Resolve(requireExisting:true);await PosDatabaseSchemaVerifier.VerifyAsync(path,ct);
  await using var db=new SqliteConnection(new SqliteConnectionStringBuilder{DataSource=path,Mode=SqliteOpenMode.ReadOnly,Pooling=false}.ToString());await db.OpenAsync(ct);
  double revenue,cost,expenses;
  await using(var cmd=db.CreateCommand()){cmd.CommandText="""
   SELECT COALESCE((SELECT SUM(CASE WHEN COALESCE(final_amount,0)>0 OR COALESCE(total_amount,0)<=0 THEN COALESCE(final_amount,0)
    WHEN COALESCE(discount,0)>0 THEN MAX(total_amount-discount,0) ELSE COALESCE(total_amount,0) END) FROM sales),0)
    - COALESCE((SELECT SUM(refund_amount) FROM sale_returns),0);
   """;revenue=Convert.ToDouble(await cmd.ExecuteScalarAsync(ct),System.Globalization.CultureInfo.InvariantCulture);}
  await using(var cmd=db.CreateCommand()){cmd.CommandText="SELECT COALESCE((SELECT SUM(cost_total) FROM sale_items),0)-COALESCE((SELECT SUM(cost_total) FROM sale_return_items WHERE condition='saleable'),0);";cost=Convert.ToDouble(await cmd.ExecuteScalarAsync(ct),System.Globalization.CultureInfo.InvariantCulture);}
  await using(var cmd=db.CreateCommand()){cmd.CommandText="SELECT COALESCE(SUM(amount),0) FROM expenses;";expenses=Convert.ToDouble(await cmd.ExecuteScalarAsync(ct),System.Globalization.CultureInfo.InvariantCulture);}
  return new ProfitLossSnapshot(revenue,cost,expenses,revenue-cost-expenses);
 }
}
public sealed record ProfitLossSnapshot(double Revenue,double Cost,double Expenses,double Profit);