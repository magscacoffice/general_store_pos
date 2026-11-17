using System.Text.Json;
using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;

namespace KhanBabaPos.Wpf.Services;

/// <summary>Persists WPF pending bills in the existing schema-v18 pending_bills table.</summary>
public sealed class PendingBillService(string? databasePath = null)
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true
    };

    private string ResolvePath() =>
        string.IsNullOrWhiteSpace(databasePath)
            ? PosDatabasePath.Resolve(requireExisting: true)
            : databasePath;

    public async Task SaveAsync(PendingBillSnapshot bill, CancellationToken cancellationToken = default)
    {
        AccessService.RequireCurrentRole(AccessRole.Admin, AccessRole.Salesman);
        var session = AccessService.CurrentSession
            ?? throw new UnauthorizedAccessException("Active cashier session required.");
        if (string.IsNullOrWhiteSpace(bill.BillId))
            throw new InvalidOperationException("Pending bill ID is required.");

        var path = ResolvePath();
        await PosDatabaseSchemaVerifier.VerifyAsync(path, cancellationToken);
        await DatabaseSafetyService.EnsureVerifiedBackupAsync(path, cancellationToken);
        await using var connection = await OpenAsync(path, cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        var existingFound = false;
        var existingOwner = string.Empty;
        await using (var lookup = connection.CreateCommand())
        {
            lookup.Transaction = (SqliteTransaction)transaction;
            lookup.CommandText = "SELECT payload FROM pending_bills WHERE bill_id=$id LIMIT 1;";
            lookup.Parameters.AddWithValue("$id", bill.BillId);
            var raw = await lookup.ExecuteScalarAsync(cancellationToken);
            existingFound = raw is not null and not DBNull;
            if (existingFound)
            {
                try
                {
                    existingOwner = JsonSerializer.Deserialize<PendingBillPayload>(Convert.ToString(raw)!, JsonOptions)?.CashierUid ?? string.Empty;
                }
                catch (JsonException)
                {
                    // An unowned/corrupt legacy draft may only be repaired by Admin.
                }
            }
        }

        if (session.Role == AccessRole.Salesman && existingFound &&
            !string.Equals(existingOwner, session.UserId, StringComparison.Ordinal))
            throw new UnauthorizedAccessException("Salesman doosray cashier ka pending bill overwrite nahi kar sakta.");

        var ownerUid = session.Role == AccessRole.Salesman
            ? session.UserId
            : !string.IsNullOrWhiteSpace(existingOwner)
                ? existingOwner
                : !string.IsNullOrWhiteSpace(bill.CashierUid) ? bill.CashierUid : session.UserId;
        var ownedBill = bill with { CashierUid = ownerUid };

        await using var command = connection.CreateCommand();
        command.Transaction = (SqliteTransaction)transaction;
        command.CommandText = """
            INSERT INTO pending_bills (bill_id, label, payload, updated_at)
            VALUES ($id, $label, $payload, $updated)
            ON CONFLICT(bill_id) DO UPDATE SET
                label = excluded.label,
                payload = excluded.payload,
                updated_at = excluded.updated_at;
            """;
        command.Parameters.AddWithValue("$id", ownedBill.BillId);
        command.Parameters.AddWithValue("$label", string.IsNullOrWhiteSpace(ownedBill.Label) ? "Pending Bill" : ownedBill.Label);
        command.Parameters.AddWithValue("$payload", JsonSerializer.Serialize(ownedBill.ToPayload(), JsonOptions));
        command.Parameters.AddWithValue("$updated", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
        await command.ExecuteNonQueryAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<PendingBillSnapshot>> GetAllAsync(CancellationToken cancellationToken = default)
    {
        AccessService.RequireCurrentRole(AccessRole.Admin, AccessRole.Salesman);
        var session = AccessService.CurrentSession
            ?? throw new UnauthorizedAccessException("Active cashier session required.");
        var path = ResolvePath();
        await PosDatabaseSchemaVerifier.VerifyAsync(path, cancellationToken);
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
                var ownerUid = payload.CashierUid ?? string.Empty;
                if (session.Role == AccessRole.Salesman &&
                    !string.Equals(ownerUid, session.UserId, StringComparison.Ordinal))
                    continue;

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
                    payload.ReceivedAmount ?? string.Empty,
                    ownerUid));
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
        AccessService.RequireCurrentRole(AccessRole.Admin, AccessRole.Salesman);
        var session = AccessService.CurrentSession
            ?? throw new UnauthorizedAccessException("Active cashier session required.");
        if (string.IsNullOrWhiteSpace(billId)) return;
        var path = ResolvePath();
        await PosDatabaseSchemaVerifier.VerifyAsync(path, cancellationToken);
        await DatabaseSafetyService.EnsureVerifiedBackupAsync(path, cancellationToken);
        await using var connection = await OpenAsync(path, cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        await using (var lookup = connection.CreateCommand())
        {
            lookup.Transaction = (SqliteTransaction)transaction;
            lookup.CommandText = "SELECT payload FROM pending_bills WHERE bill_id=$id LIMIT 1;";
            lookup.Parameters.AddWithValue("$id", billId);
            var raw = await lookup.ExecuteScalarAsync(cancellationToken);
            if (raw is null or DBNull)
            {
                await transaction.CommitAsync(cancellationToken);
                return;
            }

            if (session.Role == AccessRole.Salesman)
            {
                string ownerUid;
                try
                {
                    ownerUid = JsonSerializer.Deserialize<PendingBillPayload>(Convert.ToString(raw)!, JsonOptions)?.CashierUid ?? string.Empty;
                }
                catch (JsonException)
                {
                    ownerUid = string.Empty;
                }
                if (!string.Equals(ownerUid, session.UserId, StringComparison.Ordinal))
                    throw new UnauthorizedAccessException("Salesman doosray cashier ka pending bill delete nahi kar sakta.");
            }
        }

        await using var command = connection.CreateCommand();
        command.Transaction = (SqliteTransaction)transaction;
        command.CommandText = "DELETE FROM pending_bills WHERE bill_id = $id;";
        command.Parameters.AddWithValue("$id", billId);
        await command.ExecuteNonQueryAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
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
    string ReceivedAmount,
    string CashierUid = "")
{
    internal PendingBillPayload ToPayload() => new()
    {
        Cart = Cart,
        SelectedCustomerId = SelectedCustomerId,
        SelectedSaleType = SelectedSaleType,
        CustomerPaymentMode = CustomerPaymentMode,
        OverallDiscount = OverallDiscount,
        IsPercentageDiscount = IsPercentageDiscount,
        ReceivedAmount = ReceivedAmount,
        CashierUid = CashierUid
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
    public string? CashierUid { get; init; }
}
