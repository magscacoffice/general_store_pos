// Initial WPF data foundation. Maps Flutter SQLite schema v18; no schema writes or migrations.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;

namespace KhanBabaPos.Wpf.Data;

[Table("products")]
public sealed class Product
{
    [Key]
    [Column("id")]
    public int Id { get; set; }
    [Column("name")]
    public string Name { get; set; } = string.Empty;
    [Column("barcode")]
    public string Barcode { get; set; } = string.Empty;
    [Column("price")]
    public double Price { get; set; }
    [Column("purchasePrice")]
    public double? PurchasePrice { get; set; }
    [Column("wholesalePrice")]
    public double? WholesalePrice { get; set; }
    [Column("damaged_quantity")]
    public int? DamagedQuantity { get; set; }
    [Column("quantity")]
    public int Quantity { get; set; }
    [Column("is_active")]
    public int IsActive { get; set; }
    [Column("stock_unit")]
    public string? StockUnit { get; set; }
}

[Table("sales")]
public sealed class Sale
{
    [Key]
    [Column("id")]
    public int Id { get; set; }
    [Column("total_amount")]
    public double TotalAmount { get; set; }
    [Column("discount")]
    public double? Discount { get; set; }
    [Column("final_amount")]
    public double? FinalAmount { get; set; }
    [Column("payment_type")]
    public string? PaymentType { get; set; }
    [Column("customer_id")]
    public int? CustomerId { get; set; }
    [Column("salesman_uid")]
    public string? SalesmanUid { get; set; }
    [Column("salesman_name")]
    public string? SalesmanName { get; set; }
    [Column("customer_type")]
    public string? CustomerType { get; set; }
    [Column("received_amount")]
    public double? ReceivedAmount { get; set; }
    [Column("balance_due")]
    public double? BalanceDue { get; set; }
    [Column("sync_id")]
    public string? SyncId { get; set; }
    [Column("customer_sync_id")]
    public string? CustomerSyncId { get; set; }
    [Column("date")]
    public string Date { get; set; } = string.Empty;
}

[Table("parties")]
public sealed class Party
{
    [Key]
    [Column("id")]
    public int Id { get; set; }
    [Column("name")]
    public string Name { get; set; } = string.Empty;
    [Column("phone")]
    public string Phone { get; set; } = string.Empty;
    [Column("type")]
    public string Type { get; set; } = string.Empty;
    [Column("customer_type")]
    public string? CustomerType { get; set; }
    [Column("sync_id")]
    public string? SyncId { get; set; }
    [Column("balance")]
    public double? Balance { get; set; }
}

[Table("expenses")]
public sealed class Expense
{
    [Key]
    [Column("id")]
    public int Id { get; set; }
    [Column("title")]
    public string Title { get; set; } = string.Empty;
    [Column("amount")]
    public double Amount { get; set; }
    [Column("date")]
    public string Date { get; set; } = string.Empty;
    [Column("sync_id")]
    public string? SyncId { get; set; }
}

[Table("reminders")]
public sealed class Reminder
{
    [Key]
    [Column("id")]
    public int Id { get; set; }
    [Column("title")]
    public string Title { get; set; } = string.Empty;
    [Column("details")]
    public string? Details { get; set; }
    [Column("date")]
    public string Date { get; set; } = string.Empty;
    [Column("is_done")]
    public int? IsDone { get; set; }
    [Column("sync_id")]
    public string? SyncId { get; set; }
}

[Table("purchases")]
public sealed class Purchase
{
    [Key]
    [Column("id")]
    public int Id { get; set; }
    [Column("product_id")]
    public int ProductId { get; set; }
    [Column("product_name")]
    public string ProductName { get; set; } = string.Empty;
    [Column("barcode")]
    public string Barcode { get; set; } = string.Empty;
    [Column("quantity")]
    public int Quantity { get; set; }
    [Column("unit_cost")]
    public double UnitCost { get; set; }
    [Column("total_cost")]
    public double TotalCost { get; set; }
    [Column("supplier_id")]
    public int? SupplierId { get; set; }
    [Column("sync_id")]
    public string? SyncId { get; set; }
    [Column("supplier_sync_id")]
    public string? SupplierSyncId { get; set; }
    [Column("date")]
    public string Date { get; set; } = string.Empty;
    [Column("invoice_group_id")]
    public string? InvoiceGroupId { get; set; }
    [Column("invoice_number")]
    public string? InvoiceNumber { get; set; }
    [Column("invoice_date")]
    public string? InvoiceDate { get; set; }
    [Column("invoice_total")]
    public double? InvoiceTotal { get; set; }
    [Column("invoice_discount")]
    public double? InvoiceDiscount { get; set; }
    [Column("invoice_tax")]
    public double? InvoiceTax { get; set; }
    [Column("invoice_paid_amount")]
    public double? InvoicePaidAmount { get; set; }
    [Column("invoice_balance_due")]
    public double? InvoiceBalanceDue { get; set; }
    [Column("invoice_image_path")]
    public string? InvoiceImagePath { get; set; }
    [Column("unit_label")]
    public string? UnitLabel { get; set; }
    [Column("invoice_quantity")]
    public double? InvoiceQuantity { get; set; }
    [Column("conversion_factor")]
    public double? ConversionFactor { get; set; }
    [Column("base_unit")]
    public string? BaseUnit { get; set; }
    [Column("invoice_unit_cost")]
    public double? InvoiceUnitCost { get; set; }
}

[Table("sale_items")]
public sealed class SaleItem
{
    [Key]
    [Column("id")]
    public int Id { get; set; }
    [Column("sale_id")]
    public int SaleId { get; set; }
    [Column("product_id")]
    public int? ProductId { get; set; }
    [Column("barcode")]
    public string Barcode { get; set; } = string.Empty;
    [Column("product_name")]
    public string ProductName { get; set; } = string.Empty;
    [Column("quantity")]
    public int Quantity { get; set; }
    [Column("sale_price")]
    public double SalePrice { get; set; }
    [Column("purchase_price")]
    public double PurchasePrice { get; set; }
    [Column("line_total")]
    public double LineTotal { get; set; }
    [Column("cost_total")]
    public double CostTotal { get; set; }
    [Column("sync_id")]
    public string? SyncId { get; set; }
    [Column("sale_sync_id")]
    public string? SaleSyncId { get; set; }
    [Column("stock_unit")]
    public string? StockUnit { get; set; }
}

[Table("sync_queue")]
public sealed class SyncQueueItem
{
    [Key]
    [Column("id")]
    public int Id { get; set; }
    [Column("collection_name")]
    public string CollectionName { get; set; } = string.Empty;
    [Column("document_id")]
    public string DocumentId { get; set; } = string.Empty;
    [Column("operation")]
    public string Operation { get; set; } = string.Empty;
    [Column("payload")]
    public string? Payload { get; set; }
    [Column("created_at")]
    public string CreatedAt { get; set; } = string.Empty;
    [Column("attempts")]
    public int Attempts { get; set; }
    [Column("last_error")]
    public string? LastError { get; set; }
}

[Table("khata_transactions")]
public sealed class KhataTransaction
{
    [Key]
    [Column("id")]
    public int Id { get; set; }
    [Column("party_id")]
    public int PartyId { get; set; }
    [Column("type")]
    public string Type { get; set; } = string.Empty;
    [Column("amount")]
    public double Amount { get; set; }
    [Column("note")]
    public string? Note { get; set; }
    [Column("date")]
    public string Date { get; set; } = string.Empty;
    [Column("sync_id")]
    public string? SyncId { get; set; }
    [Column("party_sync_id")]
    public string? PartySyncId { get; set; }
}

[Table("sale_returns")]
public sealed class SaleReturn
{
    [Key]
    [Column("id")]
    public int Id { get; set; }
    [Column("sale_id")]
    public int SaleId { get; set; }
    [Column("customer_id")]
    public int? CustomerId { get; set; }
    [Column("reason")]
    public string Reason { get; set; } = string.Empty;
    [Column("refund_method")]
    public string RefundMethod { get; set; } = string.Empty;
    [Column("refund_amount")]
    public double RefundAmount { get; set; }
    [Column("date")]
    public string Date { get; set; } = string.Empty;
    [Column("sync_id")]
    public string? SyncId { get; set; }
    [Column("sale_sync_id")]
    public string? SaleSyncId { get; set; }
    [Column("party_sync_id")]
    public string? PartySyncId { get; set; }
}

[Table("sale_return_items")]
public sealed class SaleReturnItem
{
    [Key]
    [Column("id")]
    public int Id { get; set; }
    [Column("return_id")]
    public int ReturnId { get; set; }
    [Column("sale_item_id")]
    public int SaleItemId { get; set; }
    [Column("product_id")]
    public int? ProductId { get; set; }
    [Column("barcode")]
    public string Barcode { get; set; } = string.Empty;
    [Column("product_name")]
    public string ProductName { get; set; } = string.Empty;
    [Column("quantity")]
    public int Quantity { get; set; }
    [Column("sale_price")]
    public double SalePrice { get; set; }
    [Column("purchase_price")]
    public double PurchasePrice { get; set; }
    [Column("line_total")]
    public double LineTotal { get; set; }
    [Column("cost_total")]
    public double CostTotal { get; set; }
    [Column("condition")]
    public string Condition { get; set; } = string.Empty;
    [Column("sync_id")]
    public string? SyncId { get; set; }
    [Column("return_sync_id")]
    public string? ReturnSyncId { get; set; }
    [Column("sale_item_sync_id")]
    public string? SaleItemSyncId { get; set; }
    [Column("stock_unit")]
    public string? StockUnit { get; set; }
}

[Table("khata_reminder_log")]
public sealed class KhataReminderLog
{
    [Key]
    [Column("id")]
    public int Id { get; set; }
    [Column("party_id")]
    public int PartyId { get; set; }
    [Column("oldest_due_date")]
    public string OldestDueDate { get; set; } = string.Empty;
    [Column("created_at")]
    public string CreatedAt { get; set; } = string.Empty;
}

[Table("pending_bills")]
public sealed class PendingBill
{
    [Key]
    [Column("bill_id")]
    public string BillId { get; set; } = string.Empty;
    [Column("label")]
    public string Label { get; set; } = string.Empty;
    [Column("payload")]
    public string Payload { get; set; } = string.Empty;
    [Column("updated_at")]
    public string UpdatedAt { get; set; } = string.Empty;
}

[Table("drive_sync_conflicts")]
public sealed class DriveSyncConflict
{
    [Key]
    [Column("id")]
    public int Id { get; set; }
    [Column("source_device_id")]
    public string SourceDeviceId { get; set; } = string.Empty;
    [Column("snapshot_hash")]
    public string SnapshotHash { get; set; } = string.Empty;
    [Column("entity_type")]
    public string EntityType { get; set; } = string.Empty;
    [Column("entity_key")]
    public string EntityKey { get; set; } = string.Empty;
    [Column("local_payload")]
    public string LocalPayload { get; set; } = string.Empty;
    [Column("remote_payload")]
    public string RemotePayload { get; set; } = string.Empty;
    [Column("status")]
    public string Status { get; set; } = string.Empty;
    [Column("resolution")]
    public string? Resolution { get; set; }
    [Column("created_at")]
    public string CreatedAt { get; set; } = string.Empty;
    [Column("resolved_at")]
    public string? ResolvedAt { get; set; }
}

[Table("drive_sync_aliases")]
public sealed class DriveSyncAlias
{
    [Column("source_device_id")]
    public string SourceDeviceId { get; set; } = string.Empty;
    [Column("remote_sync_id")]
    public string RemoteSyncId { get; set; } = string.Empty;
    [Column("local_sync_id")]
    public string LocalSyncId { get; set; } = string.Empty;
}

[Table("drive_sync_tombstones")]
public sealed class DriveSyncTombstone
{
    [Key]
    [Column("id")]
    public int Id { get; set; }
    [Column("entity_type")]
    public string EntityType { get; set; } = string.Empty;
    [Column("entity_key")]
    public string EntityKey { get; set; } = string.Empty;
    [Column("deleted_at")]
    public string DeletedAt { get; set; } = string.Empty;
    [Column("source_device_id")]
    public string SourceDeviceId { get; set; } = string.Empty;
}

[Table("drive_sync_ignored_tombstones")]
public sealed class DriveSyncIgnoredTombstone
{
    [Column("source_device_id")]
    public string SourceDeviceId { get; set; } = string.Empty;
    [Column("entity_type")]
    public string EntityType { get; set; } = string.Empty;
    [Column("entity_key")]
    public string EntityKey { get; set; } = string.Empty;
}

public sealed class PosDbContext(DbContextOptions<PosDbContext> options) : DbContext(options)
{
    public DbSet<Product> Products => Set<Product>();
    public DbSet<Sale> Sales => Set<Sale>();
    public DbSet<Party> Parties => Set<Party>();
    public DbSet<Expense> Expenses => Set<Expense>();
    public DbSet<Reminder> Reminders => Set<Reminder>();
    public DbSet<Purchase> Purchases => Set<Purchase>();
    public DbSet<SaleItem> SaleItems => Set<SaleItem>();
    public DbSet<SyncQueueItem> SyncQueue => Set<SyncQueueItem>();
    public DbSet<KhataTransaction> KhataTransactions => Set<KhataTransaction>();
    public DbSet<SaleReturn> SaleReturns => Set<SaleReturn>();
    public DbSet<SaleReturnItem> SaleReturnItems => Set<SaleReturnItem>();
    public DbSet<KhataReminderLog> KhataReminderLogs => Set<KhataReminderLog>();
    public DbSet<PendingBill> PendingBills => Set<PendingBill>();
    public DbSet<DriveSyncConflict> DriveSyncConflicts => Set<DriveSyncConflict>();
    public DbSet<DriveSyncAlias> DriveSyncAliases => Set<DriveSyncAlias>();
    public DbSet<DriveSyncTombstone> DriveSyncTombstones => Set<DriveSyncTombstone>();
    public DbSet<DriveSyncIgnoredTombstone> DriveSyncIgnoredTombstones => Set<DriveSyncIgnoredTombstone>();
    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<Product>().HasIndex(x => x.Barcode).IsUnique();
        b.Entity<SyncQueueItem>().HasIndex(x => new { x.CollectionName, x.DocumentId }).IsUnique();
        b.Entity<KhataReminderLog>().HasIndex(x => new { x.PartyId, x.OldestDueDate }).IsUnique();
        b.Entity<DriveSyncConflict>().HasIndex(x => new { x.SourceDeviceId, x.SnapshotHash, x.EntityType, x.EntityKey }).IsUnique();
        b.Entity<DriveSyncTombstone>().HasIndex(x => new { x.EntityType, x.EntityKey }).IsUnique();
        b.Entity<DriveSyncAlias>().HasKey(x => new { x.SourceDeviceId, x.RemoteSyncId });
        b.Entity<DriveSyncIgnoredTombstone>().HasKey(x => new { x.SourceDeviceId, x.EntityType, x.EntityKey });
        b.Entity<Product>().Property(x => x.PurchasePrice).HasDefaultValue(0.0); b.Entity<Product>().Property(x => x.WholesalePrice).HasDefaultValue(0.0); b.Entity<Product>().Property(x => x.DamagedQuantity).HasDefaultValue(0); b.Entity<Product>().Property(x => x.IsActive).HasDefaultValue(1);
        b.Entity<Sale>().Property(x => x.Discount).HasDefaultValue(0.0); b.Entity<Sale>().Property(x => x.FinalAmount).HasDefaultValue(0.0); b.Entity<Sale>().Property(x => x.PaymentType).HasDefaultValue("Cash"); b.Entity<Sale>().Property(x => x.CustomerType).HasDefaultValue("Walk-in"); b.Entity<Sale>().Property(x => x.ReceivedAmount).HasDefaultValue(0.0); b.Entity<Sale>().Property(x => x.BalanceDue).HasDefaultValue(0.0);
        b.Entity<Party>().Property(x => x.CustomerType).HasDefaultValue("Khata"); b.Entity<Party>().Property(x => x.Balance).HasDefaultValue(0.0); b.Entity<Reminder>().Property(x => x.IsDone).HasDefaultValue(0); b.Entity<Purchase>().Property(x => x.ConversionFactor).HasDefaultValue(1.0); b.Entity<SyncQueueItem>().Property(x => x.Operation).HasDefaultValue("set"); b.Entity<SyncQueueItem>().Property(x => x.Attempts).HasDefaultValue(0); b.Entity<SaleReturnItem>().Property(x => x.Condition).HasDefaultValue("saleable"); b.Entity<DriveSyncConflict>().Property(x => x.Status).HasDefaultValue("pending"); b.Entity<DriveSyncTombstone>().Property(x => x.SourceDeviceId).HasDefaultValue("local");
    }
}

public static class PosDatabasePath
{
    public static string GetDirectory()
    {
        var profile = Environment.GetEnvironmentVariable("USERPROFILE");
        var roots = new[] { Environment.GetEnvironmentVariable("LOCALAPPDATA"), Environment.GetEnvironmentVariable("APPDATA"), string.IsNullOrWhiteSpace(profile) ? null : Path.Combine(profile, "AppData", "Local") };
        var errors = new List<string>();
        foreach (var root in roots.Where(x => !string.IsNullOrWhiteSpace(x)).Distinct(StringComparer.OrdinalIgnoreCase))
        {
            var dir = Path.Combine(root!, "KhanBabaPOS", "Data");
            try { Directory.CreateDirectory(dir); var probe = Path.Combine(dir, ".write_test_" + Environment.ProcessId); File.WriteAllText(probe, "ok"); File.Delete(probe); return dir; }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { errors.Add(dir + ": " + ex.Message); }
        }
        throw new IOException("No writable Khan Baba POS user-data directory was found. " + string.Join(" | ", errors));
    }
    public static string Resolve(bool requireExisting = true)
    {
        var dir = GetDirectory(); var marker = Path.Combine(dir, ".active_database"); var name = "khan_baba_pos.db";
        if (File.Exists(marker)) { name = File.ReadAllText(marker).Trim(); if (string.IsNullOrWhiteSpace(name) || Path.GetFileName(name) != name || !name.StartsWith("khan_baba_pos_", StringComparison.Ordinal) || !name.EndsWith(".db", StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Invalid active database pointer; existing data was not changed."); }
        var path = Path.Combine(dir, name); if (requireExisting && !File.Exists(path)) throw new FileNotFoundException("Existing POS database not found; refusing to create an empty replacement.", path); return path;
    }
}

public sealed class PosDatabaseSchemaException(string message) : Exception(message);

public static class PosDatabaseSchemaVerifier
{
    public const int Version = 18;

    private static readonly IReadOnlyDictionary<string, string[]> Tables = new Dictionary<string, string[]>
    {
        ["products"] = ["id", "name", "barcode", "price", "purchasePrice", "wholesalePrice", "damaged_quantity", "quantity", "is_active", "stock_unit"],
        ["sales"] = ["id", "total_amount", "discount", "final_amount", "payment_type", "customer_id", "salesman_uid", "salesman_name", "customer_type", "received_amount", "balance_due", "sync_id", "customer_sync_id", "date"],
        ["parties"] = ["id", "name", "phone", "type", "customer_type", "sync_id", "balance"],
        ["expenses"] = ["id", "title", "amount", "date", "sync_id"],
        ["reminders"] = ["id", "title", "details", "date", "is_done", "sync_id"],
        ["purchases"] = ["id", "product_id", "product_name", "barcode", "quantity", "unit_cost", "total_cost", "supplier_id", "sync_id", "supplier_sync_id", "date", "invoice_group_id", "invoice_number", "invoice_date", "invoice_total", "invoice_discount", "invoice_tax", "invoice_paid_amount", "invoice_balance_due", "invoice_image_path", "unit_label", "invoice_quantity", "conversion_factor", "base_unit", "invoice_unit_cost"],
        ["sale_items"] = ["id", "sale_id", "product_id", "barcode", "product_name", "quantity", "sale_price", "purchase_price", "line_total", "cost_total", "sync_id", "sale_sync_id", "stock_unit"],
        ["sync_queue"] = ["id", "collection_name", "document_id", "operation", "payload", "created_at", "attempts", "last_error"],
        ["khata_transactions"] = ["id", "party_id", "type", "amount", "note", "date", "sync_id", "party_sync_id"],
        ["sale_returns"] = ["id", "sale_id", "customer_id", "reason", "refund_method", "refund_amount", "date", "sync_id", "sale_sync_id", "party_sync_id"],
        ["sale_return_items"] = ["id", "return_id", "sale_item_id", "product_id", "barcode", "product_name", "quantity", "sale_price", "purchase_price", "line_total", "cost_total", "condition", "sync_id", "return_sync_id", "sale_item_sync_id", "stock_unit"],
        ["khata_reminder_log"] = ["id", "party_id", "oldest_due_date", "created_at"],
        ["pending_bills"] = ["bill_id", "label", "payload", "updated_at"],
        ["drive_sync_conflicts"] = ["id", "source_device_id", "snapshot_hash", "entity_type", "entity_key", "local_payload", "remote_payload", "status", "resolution", "created_at", "resolved_at"],
        ["drive_sync_aliases"] = ["source_device_id", "remote_sync_id", "local_sync_id"],
        ["drive_sync_tombstones"] = ["id", "entity_type", "entity_key", "deleted_at", "source_device_id"],
        ["drive_sync_ignored_tombstones"] = ["source_device_id", "entity_type", "entity_key"],
    };

    private static readonly IReadOnlyDictionary<string, string[]> PrimaryKeys = new Dictionary<string, string[]>
    {
        ["products"] = ["id"], ["sales"] = ["id"], ["parties"] = ["id"],
        ["expenses"] = ["id"], ["reminders"] = ["id"], ["purchases"] = ["id"],
        ["sale_items"] = ["id"], ["sync_queue"] = ["id"], ["khata_transactions"] = ["id"],
        ["sale_returns"] = ["id"], ["sale_return_items"] = ["id"], ["khata_reminder_log"] = ["id"],
        ["pending_bills"] = ["bill_id"], ["drive_sync_conflicts"] = ["id"],
        ["drive_sync_aliases"] = ["source_device_id", "remote_sync_id"],
        ["drive_sync_tombstones"] = ["id"],
        ["drive_sync_ignored_tombstones"] = ["source_device_id", "entity_type", "entity_key"],
    };

    private static readonly (string Table, string[] Columns)[] UniqueConstraints =
    [
        ("products", ["barcode"]),
        ("sync_queue", ["collection_name", "document_id"]),
        ("khata_reminder_log", ["party_id", "oldest_due_date"]),
        ("drive_sync_conflicts", ["source_device_id", "snapshot_hash", "entity_type", "entity_key"]),
        ("drive_sync_tombstones", ["entity_type", "entity_key"]),
    ];

    private static readonly IReadOnlyDictionary<string, string> ExpectedDefaults = new Dictionary<string, string>
    {
        ["products.purchasePrice"] = "0.0",
        ["products.wholesalePrice"] = "0.0",
        ["products.damaged_quantity"] = "0",
        ["products.is_active"] = "1",
        ["sales.discount"] = "0.0",
        ["sales.final_amount"] = "0.0",
        ["sales.payment_type"] = "Cash",
        ["sales.customer_type"] = "Walk-in",
        ["sales.received_amount"] = "0.0",
        ["sales.balance_due"] = "0.0",
        ["parties.customer_type"] = "Khata",
        ["parties.balance"] = "0.0",
        ["reminders.is_done"] = "0",
        ["purchases.conversion_factor"] = "1",
        ["sync_queue.operation"] = "set",
        ["sync_queue.attempts"] = "0",
        ["sale_return_items.condition"] = "saleable",
        ["drive_sync_conflicts.status"] = "pending",
        ["drive_sync_tombstones.source_device_id"] = "local",
    };

    private static string NormalizeDefault(string? value) =>
        (value ?? string.Empty).Trim().Trim('(', ')', '\'', '"', ' ');

    private static async Task<object?> ScalarAsync(SqliteConnection connection, string sql, CancellationToken token)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = sql;
        return await command.ExecuteScalarAsync(token);
    }

    public static async Task VerifyAsync(string path, CancellationToken cancellationToken = default)
    {
        if (!File.Exists(path))
            throw new FileNotFoundException("Existing POS database not found; no empty database will be created.", path);

        await using var connection = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = path,
            Mode = SqliteOpenMode.ReadOnly,
            Pooling = false
        }.ToString());
        await connection.OpenAsync(cancellationToken);

        var version = Convert.ToInt32(await ScalarAsync(connection, "PRAGMA user_version;", cancellationToken));
        if (version != Version)
            throw new PosDatabaseSchemaException($"Database schema version {version} is unsupported; expected {Version}. No migration was attempted.");

        var integrity = Convert.ToString(await ScalarAsync(connection, "PRAGMA quick_check;", cancellationToken));
        if (!string.Equals(integrity, "ok", StringComparison.OrdinalIgnoreCase))
            throw new PosDatabaseSchemaException("SQLite quick_check failed: " + integrity);

        var problems = new List<string>();
        foreach (var table in Tables)
        {
            await using (var exists = connection.CreateCommand())
            {
                exists.CommandText = "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = $name;";
                exists.Parameters.AddWithValue("$name", table.Key);
                if (Convert.ToInt32(await exists.ExecuteScalarAsync(cancellationToken)) != 1)
                {
                    problems.Add("missing table " + table.Key);
                    continue;
                }
            }

            var columns = new Dictionary<string, (string Type, int NotNull, int PrimaryKey, string? Default)>(StringComparer.OrdinalIgnoreCase);
            await using (var command = connection.CreateCommand())
            {
                command.CommandText = $"PRAGMA table_info(\"{table.Key}\");";
                await using var reader = await command.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    columns[reader.GetString(1)] = (
                        reader.GetString(2),
                        reader.GetInt32(3),
                        reader.GetInt32(5),
                        reader.IsDBNull(4) ? null : reader.GetString(4));
                }
            }

            foreach (var column in table.Value)
                if (!columns.ContainsKey(column))
                    problems.Add($"missing column {table.Key}.{column}");

            if (!PrimaryKeys.TryGetValue(table.Key, out var expectedKey))
                continue;
            var actualKey = columns
                .Where(x => x.Value.PrimaryKey > 0)
                .OrderBy(x => x.Value.PrimaryKey)
                .Select(x => x.Key)
                .ToArray();
            if (!actualKey.SequenceEqual(expectedKey, StringComparer.OrdinalIgnoreCase))
                problems.Add($"primary key mismatch on {table.Key}: expected ({string.Join(", ", expectedKey)}), found ({string.Join(", ", actualKey)})");
        }

        foreach (var expected in ExpectedDefaults)
        {
            var split = expected.Key.Split('.', 2);
            if (split.Length != 2 || !Tables.ContainsKey(split[0])) continue;
            await using var command = connection.CreateCommand();
            command.CommandText = $"PRAGMA table_info(\"{split[0]}\");";
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            var actual = (string?)null;
            while (await reader.ReadAsync(cancellationToken))
                if (string.Equals(reader.GetString(1), split[1], StringComparison.OrdinalIgnoreCase))
                {
                    actual = reader.IsDBNull(4) ? null : reader.GetString(4);
                    break;
                }
            if (!string.Equals(NormalizeDefault(actual), NormalizeDefault(expected.Value), StringComparison.OrdinalIgnoreCase))
                problems.Add($"default mismatch on {expected.Key}: expected {expected.Value}, found {actual ?? "<none>"}");
        }

        foreach (var expected in UniqueConstraints)
        {
            var found = false;
            await using var list = connection.CreateCommand();
            list.CommandText = $"PRAGMA index_list(\"{expected.Table}\");";
            await using var indexes = await list.ExecuteReaderAsync(cancellationToken);
            var indexNames = new List<string>();
            while (await indexes.ReadAsync(cancellationToken))
                if (indexes.GetInt32(2) == 1) indexNames.Add(indexes.GetString(1));
            await indexes.DisposeAsync();

            foreach (var indexName in indexNames)
            {
                var actualColumns = new List<string>();
                await using var info = connection.CreateCommand();
                info.CommandText = $"PRAGMA index_info(\"{indexName}\");";
                await using var reader = await info.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                    if (!reader.IsDBNull(2)) actualColumns.Add(reader.GetString(2));
                if (actualColumns.SequenceEqual(expected.Columns, StringComparer.OrdinalIgnoreCase))
                {
                    found = true;
                    break;
                }
            }
            if (!found)
                problems.Add($"missing unique constraint on {expected.Table}({string.Join(", ", expected.Columns)})");
        }

        await using (var foreignKeys = connection.CreateCommand())
        {
            foreignKeys.CommandText = "PRAGMA foreign_key_check;";
            await using var reader = await foreignKeys.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
                problems.Add("foreign_key_check reported one or more violations");
        }

        if (problems.Count > 0)
            throw new PosDatabaseSchemaException("SQLite v18 schema mismatch: " + string.Join("; ", problems));
    }
}

public static class PosDbContextFactory
{
    public static async Task<PosDbContext> CreateVerifiedAsync(CancellationToken cancellationToken = default)
    {
        var path = PosDatabasePath.Resolve(); await PosDatabaseSchemaVerifier.VerifyAsync(path, cancellationToken);
        var options = new DbContextOptionsBuilder<PosDbContext>().UseSqlite(new SqliteConnectionStringBuilder { DataSource = path, Mode = SqliteOpenMode.ReadWrite, Pooling = false }.ToString()).Options;
        return new PosDbContext(options);
    }
}
