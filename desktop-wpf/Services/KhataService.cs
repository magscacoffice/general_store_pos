using System.Globalization;
using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;

namespace KhanBabaPos.Wpf.Services;

public sealed class KhataService
{
    public async Task<IReadOnlyList<KhataCustomer>> GetCustomersAsync(string search="",CancellationToken ct=default)
    {
        var path=PosDatabasePath.Resolve(requireExisting:true);
        await PosDatabaseSchemaVerifier.VerifyAsync(path,ct);
        await using var db=await OpenAsync(path,true,ct);
        await using var cmd=db.CreateCommand();
        cmd.CommandText="""
            SELECT id,name,COALESCE(phone,''),COALESCE(balance,0)
            FROM parties WHERE type='customer' AND ($search='' OR name LIKE $like OR phone LIKE $like)
            ORDER BY name COLLATE NOCASE;
            """;
        cmd.Parameters.AddWithValue("$search",search.Trim());
        cmd.Parameters.AddWithValue("$like","%"+search.Trim()+"%");
        await using var reader=await cmd.ExecuteReaderAsync(ct);
        var rows=new List<KhataCustomer>();
        while(await reader.ReadAsync(ct))rows.Add(new KhataCustomer(reader.GetInt32(0),reader.GetString(1),reader.GetString(2),reader.GetDouble(3)));
        return rows;
    }

    public async Task<IReadOnlyList<KhataEntry>> GetLedgerAsync(int partyId,CancellationToken ct=default)
    {
        var path=PosDatabasePath.Resolve(requireExisting:true);
        await PosDatabaseSchemaVerifier.VerifyAsync(path,ct);
        await using var db=await OpenAsync(path,true,ct);
        await using var cmd=db.CreateCommand();
        cmd.CommandText="SELECT id,date,type,amount,COALESCE(note,'') FROM khata_transactions WHERE party_id=$id ORDER BY id DESC;";
        cmd.Parameters.AddWithValue("$id",partyId);
        await using var reader=await cmd.ExecuteReaderAsync(ct);
        var rows=new List<KhataEntry>();
        while(await reader.ReadAsync(ct))rows.Add(new KhataEntry(reader.GetInt32(0),reader.GetString(1),reader.GetString(2),reader.GetDouble(3),reader.GetString(4)));
        return rows;
    }

    public async Task RecordReceiptAsync(int partyId,double amount,string note,CancellationToken ct=default)
    {
        if(!double.IsFinite(amount)||amount<=0)throw new InvalidOperationException("Receipt amount zero se zyada hona chahiye.");
        var path=PosDatabasePath.Resolve(requireExisting:true);
        await PosDatabaseSchemaVerifier.VerifyAsync(path,ct);
        await DatabaseSafetyService.EnsureVerifiedBackupAsync(path,ct);
        await using var db=await OpenAsync(path,false,ct);
        using var tx=db.BeginTransaction();
        try{
            string? partySyncId;double balance;
            await using(var customer=db.CreateCommand()){
                customer.Transaction=tx;
                customer.CommandText="SELECT sync_id,COALESCE(balance,0) FROM parties WHERE id=$id AND type='customer' LIMIT 1;";
                customer.Parameters.AddWithValue("$id",partyId);
                await using var reader=await customer.ExecuteReaderAsync(ct);
                if(!await reader.ReadAsync(ct))throw new InvalidOperationException("Customer not found.");
                partySyncId=reader.IsDBNull(0)?null:reader.GetString(0);
                balance=reader.GetDouble(1);
            }
            if(balance<=0)throw new InvalidOperationException("Is customer ke khate mein koi baqi raqam mojood nahi.");
            if(amount>balance+0.000001)throw new InvalidOperationException($"Receipt baqi Khata balance (Rs. {balance.ToString("N2",CultureInfo.InvariantCulture)}) se zyada nahi ho sakti.");
            await using(var update=db.CreateCommand()){
                update.Transaction=tx;update.CommandText="UPDATE parties SET balance=balance-$amount WHERE id=$id;";
                update.Parameters.AddWithValue("$amount",amount);update.Parameters.AddWithValue("$id",partyId);
                if(await update.ExecuteNonQueryAsync(ct)!=1)throw new InvalidOperationException("Customer balance update failed.");
            }
            await using(var entry=db.CreateCommand()){
                entry.Transaction=tx;
                entry.CommandText="""
                    INSERT INTO khata_transactions(party_id,party_sync_id,sync_id,type,amount,note,date)
                    VALUES($party,$partySync,$sync,'receipt',$amount,$note,$date);
                    """;
                entry.Parameters.AddWithValue("$party",partyId);
                entry.Parameters.AddWithValue("$partySync",(object?)partySyncId??DBNull.Value);
                entry.Parameters.AddWithValue("$sync",NewSyncId());
                entry.Parameters.AddWithValue("$amount",amount);
                entry.Parameters.AddWithValue("$note",note.Trim());
                entry.Parameters.AddWithValue("$date",DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss",CultureInfo.InvariantCulture));
                await entry.ExecuteNonQueryAsync(ct);
            }
            tx.Commit();
        }catch{tx.Rollback();throw;}
    }

    private static string NewSyncId()=>$"{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}_{Guid.NewGuid():N}";
    private static async Task<SqliteConnection> OpenAsync(string path,bool readOnly,CancellationToken ct){
        var db=new SqliteConnection(new SqliteConnectionStringBuilder{DataSource=path,Mode=readOnly?SqliteOpenMode.ReadOnly:SqliteOpenMode.ReadWrite,Pooling=false}.ToString());
        await db.OpenAsync(ct);return db;
    }
}
public sealed record KhataCustomer(int Id,string Name,string Phone,double Balance);
public sealed record KhataEntry(int Id,string Date,string Type,double Amount,string Note);
