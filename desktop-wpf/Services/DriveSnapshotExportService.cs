using System.IO;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Encodings.Web;
using System.Text.Json.Serialization;
using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;

namespace KhanBabaPos.Wpf.Services;

/// <summary>
/// Produces the schema-v2 Drive snapshot consumed by the Android Windows-master
/// protocol. Local integer IDs and device-local foreign keys are omitted; stable
/// sync IDs and barcode keys are retained. Missing legacy IDs are assigned only
/// after a verified safety backup has been made.
/// </summary>
public sealed class DriveSnapshotExportService
{
    private static readonly IReadOnlyDictionary<string, string[]> RemovedColumns =
        new Dictionary<string, string[]>
        {
            ["products"] = ["id"],
            ["parties"] = ["id"],
            ["sales"] = ["id", "customer_id"],
            ["sale_items"] = ["id", "sale_id", "product_id"],
            ["purchases"] = ["id", "product_id", "supplier_id", "invoice_image_path"],
            ["khata_transactions"] = ["id", "party_id"],
            ["expenses"] = ["id"],
            ["reminders"] = ["id"],
            ["sale_returns"] = ["id", "sale_id", "customer_id"],
            ["sale_return_items"] = ["id", "return_id", "sale_item_id", "product_id"],
            ["tombstones"] = []
        };

    public async Task<DriveSnapshotPayload> ExportAsync(
        string? databasePath = null,
        CancellationToken cancellationToken = default)
    {
        var path = databasePath ?? PosDatabasePath.Resolve();
        await PosDatabaseSchemaVerifier.VerifyAsync(path, cancellationToken);
        if (await HasMissingStableIdsAsync(path, cancellationToken))
        {
            await DatabaseBackupServiceForDrive.CreateBeforeIdentityRepairAsync(path, cancellationToken);
            await EnsureStableIdsAsync(path, cancellationToken);
        }

        await using var connection = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = path,
            Mode = SqliteOpenMode.ReadOnly,
            Pooling = false
        }.ToString());
        await connection.OpenAsync(cancellationToken);

        var snapshot = new Dictionary<string, object?>
        {
            ["schemaVersion"] = 2
        };
        foreach (var table in new[]
        {
            "products", "parties", "sales", "sale_items", "purchases",
            "khata_transactions", "expenses", "reminders", "sale_returns",
            "sale_return_items"
        })
        {
            snapshot[table] = await ReadRowsAsync(
                connection, table, RemovedColumns[table], cancellationToken);
        }
        snapshot["tombstones"] = await ReadRowsAsync(
            connection, "drive_sync_tombstones", [], cancellationToken);

        var json = JsonSerializer.Serialize(snapshot, new JsonSerializerOptions
        {
            Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
            Converters = { new DartCompatibleDoubleConverter() }
        });
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(json)))
            .ToLowerInvariant();
        return new DriveSnapshotPayload(snapshot, hash, json);
    }

    private static async Task<bool> HasMissingStableIdsAsync(
        string path, CancellationToken cancellationToken)
    {
        await using var connection = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = path, Mode = SqliteOpenMode.ReadOnly, Pooling = false
        }.ToString());
        await connection.OpenAsync(cancellationToken);
        foreach (var table in new[]
        {
            "parties", "sales", "sale_items", "purchases", "khata_transactions",
            "expenses", "reminders", "sale_returns", "sale_return_items"
        })
        {
            await using var command = connection.CreateCommand();
            command.CommandText = $"SELECT COUNT(*) FROM \"{table}\" WHERE sync_id IS NULL OR trim(sync_id) = '';"; 
            if (Convert.ToInt64(await command.ExecuteScalarAsync(cancellationToken)) > 0)
                return true;
        }
        var relationChecks = new[]
        {
            "SELECT COUNT(*) FROM sales WHERE customer_sync_id IS NOT (SELECT sync_id FROM parties WHERE parties.id = sales.customer_id) OR customer_type IS NOT CASE WHEN customer_id IS NULL THEN 'Walk-in' ELSE COALESCE(NULLIF(customer_type, ''), 'Khata') END;",
            "SELECT COUNT(*) FROM sale_items WHERE sale_sync_id IS NOT (SELECT sync_id FROM sales WHERE sales.id = sale_items.sale_id);",
            "SELECT COUNT(*) FROM purchases WHERE supplier_sync_id IS NOT (SELECT sync_id FROM parties WHERE parties.id = purchases.supplier_id);",
            "SELECT COUNT(*) FROM khata_transactions WHERE party_sync_id IS NOT (SELECT sync_id FROM parties WHERE parties.id = khata_transactions.party_id);",
            "SELECT COUNT(*) FROM sale_returns WHERE sale_sync_id IS NOT (SELECT sync_id FROM sales WHERE sales.id = sale_returns.sale_id) OR party_sync_id IS NOT (SELECT sync_id FROM parties WHERE parties.id = sale_returns.customer_id);",
            "SELECT COUNT(*) FROM sale_return_items WHERE return_sync_id IS NOT (SELECT sync_id FROM sale_returns WHERE sale_returns.id = sale_return_items.return_id) OR sale_item_sync_id IS NOT (SELECT sync_id FROM sale_items WHERE sale_items.id = sale_return_items.sale_item_id);"
        };
        foreach (var sql in relationChecks)
        {
            await using var command = connection.CreateCommand();
            command.CommandText = sql;
            if (Convert.ToInt64(await command.ExecuteScalarAsync(cancellationToken)) > 0)
                return true;
        }
        return false;
    }

    private static async Task EnsureStableIdsAsync(
        string path, CancellationToken cancellationToken)
    {
        await using var connection = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = path, Mode = SqliteOpenMode.ReadWrite, Pooling = false
        }.ToString());
        await connection.OpenAsync(cancellationToken);
        await using var transaction = connection.BeginTransaction();
        foreach (var table in new[]
        {
            "parties", "sales", "sale_items", "purchases", "khata_transactions",
            "expenses", "reminders", "sale_returns", "sale_return_items"
        })
        {
            await using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = $"SELECT id FROM \"{table}\" WHERE sync_id IS NULL OR trim(sync_id) = '';";
            var ids = new List<long>();
            await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
                while (await reader.ReadAsync(cancellationToken)) ids.Add(reader.GetInt64(0));

            foreach (var id in ids)
            {
                await using var update = connection.CreateCommand();
                update.Transaction = transaction;
                update.CommandText = $"UPDATE \"{table}\" SET sync_id = $syncId WHERE id = $id;";
                update.Parameters.AddWithValue("$syncId",
                    $"{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}_{Convert.ToHexString(RandomNumberGenerator.GetBytes(8)).ToLowerInvariant()}");
                update.Parameters.AddWithValue("$id", id);
                await update.ExecuteNonQueryAsync(cancellationToken);
            }
        }

        var relations = new[]
        {
            "UPDATE sales SET customer_sync_id = (SELECT sync_id FROM parties WHERE parties.id = sales.customer_id), customer_type = COALESCE(NULLIF(customer_type, ''), CASE WHEN customer_id IS NULL THEN 'Walk-in' ELSE 'Khata' END) ;",
            "UPDATE sale_items SET sale_sync_id = (SELECT sync_id FROM sales WHERE sales.id = sale_items.sale_id) ;",
            "UPDATE purchases SET supplier_sync_id = (SELECT sync_id FROM parties WHERE parties.id = purchases.supplier_id) ;",
            "UPDATE khata_transactions SET party_sync_id = (SELECT sync_id FROM parties WHERE parties.id = khata_transactions.party_id) ;",
            "UPDATE sale_returns SET sale_sync_id = (SELECT sync_id FROM sales WHERE sales.id = sale_returns.sale_id), party_sync_id = (SELECT sync_id FROM parties WHERE parties.id = sale_returns.customer_id) WHERE sale_id IS NOT NULL;",
            "UPDATE sale_return_items SET return_sync_id = (SELECT sync_id FROM sale_returns WHERE sale_returns.id = sale_return_items.return_id), sale_item_sync_id = (SELECT sync_id FROM sale_items WHERE sale_items.id = sale_return_items.sale_item_id) ;"
        };
        foreach (var sql in relations)
        {
            await using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = sql;
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
        await transaction.CommitAsync(cancellationToken);
    }

    private static async Task<List<Dictionary<string, object?>>> ReadRowsAsync(
        SqliteConnection connection,
        string table,
        IReadOnlyCollection<string> removedColumns,
        CancellationToken cancellationToken)
    {
        var rows = new List<Dictionary<string, object?>>();
        await using var command = connection.CreateCommand();
        command.CommandText = table == "drive_sync_tombstones"
            ? "SELECT * FROM drive_sync_tombstones ORDER BY id ASC;"
            : $"SELECT * FROM \"{table}\" ORDER BY id ASC;";
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var row = new Dictionary<string, object?>(StringComparer.Ordinal);
            for (var i = 0; i < reader.FieldCount; i++)
            {
                var name = reader.GetName(i);
                if (removedColumns.Contains(name)) continue;
                var value = reader.IsDBNull(i) ? null : reader.GetValue(i);
                if (value is byte[] bytes) value = Convert.ToBase64String(bytes);
                row[name] = value;
            }
            rows.Add(row);
        }
        return rows;
    }
}


internal sealed class DartCompatibleDoubleConverter : JsonConverter<double>
{
    public override double Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
        reader.GetDouble();

    public override void Write(Utf8JsonWriter writer, double value, JsonSerializerOptions options)
    {
        var raw = value.ToString("R", CultureInfo.InvariantCulture);
        if (!raw.Contains('.') && !raw.Contains('E') && !raw.Contains('e'))
            raw += ".0";
        writer.WriteRawValue(raw);
    }
}

public sealed record DriveSnapshotPayload(
    IReadOnlyDictionary<string, object?> Data,
    string Sha256,
    string Json);
