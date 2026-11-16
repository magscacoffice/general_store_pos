using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;
namespace KhanBabaPos.Wpf.Services;
public sealed class PurchaseService
{
 public async Task<IReadOnlyList<PurchaseRow>> GetAllAsync(CancellationToken ct=default)
 {
  var path=PosDatabasePath.Resolve(requireExisting:true);await PosDatabaseSchemaVerifier.VerifyAsync(path,ct);
  await using var db=await Open(path,true,ct);await using var cmd=db.CreateCommand();cmd.CommandText="""
   SELECT p.id,p.product_name,p.barcode,p.quantity,p.unit_cost,p.total_cost,p.date,
          COALESCE(s.name,'Quick Stock Entry'),COALESCE(p.invoice_number,''),COALESCE(p.invoice_date,''),
          COALESCE(p.invoice_total,0),COALESCE(p.invoice_paid_amount,0),COALESCE(p.invoice_balance_due,0)
   FROM purchases p LEFT JOIN parties s ON s.id=p.supplier_id ORDER BY p.id DESC;
   """;
  await using var rd=await cmd.ExecuteReaderAsync(ct);var rows=new List<PurchaseRow>();
  while(await rd.ReadAsync(ct))rows.Add(new(rd.GetInt32(0),rd.GetString(1),rd.GetString(2),rd.GetInt32(3),rd.GetDouble(4),rd.GetDouble(5),rd.GetString(6),
   rd.GetString(7),rd.GetString(8),rd.GetString(9),rd.GetDouble(10),rd.GetDouble(11),rd.GetDouble(12)));
  return rows;
 }
 public Task<int> RecordAsync(int productId,int quantity,double unitCost,double? salePrice,CancellationToken ct=default) =>
  RecordAsync(productId,quantity,unitCost,salePrice,PosDatabasePath.Resolve(requireExisting:true),ct);

 public async Task<int> RecordAsync(int productId,int quantity,double unitCost,double? salePrice,string databasePath,CancellationToken ct=default)
 {
        AccessService.RequireCurrentAdmin();
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

 public Task<string> RecordInvoiceAsync(PurchaseInvoiceRequest request,CancellationToken ct=default) =>
  RecordInvoiceAsync(request,PosDatabasePath.Resolve(requireExisting:true),ct);

 public async Task<string> RecordInvoiceAsync(PurchaseInvoiceRequest request,string databasePath,CancellationToken ct=default)
 {
  AccessService.RequireCurrentAdmin();
  ArgumentNullException.ThrowIfNull(request);
  var invoiceNumber=request.InvoiceNumber.Trim().ToUpperInvariant();
  if(invoiceNumber.Length==0)throw new InvalidOperationException("Supplier invoice number zaroori hai.");
  if(!double.IsFinite(request.InvoiceTotal)||request.InvoiceTotal<=0||
     !double.IsFinite(request.InvoiceDiscount)||request.InvoiceDiscount<0||
     !double.IsFinite(request.InvoiceTax)||request.InvoiceTax<0||
     !double.IsFinite(request.PaidAmount)||request.PaidAmount<0||request.PaidAmount>request.InvoiceTotal)
   throw new InvalidOperationException("Invoice total, discount, tax aur paid amount valid enter karein.");
  if(request.Items is null||request.Items.Count==0)throw new InvalidOperationException("Invoice mein kam az kam aik item zaroori hai.");
  var lines=new List<PreparedInvoiceLine>(request.Items.Count);
  var rawTotal=0d;
  foreach(var item in request.Items)
  {
   if(item.Quantity<=0||!double.IsFinite(item.InvoiceQuantity)||item.InvoiceQuantity<=0||
      !double.IsFinite(item.ConversionFactor)||item.ConversionFactor<=0||
      !double.IsFinite(item.UnitCost)||item.UnitCost<0||string.IsNullOrWhiteSpace(item.BaseUnit))
    throw new InvalidOperationException("Har item ki invoice quantity, conversion, stock unit aur rate valid honi chahiye.");
   var converted=item.InvoiceQuantity*item.ConversionFactor;
   if(!double.IsFinite(converted)||converted>int.MaxValue||
      Math.Abs(converted-item.Quantity)>0.000001)
    throw new InvalidOperationException("Invoice quantity aur conversion factor ka result stock quantity se match nahi karta.");
   var lineTotal=item.LineTotal??item.InvoiceQuantity*item.UnitCost;
   if(!double.IsFinite(lineTotal)||lineTotal<0)throw new InvalidOperationException("Invoice item amount valid nahi.");
   if(item.SalePrice is not null&&(!double.IsFinite(item.SalePrice.Value)||item.SalePrice.Value<0))
    throw new InvalidOperationException("Retail sale price valid nahi.");
   rawTotal+=lineTotal;
   lines.Add(new PreparedInvoiceLine(item,lineTotal));
  }
  if(!double.IsFinite(rawTotal))throw new InvalidOperationException("Invoice item total supported range se zyada hai.");

  var path=databasePath;
  await PosDatabaseSchemaVerifier.VerifyAsync(path,ct);
  await DatabaseSafetyService.EnsureVerifiedBackupAsync(path,ct);
  await using var db=await Open(path,false,ct);
  await using var tx=await db.BeginTransactionAsync(ct);
  var transaction=(SqliteTransaction)tx;
  var supplierSyncId="";
  await using(var supplier=db.CreateCommand())
  {
   supplier.Transaction=transaction;
   supplier.CommandText="SELECT COALESCE(sync_id,'') FROM parties WHERE id=$id AND type='supplier' LIMIT 1;";
   supplier.Parameters.AddWithValue("$id",request.SupplierId);
   var value=await supplier.ExecuteScalarAsync(ct);
   if(value is null or DBNull)throw new InvalidOperationException("Selected supplier nahi mila.");
   supplierSyncId=Convert.ToString(value,System.Globalization.CultureInfo.InvariantCulture)??"";
  }
  await using(var duplicate=db.CreateCommand())
  {
   duplicate.Transaction=transaction;
   duplicate.CommandText="SELECT 1 FROM purchases WHERE supplier_id=$supplier AND UPPER(invoice_number)=$number LIMIT 1;";
   duplicate.Parameters.AddWithValue("$supplier",request.SupplierId);
   duplicate.Parameters.AddWithValue("$number",invoiceNumber);
   if(await duplicate.ExecuteScalarAsync(ct)is not null)throw new InvalidOperationException("Ye supplier invoice pehle hi stock mein post ho chuka hai.");
  }

  var groupId=NewSyncId();
  var now=DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss",System.Globalization.CultureInfo.InvariantCulture);
  var payable=request.InvoiceTotal-request.PaidAmount;
  for(var index=0;index<lines.Count;index++)
  {
   var line=lines[index];var item=line.Input;int productId;string name,barcode,storedUnit;
   if(item.ProductId is null)
   {
    name=item.NewProductName?.Trim()??"";barcode=item.NewProductBarcode?.Trim()??"";
    if(name.Length==0||barcode.Length==0)throw new InvalidOperationException("Naye product ke liye name aur barcode dono zaroori hain.");
    await using(var barcodeCheck=db.CreateCommand())
    {
     barcodeCheck.Transaction=transaction;barcodeCheck.CommandText="SELECT name FROM products WHERE barcode=$barcode COLLATE NOCASE LIMIT 1;";
     barcodeCheck.Parameters.AddWithValue("$barcode",barcode);
     if(await barcodeCheck.ExecuteScalarAsync(ct)is not null)throw new InvalidOperationException($"New product barcode {barcode} pehle se inventory mein mojood hai.");
    }
    await using var create=db.CreateCommand();create.Transaction=transaction;
    create.CommandText="INSERT INTO products(name,barcode,price,purchasePrice,wholesalePrice,damaged_quantity,quantity,is_active,stock_unit) VALUES($name,$barcode,$price,0,0,0,0,1,$unit); SELECT last_insert_rowid();";
    create.Parameters.AddWithValue("$name",name);create.Parameters.AddWithValue("$barcode",barcode);
    create.Parameters.AddWithValue("$price",item.SalePrice??0);create.Parameters.AddWithValue("$unit",item.BaseUnit.Trim());
    productId=Convert.ToInt32(await create.ExecuteScalarAsync(ct),System.Globalization.CultureInfo.InvariantCulture);
    storedUnit=item.BaseUnit.Trim();
   }
   else
   {
    productId=item.ProductId.Value;
    await using var product=db.CreateCommand();product.Transaction=transaction;
    product.CommandText="SELECT name,barcode,COALESCE(stock_unit,'') FROM products WHERE id=$id LIMIT 1;";
    product.Parameters.AddWithValue("$id",productId);
    await using var reader=await product.ExecuteReaderAsync(ct);
    if(!await reader.ReadAsync(ct))throw new InvalidOperationException("Invoice ka selected product inventory mein nahi mila.");
    name=reader.GetString(0);barcode=reader.GetString(1);storedUnit=reader.GetString(2);
    await reader.DisposeAsync();
    if(storedUnit.Trim().Length>0&&CanonicalUnit(storedUnit)!=CanonicalUnit(item.BaseUnit))
     throw new InvalidOperationException($"{name} ka stock unit \"{storedUnit}\" hai. Invoice conversion mein bhi isi unit ko select karein.");
   }
   var adjustedTotal=rawTotal>0?line.RawTotal*request.InvoiceTotal/rawTotal:request.InvoiceTotal/lines.Count;
   var effectiveCost=adjustedTotal/item.Quantity;
   if(!double.IsFinite(adjustedTotal)||adjustedTotal<0||!double.IsFinite(effectiveCost))
    throw new InvalidOperationException("Invoice item ka adjusted cost valid nahi.");
   if(item.SalePrice is not null&&item.SalePrice.Value<effectiveCost)
    throw new InvalidOperationException($"Retail sale price purchase cost se kam nahi ho sakti: {name}");
   await using(var update=db.CreateCommand())
   {
    update.Transaction=transaction;
    update.CommandText=item.SalePrice is null
      ?"UPDATE products SET quantity=quantity+$qty,purchasePrice=$cost,stock_unit=$unit WHERE id=$id;"
      :"UPDATE products SET quantity=quantity+$qty,purchasePrice=$cost,price=$sale,stock_unit=$unit WHERE id=$id;";
    update.Parameters.AddWithValue("$qty",item.Quantity);update.Parameters.AddWithValue("$cost",effectiveCost);
    update.Parameters.AddWithValue("$unit",item.BaseUnit.Trim());update.Parameters.AddWithValue("$id",productId);
    if(item.SalePrice is not null)update.Parameters.AddWithValue("$sale",item.SalePrice.Value);
    if(await update.ExecuteNonQueryAsync(ct)!=1)throw new InvalidOperationException("Product stock update failed.");
   }
   await using(var insert=db.CreateCommand())
   {
    insert.Transaction=transaction;
    insert.CommandText="""
     INSERT INTO purchases(product_id,product_name,barcode,quantity,unit_cost,total_cost,supplier_id,supplier_sync_id,sync_id,date,
       invoice_group_id,invoice_number,invoice_date,invoice_total,invoice_discount,invoice_tax,invoice_paid_amount,invoice_balance_due,
       invoice_image_path,unit_label,invoice_quantity,conversion_factor,base_unit,invoice_unit_cost)
     VALUES($product,$name,$barcode,$qty,$cost,$total,$supplier,$supplierSync,$sync,$date,$group,$number,$invoiceDate,$invoiceTotal,
       $discount,$tax,$paid,$due,NULL,$unitLabel,$invoiceQty,$factor,$baseUnit,$invoiceCost);
     """;
    insert.Parameters.AddWithValue("$product",productId);insert.Parameters.AddWithValue("$name",name);insert.Parameters.AddWithValue("$barcode",barcode);
    insert.Parameters.AddWithValue("$qty",item.Quantity);insert.Parameters.AddWithValue("$cost",effectiveCost);insert.Parameters.AddWithValue("$total",adjustedTotal);
    insert.Parameters.AddWithValue("$supplier",request.SupplierId);insert.Parameters.AddWithValue("$supplierSync",supplierSyncId);
    insert.Parameters.AddWithValue("$sync",NewSyncId());insert.Parameters.AddWithValue("$date",now);insert.Parameters.AddWithValue("$group",groupId);
    insert.Parameters.AddWithValue("$number",invoiceNumber);insert.Parameters.AddWithValue("$invoiceDate",request.InvoiceDate.ToString("yyyy-MM-dd",System.Globalization.CultureInfo.InvariantCulture));
    insert.Parameters.AddWithValue("$invoiceTotal",request.InvoiceTotal);insert.Parameters.AddWithValue("$discount",request.InvoiceDiscount);
    insert.Parameters.AddWithValue("$tax",request.InvoiceTax);insert.Parameters.AddWithValue("$paid",request.PaidAmount);insert.Parameters.AddWithValue("$due",payable);
    insert.Parameters.AddWithValue("$unitLabel",item.UnitLabel?.Trim()??"");insert.Parameters.AddWithValue("$invoiceQty",item.InvoiceQuantity);
    insert.Parameters.AddWithValue("$factor",item.ConversionFactor);insert.Parameters.AddWithValue("$baseUnit",item.BaseUnit.Trim());
    insert.Parameters.AddWithValue("$invoiceCost",item.UnitCost);
    await insert.ExecuteNonQueryAsync(ct);
   }
  }
  await using(var balance=db.CreateCommand())
  {
   balance.Transaction=transaction;balance.CommandText="UPDATE parties SET balance=COALESCE(balance,0)+$payable WHERE id=$id AND type='supplier';";
   balance.Parameters.AddWithValue("$payable",payable);balance.Parameters.AddWithValue("$id",request.SupplierId);
   if(await balance.ExecuteNonQueryAsync(ct)!=1)throw new InvalidOperationException("Supplier payable balance update failed.");
  }
  await InsertSupplierLedgerAsync(db,transaction,request.SupplierId,supplierSyncId,"supplier_purchase",request.InvoiceTotal,
   $"Supplier invoice {invoiceNumber}",now,ct);
  if(request.PaidAmount>0)
   await InsertSupplierLedgerAsync(db,transaction,request.SupplierId,supplierSyncId,"supplier_payment",request.PaidAmount,
    $"Payment against supplier invoice {invoiceNumber}",now,ct);
  await tx.CommitAsync(ct);
  return groupId;
 }

 static async Task InsertSupplierLedgerAsync(SqliteConnection db,SqliteTransaction tx,int supplierId,string supplierSyncId,
  string type,double amount,string note,string date,CancellationToken ct)
 {
  await using var entry=db.CreateCommand();entry.Transaction=tx;
  entry.CommandText="INSERT INTO khata_transactions(party_id,party_sync_id,sync_id,type,amount,note,date) VALUES($party,$partySync,$sync,$type,$amount,$note,$date);";
  entry.Parameters.AddWithValue("$party",supplierId);entry.Parameters.AddWithValue("$partySync",supplierSyncId);
  entry.Parameters.AddWithValue("$sync",NewSyncId());entry.Parameters.AddWithValue("$type",type);
  entry.Parameters.AddWithValue("$amount",amount);entry.Parameters.AddWithValue("$note",note);entry.Parameters.AddWithValue("$date",date);
  await entry.ExecuteNonQueryAsync(ct);
 }

 static string CanonicalUnit(string value)
 {
  var unit=new string(value.Trim().ToLowerInvariant().Where(char.IsLetter).ToArray());
  return unit switch
  {
   "pc" or "pcs" or "piece" or "pieces" or "unit" or "units"=>"pcs",
   "kg" or "kgs" or "kilogram" or "kilograms"=>"kg",
   "g" or "gm" or "gram" or "grams"=>"g",
   "l" or "ltr" or "litre" or "litres" or "liter" or "liters"=>"l",
   "ml" or "millilitre" or "millilitres" or "milliliter" or "milliliters"=>"ml",
   "dz" or "dozen" or "dozens"=>"dozen",
   _=>unit
  };
 }
 static string NewSyncId()=>$"{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}_{Guid.NewGuid():N}";

 static async Task<SqliteConnection> Open(string path,bool ro,CancellationToken ct){var db=new SqliteConnection(new SqliteConnectionStringBuilder{DataSource=path,Mode=ro?SqliteOpenMode.ReadOnly:SqliteOpenMode.ReadWrite,Pooling=false}.ToString());await db.OpenAsync(ct);return db;}
}
public sealed record PurchaseRow(int Id,string ProductName,string Barcode,int Quantity,double UnitCost,double TotalCost,string Date,
 string SupplierName,string InvoiceNumber,string InvoiceDate,double InvoiceTotal,double InvoicePaidAmount,double InvoiceBalanceDue);
public sealed record PurchaseInvoiceRequest(int SupplierId,string InvoiceNumber,DateTime InvoiceDate,double InvoiceTotal,
 double InvoiceDiscount,double InvoiceTax,double PaidAmount,IReadOnlyList<PurchaseInvoiceLineInput> Items);
public sealed record PurchaseInvoiceLineInput(int? ProductId,string? NewProductName,string? NewProductBarcode,int Quantity,
 double InvoiceQuantity,double ConversionFactor,double UnitCost,string? UnitLabel,string BaseUnit,double? SalePrice=null,double? LineTotal=null);
internal sealed record PreparedInvoiceLine(PurchaseInvoiceLineInput Input,double RawTotal);
