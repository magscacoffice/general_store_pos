using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;
namespace KhanBabaPos.Wpf.Services;
public sealed class ExpenseService
{
 public async Task<IReadOnlyList<ExpenseRow>> GetAllAsync(CancellationToken ct=default)
 {
  var path=PosDatabasePath.Resolve(requireExisting:true);await PosDatabaseSchemaVerifier.VerifyAsync(path,ct);
  await using var db=await Open(path,true,ct);await using var cmd=db.CreateCommand();
  cmd.CommandText="SELECT id,title,amount,date FROM expenses ORDER BY id DESC;";
  await using var rd=await cmd.ExecuteReaderAsync(ct);var rows=new List<ExpenseRow>();
  while(await rd.ReadAsync(ct))rows.Add(new ExpenseRow(rd.GetInt32(0),rd.GetString(1),rd.GetDouble(2),rd.GetString(3)));
  return rows;
 }
 public async Task<int> AddAsync(string title,double amount,CancellationToken ct=default)
 {
  title=title.Trim();if(title.Length==0||!double.IsFinite(amount)||amount<=0)throw new InvalidOperationException("Title aur positive valid amount darj karein.");
  var path=PosDatabasePath.Resolve(requireExisting:true);await PosDatabaseSchemaVerifier.VerifyAsync(path,ct);await DatabaseSafetyService.EnsureVerifiedBackupAsync(path,ct);
  await using var db=await Open(path,false,ct);await using var tx=await db.BeginTransactionAsync(ct);
  await using var cmd=db.CreateCommand();cmd.Transaction=(SqliteTransaction)tx;
  cmd.CommandText="INSERT INTO expenses(title,amount,date,sync_id) VALUES($title,$amount,$date,$sync); SELECT last_insert_rowid();";
  cmd.Parameters.AddWithValue("$title",title);cmd.Parameters.AddWithValue("$amount",amount);
  cmd.Parameters.AddWithValue("$date",DateTime.Now.ToString("yyyy-MM-dd HH:mm",System.Globalization.CultureInfo.InvariantCulture));
  cmd.Parameters.AddWithValue("$sync",Guid.NewGuid().ToString("N"));
  var value=await cmd.ExecuteScalarAsync(ct);var id=Convert.ToInt32(value,System.Globalization.CultureInfo.InvariantCulture);await tx.CommitAsync(ct);return id;
 }
 static async Task<SqliteConnection> Open(string path,bool ro,CancellationToken ct){var db=new SqliteConnection(new SqliteConnectionStringBuilder{DataSource=path,Mode=ro?SqliteOpenMode.ReadOnly:SqliteOpenMode.ReadWrite,Pooling=false}.ToString());await db.OpenAsync(ct);return db;}
}
public sealed record ExpenseRow(int Id,string Title,double Amount,string Date);