using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;
namespace KhanBabaPos.Wpf.Services;
public sealed class PartyService
{
 public async Task<IReadOnlyList<PartyRow>> GetAsync(string type,CancellationToken ct=default)
 {
  if(type is not ("customer" or "supplier"))throw new ArgumentOutOfRangeException(nameof(type));
  var path=PosDatabasePath.Resolve(requireExisting:true);await PosDatabaseSchemaVerifier.VerifyAsync(path,ct);
  await using var db=await Open(path,true,ct);await using var cmd=db.CreateCommand();cmd.CommandText="SELECT id,name,COALESCE(phone,''),COALESCE(balance,0),type FROM parties WHERE type=$type ORDER BY name COLLATE NOCASE;";cmd.Parameters.AddWithValue("$type",type);
  await using var rd=await cmd.ExecuteReaderAsync(ct);var rows=new List<PartyRow>();while(await rd.ReadAsync(ct))rows.Add(new(rd.GetInt32(0),rd.GetString(1),rd.GetString(2),rd.GetDouble(3),rd.GetString(4)));return rows;
 }
 public async Task AddAsync(string name,string phone,string type,CancellationToken ct=default)
 {
  name=name.Trim();phone=phone.Trim();if(name.Length==0)throw new InvalidOperationException("Party name zaroori hai.");if(type is not ("customer" or "supplier"))throw new ArgumentOutOfRangeException(nameof(type));
  var path=PosDatabasePath.Resolve(requireExisting:true);await PosDatabaseSchemaVerifier.VerifyAsync(path,ct);await DatabaseSafetyService.EnsureVerifiedBackupAsync(path,ct);
  await using var db=await Open(path,false,ct);await using var tx=await db.BeginTransactionAsync(ct);await using var cmd=db.CreateCommand();cmd.Transaction=(SqliteTransaction)tx;
  cmd.CommandText="INSERT INTO parties(name,phone,type,customer_type,balance,sync_id) VALUES($name,$phone,$type,$customerType,0,$sync);";
  cmd.Parameters.AddWithValue("$name",name);cmd.Parameters.AddWithValue("$phone",phone);cmd.Parameters.AddWithValue("$type",type);cmd.Parameters.AddWithValue("$customerType",type=="customer"?"Khata":DBNull.Value);cmd.Parameters.AddWithValue("$sync",$"{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}_{Guid.NewGuid():N}");
  await cmd.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);
 }
 static async Task<SqliteConnection> Open(string path,bool ro,CancellationToken ct){var db=new SqliteConnection(new SqliteConnectionStringBuilder{DataSource=path,Mode=ro?SqliteOpenMode.ReadOnly:SqliteOpenMode.ReadWrite,Pooling=false}.ToString());await db.OpenAsync(ct);return db;}
}
public sealed record PartyRow(int Id,string Name,string Phone,double Balance,string Type);