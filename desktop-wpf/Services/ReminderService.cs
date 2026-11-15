using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;
namespace KhanBabaPos.Wpf.Services;
public sealed class ReminderService
{
 public async Task<IReadOnlyList<ReminderRow>> GetAllAsync(CancellationToken ct=default)
 {
  var path=PosDatabasePath.Resolve(requireExisting:true);await PosDatabaseSchemaVerifier.VerifyAsync(path,ct);
  await using var db=await Open(path,true,ct);await using var cmd=db.CreateCommand();cmd.CommandText="SELECT id,title,COALESCE(details,''),date,COALESCE(is_done,0) FROM reminders ORDER BY id DESC;";
  await using var rd=await cmd.ExecuteReaderAsync(ct);var rows=new List<ReminderRow>();while(await rd.ReadAsync(ct))rows.Add(new(rd.GetInt32(0),rd.GetString(1),rd.GetString(2),rd.GetString(3),rd.GetInt32(4)!=0));return rows;
 }
 public async Task AddAsync(string title,string details,CancellationToken ct=default)
 {
  title=title.Trim();if(title.Length==0)throw new InvalidOperationException("Reminder title zaroori hai.");
  var path=PosDatabasePath.Resolve(requireExisting:true);await PosDatabaseSchemaVerifier.VerifyAsync(path,ct);await DatabaseSafetyService.EnsureVerifiedBackupAsync(path,ct);
  await using var db=await Open(path,false,ct);await using var tx=await db.BeginTransactionAsync(ct);await using var cmd=db.CreateCommand();cmd.Transaction=(SqliteTransaction)tx;
  cmd.CommandText="INSERT INTO reminders(title,details,date,is_done,sync_id) VALUES($title,$details,$date,0,$sync);";
  cmd.Parameters.AddWithValue("$title",title);cmd.Parameters.AddWithValue("$details",details.Trim());cmd.Parameters.AddWithValue("$date",DateTime.Now.ToString("yyyy-MM-dd",System.Globalization.CultureInfo.InvariantCulture));cmd.Parameters.AddWithValue("$sync",Guid.NewGuid().ToString("N"));await cmd.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);
 }
 static async Task<SqliteConnection> Open(string path,bool ro,CancellationToken ct){var db=new SqliteConnection(new SqliteConnectionStringBuilder{DataSource=path,Mode=ro?SqliteOpenMode.ReadOnly:SqliteOpenMode.ReadWrite,Pooling=false}.ToString());await db.OpenAsync(ct);return db;}
}
public sealed record ReminderRow(int Id,string Title,string Details,string Date,bool IsDone);