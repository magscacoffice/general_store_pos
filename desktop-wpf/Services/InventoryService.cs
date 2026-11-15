using System.Globalization;
using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;

namespace KhanBabaPos.Wpf.Services;

public sealed class InventoryService
{
    public Task<string?> FindBarcodeOwnerAsync(string barcode, int? exceptId = null, CancellationToken ct = default) =>
        FindBarcodeOwnerAsync(barcode, exceptId, PosDatabasePath.Resolve(requireExisting: true), ct);

    public async Task<string?> FindBarcodeOwnerAsync(string barcode, int? exceptId, string databasePath, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(barcode)) return null;
        await PosDatabaseSchemaVerifier.VerifyAsync(databasePath, ct);
        await using var db = await OpenAsync(databasePath, true, ct);
        await using var cmd = db.CreateCommand();
        cmd.CommandText = "SELECT name FROM products WHERE barcode=$barcode COLLATE NOCASE AND ($exceptId IS NULL OR id<>$exceptId) LIMIT 1;";
        cmd.Parameters.AddWithValue("$barcode", barcode.Trim());
        cmd.Parameters.AddWithValue("$exceptId", exceptId is null ? DBNull.Value : exceptId.Value);
        var value = await cmd.ExecuteScalarAsync(ct);
        return value is null or DBNull ? null : Convert.ToString(value, CultureInfo.InvariantCulture);
    }

    public async Task<IReadOnlyList<InventoryProduct>> GetProductsAsync(string search = "", CancellationToken cancellationToken = default)
    {
        var path = PosDatabasePath.Resolve(requireExisting: true);
        await PosDatabaseSchemaVerifier.VerifyAsync(path, cancellationToken);
        await using var connection = await OpenAsync(path, true, cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT id, name, barcode, COALESCE(price,0), COALESCE(purchasePrice,0),
                   COALESCE(wholesalePrice,0), COALESCE(quantity,0), COALESCE(damaged_quantity,0),
                   COALESCE(stock_unit,'pcs'), COALESCE(is_active,1)
            FROM products
            WHERE ($search = '' OR barcode LIKE $like OR name LIKE $like)
            ORDER BY id DESC;
            """;
        command.Parameters.AddWithValue("$search", search.Trim());
        command.Parameters.AddWithValue("$like", "%" + search.Trim() + "%");
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var result = new List<InventoryProduct>();
        while (await reader.ReadAsync(cancellationToken))
            result.Add(new InventoryProduct(reader.GetInt32(0), reader.GetString(1), reader.GetString(2),
                reader.GetDouble(3), reader.GetDouble(4), reader.GetDouble(5), reader.GetInt32(6), reader.GetInt32(7),
                reader.GetString(8), reader.GetInt32(9) == 1));
        return result;
    }

    public Task CreateAsync(ProductMutation p, CancellationToken ct = default) =>
        CreateAsync(p, PosDatabasePath.Resolve(requireExisting: true), ct);

    public async Task CreateAsync(ProductMutation p, string databasePath, CancellationToken ct = default)
    {
        Validate(p);
        var path = databasePath;
        await PosDatabaseSchemaVerifier.VerifyAsync(path, ct);
        await DatabaseSafetyService.EnsureVerifiedBackupAsync(path, ct);
        await using var db = await OpenAsync(path, false, ct);
        using var tx = db.BeginTransaction();
        try
        {
            await EnsureBarcodeAsync(db, tx, p.Barcode, null, ct);
            await using var cmd = db.CreateCommand();
            cmd.Transaction = tx;
            cmd.CommandText = """
                INSERT INTO products(name,barcode,price,purchasePrice,wholesalePrice,damaged_quantity,quantity,is_active,stock_unit)
                VALUES($name,$barcode,$price,$cost,$wholesale,0,$quantity,1,$unit);
                """;
            AddParams(cmd, p);
            await cmd.ExecuteNonQueryAsync(ct);
            await using var clear = db.CreateCommand();
            clear.Transaction = tx;
            clear.CommandText = """
                DELETE FROM drive_sync_tombstones WHERE entity_type='product' AND entity_key=$barcode;
                DELETE FROM drive_sync_ignored_tombstones WHERE entity_type='product' AND entity_key=$barcode;
                """;
            clear.Parameters.AddWithValue("$barcode", p.Barcode);
            await clear.ExecuteNonQueryAsync(ct);
            tx.Commit();
        }
        catch { tx.Rollback(); throw; }
    }

    public Task UpdateAsync(int id, ProductMutation p, CancellationToken ct = default) =>
        UpdateAsync(id, p, PosDatabasePath.Resolve(requireExisting: true), ct);

    public async Task UpdateAsync(int id, ProductMutation p, string databasePath, CancellationToken ct = default)
    {
        Validate(p);
        var path = PosDatabasePath.Resolve(requireExisting: true);
        await PosDatabaseSchemaVerifier.VerifyAsync(path, ct);
        await DatabaseSafetyService.EnsureVerifiedBackupAsync(path, ct);
        await using var db = await OpenAsync(path, false, ct);
        using var tx = db.BeginTransaction();
        try
        {
            await using var old = db.CreateCommand();
            old.Transaction = tx;
            old.CommandText = "SELECT barcode FROM products WHERE id=$id LIMIT 1;";
            old.Parameters.AddWithValue("$id", id);
            var oldBarcode = Convert.ToString(await old.ExecuteScalarAsync(ct), CultureInfo.InvariantCulture)
                ?? throw new InvalidOperationException("Product not found. Please refresh and try again.");
            await EnsureBarcodeAsync(db, tx, p.Barcode, id, ct);
            await using var cmd = db.CreateCommand();
            cmd.Transaction = tx;
            cmd.CommandText = """
                UPDATE products SET name=$name,barcode=$barcode,price=$price,purchasePrice=$cost,wholesalePrice=$wholesale,
                    quantity=$quantity,stock_unit=$unit WHERE id=$id;
                """;
            AddParams(cmd, p);
            cmd.Parameters.AddWithValue("$id", id);
            if (await cmd.ExecuteNonQueryAsync(ct) != 1)
                throw new InvalidOperationException("Product not found. Please refresh and try again.");
            if (!string.Equals(oldBarcode, p.Barcode, StringComparison.Ordinal))
                await TombstoneAsync(db, tx, oldBarcode, ct);
            tx.Commit();
        }
        catch { tx.Rollback(); throw; }
    }

    public Task SetActiveAsync(int id, bool active, CancellationToken ct = default) =>
        SetActiveAsync(id, active, PosDatabasePath.Resolve(requireExisting: true), ct);

    public async Task SetActiveAsync(int id, bool active, string databasePath, CancellationToken ct = default)
    {
        var path = databasePath;
        await PosDatabaseSchemaVerifier.VerifyAsync(path, ct);
        await DatabaseSafetyService.EnsureVerifiedBackupAsync(path, ct);
        await using var db = await OpenAsync(path, false, ct);
        await using var cmd = db.CreateCommand();
        cmd.CommandText = "UPDATE products SET is_active=$active WHERE id=$id;";
        cmd.Parameters.AddWithValue("$active", active ? 1 : 0);
        cmd.Parameters.AddWithValue("$id", id);
        if (await cmd.ExecuteNonQueryAsync(ct) != 1)
            throw new InvalidOperationException("Product not found.");
    }

    public Task DeleteAsync(int id, CancellationToken ct = default) =>
        DeleteAsync(id, PosDatabasePath.Resolve(requireExisting: true), ct);

    public async Task DeleteAsync(int id, string databasePath, CancellationToken ct = default)
    {
        var path = databasePath;
        await PosDatabaseSchemaVerifier.VerifyAsync(path, ct);
        await DatabaseSafetyService.EnsureVerifiedBackupAsync(path, ct);
        await using var db = await OpenAsync(path, false, ct);
        using var tx = db.BeginTransaction();
        try
        {
            string barcode;
            int stock, damaged;
            await using (var cmd = db.CreateCommand())
            {
                cmd.Transaction = tx;
                cmd.CommandText = "SELECT barcode,COALESCE(quantity,0),COALESCE(damaged_quantity,0) FROM products WHERE id=$id LIMIT 1;";
                cmd.Parameters.AddWithValue("$id", id);
                await using var reader = await cmd.ExecuteReaderAsync(ct);
                if (!await reader.ReadAsync(ct)) { tx.Commit(); return; }
                barcode = reader.GetString(0);
                stock = reader.GetInt32(1);
                damaged = reader.GetInt32(2);
            }
            if (stock > 0 || damaged > 0)
                throw new InvalidOperationException("Pehle saleable aur damaged stock zero karein; stock mojood honay par product delete nahi ho sakta.");
            var sales = await CountAsync(db, tx, "SELECT COUNT(*) FROM sale_items WHERE barcode=$barcode;", id, barcode, false, ct);
            var purchases = await CountAsync(db, tx, "SELECT COUNT(*) FROM purchases WHERE product_id=$id OR barcode=$barcode;", id, barcode, true, ct);
            if (sales > 0 || purchases > 0)
                throw new InvalidOperationException($"Is product ki {sales} sale aur {purchases} purchase history mojood hai. Purana record mehfooz rakhne ke liye delete nahi kar sakte; stock zero ya details edit karein.");
            await TombstoneAsync(db, tx, barcode, ct);
            await using var del = db.CreateCommand();
            del.Transaction = tx;
            del.CommandText = "DELETE FROM products WHERE id=$id;";
            del.Parameters.AddWithValue("$id", id);
            await del.ExecuteNonQueryAsync(ct);
            tx.Commit();
        }
        catch { tx.Rollback(); throw; }
    }

    private static async Task<int> CountAsync(SqliteConnection db, SqliteTransaction tx, string sql,
        int id, string barcode, bool both, CancellationToken ct)
    {
        await using var cmd = db.CreateCommand();
        cmd.Transaction = tx;
        cmd.CommandText = sql;
        if (both) cmd.Parameters.AddWithValue("$id", id);
        cmd.Parameters.AddWithValue("$barcode", barcode);
        return Convert.ToInt32(await cmd.ExecuteScalarAsync(ct), CultureInfo.InvariantCulture);
    }

    private static async Task EnsureBarcodeAsync(SqliteConnection db, SqliteTransaction tx, string barcode, int? exceptId, CancellationToken ct)
    {
        await using var cmd = db.CreateCommand();
        cmd.Transaction = tx;
        cmd.CommandText = exceptId is null
            ? "SELECT COUNT(*) FROM products WHERE barcode=$barcode;"
            : "SELECT COUNT(*) FROM products WHERE barcode=$barcode AND id<>$id;";
        cmd.Parameters.AddWithValue("$barcode", barcode);
        if (exceptId is not null) cmd.Parameters.AddWithValue("$id", exceptId.Value);
        if (Convert.ToInt32(await cmd.ExecuteScalarAsync(ct), CultureInfo.InvariantCulture) > 0)
            throw new InvalidOperationException("Is barcode ka product pehle se inventory mein mojood hai. Existing product ko edit karein.");
    }

    private static async Task TombstoneAsync(SqliteConnection db, SqliteTransaction tx, string barcode, CancellationToken ct)
    {
        await using var cmd = db.CreateCommand();
        cmd.Transaction = tx;
        cmd.CommandText = """
            INSERT INTO drive_sync_tombstones(entity_type,entity_key,deleted_at,source_device_id)
            VALUES('product',$barcode,$date,'windows-master')
            ON CONFLICT(entity_type,entity_key) DO UPDATE SET
                deleted_at=excluded.deleted_at,source_device_id='windows-master';
            """;
        cmd.Parameters.AddWithValue("$barcode", barcode);
        cmd.Parameters.AddWithValue("$date", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture));
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static void AddParams(SqliteCommand cmd, ProductMutation p)
    {
        cmd.Parameters.AddWithValue("$name", p.Name);
        cmd.Parameters.AddWithValue("$barcode", p.Barcode);
        cmd.Parameters.AddWithValue("$price", p.SalePrice);
        cmd.Parameters.AddWithValue("$cost", p.PurchasePrice);
        cmd.Parameters.AddWithValue("$wholesale", p.WholesalePrice);
        cmd.Parameters.AddWithValue("$quantity", p.Quantity);
        cmd.Parameters.AddWithValue("$unit", p.StockUnit);
    }

    private static void Validate(ProductMutation p)
    {
        if (string.IsNullOrWhiteSpace(p.Name) || string.IsNullOrWhiteSpace(p.Barcode) || string.IsNullOrWhiteSpace(p.StockUnit))
            throw new InvalidOperationException("Barcode, Name aur Stock Unit lazmi hain.");
        if (p.Name.Length > 17)
            throw new InvalidOperationException("Product name 80mm bill ke liye maximum 17 characters ka ho sakta hai.");
        if (p.Quantity < 0 || !double.IsFinite(p.PurchasePrice) || !double.IsFinite(p.SalePrice) || !double.IsFinite(p.WholesalePrice) ||
            p.PurchasePrice < 0 || p.SalePrice < 0 || p.WholesalePrice < 0 ||
            (p.WholesalePrice > 0 && p.WholesalePrice < p.PurchasePrice))
            throw new InvalidOperationException("Stock aur prices valid non-negative values honi chahiye.");
    }

    private static async Task<SqliteConnection> OpenAsync(string path, bool readOnly, CancellationToken ct)
    {
        var db = new SqliteConnection(new SqliteConnectionStringBuilder {
            DataSource = path, Mode = readOnly ? SqliteOpenMode.ReadOnly : SqliteOpenMode.ReadWrite, Pooling = false
        }.ToString());
        await db.OpenAsync(ct);
        return db;
    }
}

public sealed record ProductMutation(string Name,string Barcode,int Quantity,string StockUnit,double PurchasePrice,double SalePrice,double WholesalePrice);
public sealed record InventoryProduct(int Id,string Name,string Barcode,double SalePrice,double PurchasePrice,double WholesalePrice,
    int Quantity,int DamagedQuantity,string StockUnit,bool IsActive)
{
    public string Status => IsActive ? "Active" : "Inactive";
}
