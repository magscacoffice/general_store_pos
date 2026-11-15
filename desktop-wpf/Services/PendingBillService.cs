using System.Text.Json;
using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;

namespace KhanBabaPos.Wpf.Services;

/// <summary>Persists WPF pending bills in the existing schema-v18 pending_bills table.</summary>
public sealed class PendingBillService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true
    };

    public async Task SaveAsync(PendingBillSnapshot bill, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(bill.BillId))
            throw new InvalidOperationException("Pending bill ID is required.");
        var path = PosDatabasePath.Resolve(requireExisting: true);
        await PosDatabaseSchemaVerifier.VerifyAsync(path, cancellationToken);
        await DatabaseSafetyService.EnsureVerifiedBackupAsync(path, cancellationToken);
        await using var connection = await OpenAsync(path, cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO pending_bills (bill_id, label, payload, updated_at)
            VALUES ($id, $label, $payload, $updated)
            ON CONFLICT(bill_id) DO UPDATE SET
                label = excluded.label,
                payload = excluded.payload,
                updated_at = excluded.updated_at;
            """;
        command.Parameters.AddWithValue("$id", bill.BillId);
        command.Parameters.AddWithValue("$label", string.IsNullOrWhiteSpace(bill.Label) ? "Pending Bill" : bill.Label);
        command.Parameters.AddWithValue("$payload", JsonSerializer.Serialize(bill.ToPayload(), JsonOptions));
        command.Parameters.AddWithValue("$updated", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<PendingBillSnapshot>> GetAllAsync(CancellationToken cancellationToken = default)
    {
        var path = PosDatabasePath.Resolve(requireExisting: true);
        await PosDatabaseSchemaVerifier.VerifyAsync(path, cancellationToken);
        await DatabaseSafetyService.EnsureVerifiedBackupAsync(path, cancellationToken);
        await using var connection = await OpenAsync(path, cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT bill_id, label, payload, updated_at FROM pending_bills ORDER BY updated_at DESC;";
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var bills = new List<PendingBillSnapshot>();
        while (await reader.ReadAsync(cancellationToken))
        {
            try
            {
                var payload = JsonSerializer.Deserialize<PendingBillPayload>(reader.GetString(2), JsonOptions);
                if (payload is null) continue;
                bills.Add(new PendingBillSnapshot(
                    reader.GetString(0),
                    reader.IsDBNull(1) ? "Pending Bill" : reader.GetString(1),
                    reader.IsDBNull(3) ? string.Empty : reader.GetString(3),
                    payload.Cart ?? [],
                    payload.SelectedCustomerId,
                    payload.SelectedSaleType ?? "Walk-in",
                    payload.CustomerPaymentMode ?? "Cash",
                    payload.OverallDiscount,
                    payload.IsPercentageDiscount,
                    payload.ReceivedAmount ?? string.Empty));
            }
            catch (JsonException)
            {
                // Match Flutter recovery behaviour: skip an unreadable pending bill without blocking other bills.
            }
        }
        return bills;
    }

    public async Task DeleteAsync(string billId, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(billId)) return;
        var path = PosDatabasePath.Resolve(requireExisting: true);
        await PosDatabaseSchemaVerifier.VerifyAsync(path, cancellationToken);
        await using var connection = await OpenAsync(path, cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = "DELETE FROM pending_bills WHERE bill_id = $id;";
        command.Parameters.AddWithValue("$id", billId);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task<SqliteConnection> OpenAsync(string path, CancellationToken cancellationToken)
    {
        var connection = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = path,
            Mode = SqliteOpenMode.ReadWrite,
            Pooling = false
        }.ToString());
        await connection.OpenAsync(cancellationToken);
        return connection;
    }
}

public sealed record PendingBillSnapshot(
    string BillId,
    string Label,
    string UpdatedAt,
    IReadOnlyList<PendingBillLine> Cart,
    int? SelectedCustomerId,
    string SelectedSaleType,
    string CustomerPaymentMode,
    double OverallDiscount,
    bool IsPercentageDiscount,
    string ReceivedAmount)
{
    internal PendingBillPayload ToPayload() => new()
    {
        Cart = Cart,
        SelectedCustomerId = SelectedCustomerId,
        SelectedSaleType = SelectedSaleType,
        CustomerPaymentMode = CustomerPaymentMode,
        OverallDiscount = OverallDiscount,
        IsPercentageDiscount = IsPercentageDiscount,
        ReceivedAmount = ReceivedAmount
    };
}

public sealed record PendingBillLine(
    string Barcode,
    string Name,
    double SalePrice,
    int Quantity,
    double PurchasePrice,
    string StockUnit);

internal sealed class PendingBillPayload
{
    public IReadOnlyList<PendingBillLine>? Cart { get; init; }
    public int? SelectedCustomerId { get; init; }
    public string? SelectedSaleType { get; init; }
    public string? CustomerPaymentMode { get; init; }
    public double OverallDiscount { get; init; }
    public bool IsPercentageDiscount { get; init; }
    public string? ReceivedAmount { get; init; }
}
