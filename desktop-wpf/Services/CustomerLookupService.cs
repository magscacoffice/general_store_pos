using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;

namespace KhanBabaPos.Wpf.Services;

/// <summary>Read-only customer lookup; no account or balance is changed by listing.</summary>
public sealed class CustomerLookupService
{
    public async Task<IReadOnlyList<CustomerLookup>> GetCustomersAsync(CancellationToken cancellationToken = default)
    {
        var path = PosDatabasePath.Resolve(requireExisting: true);
        await PosDatabaseSchemaVerifier.VerifyAsync(path, cancellationToken);
        await using var connection = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = path,
            Mode = SqliteOpenMode.ReadOnly,
            Pooling = false
        }.ToString());
        await connection.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT id, name, COALESCE(phone, ''), COALESCE(balance, 0), COALESCE(customer_type, 'Khata')
            FROM parties
            WHERE type = 'customer'
            ORDER BY name COLLATE NOCASE;
            """;
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var customers = new List<CustomerLookup>();
        while (await reader.ReadAsync(cancellationToken))
            customers.Add(new CustomerLookup(reader.GetInt32(0), reader.GetString(1),
                reader.GetString(2), reader.GetDouble(3), reader.IsDBNull(4) ? "Khata" : reader.GetString(4)));
        return customers;
    }
}

public sealed record CustomerLookup(int Id, string Name, string Phone, double Balance, string CustomerType);
