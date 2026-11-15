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

    public async Task<IReadOnlyList<KhataEntry>> GetLedgerAsync(int partyId,double currentBalance,CancellationToken ct=default)
    {
        var path=PosDatabasePath.Resolve(requireExisting:true);
        await PosDatabaseSchemaVerifier.VerifyAsync(path,ct);
        await using var db=await OpenAsync(path,true,ct);
        await using var cmd=db.CreateCommand();
        cmd.CommandText="""
            SELECT * FROM (
                SELECT s.id AS entry_id,s.date AS date,'sale' AS entry_type,
                    CASE WHEN COALESCE(s.final_amount,0)>0 OR COALESCE(s.total_amount,0)<=0 THEN COALESCE(s.final_amount,0)
                         WHEN COALESCE(s.discount,0)>0 THEN MAX(s.total_amount-s.discount,0)
                         ELSE COALESCE(s.total_amount,0) END AS amount,
                    ('Bill #'||s.id||' - '||COALESCE((SELECT GROUP_CONCAT(product_name||' x'||quantity,', ') FROM sale_items WHERE sale_id=s.id),'Items unavailable')) AS description
                FROM sales s WHERE s.customer_id=$id
                UNION ALL
                SELECT k.id,k.date,k.type,k.amount,
                    CASE WHEN k.type='receipt' THEN 'Cash received'||CASE WHEN COALESCE(k.note,'')='' THEN '' ELSE ' - '||k.note END ELSE COALESCE(k.note,k.type) END
                FROM khata_transactions k WHERE k.party_id=$id AND k.type NOT IN ('credit','return_adjustment')
                UNION ALL
                SELECT r.id,r.date,'return_adjustment',r.refund_amount,('Return against Bill #'||r.sale_id||' - '||r.reason)
                FROM sale_returns r WHERE r.customer_id=$id AND r.refund_method='Khata'
            ) ORDER BY date ASC,entry_id ASC;
            """;
        cmd.Parameters.AddWithValue("$id",partyId);
        await using var reader=await cmd.ExecuteReaderAsync(ct);
        var raw=new List<KhataEntry>();
        while(await reader.ReadAsync(ct))raw.Add(new KhataEntry(reader.GetInt32(0),reader.GetString(1),reader.GetString(2),reader.GetDouble(3),reader.GetString(4),0));
        var movement=raw.Sum(x=>x.Type=="sale"?x.Amount:-x.Amount);
        var running=currentBalance-movement;
        var result=new List<KhataEntry>(raw.Count);
        foreach(var row in raw){running+=row.Type=="sale"?row.Amount:-row.Amount;result.Add(row with{RunningBalance=running});}
        result.Reverse();return result;
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
public sealed record KhataEntry(int Id,string Date,string Type,double Amount,string Description,double RunningBalance)
{
 public double Debit=>Type=="sale"?Amount:0;
 public double Credit=>Type=="sale"?0:Amount;
 public string TypeLabel=>Type switch{"sale"=>"Credit Sale","receipt"=>"Cash Receipt","return_adjustment"=>"Return Adjustment",_=>Type};
}
