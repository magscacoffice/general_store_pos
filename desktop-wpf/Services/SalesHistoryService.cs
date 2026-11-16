using System.Globalization;
using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;

namespace KhanBabaPos.Wpf.Services;

public sealed class SalesHistoryService
{
    public async Task<IReadOnlyList<SaleHistoryRecord>> GetSalesAsync(
        string search = "", DateTime? from = null, DateTime? to = null,
        CancellationToken cancellationToken = default)
    {
        var path = PosDatabasePath.Resolve(requireExisting: true);
        await PosDatabaseSchemaVerifier.VerifyAsync(path, cancellationToken);
        await using var db = await OpenReadOnlyAsync(path, cancellationToken);
        await using var cmd = db.CreateCommand();
        cmd.CommandText = """
            SELECT s.id, s.date, s.customer_id, COALESCE(p.name,'Walk-in Customer'),
                   COALESCE(s.customer_type,'Walk-in'), COALESCE(s.payment_type,'Cash'),
                   COALESCE(s.total_amount,0), COALESCE(s.discount,0), s.final_amount,
                   COALESCE(s.received_amount,0), COALESCE(s.balance_due,0),
                   COALESCE(s.salesman_name,''), COALESCE((SELECT SUM(r.refund_amount)
                     FROM sale_returns r WHERE r.sale_id=s.id),0),
                   (SELECT COUNT(*) FROM sale_returns r WHERE r.sale_id=s.id)
            FROM sales s LEFT JOIN parties p ON p.id=s.customer_id
            WHERE ($search='' OR CAST(s.id AS TEXT) LIKE $like OR p.name LIKE $like
                   OR s.date LIKE $like OR s.payment_type LIKE $like)
              AND ($from IS NULL OR substr(s.date,1,10) >= $from)
              AND ($to IS NULL OR substr(s.date,1,10) <= $to)
            ORDER BY s.id DESC;
            """;
        cmd.Parameters.AddWithValue("$search", search.Trim());
        cmd.Parameters.AddWithValue("$like", "%" + search.Trim() + "%");
        cmd.Parameters.AddWithValue("$from", from is null ? DBNull.Value : from.Value.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture));
        cmd.Parameters.AddWithValue("$to", to is null ? DBNull.Value : to.Value.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture));
        await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
        var result = new List<SaleHistoryRecord>();
        while (await reader.ReadAsync(cancellationToken))
        {
            var customerId = reader.IsDBNull(2) ? (int?)null : reader.GetInt32(2);
            var total = reader.GetDouble(6);
            var discount = reader.GetDouble(7);
            var finalRaw = reader.IsDBNull(8) ? 0d : reader.GetDouble(8);
            var payment = reader.GetString(5);
            var receivedRaw = reader.GetDouble(9);
            var balanceRaw = reader.GetDouble(10);
            var final = !reader.IsDBNull(7) && (finalRaw > 0 || total <= 0)
                ? finalRaw
                : discount > 0 ? Math.Max(0d, total - discount) : total;
            var received = receivedRaw > 0 ? receivedRaw : payment == "Cash" ? final : receivedRaw;
            var balance = balanceRaw > 0 ? balanceRaw :
                payment is "Khata" or "Partial" ? Math.Max(0d, final - received) : balanceRaw;
            result.Add(new SaleHistoryRecord(reader.GetInt32(0), reader.GetString(1), reader.GetString(2),
                reader.GetString(4), payment, total, discount, final, received, balance,
                reader.GetString(11), reader.GetDouble(12), reader.GetInt32(13), customerId));
        }
        return result;
    }

    public async Task<IReadOnlyList<SaleHistoryItem>> GetSaleItemsAsync(int saleId, CancellationToken cancellationToken = default)
    {
        var path = PosDatabasePath.Resolve(requireExisting: true);
        await PosDatabaseSchemaVerifier.VerifyAsync(path, cancellationToken);
        await using var db = await OpenReadOnlyAsync(path, cancellationToken);
        await using var cmd = db.CreateCommand();
        cmd.CommandText = """
            SELECT id, barcode, product_name, quantity, COALESCE(stock_unit,'pcs'),
                   sale_price, purchase_price, line_total, cost_total
            FROM sale_items WHERE sale_id=$id ORDER BY id ASC;
            """;
        cmd.Parameters.AddWithValue("$id", saleId);
        await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
        var items = new List<SaleHistoryItem>();
        while (await reader.ReadAsync(cancellationToken))
            items.Add(new SaleHistoryItem(reader.GetInt32(0), reader.GetString(1), reader.GetString(2),
                reader.GetInt32(3), reader.GetString(4), reader.GetDouble(5), reader.GetDouble(6),
                reader.GetDouble(7), reader.GetDouble(8)));
        return items;
    }

    private static async Task<SqliteConnection> OpenReadOnlyAsync(string path, CancellationToken ct)
    {
        var db = new SqliteConnection(new SqliteConnectionStringBuilder
        { DataSource=path, Mode=SqliteOpenMode.ReadOnly, Pooling=false }.ToString());
        await db.OpenAsync(ct);
        return db;
    }
}

public sealed record SaleHistoryRecord(int SaleId,string Date,string CustomerName,string CustomerType,
    string PaymentType,double Subtotal,double Discount,double FinalAmount,double Received,double BalanceDue,
    string Cashier,double ReturnedAmount,int ReturnedCount,int? CustomerId);
public sealed record SaleHistoryItem(int Id,string Barcode,string ProductName,int Quantity,string StockUnit,
    double SalePrice,double PurchasePrice,double LineTotal,double CostTotal);
