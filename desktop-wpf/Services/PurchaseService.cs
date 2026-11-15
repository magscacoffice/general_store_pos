using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;
namespace KhanBabaPos.Wpf.Services;
public sealed class PurchaseService
{
 public async Task<IReadOnlyList<PurchaseRow>> GetAllAsync(CancellationToken ct=default)
 {
  var path=PosDatabasePath.Resolve(requireExisting:true);await PosDatabaseSchemaVerifier.VerifyAsync(path,ct);
  await using var db=await Open(path,true,ct);await using var cmd=db.CreateCommand();cmd.CommandText="SELECT id,product_name,barcode,quantity,unit_cost,total_cost,date FROM purchases ORDER BY id DESC;";
  await using var rd=await cmd.ExecuteReaderAsync(ct);var rows=new List<PurchaseRow>();while(await rd.ReadAsync(ct))rows.Add(new(rd.GetInt32(0),rd.GetString(1),rd.GetString(2),rd.GetInt32(3),rd.GetDouble(4),rd.GetDouble(5),rd.GetString(6)));return rows;
 }
 public Task<int> RecordAsync(int productId,int quantity,double unitCost,double? salePrice,CancellationToken ct=default) =>
  RecordAsync(productId,quantity,unitCost,salePrice,PosDatabasePath.Resolve(requireExisting:true),ct);

 public async Task<int> RecordAsync(int productId,int quantity,double unitCost,double? salePrice,string databasePath,CancellationToken ct=default)
 {
  if(quantity<=0||!double.IsFinite(unitCost)||unitCost<0||(salePrice is not null&&(!double.IsFinite(salePrice.Value)||salePrice.Value<0)))throw new InvalidOperationException("Quantity, purchase cost aur optional sale price valid honi chahiye.");
  var path=databasePath;await PosDatabaseSchemaVerifier.VerifyAsync(path,ct);await DatabaseSafetyService.EnsureVerifiedBackupAsync(path,ct);
  await using var db=await Open(path,false,ct);await using var tx=await db.BeginTransactionAsync(ct);
  string name,barcode,unit;
  await using(var lookup=db.CreateCommand()){lookup.Transaction=(SqliteTransaction)tx;lookup.CommandText="SELECT name,barcode,COALESCE(stock_unit,'pcs') FROM products WHERE id=$id LIMIT 1;";lookup.Parameters.AddWithValue("$id",productId);await using var rd=await lookup.ExecuteReaderAsync(ct);if(!await rd.ReadAsync(ct))throw new InvalidOperationException("Product not found.");name=rd.GetString(0);barcode=rd.GetString(1);unit=rd.GetString(2);}
  await using(var update=db.CreateCommand()){update.Transaction=(SqliteTransaction)tx;update.CommandText=salePrice is null?"UPDATE products SET quantity=quantity+$qty,purchasePrice=$cost,wholesalePrice=CASE WHEN COALESCE(wholesalePrice,0)>0 AND wholesalePrice<$cost THEN $cost ELSE wholesalePrice END WHERE id=$id;":"UPDATE products SET quantity=quantity+$qty,purchasePrice=$cost,price=$sale,wholesalePrice=CASE WHEN COALESCE(wholesalePrice,0)>0 AND wholesalePrice<$cost THEN $cost ELSE wholesalePrice END WHERE id=$id;";update.Parameters.AddWithValue("$qty",quantity);update.Parameters.AddWithValue("$cost",unitCost);update.Parameters.AddWithValue("$id",productId);if(salePrice is not null)update.Parameters.AddWithValue("$sale",salePrice.Value);if(await update.ExecuteNonQueryAsync(ct)!=1)throw new InvalidOperationException("Product stock update failed.");}
  await using(var insert=db.CreateCommand()){insert.Transaction=(SqliteTransaction)tx;insert.CommandText="""
   INSERT INTO purchases(product_id,product_name,barcode,quantity,unit_cost,total_cost,supplier_id,supplier_sync_id,sync_id,date,unit_label,base_unit)
   VALUES($product,$name,$barcode,$qty,$cost,$total,NULL,NULL,$sync,$date,$unit,$unit);
   SELECT last_insert_rowid();
   """;insert.Parameters.AddWithValue("$product",productId);insert.Parameters.AddWithValue("$name",name);insert.Parameters.AddWithValue("$barcode",barcode);insert.Parameters.AddWithValue("$qty",quantity);insert.Parameters.AddWithValue("$cost",unitCost);insert.Parameters.AddWithValue("$total",quantity*unitCost);insert.Parameters.AddWithValue("$sync",$"{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}_{Guid.NewGuid():N}");insert.Parameters.AddWithValue("$date",DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss",System.Globalization.CultureInfo.InvariantCulture));insert.Parameters.AddWithValue("$unit",unit);var value=await insert.ExecuteScalarAsync(ct);var id=Convert.ToInt32(value,System.Globalization.CultureInfo.InvariantCulture);await tx.CommitAsync(ct);return id;}
 }
 static async Task<SqliteConnection> Open(string path,bool ro,CancellationToken ct){var db=new SqliteConnection(new SqliteConnectionStringBuilder{DataSource=path,Mode=ro?SqliteOpenMode.ReadOnly:SqliteOpenMode.ReadWrite,Pooling=false}.ToString());await db.OpenAsync(ct);return db;}
}
public sealed record PurchaseRow(int Id,string ProductName,string Barcode,int Quantity,double UnitCost,double TotalCost,string Date);