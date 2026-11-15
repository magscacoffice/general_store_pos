using System.IO;
using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;

namespace KhanBabaPos.Wpf.Services;

/// <summary>Read-only product lookup against the existing SQLite v18 database.</summary>
public sealed class ProductLookupService
{
    private string? _databasePath;

    public async Task VerifyDatabaseAsync(CancellationToken cancellationToken = default)
    {
        _databasePath = PosDatabasePath.Resolve(requireExisting: true);
        await PosDatabaseSchemaVerifier.VerifyAsync(_databasePath, cancellationToken);
    }

    public async Task<IReadOnlyList<ProductLookup>> SearchAsync(string query, CancellationToken cancellationToken = default)
    {
        var path = _databasePath ?? PosDatabasePath.Resolve(requireExisting: true);
        await PosDatabaseSchemaVerifier.VerifyAsync(path, cancellationToken);
        await using var connection = await OpenReadOnlyAsync(path, cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT id, name, barcode, price, COALESCE(purchasePrice, 0),
                   quantity, COALESCE(stock_unit, 'pcs')
            FROM products
            WHERE COALESCE(is_active, 1) = 1
              AND (barcode = $barcode OR name LIKE $name)
            ORDER BY CASE WHEN barcode = $barcode THEN 0 ELSE 1 END,
                     name COLLATE NOCASE
            LIMIT 25;
            """;
        command.Parameters.AddWithValue("$barcode", query.Trim());
        command.Parameters.AddWithValue("$name", "%" + query.Trim() + "%");
        var results = new List<ProductLookup>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
            results.Add(ReadProduct(reader));
        return results;
    }

    public async Task<ProductLookup?> FindExactBarcodeAsync(string barcode, CancellationToken cancellationToken = default)
    {
        var path = _databasePath ?? PosDatabasePath.Resolve(requireExisting: true);
        await PosDatabaseSchemaVerifier.VerifyAsync(path, cancellationToken);
        await using var connection = await OpenReadOnlyAsync(path, cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT id, name, barcode, price, COALESCE(purchasePrice, 0),
                   quantity, COALESCE(stock_unit, 'pcs')
            FROM products
            WHERE barcode = $barcode AND COALESCE(is_active, 1) = 1
            LIMIT 1;
            """;
        command.Parameters.AddWithValue("$barcode", barcode.Trim());
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken) ? ReadProduct(reader) : null;
    }

    private static ProductLookup ReadProduct(SqliteDataReader reader) => new(
        reader.GetInt32(0),
        reader.GetString(1),
        reader.IsDBNull(2) ? string.Empty : reader.GetString(2),
        reader.GetDouble(3),
        reader.GetDouble(4),
        reader.GetInt32(5),
        reader.IsDBNull(6) ? "pcs" : reader.GetString(6));

    private static async Task<SqliteConnection> OpenReadOnlyAsync(string path, CancellationToken cancellationToken)
    {
        var connection = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = path,
            Mode = SqliteOpenMode.ReadOnly,
            Pooling = false
        }.ToString());
        await connection.OpenAsync(cancellationToken);
        return connection;
    }
}

public sealed record ProductLookup(
    int Id, string Name, string Barcode, double Price,
    double PurchasePrice, int Quantity, string StockUnit)
{
    public string StockLabel => $"Stock: {Quantity} {StockUnit}";
}
