using System.Globalization;
using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;
namespace KhanBabaPos.Wpf.Services;
public sealed class SaleReturnService
{
 public async Task<IReadOnlyList<ReturnableSaleItem>> GetReturnableItemsAsync(int saleId,CancellationToken ct=default)
 {
  var path=PosDatabasePath.Resolve(requireExisting:true);await PosDatabaseSchemaVerifier.VerifyAsync(path,ct);
  await using var db=await Open(path,true,ct);await using var cmd=db.CreateCommand();
  cmd.CommandText="""
   SELECT si.id,COALESCE(si.sync_id,''),si.product_id,si.barcode,si.product_name,si.quantity,
    si.sale_price,si.purchase_price,COALESCE((SELECT SUM(ri.quantity) FROM sale_return_items ri WHERE ri.sale_item_id=si.id),0)
   FROM sale_items si WHERE si.sale_id=$sale ORDER BY si.id;
   """;
  cmd.Parameters.AddWithValue("$sale",saleId);await using var rd=await cmd.ExecuteReaderAsync(ct);var rows=new List<ReturnableSaleItem>();
  while(await rd.ReadAsync(ct))rows.Add(new ReturnableSaleItem(rd.GetInt32(0),rd.GetString(1),rd.IsDBNull(2)?(int?)null:rd.GetInt32(2),rd.GetString(3),rd.GetString(4),rd.GetInt32(5),rd.GetDouble(6),rd.GetDouble(7),rd.GetInt32(8)));
  return rows;
 }
 public Task<SaleReturnResult> RecordAsync(int saleId,string reason,string refundMethod,IReadOnlyList<SaleReturnLineInput> items,CancellationToken ct=default) =>
  RecordAsync(saleId,reason,refundMethod,items,PosDatabasePath.Resolve(requireExisting:true),ct);

 public async Task<SaleReturnResult> RecordAsync(int saleId,string reason,string refundMethod,IReadOnlyList<SaleReturnLineInput> items,string databasePath,CancellationToken ct=default)
 {
        AccessService.RequireCurrentAdmin();
  if(items.Count==0)throw new InvalidOperationException("Return ke liye kam az kam aik item select karein.");
  if(string.IsNullOrWhiteSpace(reason))throw new InvalidOperationException("Return reason likhna zaroori hai.");
  if(refundMethod is not ("Cash" or "Khata"))throw new InvalidOperationException("Refund method Cash ya Khata hona chahiye.");
  var path=databasePath;await PosDatabaseSchemaVerifier.VerifyAsync(path,ct);await DatabaseSafetyService.EnsureVerifiedBackupAsync(path,ct);
  await using var db=await Open(path,false,ct);await using var tx=await db.BeginTransactionAsync(ct);
  int? customerId;string saleSync,payment;double subtotal,discount,receivedRaw,finalRaw;
  await using(var sale=db.CreateCommand()){
   sale.Transaction=(SqliteTransaction)tx;sale.CommandText="SELECT customer_id,COALESCE(sync_id,''),COALESCE(payment_type,'Cash'),COALESCE(total_amount,0),COALESCE(discount,0),COALESCE(received_amount,0),final_amount FROM sales WHERE id=$id LIMIT 1;";sale.Parameters.AddWithValue("$id",saleId);
   await using var rd=await sale.ExecuteReaderAsync(ct);if(!await rd.ReadAsync(ct))throw new InvalidOperationException("Original invoice nahi mila.");
   customerId=rd.IsDBNull(0)?(int?)null:rd.GetInt32(0);saleSync=rd.GetString(1);payment=rd.GetString(2);subtotal=rd.GetDouble(3);discount=rd.GetDouble(4);receivedRaw=rd.GetDouble(5);finalRaw=rd.IsDBNull(6)?0:rd.GetDouble(6);
  }
  if(string.IsNullOrWhiteSpace(saleSync))throw new InvalidOperationException("Original invoice sync ID missing hai.");
  string? partySync=null;
  if(customerId is not null){await using var party=db.CreateCommand();party.Transaction=(SqliteTransaction)tx;party.CommandText="SELECT sync_id FROM parties WHERE id=$id LIMIT 1;";party.Parameters.AddWithValue("$id",customerId.Value);var v=await party.ExecuteScalarAsync(ct);partySync=v is null or DBNull?null:Convert.ToString(v,CultureInfo.InvariantCulture);}
  if(refundMethod=="Khata"&&customerId is null)throw new InvalidOperationException("Walk-in sale ka refund Khata mein adjust nahi ho sakta.");
  var prepared=new List<PreparedReturnLine>();var gross=0d;
  foreach(var request in items){
   if(request.Quantity<=0)continue;
   await using var lookup=db.CreateCommand();lookup.Transaction=(SqliteTransaction)tx;lookup.CommandText="SELECT sync_id,product_id,barcode,product_name,quantity,sale_price,purchase_price FROM sale_items WHERE id=$item AND sale_id=$sale LIMIT 1;";lookup.Parameters.AddWithValue("$item",request.SaleItemId);lookup.Parameters.AddWithValue("$sale",saleId);
   await using var rd=await lookup.ExecuteReaderAsync(ct);if(!await rd.ReadAsync(ct))throw new InvalidOperationException("Selected item original invoice ka hissa nahi hai.");
   var sync=rd.IsDBNull(0)?null:rd.GetString(0);var product=rd.IsDBNull(1)?(int?)null:rd.GetInt32(1);var barcode=rd.GetString(2);var name=rd.GetString(3);var sold=rd.GetInt32(4);var price=rd.GetDouble(5);var cost=rd.GetDouble(6);await rd.DisposeAsync();
   await using var returned=db.CreateCommand();returned.Transaction=(SqliteTransaction)tx;returned.CommandText="SELECT COALESCE(SUM(quantity),0) FROM sale_return_items WHERE sale_item_id=$id;";returned.Parameters.AddWithValue("$id",request.SaleItemId);var already=Convert.ToInt32(await returned.ExecuteScalarAsync(ct),CultureInfo.InvariantCulture);
   if(request.Quantity>sold-already)throw new InvalidOperationException("Return quantity sold quantity se zyada hai: "+name);
   var condition=request.Condition=="damaged"?"damaged":"saleable";var line=price*request.Quantity;gross+=line;
   prepared.Add(new PreparedReturnLine(request.SaleItemId,sync,product,barcode,name,request.Quantity,price,cost,line,cost*request.Quantity,condition));
  }
  if(prepared.Count==0)throw new InvalidOperationException("Return quantity select karein.");
  var discountShare=subtotal>0?Math.Clamp(discount*gross/subtotal,0,gross):0;var refund=Math.Max(0,gross-discountShare);
  var finalAmount=finalRaw>0||subtotal<=0?finalRaw:discount>0?Math.Max(0,subtotal-discount):subtotal;
  var effectiveReceived=receivedRaw>0?receivedRaw:payment=="Cash"?finalAmount:receivedRaw;
  if(refundMethod=="Cash"&&customerId is not null){
   await using var cash=db.CreateCommand();cash.Transaction=(SqliteTransaction)tx;cash.CommandText="SELECT COALESCE(SUM(refund_amount),0) FROM sale_returns WHERE sale_id=$sale AND refund_method='Cash';";cash.Parameters.AddWithValue("$sale",saleId);
   var already=Convert.ToDouble(await cash.ExecuteScalarAsync(ct),CultureInfo.InvariantCulture);
   if(already+refund>effectiveReceived+0.000001)throw new InvalidOperationException("Cash refund received cash se zyada hai. Khata adjustment select karein.");
  }
  var date=DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss",CultureInfo.InvariantCulture);var returnSync=NewSyncId();int returnId;
  await using(var insert=db.CreateCommand()){
   insert.Transaction=(SqliteTransaction)tx;insert.CommandText="INSERT INTO sale_returns(sale_id,sale_sync_id,customer_id,party_sync_id,reason,refund_method,refund_amount,date,sync_id) VALUES($sale,$saleSync,$customer,$partySync,$reason,$method,$amount,$date,$sync); SELECT last_insert_rowid();";
   insert.Parameters.AddWithValue("$sale",saleId);insert.Parameters.AddWithValue("$saleSync",saleSync);insert.Parameters.AddWithValue("$customer",customerId is null?DBNull.Value:customerId.Value);insert.Parameters.AddWithValue("$partySync",(object?)partySync??DBNull.Value);insert.Parameters.AddWithValue("$reason",reason.Trim());insert.Parameters.AddWithValue("$method",refundMethod);insert.Parameters.AddWithValue("$amount",refund);insert.Parameters.AddWithValue("$date",date);insert.Parameters.AddWithValue("$sync",returnSync);
   returnId=Convert.ToInt32(await insert.ExecuteScalarAsync(ct),CultureInfo.InvariantCulture);
  }
  foreach(var item in prepared){
   await using(var ins=db.CreateCommand()){
    ins.Transaction=(SqliteTransaction)tx;ins.CommandText="INSERT INTO sale_return_items(return_id,return_sync_id,sale_item_id,sale_item_sync_id,product_id,barcode,product_name,quantity,sale_price,purchase_price,line_total,cost_total,condition,sync_id) VALUES($return,$returnSync,$saleItem,$saleItemSync,$product,$barcode,$name,$qty,$price,$cost,$line,$costTotal,$condition,$sync);";
    ins.Parameters.AddWithValue("$return",returnId);ins.Parameters.AddWithValue("$returnSync",returnSync);ins.Parameters.AddWithValue("$saleItem",item.SaleItemId);ins.Parameters.AddWithValue("$saleItemSync",(object?)item.SaleItemSyncId??DBNull.Value);ins.Parameters.AddWithValue("$product",item.ProductId is null?DBNull.Value:item.ProductId.Value);ins.Parameters.AddWithValue("$barcode",item.Barcode);ins.Parameters.AddWithValue("$name",item.ProductName);ins.Parameters.AddWithValue("$qty",item.Quantity);ins.Parameters.AddWithValue("$price",item.SalePrice);ins.Parameters.AddWithValue("$cost",item.PurchasePrice);ins.Parameters.AddWithValue("$line",item.LineTotal);ins.Parameters.AddWithValue("$costTotal",item.CostTotal);ins.Parameters.AddWithValue("$condition",item.Condition);ins.Parameters.AddWithValue("$sync",NewSyncId());await ins.ExecuteNonQueryAsync(ct);
   }
   if(item.ProductId is not null){await using var stock=db.CreateCommand();stock.Transaction=(SqliteTransaction)tx;stock.CommandText=item.Condition=="saleable"?"UPDATE products SET quantity=quantity+$qty WHERE id=$id;":"UPDATE products SET damaged_quantity=COALESCE(damaged_quantity,0)+$qty WHERE id=$id;";stock.Parameters.AddWithValue("$qty",item.Quantity);stock.Parameters.AddWithValue("$id",item.ProductId.Value);await stock.ExecuteNonQueryAsync(ct);}
  }
  if(refundMethod=="Khata"&&customerId is not null&&refund>0){
   await using(var update=db.CreateCommand()){update.Transaction=(SqliteTransaction)tx;update.CommandText="UPDATE parties SET balance=balance-$amount WHERE id=$id;";update.Parameters.AddWithValue("$amount",refund);update.Parameters.AddWithValue("$id",customerId.Value);await update.ExecuteNonQueryAsync(ct);}
   await using(var entry=db.CreateCommand()){entry.Transaction=(SqliteTransaction)tx;entry.CommandText="INSERT INTO khata_transactions(party_id,party_sync_id,sync_id,type,amount,note,date) VALUES($id,$partySync,$sync,'return_adjustment',$amount,$note,$date);";entry.Parameters.AddWithValue("$id",customerId.Value);entry.Parameters.AddWithValue("$partySync",(object?)partySync??DBNull.Value);entry.Parameters.AddWithValue("$sync",NewSyncId());entry.Parameters.AddWithValue("$amount",refund);entry.Parameters.AddWithValue("$note",$"Return #{returnId} against Bill #{saleId}");entry.Parameters.AddWithValue("$date",date);await entry.ExecuteNonQueryAsync(ct);}
  }
  await tx.CommitAsync(ct);return new SaleReturnResult(returnId,refund,prepared.Count);
 }
 static string NewSyncId()=>$"{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}_{Guid.NewGuid():N}";
 static async Task<SqliteConnection> Open(string path,bool ro,CancellationToken ct){var db=new SqliteConnection(new SqliteConnectionStringBuilder{DataSource=path,Mode=ro?SqliteOpenMode.ReadOnly:SqliteOpenMode.ReadWrite,Pooling=false}.ToString());await db.OpenAsync(ct);return db;}
 private sealed record PreparedReturnLine(int SaleItemId,string? SaleItemSyncId,int? ProductId,string Barcode,string ProductName,int Quantity,double SalePrice,double PurchasePrice,double LineTotal,double CostTotal,string Condition);
}
public sealed record ReturnableSaleItem(int SaleItemId,string SaleItemSyncId,int? ProductId,string Barcode,string ProductName,int SoldQuantity,double SalePrice,double PurchasePrice,int ReturnedQuantity){public int RemainingQuantity=>Math.Max(0,SoldQuantity-ReturnedQuantity);}
public sealed record SaleReturnLineInput(int SaleItemId,int Quantity,string Condition);
public sealed record SaleReturnResult(int ReturnId,double RefundAmount,int ItemCount);