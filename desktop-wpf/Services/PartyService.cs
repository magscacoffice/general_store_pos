using System.Globalization;
using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;
namespace KhanBabaPos.Wpf.Services;
public sealed class PartyService
{
 public async Task<IReadOnlyList<PartyRow>> GetAsync(string type,CancellationToken ct=default)
 {
  if(type is not ("customer" or "supplier"))throw new ArgumentOutOfRangeException(nameof(type));
  var path=PosDatabasePath.Resolve(requireExisting:true);await PosDatabaseSchemaVerifier.VerifyAsync(path,ct);
  await using var db=await Open(path,true,ct);await using var cmd=db.CreateCommand();cmd.CommandText="SELECT id,name,COALESCE(phone,''),COALESCE(balance,0),type,COALESCE(customer_type,'Khata') FROM parties WHERE type=$type ORDER BY name COLLATE NOCASE;";cmd.Parameters.AddWithValue("$type",type);
  await using var rd=await cmd.ExecuteReaderAsync(ct);var rows=new List<PartyRow>();while(await rd.ReadAsync(ct))rows.Add(new(rd.GetInt32(0),rd.GetString(1),rd.GetString(2),rd.GetDouble(3),rd.GetString(4),rd.IsDBNull(5)?"Khata":rd.GetString(5)));return rows;
 }
 public async Task AddAsync(string name,string phone,string type,string customerType="Khata",CancellationToken ct=default)
 {
        AccessService.RequireCurrentAdmin();
  name=name.Trim();phone=phone.Trim();if(name.Length==0)throw new InvalidOperationException("Party name zaroori hai.");if(type is not ("customer" or "supplier"))throw new ArgumentOutOfRangeException(nameof(type));
  if(type=="customer" && customerType is not ("Khata" or "Wholesale"))throw new InvalidOperationException("Customer type must be Khata or Wholesale.");
  var path=PosDatabasePath.Resolve(requireExisting:true);await PosDatabaseSchemaVerifier.VerifyAsync(path,ct);await DatabaseSafetyService.EnsureVerifiedBackupAsync(path,ct);
  await using var db=await Open(path,false,ct);await using var tx=await db.BeginTransactionAsync(ct);await using var cmd=db.CreateCommand();cmd.Transaction=(SqliteTransaction)tx;
  cmd.CommandText="INSERT INTO parties(name,phone,type,customer_type,balance,sync_id) VALUES($name,$phone,$type,$customerType,0,$sync);";
  cmd.Parameters.AddWithValue("$name",name);cmd.Parameters.AddWithValue("$phone",phone);cmd.Parameters.AddWithValue("$type",type);cmd.Parameters.AddWithValue("$customerType",type=="customer"?customerType:DBNull.Value);cmd.Parameters.AddWithValue("$sync",$"{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}_{Guid.NewGuid():N}");
  await cmd.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);
 }
 public async Task UpdateCustomerTypeAsync(int id,string customerType,CancellationToken ct=default)
 {
        AccessService.RequireCurrentAdmin();
  if(customerType is not ("Khata" or "Wholesale"))throw new InvalidOperationException("Customer type must be Khata or Wholesale.");
  var path=PosDatabasePath.Resolve(requireExisting:true);await PosDatabaseSchemaVerifier.VerifyAsync(path,ct);await DatabaseSafetyService.EnsureVerifiedBackupAsync(path,ct);
  await using var db=await Open(path,false,ct);await using var cmd=db.CreateCommand();
  cmd.CommandText="UPDATE parties SET customer_type=$type WHERE id=$id AND type='customer';";
  cmd.Parameters.AddWithValue("$type",customerType);cmd.Parameters.AddWithValue("$id",id);
  if(await cmd.ExecuteNonQueryAsync(ct)!=1)throw new InvalidOperationException("Customer account not found.");
 }

 public Task<int> DeleteAsync(int id,string type,CancellationToken ct=default) =>
  DeleteAsync(id,type,PosDatabasePath.Resolve(requireExisting:true),ct);

 public async Task<int> DeleteAsync(int id,string type,string databasePath,CancellationToken ct=default)
 {
  AccessService.RequireCurrentAdmin();
  if(type is not ("customer" or "supplier"))throw new ArgumentOutOfRangeException(nameof(type));
  if(string.IsNullOrWhiteSpace(databasePath))throw new ArgumentException("Database path is required.",nameof(databasePath));
  await PosDatabaseSchemaVerifier.VerifyAsync(databasePath,ct);
  await DatabaseSafetyService.EnsureVerifiedBackupAsync(databasePath,ct);
  await using var db=await Open(databasePath,false,ct);
  await using var tx=await db.BeginTransactionAsync(ct);
  string? syncId;double balance;string actualType;
  await using(var lookup=db.CreateCommand())
  {
   lookup.Transaction=(SqliteTransaction)tx;
   lookup.CommandText="SELECT type,COALESCE(balance,0),sync_id FROM parties WHERE id=$id LIMIT 1;";
   lookup.Parameters.AddWithValue("$id",id);
   await using var rd=await lookup.ExecuteReaderAsync(ct);
   if(!await rd.ReadAsync(ct))return 0;
   actualType=rd.GetString(0);balance=rd.GetDouble(1);syncId=rd.IsDBNull(2)?null:rd.GetString(2);
  }
  if(!string.Equals(actualType,type,StringComparison.Ordinal))
   throw new InvalidOperationException("Selected account type does not match the stored account.");
  int references;
  await using(var count=db.CreateCommand())
  {
   count.Transaction=(SqliteTransaction)tx;
   count.CommandText=type=="customer"
    ? "SELECT (SELECT COUNT(*) FROM sales WHERE customer_id=$id)+(SELECT COUNT(*) FROM khata_transactions WHERE party_id=$id);"
    : "SELECT COUNT(*) FROM purchases WHERE supplier_id=$id;";
   count.Parameters.AddWithValue("$id",id);
   references=Convert.ToInt32(await count.ExecuteScalarAsync(ct),CultureInfo.InvariantCulture);
  }
  if(references>0||Math.Abs(balance)>0.000001)
   throw new InvalidOperationException("Is account ki transaction history ya outstanding balance mojood hai. Ledger aur purane records mehfooz rakhne ke liye delete nahi kar sakte.");
  if(!string.IsNullOrWhiteSpace(syncId))
  {
   await using var tombstone=db.CreateCommand();
   tombstone.Transaction=(SqliteTransaction)tx;
   tombstone.CommandText="""
    INSERT INTO drive_sync_tombstones(entity_type,entity_key,deleted_at,source_device_id)
    VALUES('party',$key,$date,'windows-master')
    ON CONFLICT(entity_type,entity_key) DO UPDATE SET
      deleted_at=excluded.deleted_at,source_device_id='windows-master';
    """;
   tombstone.Parameters.AddWithValue("$key",syncId);
   tombstone.Parameters.AddWithValue("$date",DateTime.UtcNow.ToString("O",CultureInfo.InvariantCulture));
   await tombstone.ExecuteNonQueryAsync(ct);
  }
  await using var delete=db.CreateCommand();
  delete.Transaction=(SqliteTransaction)tx;
  delete.CommandText="DELETE FROM parties WHERE id=$id AND type=$type;";
  delete.Parameters.AddWithValue("$id",id);
  delete.Parameters.AddWithValue("$type",type);
  var deleted=await delete.ExecuteNonQueryAsync(ct);
  await tx.CommitAsync(ct);
  return deleted;
 }

 static async Task<SqliteConnection> Open(string path,bool ro,CancellationToken ct){var db=new SqliteConnection(new SqliteConnectionStringBuilder{DataSource=path,Mode=ro?SqliteOpenMode.ReadOnly:SqliteOpenMode.ReadWrite,Pooling=false}.ToString());await db.OpenAsync(ct);return db;}
}
public sealed record PartyRow(int Id,string Name,string Phone,double Balance,string Type,string CustomerType);