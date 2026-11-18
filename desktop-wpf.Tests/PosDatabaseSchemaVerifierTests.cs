using System.Text;
using System.Text.Json;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using Microsoft.Data.Sqlite;
using Xunit;
using KhanBabaPos.Wpf.Data;
using KhanBabaPos.Wpf.Services;

[assembly: CollectionBehavior(DisableTestParallelization = true)]

namespace KhanBabaPos.Wpf.Tests;

public sealed class PosDatabaseSchemaVerifierTests
{
    private static readonly AccessService TestAccess = CreateTestAccess();

    public PosDatabaseSchemaVerifierTests() => AccessService.RegisterProcess(TestAccess);

    private static AccessService CreateTestAccess()
    {
        var path = Path.Combine(Path.GetTempPath(), "khan-baba-sale-tests-" + Guid.NewGuid().ToString("N") + ".dat");
        var access = new AccessService(path);
        access.ProvisionFirstAdmin("testadmin", "Local Windows User", "TestPassword!2026");
        AccessService.RegisterProcess(access);
        return access;
    }

    private static string FindRepositoryRoot()
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory);
             directory is not null;
             directory = directory.Parent)
        {
            if (File.Exists(Path.Combine(directory.FullName, "lib", "db_helper.dart")))
                return directory.FullName;
        }

        throw new DirectoryNotFoundException("Could not locate the repository's lib/db_helper.dart schema source.");
    }

    private static async Task<string> CreateFixtureAsync(string? replacement = null)
    {
        var root = FindRepositoryRoot();
        var dart = await File.ReadAllTextAsync(Path.Combine(root, "lib", "db_helper.dart"));
        var createStart = dart.IndexOf("version: 18,", StringComparison.Ordinal);
        var upgradeStart = dart.IndexOf("onUpgrade: (db, oldVersion, newVersion)", createStart, StringComparison.Ordinal);
        Assert.True(createStart >= 0 && upgradeStart > createStart, "Could not locate schema-v18 onCreate DDL.");

        var createSection = dart[createStart..upgradeStart];
        var statements = Regex.Matches(createSection, @"'''(?<sql>[\s\S]*?)'''")
            .Select(match => match.Groups["sql"].Value.Trim())
            .Where(sql => sql.StartsWith("CREATE TABLE", StringComparison.OrdinalIgnoreCase))
            .ToArray();

        Assert.Equal(17, statements.Length);
        if (replacement is not null)
        {
            statements[0] = statements[0].Replace(
                "barcode TEXT UNIQUE NOT NULL",
                replacement,
                StringComparison.Ordinal);
        }

        var path = Path.Combine(Path.GetTempPath(), "khan-baba-schema-" + Guid.NewGuid().ToString("N") + ".db");
        await using var connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString());
        await connection.OpenAsync();
        foreach (var statement in statements)
        {
            await using var command = connection.CreateCommand();
            command.CommandText = statement;
            await command.ExecuteNonQueryAsync();
        }

        await using (var version = connection.CreateCommand())
        {
            version.CommandText = "PRAGMA user_version = 18;";
            await version.ExecuteNonQueryAsync();
        }

        return path;
    }

    private static async Task<string> Sha256Async(string path)
    {
        await using var stream = File.OpenRead(path);
        return Convert.ToHexString(await SHA256.HashDataAsync(stream));
    }

    private static async Task AddProductAsync(string path, string name, string barcode)
    {
        await using var connection = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = path,
            Pooling = false
        }.ToString());
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO products
                (name,barcode,price,purchasePrice,wholesalePrice,damaged_quantity,quantity,is_active,stock_unit)
            VALUES ($name,$barcode,12,5,10,0,3,1,'pcs');
            """;
        command.Parameters.AddWithValue("$name", name);
        command.Parameters.AddWithValue("$barcode", barcode);
        await command.ExecuteNonQueryAsync();
    }

    [Fact]
    public async Task BackupAndRestoreKeepsCurrentDatabaseAndActivatesVerifiedStagedCopy()
    {
        var currentFixture = await CreateFixtureAsync();
        var restoreFixture = await CreateFixtureAsync();
        var dataDirectory = Path.Combine(Path.GetTempPath(), "khan-baba-backup-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dataDirectory);
        var currentPath = Path.Combine(dataDirectory, "khan_baba_pos.db");
        var selectedBackup = Path.Combine(dataDirectory, "selected_backup.db");
        try
        {
            File.Copy(currentFixture, currentPath);
            File.Copy(restoreFixture, selectedBackup);
            await AddProductAsync(currentPath, "Current Database", "CURRENT-1");
            await AddProductAsync(selectedBackup, "Restore Source", "RESTORE-1");
            var currentHash = await Sha256Async(currentPath);

            var service = new DatabaseBackupService();
            var firstBackup = await service.CreateBackupAsync(currentPath, Path.Combine(dataDirectory, "Backups"));
            Assert.True(File.Exists(firstBackup));
            Assert.True(File.Exists(firstBackup + ".sha256"));
            Assert.True(await service.IsVerifiedBackupAsync(firstBackup));
            await File.WriteAllTextAsync(firstBackup + ".sha256", "invalid-checksum");
            Assert.False(await service.IsVerifiedBackupAsync(firstBackup));

            var restoredPath = await service.RestoreAsync(currentPath, selectedBackup, dataDirectory);
            Assert.True(File.Exists(currentPath));
            Assert.Equal(currentHash, await Sha256Async(currentPath));
            Assert.Equal(Path.GetFileName(restoredPath), (await File.ReadAllTextAsync(Path.Combine(dataDirectory, ".active_database"))).Trim());
            await PosDatabaseSchemaVerifier.VerifyAsync(restoredPath);

            await using var restored = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = restoredPath, Pooling = false }.ToString());
            await restored.OpenAsync();
            await using var query = restored.CreateCommand();
            query.CommandText = "SELECT name FROM products ORDER BY id;";
            await using var reader = await query.ExecuteReaderAsync();
            Assert.True(await reader.ReadAsync());
            Assert.Equal("Restore Source", reader.GetString(0));
            Assert.False(await reader.ReadAsync());

            Assert.True(DatabaseBackupService.ListBackups(dataDirectory).Count >= 2);
        }
        finally
        {
            File.Delete(currentFixture);
            File.Delete(restoreFixture);
            if (Directory.Exists(dataDirectory)) Directory.Delete(dataDirectory, recursive: true);
        }
    }

    private static async Task<string> CreateDisposableDatabaseAsync()
    {
        var fixture = await CreateFixtureAsync();
        var directory = Path.Combine(Path.GetTempPath(), "khan-baba-sale-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, "khan_baba_pos.db");
        File.Copy(fixture, path);
        File.Delete(fixture);
        return path;
    }

    private static async Task<int> SeedSaleAccountAsync(string path, string customerType, int stock)
    {
        await using var connection = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = path,
            Pooling = false
        }.ToString());
        await connection.OpenAsync();
        await using var transaction = await connection.BeginTransactionAsync();
        await using (var product = connection.CreateCommand())
        {
            product.Transaction = (SqliteTransaction)transaction;
            product.CommandText = """
                INSERT OR IGNORE INTO products
                    (name,barcode,price,purchasePrice,wholesalePrice,damaged_quantity,quantity,is_active,stock_unit)
                VALUES ('Wholesale Test Item','WPF-WH-1',22,10,18,0,$stock,1,'pcs');
                """;
            product.Parameters.AddWithValue("$stock", stock);
            await product.ExecuteNonQueryAsync();
        }
        await using var party = connection.CreateCommand();
        party.Transaction = (SqliteTransaction)transaction;
        party.CommandText = """
            INSERT INTO parties (name,phone,type,customer_type,sync_id,balance)
            VALUES ('WPF Wholesale Account','03000000000','customer',$type,'wpf-wholesale-sync',0);
            SELECT last_insert_rowid();
            """;
        party.Parameters.AddWithValue("$type", customerType);
        var id = Convert.ToInt32(await party.ExecuteScalarAsync());
        await transaction.CommitAsync();
        return id;
    }


    private static async Task<int> SeedSupplierAsync(string path, string name = "WPF Test Supplier")
    {
        await using var connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString());
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO parties(name,phone,type,customer_type,sync_id,balance)
            VALUES($name,'03001112222','supplier',NULL,'wpf-supplier-sync',0);
            SELECT last_insert_rowid();
            """;
        command.Parameters.AddWithValue("$name", name);
        return Convert.ToInt32(await command.ExecuteScalarAsync());
    }

    [Fact]
    public async Task RestoreRejectsBackupWithBadShaSidecarWithoutChangingActivePointer()
    {
        var currentFixture = await CreateFixtureAsync();
        var restoreFixture = await CreateFixtureAsync();
        var dataDirectory = Path.Combine(Path.GetTempPath(), "khan-baba-bad-backup-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dataDirectory);
        var currentPath = Path.Combine(dataDirectory, "khan_baba_pos.db");
        var selectedBackup = Path.Combine(dataDirectory, "selected_backup.db");
        var pointer = Path.Combine(dataDirectory, ".active_database");
        try
        {
            File.Copy(currentFixture, currentPath);
            File.Copy(restoreFixture, selectedBackup);
            await File.WriteAllTextAsync(selectedBackup + ".sha256", new string('0', 64));
            var currentHash = await Sha256Async(currentPath);
            var service = new DatabaseBackupService();

            await Assert.ThrowsAsync<InvalidDataException>(() =>
                service.RestoreAsync(currentPath, selectedBackup, dataDirectory));

            Assert.False(File.Exists(pointer));
            Assert.Equal(currentHash, await Sha256Async(currentPath));
        }
        finally
        {
            File.Delete(currentFixture);
            File.Delete(restoreFixture);
            if (Directory.Exists(dataDirectory)) Directory.Delete(dataDirectory, recursive: true);
        }
    }

    [Fact]
    public async Task WpfWholesalePartialAndCashSalesPostReceiptsToSameKhataAccount()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            var customerId = await SeedSaleAccountAsync(path, "Wholesale", 10);
            var service = new SalePostingService(TestAccess);
            var partial = await service.CompleteSaleAsync(
                new SaleCheckoutRequest(
                    [new SaleLineInput("WPF-WH-1", 2, 18)],
                    customerId,
                    "Partial",
                    10,
                    10,
                    true,
                    "Wholesale",
                    "Local Windows User"),
                path);
            Assert.Equal(36, partial.Subtotal, 2);
            Assert.Equal(3.6, partial.Discount, 2);
            Assert.Equal(32.4, partial.FinalAmount, 2);
            Assert.Equal(10, partial.ReceivedAmount, 2);
            Assert.Equal(22.4, partial.BalanceDue, 2);

            var cash = await service.CompleteSaleAsync(
                new SaleCheckoutRequest(
                    [new SaleLineInput("WPF-WH-1", 1, 18)],
                    customerId,
                    "Cash",
                    null,
                    0,
                    false,
                    "Wholesale",
                    "Local Windows User"),
                path);
            Assert.Equal(18, cash.ReceivedAmount, 2);
            Assert.Equal(0, cash.BalanceDue, 2);

            await using var connection = new SqliteConnection(new SqliteConnectionStringBuilder
            {
                DataSource = path,
                Pooling = false
            }.ToString());
            await connection.OpenAsync();
            await using (var sales = connection.CreateCommand())
            {
                sales.CommandText = "SELECT COUNT(*), SUM(CASE WHEN customer_type='Wholesale' THEN 1 ELSE 0 END), SUM(received_amount), SUM(balance_due) FROM sales;";
                await using var reader = await sales.ExecuteReaderAsync();
                Assert.True(await reader.ReadAsync());
                Assert.Equal(2, reader.GetInt32(0));
                Assert.Equal(2, reader.GetInt32(1));
                Assert.Equal(28, reader.GetDouble(2), 2);
                Assert.Equal(22.4, reader.GetDouble(3), 2);
            }
            await using (var party = connection.CreateCommand())
            {
                party.CommandText = "SELECT balance FROM parties WHERE id=$id;";
                party.Parameters.AddWithValue("$id", customerId);
                Assert.Equal(22.4, Convert.ToDouble(await party.ExecuteScalarAsync()), 2);
            }
            await using (var ledger = connection.CreateCommand())
            {
                ledger.CommandText = "SELECT COUNT(*), SUM(CASE WHEN type='receipt' THEN amount ELSE 0 END) FROM khata_transactions WHERE party_id=$id;";
                ledger.Parameters.AddWithValue("$id", customerId);
                await using var reader = await ledger.ExecuteReaderAsync();
                Assert.True(await reader.ReadAsync());
                Assert.Equal(4, reader.GetInt32(0));
                Assert.Equal(28, reader.GetDouble(1), 2);
            }
            await using (var stock = connection.CreateCommand())
            {
                stock.CommandText = "SELECT quantity FROM products WHERE barcode='WPF-WH-1';";
                Assert.Equal(7, Convert.ToInt32(await stock.ExecuteScalarAsync()));
            }
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public async Task WpfFixedDiscountPostsMatchingNetTotalReceivedAndKhataValues()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            var customerId = await SeedSaleAccountAsync(path, "Khata", 5);
            var service = new SalePostingService(TestAccess);
            var result = await service.CompleteSaleAsync(
                new SaleCheckoutRequest(
                    [new SaleLineInput("WPF-WH-1", 2, 22)],
                    customerId, "Cash", null, 4, false, "Khata", "Local Windows User"),
                path);

            Assert.Equal(44, result.Subtotal, 2);
            Assert.Equal(4, result.Discount, 2);
            Assert.Equal(40, result.FinalAmount, 2);
            Assert.Equal(40, result.ReceivedAmount, 2);
            Assert.Equal(0, result.BalanceDue, 2);

            await using var db = new SqliteConnection(new SqliteConnectionStringBuilder
            { DataSource = path, Pooling = false }.ToString());
            await db.OpenAsync();
            await using var sale = db.CreateCommand();
            sale.CommandText = "SELECT total_amount,discount,final_amount,received_amount,balance_due FROM sales LIMIT 1;";
            await using var reader = await sale.ExecuteReaderAsync();
            Assert.True(await reader.ReadAsync());
            Assert.Equal(44, reader.GetDouble(0), 2);
            Assert.Equal(4, reader.GetDouble(1), 2);
            Assert.Equal(40, reader.GetDouble(2), 2);
            Assert.Equal(40, reader.GetDouble(3), 2);
            Assert.Equal(0, reader.GetDouble(4), 2);
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public async Task WpfPartialPaymentRejectsZeroExactAndOverTotalWithoutPosting()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            var customerId = await SeedSaleAccountAsync(path, "Khata", 5);
            var service = new SalePostingService(TestAccess);
            foreach (var received in new double?[] { 0, 22, 25 })
            {
                await Assert.ThrowsAsync<InvalidOperationException>(() =>
                    service.CompleteSaleAsync(
                        new SaleCheckoutRequest(
                            [new SaleLineInput("WPF-WH-1", 1, 22)],
                            customerId, "Partial", received, 0, false, "Khata", "Local Windows User"),
                        path));
            }

            await using var db = new SqliteConnection(new SqliteConnectionStringBuilder
            { DataSource = path, Pooling = false }.ToString());
            await db.OpenAsync();
            await using var check = db.CreateCommand();
            check.CommandText = """
                SELECT
                    (SELECT quantity FROM products WHERE barcode='WPF-WH-1'),
                    (SELECT COUNT(*) FROM sales),
                    (SELECT COUNT(*) FROM khata_transactions),
                    (SELECT balance FROM parties WHERE id=$customer);
                """;
            check.Parameters.AddWithValue("$customer", customerId);
            await using var reader = await check.ExecuteReaderAsync();
            Assert.True(await reader.ReadAsync());
            Assert.Equal(5, reader.GetInt32(0));
            Assert.Equal(0, reader.GetInt32(1));
            Assert.Equal(0, reader.GetInt32(2));
            Assert.Equal(0, reader.GetDouble(3), 2);
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public async Task WpfWholesaleSaleRejectsKhataAccountBeforeChangingStock()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            var customerId = await SeedSaleAccountAsync(path, "Khata", 5);
            var service = new SalePostingService(TestAccess);
            await Assert.ThrowsAsync<InvalidOperationException>(() =>
                service.CompleteSaleAsync(
                    new SaleCheckoutRequest(
                        [new SaleLineInput("WPF-WH-1", 1, 18)],
                        customerId,
                        "Cash",
                        null,
                        0,
                        false,
                        "Wholesale"),
                    path));
            await using var connection = new SqliteConnection(new SqliteConnectionStringBuilder
            {
                DataSource = path,
                Pooling = false
            }.ToString());
            await connection.OpenAsync();
            await using var stock = connection.CreateCommand();
            stock.CommandText = "SELECT quantity FROM products WHERE barcode='WPF-WH-1';";
            Assert.Equal(5, Convert.ToInt32(await stock.ExecuteScalarAsync()));
            await using var sales = connection.CreateCommand();
            sales.CommandText = "SELECT COUNT(*) FROM sales;";
            Assert.Equal(0, Convert.ToInt32(await sales.ExecuteScalarAsync()));
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public async Task WpfPurchaseUpdatesStockCostAndKeepsWholesaleRateAboveNewCost()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            await SeedSaleAccountAsync(path, "Wholesale", 10);
            await using var connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString());
            await connection.OpenAsync();
            await using var find = connection.CreateCommand();
            find.CommandText = "SELECT id FROM products WHERE barcode='WPF-WH-1';";
            var productId = Convert.ToInt32(await find.ExecuteScalarAsync());

            var purchaseId = await new PurchaseService().RecordAsync(productId, 4, 20, 24, path);
            Assert.True(purchaseId > 0);

            await using var query = connection.CreateCommand();
            query.CommandText = "SELECT quantity,purchasePrice,price,wholesalePrice FROM products WHERE id=$id;";
            query.Parameters.AddWithValue("$id", productId);
            await using var reader = await query.ExecuteReaderAsync();
            Assert.True(await reader.ReadAsync());
            Assert.Equal(14, reader.GetInt32(0));
            Assert.Equal(20, reader.GetDouble(1), 2);
            Assert.Equal(24, reader.GetDouble(2), 2);
            Assert.Equal(20, reader.GetDouble(3), 2);
            await reader.DisposeAsync();

            await using var purchase = connection.CreateCommand();
            purchase.CommandText = "SELECT quantity,unit_cost,total_cost FROM purchases WHERE id=$id;";
            purchase.Parameters.AddWithValue("$id", purchaseId);
            await using var purchaseReader = await purchase.ExecuteReaderAsync();
            Assert.True(await purchaseReader.ReadAsync());
            Assert.Equal(4, purchaseReader.GetInt32(0));
            Assert.Equal(20, purchaseReader.GetDouble(1), 2);
            Assert.Equal(80, purchaseReader.GetDouble(2), 2);
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }


    [Fact]
    public async Task WpfSupplierInvoicePostsStockDiscountTaxPaidAndPayableAtomically()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            await SeedSaleAccountAsync(path, "Wholesale", 3);
            var supplierId = await SeedSupplierAsync(path);
            int productId;
            await using (var db = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString()))
            {
                await db.OpenAsync();
                await using var find = db.CreateCommand();
                find.CommandText = "SELECT id FROM products WHERE barcode='WPF-WH-1';";
                productId = Convert.ToInt32(await find.ExecuteScalarAsync());
            }

            var group = await new PurchaseService().RecordInvoiceAsync(
                new PurchaseInvoiceRequest(supplierId, " inv-2026-001 ", new DateTime(2026, 11, 16),
                    200, 10, 30, 50,
                    [new PurchaseInvoiceLineInput(productId, null, null, 18, 1.5, 12, 120, "carton", "pcs", 20, 180)]),
                path);
            Assert.False(string.IsNullOrWhiteSpace(group));

            await using var connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString());
            await connection.OpenAsync();
            await using (var stock = connection.CreateCommand())
            {
                stock.CommandText = "SELECT quantity,purchasePrice,price,stock_unit FROM products WHERE id=$id;";
                stock.Parameters.AddWithValue("$id", productId);
                await using var reader = await stock.ExecuteReaderAsync();
                Assert.True(await reader.ReadAsync());
                Assert.Equal(21, reader.GetInt32(0));
                Assert.Equal(200d / 18d, reader.GetDouble(1), 4);
                Assert.Equal(20, reader.GetDouble(2), 2);
                Assert.Equal("pcs", reader.GetString(3));
            }
            await using (var invoice = connection.CreateCommand())
            {
                invoice.CommandText = "SELECT supplier_id,invoice_number,invoice_date,invoice_total,invoice_discount,invoice_tax,invoice_paid_amount,invoice_balance_due,quantity,unit_cost,total_cost,invoice_quantity,conversion_factor,invoice_unit_cost FROM purchases WHERE invoice_group_id=$group;";
                invoice.Parameters.AddWithValue("$group", group);
                await using var reader = await invoice.ExecuteReaderAsync();
                Assert.True(await reader.ReadAsync());
                Assert.Equal(supplierId, reader.GetInt32(0));
                Assert.Equal("INV-2026-001", reader.GetString(1));
                Assert.Equal("2026-11-16", reader.GetString(2));
                Assert.Equal(200, reader.GetDouble(3), 2);
                Assert.Equal(10, reader.GetDouble(4), 2);
                Assert.Equal(30, reader.GetDouble(5), 2);
                Assert.Equal(50, reader.GetDouble(6), 2);
                Assert.Equal(150, reader.GetDouble(7), 2);
                Assert.Equal(18, reader.GetInt32(8));
                Assert.Equal(200d / 18d, reader.GetDouble(9), 4);
                Assert.Equal(200, reader.GetDouble(10), 2);
                Assert.Equal(1.5, reader.GetDouble(11), 2);
                Assert.Equal(12, reader.GetDouble(12), 2);
                Assert.Equal(120, reader.GetDouble(13), 2);
                Assert.False(await reader.ReadAsync());
            }
            await using (var balance = connection.CreateCommand())
            {
                balance.CommandText = "SELECT balance FROM parties WHERE id=$id AND type='supplier';";
                balance.Parameters.AddWithValue("$id", supplierId);
                Assert.Equal(150, Convert.ToDouble(await balance.ExecuteScalarAsync()), 2);
            }
            await using (var ledger = connection.CreateCommand())
            {
                ledger.CommandText = "SELECT COUNT(*),SUM(CASE WHEN type='supplier_purchase' THEN amount ELSE 0 END),SUM(CASE WHEN type='supplier_payment' THEN amount ELSE 0 END) FROM khata_transactions WHERE party_id=$id;";
                ledger.Parameters.AddWithValue("$id", supplierId);
                await using var reader = await ledger.ExecuteReaderAsync();
                Assert.True(await reader.ReadAsync());
                Assert.Equal(2, reader.GetInt32(0));
                Assert.Equal(200, reader.GetDouble(1), 2);
                Assert.Equal(50, reader.GetDouble(2), 2);
            }
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public async Task WpfSupplierInvoiceRejectsDuplicateInvoiceAndRollsBackInvalidLine()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            await SeedSaleAccountAsync(path, "Wholesale", 3);
            var supplierId = await SeedSupplierAsync(path);
            int productId;
            await using (var db = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString()))
            {
                await db.OpenAsync();
                await using var find = db.CreateCommand();
                find.CommandText = "SELECT id FROM products WHERE barcode='WPF-WH-1';";
                productId = Convert.ToInt32(await find.ExecuteScalarAsync());
            }
            var service = new PurchaseService();
            var request = new PurchaseInvoiceRequest(supplierId, "INV-DUP-1", DateTime.Today, 100, 0, 0, 0,
                [new PurchaseInvoiceLineInput(productId, null, null, 2, 2, 1, 50, "pcs", "pcs", 60, 100)]);
            await service.RecordInvoiceAsync(request, path);
            await Assert.ThrowsAsync<InvalidOperationException>(() => service.RecordInvoiceAsync(request, path));
            var invalid = request with { InvoiceNumber = "INV-INVALID-1", Items = [new PurchaseInvoiceLineInput(productId, null, null, 2, 2, 1, 50, "pcs", "pcs", 10, 100)] };
            await Assert.ThrowsAsync<InvalidOperationException>(() => service.RecordInvoiceAsync(invalid, path));

            await using var connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString());
            await connection.OpenAsync();
            await using var stock = connection.CreateCommand();
            stock.CommandText = "SELECT quantity FROM products WHERE id=$id;";
            stock.Parameters.AddWithValue("$id", productId);
            Assert.Equal(5, Convert.ToInt32(await stock.ExecuteScalarAsync()));
            await using var invoices = connection.CreateCommand();
            invoices.CommandText = "SELECT COUNT(*) FROM purchases WHERE supplier_id=$id;";
            invoices.Parameters.AddWithValue("$id", supplierId);
            Assert.Equal(1, Convert.ToInt32(await invoices.ExecuteScalarAsync()));
            await using var balance = connection.CreateCommand();
            balance.CommandText = "SELECT balance FROM parties WHERE id=$id;";
            balance.Parameters.AddWithValue("$id", supplierId);
            Assert.Equal(100, Convert.ToDouble(await balance.ExecuteScalarAsync()), 2);
            await using var ledger = connection.CreateCommand();
            ledger.CommandText = "SELECT COUNT(*) FROM khata_transactions WHERE party_id=$id;";
            ledger.Parameters.AddWithValue("$id", supplierId);
            Assert.Equal(1, Convert.ToInt32(await ledger.ExecuteScalarAsync()));
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public async Task WpfKhataReceiptReducesOutstandingBalanceAndRejectsOverpayment()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            var customerId = await SeedSaleAccountAsync(path, "Khata", 5);
            await new SalePostingService(TestAccess).CompleteSaleAsync(
                new SaleCheckoutRequest(
                    [new SaleLineInput("WPF-WH-1", 1, 18)],
                    customerId,
                    "Credit",
                    null,
                    0,
                    false,
                    "Khata"),
                path);

            var service = new KhataService();
            await service.RecordReceiptAsync(customerId, 8, "Partial counter receipt", path);
            await Assert.ThrowsAsync<InvalidOperationException>(() =>
                service.RecordReceiptAsync(customerId, 11, "Overpayment", path));

            await using var connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString());
            await connection.OpenAsync();
            await using var party = connection.CreateCommand();
            party.CommandText = "SELECT balance FROM parties WHERE id=$id;";
            party.Parameters.AddWithValue("$id", customerId);
            Assert.Equal(10, Convert.ToDouble(await party.ExecuteScalarAsync()), 2);
            await using var ledger = connection.CreateCommand();
            ledger.CommandText = "SELECT COUNT(*),SUM(amount) FROM khata_transactions WHERE party_id=$id AND type='receipt';";
            ledger.Parameters.AddWithValue("$id", customerId);
            await using var reader = await ledger.ExecuteReaderAsync();
            Assert.True(await reader.ReadAsync());
            Assert.Equal(1, reader.GetInt32(0));
            Assert.Equal(8, reader.GetDouble(1), 2);
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public async Task WpfSaleReturnsRestoreSaleableStockAndTrackDamagedItemsAndKhataAdjustments()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            var customerId = await SeedSaleAccountAsync(path, "Wholesale", 10);
            var sale = await new SalePostingService(TestAccess).CompleteSaleAsync(
                new SaleCheckoutRequest(
                    [new SaleLineInput("WPF-WH-1", 2, 18)],
                    customerId,
                    "Credit",
                    null,
                    0,
                    false,
                    "Wholesale"),
                path);

            int saleItemId;
            await using (var connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString()))
            {
                await connection.OpenAsync();
                await using var find = connection.CreateCommand();
                find.CommandText = "SELECT id FROM sale_items WHERE sale_id=$sale;";
                find.Parameters.AddWithValue("$sale", sale.SaleId);
                saleItemId = Convert.ToInt32(await find.ExecuteScalarAsync());
            }

            var service = new SaleReturnService();
            var saleable = await service.RecordAsync(
                sale.SaleId, "Customer returned sealed item", "Khata",
                [new SaleReturnLineInput(saleItemId, 1, "saleable")], path);
            var damaged = await service.RecordAsync(
                sale.SaleId, "Customer returned damaged item", "Khata",
                [new SaleReturnLineInput(saleItemId, 1, "damaged")], path);
            Assert.Equal(18, saleable.RefundAmount, 2);
            Assert.Equal(18, damaged.RefundAmount, 2);

            await using var db = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString());
            await db.OpenAsync();
            await using var stock = db.CreateCommand();
            stock.CommandText = "SELECT quantity,damaged_quantity FROM products WHERE barcode='WPF-WH-1';";
            await using var stockReader = await stock.ExecuteReaderAsync();
            Assert.True(await stockReader.ReadAsync());
            Assert.Equal(9, stockReader.GetInt32(0));
            Assert.Equal(1, stockReader.GetInt32(1));
            await stockReader.DisposeAsync();

            await using var party = db.CreateCommand();
            party.CommandText = "SELECT balance FROM parties WHERE id=$id;";
            party.Parameters.AddWithValue("$id", customerId);
            Assert.Equal(0, Convert.ToDouble(await party.ExecuteScalarAsync()), 2);

            await using var returns = db.CreateCommand();
            returns.CommandText = "SELECT COUNT(*),SUM(refund_amount) FROM sale_returns WHERE sale_id=$sale AND refund_method='Khata';";
            returns.Parameters.AddWithValue("$sale", sale.SaleId);
            await using var returnReader = await returns.ExecuteReaderAsync();
            Assert.True(await returnReader.ReadAsync());
            Assert.Equal(2, returnReader.GetInt32(0));
            Assert.Equal(36, returnReader.GetDouble(1), 2);
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }


    [Fact]
    public async Task WpfSaleReturnRejectsDuplicateLinesThatExceedSoldQuantityAndRollsBack()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            var customerId = await SeedSaleAccountAsync(path, "Wholesale", 10);
            var sale = await new SalePostingService(TestAccess).CompleteSaleAsync(
                new SaleCheckoutRequest(
                    [new SaleLineInput("WPF-WH-1", 2, 18)],
                    customerId,
                    "Credit",
                    null,
                    0,
                    false,
                    "Wholesale"),
                path);

            int saleItemId;
            await using (var connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString()))
            {
                await connection.OpenAsync();
                await using var find = connection.CreateCommand();
                find.CommandText = "SELECT id FROM sale_items WHERE sale_id=$sale;";
                find.Parameters.AddWithValue("$sale", sale.SaleId);
                saleItemId = Convert.ToInt32(await find.ExecuteScalarAsync());
            }

            var service = new SaleReturnService();
            await Assert.ThrowsAsync<InvalidOperationException>(() => service.RecordAsync(
                sale.SaleId,
                "Duplicate line quantity must not exceed sold quantity",
                "Khata",
                [
                    new SaleReturnLineInput(saleItemId, 2, "saleable"),
                    new SaleReturnLineInput(saleItemId, 1, "damaged")
                ],
                path));

            await using var db = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString());
            await db.OpenAsync();
            await using var returns = db.CreateCommand();
            returns.CommandText = "SELECT COUNT(*) FROM sale_returns WHERE sale_id=$sale;";
            returns.Parameters.AddWithValue("$sale", sale.SaleId);
            Assert.Equal(0, Convert.ToInt32(await returns.ExecuteScalarAsync()));

            await using var returnItems = db.CreateCommand();
            returnItems.CommandText = "SELECT COUNT(*) FROM sale_return_items WHERE sale_item_id=$item;";
            returnItems.Parameters.AddWithValue("$item", saleItemId);
            Assert.Equal(0, Convert.ToInt32(await returnItems.ExecuteScalarAsync()));

            await using var stock = db.CreateCommand();
            stock.CommandText = "SELECT quantity,damaged_quantity FROM products WHERE barcode='WPF-WH-1';";
            await using var stockReader = await stock.ExecuteReaderAsync();
            Assert.True(await stockReader.ReadAsync());
            Assert.Equal(8, stockReader.GetInt32(0));
            Assert.Equal(0, stockReader.GetInt32(1));
            await stockReader.DisposeAsync();

            await using var party = db.CreateCommand();
            party.CommandText = "SELECT balance FROM parties WHERE id=$id;";
            party.Parameters.AddWithValue("$id", customerId);
            Assert.Equal(36, Convert.ToDouble(await party.ExecuteScalarAsync()), 2);
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public async Task WpfSalesReportAndProfitLossIncludeDiscountsReturnsPurchasesAndExpenses()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            var customerId = await SeedSaleAccountAsync(path, "Wholesale", 10);
            var sale = await new SalePostingService(TestAccess).CompleteSaleAsync(
                new SaleCheckoutRequest(
                    [new SaleLineInput("WPF-WH-1", 2, 18)],
                    customerId,
                    "Credit",
                    null,
                    10,
                    true,
                    "Wholesale"),
                path);

            int saleItemId;
            await using (var connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString()))
            {
                await connection.OpenAsync();
                await using var find = connection.CreateCommand();
                find.CommandText = "SELECT id FROM sale_items WHERE sale_id=$sale;";
                find.Parameters.AddWithValue("$sale", sale.SaleId);
                saleItemId = Convert.ToInt32(await find.ExecuteScalarAsync());
            }

            var returned = await new SaleReturnService().RecordAsync(
                sale.SaleId, "Report return", "Khata",
                [new SaleReturnLineInput(saleItemId, 1, "saleable")], path);
            Assert.Equal(16.2, returned.RefundAmount, 2);

            int productId;
            await using (var connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString()))
            {
                await connection.OpenAsync();
                await using var find = connection.CreateCommand();
                find.CommandText = "SELECT id FROM products WHERE barcode='WPF-WH-1';";
                productId = Convert.ToInt32(await find.ExecuteScalarAsync());
                await using var expense = connection.CreateCommand();
                expense.CommandText = "INSERT INTO expenses(title,amount,date,sync_id) VALUES('Report test expense',5,$date,'report-expense-sync');";
                expense.Parameters.AddWithValue("$date", DateTime.Now.ToString("yyyy-MM-dd HH:mm", System.Globalization.CultureInfo.InvariantCulture));
                await expense.ExecuteNonQueryAsync();
            }
            await new PurchaseService().RecordAsync(productId, 4, 20, 24, path);

            var from = DateTime.Today;
            var to = DateTime.Today;
            var statement = await new KhataService().GetStatementAsync(customerId, from, to, path);
            Assert.Equal(2, statement.Count);
            Assert.Equal("Sale", statement[0].EntryType);
            Assert.Equal(2, statement[0].Quantity);
            Assert.Equal("Return", statement[1].EntryType);
            Assert.Equal(-1, statement[1].Quantity);
            Assert.Equal(16.2, statement.Sum(x => x.Amount), 2);

            var report = await new SalesReportService().GetAsync(from, to, path);
            Assert.Equal(16.2, report.Sales, 2);
            Assert.Equal(80, report.Purchases, 2);
            Assert.Equal(5, report.Expenses, 2);
            Assert.Equal(3.6, report.Discount, 2);
            Assert.Equal(16.2, report.Returned, 2);
            Assert.Equal(1, report.SalesCount);
            Assert.Equal(-68.8, report.NetActivity, 2);
            Assert.Single(report.Days);

            var profit = await new ProfitLossService().GetAsync(path);
            Assert.Equal(16.2, profit.Revenue, 2);
            Assert.Equal(10, profit.Cost, 2);
            Assert.Equal(5, profit.Expenses, 2);
            Assert.Equal(1.2, profit.Profit, 2);
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public async Task WpfInventoryCreateUpdateDuplicateAndDeleteRulesPreserveBarcodeHistory()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            await SeedSaleAccountAsync(path, "Khata", 5);
            var service = new InventoryService();
            var initial = new ProductMutation("New Test Item", "WPF-NEW-1", 4, "pcs", 5, 10, 8);
            await service.CreateAsync(initial, path);
            Assert.Equal("New Test Item", await service.FindBarcodeOwnerAsync("wpf-new-1", null, path));

            await using var db = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString());
            await db.OpenAsync();
            await using var find = db.CreateCommand();
            find.CommandText = "SELECT id,wholesalePrice FROM products WHERE barcode='WPF-NEW-1';";
            await using var reader = await find.ExecuteReaderAsync();
            Assert.True(await reader.ReadAsync());
            var id = reader.GetInt32(0);
            Assert.Equal(8, reader.GetDouble(1), 2);
            await reader.DisposeAsync();

            Assert.Null(await service.FindBarcodeOwnerAsync("WPF-NEW-1", id, path));
            await Assert.ThrowsAsync<InvalidOperationException>(() => service.CreateAsync(initial, path));
            await service.UpdateAsync(id, new ProductMutation("Updated Item", "WPF-NEW-2", 7, "pcs", 6, 12, 10), path);
            Assert.Null(await service.FindBarcodeOwnerAsync("WPF-NEW-1", null, path));
            Assert.Equal("Updated Item", await service.FindBarcodeOwnerAsync("WPF-NEW-2", null, path));
            await Assert.ThrowsAsync<InvalidOperationException>(() =>
                service.UpdateAsync(id, new ProductMutation("Updated Item", "WPF-WH-1", 7, "pcs", 6, 12, 10), path));
            await service.SetActiveAsync(id, false, path);

            await using (var state = db.CreateCommand())
            {
                state.CommandText = "SELECT barcode,is_active,wholesalePrice FROM products WHERE id=$id;";
                state.Parameters.AddWithValue("$id", id);
                await using var stateReader = await state.ExecuteReaderAsync();
                Assert.True(await stateReader.ReadAsync());
                Assert.Equal("WPF-NEW-2", stateReader.GetString(0));
                Assert.Equal(0, stateReader.GetInt32(1));
                Assert.Equal(10, stateReader.GetDouble(2), 2);
            }

            await using (var zero = db.CreateCommand())
            {
                zero.CommandText = "UPDATE products SET quantity=0,damaged_quantity=0 WHERE id=$id;";
                zero.Parameters.AddWithValue("$id", id);
                await zero.ExecuteNonQueryAsync();
            }
            await service.DeleteAsync(id, path);

            await using var verify = db.CreateCommand();
            verify.CommandText = """
                SELECT
                  (SELECT COUNT(*) FROM products WHERE id=$id),
                  (SELECT COUNT(*) FROM drive_sync_tombstones WHERE entity_type='product' AND entity_key IN ('WPF-NEW-1','WPF-NEW-2'));
                """;
            verify.Parameters.AddWithValue("$id", id);
            await using var verifyReader = await verify.ExecuteReaderAsync();
            Assert.True(await verifyReader.ReadAsync());
            Assert.Equal(0, verifyReader.GetInt32(0));
            Assert.Equal(2, verifyReader.GetInt32(1));
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public async Task WpfInventoryCannotDeleteProductWithSaleHistoryEvenWhenStockIsZero()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            var customerId = await SeedSaleAccountAsync(path, "Khata", 5);
            await new SalePostingService(TestAccess).CompleteSaleAsync(
                new SaleCheckoutRequest(
                    [new SaleLineInput("WPF-WH-1", 1, 18)],
                    customerId,
                    "Cash",
                    null,
                    0,
                    false,
                    "Khata"),
                path);

            int productId;
            await using (var db = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString()))
            {
                await db.OpenAsync();
                await using var find = db.CreateCommand();
                find.CommandText = "SELECT id FROM products WHERE barcode='WPF-WH-1';";
                productId = Convert.ToInt32(await find.ExecuteScalarAsync());
                await using var zero = db.CreateCommand();
                zero.CommandText = "UPDATE products SET quantity=0,damaged_quantity=0 WHERE id=$id;";
                zero.Parameters.AddWithValue("$id", productId);
                await zero.ExecuteNonQueryAsync();
            }

            await Assert.ThrowsAsync<InvalidOperationException>(() =>
                new InventoryService().DeleteAsync(productId, path));
            await using var check = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString());
            await check.OpenAsync();
            await using var exists = check.CreateCommand();
            exists.CommandText = "SELECT COUNT(*) FROM products WHERE id=$id;";
            exists.Parameters.AddWithValue("$id", productId);
            Assert.Equal(1, Convert.ToInt32(await exists.ExecuteScalarAsync()));
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public async Task AcceptsExactFlutterSchemaV18WithoutModifyingDatabase()
    {
        var path = await CreateFixtureAsync();
        try
        {
            var before = await Sha256Async(path);
            await PosDatabaseSchemaVerifier.VerifyAsync(path);
            Assert.Equal(before, await Sha256Async(path));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public async Task RejectsMissingBarcodeNotNullConstraintWithoutModifyingDatabase()
    {
        var path = await CreateFixtureAsync("barcode TEXT UNIQUE");
        try
        {
            var before = await Sha256Async(path);
            await Assert.ThrowsAsync<PosDatabaseSchemaException>(() => PosDatabaseSchemaVerifier.VerifyAsync(path));
            Assert.Equal(before, await Sha256Async(path));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public async Task RejectsMissingBarcodeUniqueConstraintWithoutModifyingDatabase()
    {
        var path = await CreateFixtureAsync("barcode TEXT NOT NULL");
        try
        {
            var before = await Sha256Async(path);
            await Assert.ThrowsAsync<PosDatabaseSchemaException>(() => PosDatabaseSchemaVerifier.VerifyAsync(path));
            Assert.Equal(before, await Sha256Async(path));
        }
        finally
        {
            File.Delete(path);
        }
    }
 
    [Fact]
    public async Task DriveSnapshotExportCreatesSafetyCopyAndRepairsStableReferences()
    {
        var fixture = await CreateFixtureAsync();
        var directory = Path.Combine(Path.GetTempPath(), "khan-baba-drive-export-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        var databasePath = Path.Combine(directory, "khan_baba_pos.db");
        File.Copy(fixture, databasePath);
        File.Delete(fixture);
        try
        {
            await using (var connection = new SqliteConnection(new SqliteConnectionStringBuilder
            {
                DataSource = databasePath, Pooling = false
            }.ToString()))
            {
                await connection.OpenAsync();
                await using var seed = connection.CreateCommand();
                seed.CommandText = """
                    INSERT INTO products (name,barcode,price,purchasePrice,wholesalePrice,damaged_quantity,quantity,is_active,stock_unit)
                    VALUES ('Milk <Fresh>','DRIVE-EXP-1',20,10,18,0,5,1,'pcs');
                    INSERT INTO parties (name,phone,type,customer_type,sync_id,balance)
                    VALUES ('Drive Customer','03000000001','customer','Khata',NULL,0);
                    INSERT INTO sales (total_amount,discount,final_amount,payment_type,customer_id,customer_type,received_amount,balance_due,sync_id,customer_sync_id,date)
                    VALUES (20,0,20,'Cash',last_insert_rowid(),'Khata',20,0,NULL,NULL,'2026-11-16 10:00:00');
                    """;
                await seed.ExecuteNonQueryAsync();
            }

            var payload = await new DriveSnapshotExportService().ExportAsync(databasePath);
            using var json = JsonDocument.Parse(payload.Json);
            Assert.Equal(2, json.RootElement.GetProperty("schemaVersion").GetInt32());
            var product = json.RootElement.GetProperty("products")[0];
            Assert.Equal("Milk <Fresh>", product.GetProperty("name").GetString());
            Assert.Equal("20.0", product.GetProperty("price").GetRawText());
            Assert.False(product.TryGetProperty("id", out _));
            var party = json.RootElement.GetProperty("parties")[0];
            var partySyncId = party.GetProperty("sync_id").GetString();
            Assert.False(string.IsNullOrWhiteSpace(partySyncId));
            Assert.False(party.TryGetProperty("id", out _));
            var sale = json.RootElement.GetProperty("sales")[0];
            Assert.Equal(partySyncId, sale.GetProperty("customer_sync_id").GetString());
            Assert.False(sale.TryGetProperty("customer_id", out _));
            Assert.False(payload.Json.Contains("\\u003C", StringComparison.OrdinalIgnoreCase));
            Assert.Equal(Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(payload.Json))).ToLowerInvariant(), payload.Sha256);
            var backups = Directory.GetFiles(Path.Combine(directory, "Backups"), "*.db");
            Assert.Single(backups);
            Assert.True(File.Exists(backups[0] + ".sha256"));
            await PosDatabaseSchemaVerifier.VerifyAsync(databasePath);
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }


    [Fact]
    public void DriveEnvelopeValidatorAcceptsValidAndroidSchemaV2AndRejectsTampering()
    {
        var data = new Dictionary<string, object?>
        {
            ["products"] = new object[] { new Dictionary<string, object?> { ["barcode"] = "A-1", ["price"] = 12.0 } },
            ["parties"] = Array.Empty<object>(),
            ["sales"] = Array.Empty<object>(),
            ["sale_items"] = Array.Empty<object>(),
            ["purchases"] = Array.Empty<object>(),
            ["khata_transactions"] = Array.Empty<object>(),
            ["expenses"] = Array.Empty<object>(),
            ["reminders"] = Array.Empty<object>(),
            ["sale_returns"] = Array.Empty<object>(),
            ["sale_return_items"] = Array.Empty<object>(),
            ["tombstones"] = Array.Empty<object>()
        };
        var options = new JsonSerializerOptions
        {
            Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
        };
        options.Converters.Add(new DartCompatibleDoubleConverter());
        var compactData = JsonSerializer.Serialize(data, options);
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(compactData))).ToLowerInvariant();
        var envelope = JsonSerializer.Serialize(new
        {
            schemaVersion = 2,
            deviceId = "android-fixture",
            snapshotHash = hash,
            data
        }, options);

        var validated = DriveSnapshotEnvelopeValidator.ValidateDeviceEnvelope(envelope);
        Assert.Equal("android-fixture", validated.DeviceId);
        Assert.Equal(hash, validated.SnapshotHash);
        Assert.Contains("\"barcode\":\"A-1\"", validated.CompactJson);

        var tampered = envelope.Replace("\"A-1\"", "\"A-2\"", StringComparison.Ordinal);
        Assert.Throws<FormatException>(() => DriveSnapshotEnvelopeValidator.ValidateDeviceEnvelope(tampered));
    }

    [Fact]
    public void DriveEnvelopeValidatorRequiresEverySchemaV2Collection()
    {
        var incomplete = """{"schemaVersion":2,"deviceId":"device-1","snapshotHash":"deadbeef","data":{"products":[]}}""";
        var error = Assert.Throws<FormatException>(() =>
            DriveSnapshotEnvelopeValidator.ValidateDeviceEnvelope(incomplete));
        Assert.Contains("parties", error.Message);
    }

    [Fact]
    public void DriveEnvelopeValidatorChecksMasterProcessedSnapshotManifest()
    {
        var data = new Dictionary<string, object?>
        {
            ["products"] = Array.Empty<object>(), ["parties"] = Array.Empty<object>(),
            ["sales"] = Array.Empty<object>(), ["sale_items"] = Array.Empty<object>(),
            ["purchases"] = Array.Empty<object>(), ["khata_transactions"] = Array.Empty<object>(),
            ["expenses"] = Array.Empty<object>(), ["reminders"] = Array.Empty<object>(),
            ["sale_returns"] = Array.Empty<object>(), ["sale_return_items"] = Array.Empty<object>(),
            ["tombstones"] = Array.Empty<object>()
        };
        var options = new JsonSerializerOptions
        {
            Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
        };
        var dataJson = JsonSerializer.Serialize(data, options);
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(dataJson))).ToLowerInvariant();
        var master = JsonSerializer.Serialize(new
        {
            schemaVersion = 2,
            masterDeviceId = "windows-1",
            processedSnapshots = new Dictionary<string, string> { ["android-1"] = "aabbcc" },
            preMergeBackups = new Dictionary<string, string>(),
            data,
            snapshotHash = hash
        }, options);

        var validated = DriveSnapshotEnvelopeValidator.ValidateMasterEnvelope(master);
        Assert.Equal("windows-master", validated.DeviceId);
        Assert.Equal(hash, validated.SnapshotHash);
    }


    [Fact]
    public void DriveMasterManifestTracksProcessedHashesAndBackupFilenames()
    {
        var manifest = DriveMasterManifest.Empty("windows-device-1");
        const string deviceHash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        manifest.SetPreMergeBackup("android-device-1", "drive-premerge-android-device-1.db", deviceHash);
        Assert.Equal("drive-premerge-android-device-1.db", manifest.GetPreMergeBackup("android-device-1"));
        Assert.Equal(deviceHash, manifest.GetPreMergeBackupHash("android-device-1"));
        Assert.True(manifest.HasPreMergeBackupForSnapshot("android-device-1", deviceHash));
        Assert.False(manifest.HasPreMergeBackupForSnapshot("android-device-1", new string('b', 64)));
        Assert.False(manifest.IsProcessed("android-device-1", deviceHash));

        manifest.MarkProcessed("android-device-1", deviceHash);
        Assert.True(manifest.IsProcessed("android-device-1", deviceHash));
        Assert.False(manifest.IsProcessed("android-device-1", new string('b', 64)));

        manifest.MarkPending("android-device-1");
        Assert.False(manifest.IsProcessed("android-device-1", deviceHash));
        Assert.Throws<ArgumentException>(() => manifest.SetPreMergeBackup("android-device-1", @"C:\\Users\\user\\backup.db"));
    }

    [Fact]
    public void DriveMasterManifestRoundTripsWithoutExposingLocalBackupPaths()
    {
        var manifest = DriveMasterManifest.Empty("windows-device-1");
        const string deviceHash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        manifest.MarkProcessed("android-device-1", deviceHash);
        manifest.SetPreMergeBackup("android-device-1", "backup-android-device-1.db", deviceHash);

        var data = new Dictionary<string, object?>
        {
            ["products"] = Array.Empty<object>(), ["parties"] = Array.Empty<object>(),
            ["sales"] = Array.Empty<object>(), ["sale_items"] = Array.Empty<object>(),
            ["purchases"] = Array.Empty<object>(), ["khata_transactions"] = Array.Empty<object>(),
            ["expenses"] = Array.Empty<object>(), ["reminders"] = Array.Empty<object>(),
            ["sale_returns"] = Array.Empty<object>(), ["sale_return_items"] = Array.Empty<object>(),
            ["tombstones"] = Array.Empty<object>()
        };
        var dataJson = JsonSerializer.Serialize(data);
        using var dataDocument = JsonDocument.Parse(dataJson);
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(dataJson))).ToLowerInvariant();

        var json = manifest.ToJson(dataDocument.RootElement, hash, DateTimeOffset.Parse("2026-11-16T00:00:00Z"));
        var restored = DriveMasterManifest.Parse(json);
        Assert.Equal("windows-device-1", restored.MasterDeviceId);
        Assert.True(restored.IsProcessed("android-device-1", deviceHash));
        Assert.Equal("backup-android-device-1.db", restored.GetPreMergeBackup("android-device-1"));
        Assert.Equal(deviceHash, restored.GetPreMergeBackupHash("android-device-1"));
        Assert.DoesNotContain(Environment.UserName, json, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("backup-android-device-1.db", json);
    }

    private static ValidatedDriveSnapshot BuildTestSnapshot(
        List<Dictionary<string, object?>>? products = null,
        List<Dictionary<string, object?>>? tombstones = null)
    {
        var data = new Dictionary<string, object?>(StringComparer.Ordinal)
        {
            ["schemaVersion"] = 2,
            ["products"] = (products ?? []).Cast<object?>().ToList(),
            ["parties"] = new List<object?>(),
            ["sales"] = new List<object?>(),
            ["sale_items"] = new List<object?>(),
            ["purchases"] = new List<object?>(),
            ["khata_transactions"] = new List<object?>(),
            ["expenses"] = new List<object?>(),
            ["reminders"] = new List<object?>(),
            ["sale_returns"] = new List<object?>(),
            ["sale_return_items"] = new List<object?>(),
            ["tombstones"] = (tombstones ?? []).Cast<object?>().ToList()
        };
        return new ValidatedDriveSnapshot("android-test-device", new string('a', 64), data, "{}");
    }

    [Fact]
    public async Task DriveMergeCreatesExplicitProductConflictAndResolvesRemoteChoice()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            await SeedSaleAccountAsync(path, "Wholesale", 10);
            var snapshot = BuildTestSnapshot(products:
            [
                new Dictionary<string, object?>
                {
                    ["name"] = "Remote Item", ["barcode"] = "WPF-WH-1",
                    ["price"] = 25d, ["purchasePrice"] = 10d, ["wholesalePrice"] = 19d,
                    ["quantity"] = 4L, ["damaged_quantity"] = 0L, ["is_active"] = 1L, ["stock_unit"] = "pcs"
                }
            ]);
            var service = new DriveSnapshotMergeService();
            var result = await service.MergeAsync(snapshot, snapshot.DeviceId, path);
            Assert.Equal(1, result.PendingConflicts);
            Assert.False(result.SnapshotFullyAccepted);
            var conflicts = await service.GetPendingConflictsAsync(path);
            var conflict = Assert.Single(conflicts);
            Assert.Equal("product", conflict.EntityType);
            Assert.Equal("WPF-WH-1", conflict.EntityKey);

            await service.ResolveConflictAsync(conflict.Id, useRemote: true, path);
            var remaining = await service.GetPendingConflictsAsync(path);
            Assert.Empty(remaining);
            await using var db = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString());
            await db.OpenAsync();
            await using var query = db.CreateCommand();
            query.CommandText = "SELECT name,price,quantity FROM products WHERE barcode='WPF-WH-1';";
            await using var reader = await query.ExecuteReaderAsync();
            Assert.True(await reader.ReadAsync());
            Assert.Equal("Remote Item", reader.GetString(0));
            Assert.Equal(25, reader.GetDouble(1), 2);
            Assert.Equal(4, reader.GetInt32(2));
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public async Task DriveDeleteTombstoneRequiresExplicitChoiceAndCannotRemoveStockedProduct()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            await SeedSaleAccountAsync(path, "Wholesale", 10);
            var snapshot = BuildTestSnapshot(tombstones:
            [
                new Dictionary<string, object?>
                {
                    ["entity_type"] = "product", ["entity_key"] = "WPF-WH-1",
                    ["deleted_at"] = DateTimeOffset.UtcNow.ToString("O")
                }
            ]);
            var service = new DriveSnapshotMergeService();
            var result = await service.MergeAsync(snapshot, snapshot.DeviceId, path);
            Assert.Equal(1, result.PendingConflicts);
            var conflict = Assert.Single(await service.GetPendingConflictsAsync(path));
            Assert.Equal("product_delete", conflict.EntityType);

            await Assert.ThrowsAsync<InvalidOperationException>(() =>
                service.ResolveConflictAsync(conflict.Id, useRemote: true, path));
            await service.ResolveConflictAsync(conflict.Id, useRemote: false, path);
            Assert.Empty(await service.GetPendingConflictsAsync(path));

            await using var db = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString());
            await db.OpenAsync();
            await using var stock = db.CreateCommand();
            stock.CommandText = "SELECT quantity FROM products WHERE barcode='WPF-WH-1';";
            Assert.Equal(10, Convert.ToInt32(await stock.ExecuteScalarAsync()));
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public async Task SalesmanCannotMutatePartyThroughServiceLayer()
    {
        var directory = Path.Combine(Path.GetTempPath(), "khan-baba-role-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            var access = new AccessService(Path.Combine(directory, "users.dat"));
            access.ProvisionFirstAdmin("owner", "Owner", "OwnerPassword!2026");
            access.CreateStaff("cashier", "Cashier", "CashierPassword!2026", AccessRole.Salesman);
            access.Logout();
            access.Authenticate("cashier", "CashierPassword!2026");
            AccessService.RegisterProcess(access);
            await Assert.ThrowsAsync<UnauthorizedAccessException>(() =>
                new PartyService().AddAsync("Blocked Party", "03000000000", "customer"));
        }
        finally
        {
            AccessService.RegisterProcess(TestAccess);
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }


    [Fact]
    public async Task WpfRecallRecalculatesEditedTotalsAndAdjustsStockAndKhataInOneTransaction()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            var customerId = await SeedSaleAccountAsync(path, "Khata", 10);
            var service = new SalePostingService(TestAccess);
            var original = await service.CompleteSaleAsync(
                new SaleCheckoutRequest(
                    [new SaleLineInput("WPF-WH-1", 2, 18)],
                    customerId, "Partial", 10, 0, false, "Khata", TestAccess.CurrentSession!.DisplayName, TestAccess.CurrentSession.UserId),
                path);
            Assert.Equal(26, original.BalanceDue, 2);

            var updated = await service.UpdateSaleFromRecallAsync(
                original.SaleId,
                new SaleCheckoutRequest(
                    [new SaleLineInput("WPF-WH-1", 3, 18)],
                    customerId, "Partial", 20, 10, true, "Khata", TestAccess.CurrentSession!.DisplayName, TestAccess.CurrentSession.UserId),
                path);

            Assert.Equal(54, updated.Subtotal, 2);
            Assert.Equal(5.4, updated.Discount, 2);
            Assert.Equal(48.6, updated.FinalAmount, 2);
            Assert.Equal(20, updated.ReceivedAmount, 2);
            Assert.Equal(28.6, updated.BalanceDue, 2);

            await using var db = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString());
            await db.OpenAsync();
            await using (var rows = db.CreateCommand())
            {
                rows.CommandText = "SELECT total_amount,discount,final_amount,received_amount,balance_due FROM sales WHERE id=$id;";
                rows.Parameters.AddWithValue("$id", original.SaleId);
                await using var reader = await rows.ExecuteReaderAsync();
                Assert.True(await reader.ReadAsync());
                Assert.Equal(54, reader.GetDouble(0), 2);
                Assert.Equal(5.4, reader.GetDouble(1), 2);
                Assert.Equal(48.6, reader.GetDouble(2), 2);
                Assert.Equal(20, reader.GetDouble(3), 2);
                Assert.Equal(28.6, reader.GetDouble(4), 2);
            }
            await using (var stock = db.CreateCommand())
            {
                stock.CommandText = "SELECT quantity FROM products WHERE barcode='WPF-WH-1';";
                Assert.Equal(7, Convert.ToInt32(await stock.ExecuteScalarAsync()));
            }
            await using (var party = db.CreateCommand())
            {
                party.CommandText = "SELECT balance FROM parties WHERE id=$id;";
                party.Parameters.AddWithValue("$id", customerId);
                Assert.Equal(28.6, Convert.ToDouble(await party.ExecuteScalarAsync()), 2);
            }
            await using (var ledger = db.CreateCommand())
            {
                ledger.CommandText = "SELECT COUNT(*),SUM(CASE WHEN type='credit' THEN amount ELSE 0 END),SUM(CASE WHEN type='receipt' THEN amount ELSE 0 END) FROM khata_transactions WHERE party_id=$id;";
                ledger.Parameters.AddWithValue("$id", customerId);
                await using var reader = await ledger.ExecuteReaderAsync();
                Assert.True(await reader.ReadAsync());
                Assert.Equal(2, reader.GetInt32(0));
                Assert.Equal(48.6, reader.GetDouble(1), 2);
                Assert.Equal(20, reader.GetDouble(2), 2);
            }
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public async Task WpfRecallAllowsEarlierReceiptButBlocksLaterReceiptWithoutChangingStock()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            var customerId = await SeedSaleAccountAsync(path, "Khata", 10);
            await using (var seed = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString()))
            {
                await seed.OpenAsync();
                await using var prior = seed.CreateCommand();
                prior.CommandText = """
                    INSERT INTO khata_transactions(party_id,type,amount,note,date,sync_id,party_sync_id)
                    VALUES($party,'receipt',1,'Prior receipt','2026-11-16 10:00:00','wpf-prior-receipt','wpf-wholesale-sync');
                    """;
                prior.Parameters.AddWithValue("$party", customerId);
                await prior.ExecuteNonQueryAsync();
            }

            var service = new SalePostingService(TestAccess);
            var original = await service.CompleteSaleAsync(
                new SaleCheckoutRequest(
                    [new SaleLineInput("WPF-WH-1", 1, 18)],
                    customerId, "Partial", 5, 0, false, "Khata", TestAccess.CurrentSession!.DisplayName, TestAccess.CurrentSession.UserId,
                    new DateTime(2026, 11, 16, 10, 0, 0)),
                path);
            var request = new SaleCheckoutRequest(
                [new SaleLineInput("WPF-WH-1", 1, 18)],
                customerId, "Partial", 5, 0, false, "Khata", TestAccess.CurrentSession!.DisplayName, TestAccess.CurrentSession.UserId);
            await service.UpdateSaleFromRecallAsync(original.SaleId, request, path);

            await using (var later = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString()))
            {
                await later.OpenAsync();
                await using var receipt = later.CreateCommand();
                receipt.CommandText = """
                    INSERT INTO khata_transactions(party_id,type,amount,note,date,sync_id,party_sync_id)
                    VALUES($party,'receipt',1,'Later receipt','2026-11-16 10:00:00','wpf-later-receipt','wpf-wholesale-sync');
                    """;
                receipt.Parameters.AddWithValue("$party", customerId);
                await receipt.ExecuteNonQueryAsync();
            }

            var stockBefore = 9;
            await Assert.ThrowsAsync<InvalidOperationException>(() =>
                service.UpdateSaleFromRecallAsync(original.SaleId, request, path));
            await using var verify = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString());
            await verify.OpenAsync();
            await using var stock = verify.CreateCommand();
            stock.CommandText = "SELECT quantity FROM products WHERE barcode='WPF-WH-1';";
            Assert.Equal(stockBefore, Convert.ToInt32(await stock.ExecuteScalarAsync()));
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }


    [Fact]
    public void WindowsDriveSyncIsEnabledAndWaitsForAdminOAuthBeforeAutoSync()
    {
        var sync = new WindowsDriveSyncService(TestAccess);

        Assert.True(sync.IsEnabled);
        Assert.False(sync.HasSavedCredentials);
        sync.StartAutoSync();
        Assert.Contains("connect", sync.Status.ToLowerInvariant());
    }


    [Theory]
    [InlineData("KhanBabaPOS-Setup-x64.exe", true)]
    [InlineData("../KhanBabaPOS-Setup-x64.exe", false)]
    [InlineData(@"..\\KhanBabaPOS-Setup-x64.exe", false)]
    [InlineData(@"C:\\Temp\\KhanBabaPOS-Setup-x64.exe", false)]
    [InlineData("release-notes.txt", false)]
    [InlineData("", false)]
    public void NativeUpdaterAcceptsOnlyPlainExeAssetNames(string name, bool expected)
    {
        Assert.Equal(expected, NativeUpdateService.IsSafeInstallerAssetName(name));
    }


    [Fact]
    public async Task PartyDeleteAllowsOnlyEmptyZeroBalanceAccountAndWritesTombstone()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            var customerId = await SeedSaleAccountAsync(path, "Khata", 0);
            var service = new PartyService();
            Assert.Equal(1, await service.DeleteAsync(customerId, "customer", path));

            await using var db = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString());
            await db.OpenAsync();
            await using var party = db.CreateCommand();
            party.CommandText = "SELECT COUNT(*) FROM parties WHERE id=$id;";
            party.Parameters.AddWithValue("$id", customerId);
            Assert.Equal(0, Convert.ToInt32(await party.ExecuteScalarAsync()));
            await using var tombstone = db.CreateCommand();
            tombstone.CommandText = "SELECT COUNT(*) FROM drive_sync_tombstones WHERE entity_type='party' AND entity_key='wpf-wholesale-sync';";
            Assert.Equal(1, Convert.ToInt32(await tombstone.ExecuteScalarAsync()));
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public async Task PartyDeleteBlocksCustomerLedgerHistoryAndSupplierPurchaseHistory()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            var customerId = await SeedSaleAccountAsync(path, "Khata", 0);
            var supplierId = await SeedSupplierAsync(path);
            await using (var db = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString()))
            {
                await db.OpenAsync();
                await using var customerHistory = db.CreateCommand();
                customerHistory.CommandText = "INSERT INTO khata_transactions(party_id,type,amount,note,date) VALUES($id,'receipt',1,'Existing history','2026-11-17 08:00:00');";
                customerHistory.Parameters.AddWithValue("$id", customerId);
                await customerHistory.ExecuteNonQueryAsync();
                await using var supplierHistory = db.CreateCommand();
                supplierHistory.CommandText = "INSERT INTO purchases(product_id,product_name,barcode,quantity,unit_cost,total_cost,supplier_id,date) VALUES(1,'History Item','HISTORY-1',1,5,5,$id,'2026-11-17 08:00:00');";
                supplierHistory.Parameters.AddWithValue("$id", supplierId);
                await supplierHistory.ExecuteNonQueryAsync();
            }

            var service = new PartyService();
            var balanceOnlyId = await SeedSaleAccountAsync(path, "Khata", 0);
            await using (var balanceDb = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString()))
            {
                await balanceDb.OpenAsync();
                await using var setBalance = balanceDb.CreateCommand();
                setBalance.CommandText = "UPDATE parties SET balance=12 WHERE id=$id;";
                setBalance.Parameters.AddWithValue("$id", balanceOnlyId);
                await setBalance.ExecuteNonQueryAsync();
            }
            await Assert.ThrowsAsync<InvalidOperationException>(() => service.DeleteAsync(balanceOnlyId, "customer", path));
            await Assert.ThrowsAsync<InvalidOperationException>(() => service.DeleteAsync(customerId, "customer", path));
            await Assert.ThrowsAsync<InvalidOperationException>(() => service.DeleteAsync(supplierId, "supplier", path));
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public async Task SalesHistoryMapsCustomerNameAndLimitsSalesmanRecallToOwnUserId()
    {
        var path = await CreateFixtureAsync();
        try
        {
            var customerId = await SeedSaleAccountAsync(path, "Khata", 0);
            await using (var db = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString()))
            {
                await db.OpenAsync();
                await using var command = db.CreateCommand();
                command.CommandText = """
                    INSERT INTO sales(total_amount,discount,final_amount,payment_type,customer_id,customer_type,
                        received_amount,balance_due,sync_id,customer_sync_id,date,salesman_uid,salesman_name)
                    VALUES
                        (18,0,18,'Cash',$customer,'Khata',18,0,'history-sale-1','history-party','2026-11-16 10:00:00','salesman-1','Cashier One'),
                        (18,0,18,'Cash',$customer,'Khata',18,0,'history-sale-2','history-party','2026-11-16 10:01:00','salesman-2','Cashier Two'),
                        (12,0,12,'Cash',NULL,'Walk-in',12,0,'history-sale-3',NULL,'2026-11-16 10:02:00','salesman-1','Cashier One');
                    """;
                command.Parameters.AddWithValue("$customer", customerId);
                await command.ExecuteNonQueryAsync();
            }

            var service = new SalesHistoryService();
            var all = await service.GetSalesAsync("", null, null, path);
            Assert.Equal(3, all.Count);
            Assert.Contains(all, x => x.CustomerName == "WPF Wholesale Account" && x.CashierUid == "salesman-1");
            Assert.Contains(all, x => x.CustomerName == "Walk-in Customer" && x.CashierUid == "salesman-1");

            var salesman = new AccessSession(
                "salesman-1", "cashier-one", "Cashier One", AccessRole.Salesman,
                DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow.AddHours(1));
            var own = await service.GetSalesForSessionAsync(salesman, databasePath: path);
            Assert.Equal(2, own.Count);
            Assert.All(own, x => Assert.Equal("salesman-1", x.CashierUid));

            var admin = new AccessSession(
                "admin-1", "admin", "Admin", AccessRole.Admin,
                DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow.AddHours(1));
            var adminRecords = await service.GetSalesForSessionAsync(admin, databasePath: path);
            Assert.Equal(3, adminRecords.Count);
        }
        finally
        {
            File.Delete(path);
        }
    }


    [Fact]
    public async Task SalesmanCannotOverwriteAnotherCashiersSaleEvenWhenCallingServiceDirectly()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        var accessPath = Path.Combine(directory, "recall-salesman-access.dat");
        try
        {
            var customerId = await SeedSaleAccountAsync(path, "Khata", 10);
            int saleId;
            await using (var db = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString()))
            {
                await db.OpenAsync();
                await using var command = db.CreateCommand();
                command.CommandText = """
                    INSERT INTO sales(total_amount,discount,final_amount,payment_type,customer_id,customer_type,
                        received_amount,balance_due,sync_id,customer_sync_id,date,salesman_uid,salesman_name)
                    VALUES(18,0,18,'Cash',$customer,'Khata',18,0,'other-cashier-sale','history-party',
                        '2026-11-16 10:00:00','salesman-2','Cashier Two');
                    SELECT last_insert_rowid();
                    """;
                command.Parameters.AddWithValue("$customer", customerId);
                saleId = Convert.ToInt32(await command.ExecuteScalarAsync());
            }

            var access = new AccessService(accessPath);
                access.ProvisionFirstAdmin("testadmin", "Test Admin", "TestPassword!2026");
                access.CreateStaff("cashier-one", "Cashier One", "CashierPass!2026", AccessRole.Salesman);
                var session = access.Authenticate("cashier-one", "CashierPass!2026");
                AccessService.RegisterProcess(access);

                var service = new SalePostingService(access);
                var request = new SaleCheckoutRequest(
                    [new SaleLineInput("WPF-WH-1", 1, 22)],
                    customerId, "Cash", null, 0, false, "Khata",
                    session.DisplayName, session.UserId);

                await Assert.ThrowsAsync<UnauthorizedAccessException>(
                    () => service.UpdateSaleFromRecallAsync(saleId, request, path));
        }
        finally
        {
            AccessService.RegisterProcess(TestAccess);
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }


    [Fact]
    public async Task PendingBillsAreIsolatedByCashierAndAdminRetainsAllAccess()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        var accessPath = Path.Combine(directory, "pending-bill-access.dat");
        try
        {
            var access = new AccessService(accessPath);
            access.ProvisionFirstAdmin("testadmin", "Test Admin", "TestPassword!2026");
            AccessService.RegisterProcess(access);
            var service = new PendingBillService(access, path);

            var adminDraft = new PendingBillSnapshot(
                "admin-draft", "Admin Draft", DateTime.Now.ToString("s"), [],
                null, "Walk-in", "Cash", 0, false, "");
            await service.SaveAsync(adminDraft);

            access.CreateStaff("cashier-one", "Cashier One", "CashierPass!2026", AccessRole.Salesman);
            var salesmanSession = access.Authenticate("cashier-one", "CashierPass!2026");
            AccessService.RegisterProcess(access);

            var salesmanDraft = new PendingBillSnapshot(
                "salesman-draft", "Salesman Draft", DateTime.Now.ToString("s"),
                [new PendingBillLine("WPF-WH-1", "Saved item", 18, 2, 10, "pcs")],
                23, "Wholesale", "Partial", 12.5, true, "7.50");
            await service.SaveAsync(salesmanDraft);

            var visibleToSalesman = await service.GetAllAsync();
            Assert.Single(visibleToSalesman);
            Assert.Equal("salesman-draft", visibleToSalesman[0].BillId);
            Assert.Equal(salesmanSession.UserId, visibleToSalesman[0].CashierUid);
            Assert.Equal(23, visibleToSalesman[0].SelectedCustomerId);
            Assert.Equal("Wholesale", visibleToSalesman[0].SelectedSaleType);
            Assert.Equal("Partial", visibleToSalesman[0].CustomerPaymentMode);
            Assert.Equal(12.5, visibleToSalesman[0].OverallDiscount, 2);
            Assert.True(visibleToSalesman[0].IsPercentageDiscount);
            Assert.Equal("7.50", visibleToSalesman[0].ReceivedAmount);
            Assert.Single(visibleToSalesman[0].Cart);
            Assert.Equal("WPF-WH-1", visibleToSalesman[0].Cart[0].Barcode);
            Assert.Equal(2, visibleToSalesman[0].Cart[0].Quantity);

            await Assert.ThrowsAsync<UnauthorizedAccessException>(
                () => service.SaveAsync(adminDraft with { Label = "Overwritten by Salesman" }));
            await Assert.ThrowsAsync<UnauthorizedAccessException>(
                () => service.DeleteAsync("admin-draft"));

            await service.DeleteAsync("salesman-draft");
            Assert.Empty(await service.GetAllAsync());

            access.Authenticate("testadmin", "TestPassword!2026");
            AccessService.RegisterProcess(access);
            var visibleToAdmin = await service.GetAllAsync();
            Assert.Single(visibleToAdmin);
            Assert.Equal("admin-draft", visibleToAdmin[0].BillId);
            await service.DeleteAsync("admin-draft");
            Assert.Empty(await service.GetAllAsync());
        }
        finally
        {
            AccessService.RegisterProcess(TestAccess);
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }



    private static ValidatedDriveSnapshot CreateDriveProductSnapshot(string name, long quantity, string hash)
    {
        var product = new Dictionary<string, object?>(StringComparer.Ordinal)
        {
            ["name"] = name,
            ["barcode"] = "CURRENT-1",
            ["price"] = 12d,
            ["purchasePrice"] = 5d,
            ["wholesalePrice"] = 10d,
            ["damaged_quantity"] = 0L,
            ["quantity"] = quantity,
            ["is_active"] = 1L,
            ["stock_unit"] = "pcs"
        };
        var data = new Dictionary<string, object?>(StringComparer.Ordinal)
        {
            ["products"] = new List<object?> { product },
            ["parties"] = new List<object?>(),
            ["sales"] = new List<object?>(),
            ["sale_items"] = new List<object?>(),
            ["purchases"] = new List<object?>(),
            ["khata_transactions"] = new List<object?>(),
            ["expenses"] = new List<object?>(),
            ["reminders"] = new List<object?>(),
            ["sale_returns"] = new List<object?>(),
            ["sale_return_items"] = new List<object?>(),
            ["tombstones"] = new List<object?>()
        };
        return new ValidatedDriveSnapshot("android-device", hash, data, "{}");
    }

    private static async Task<string> CreateDriveMergeFixtureAsync()
    {
        var source = await CreateFixtureAsync();
        var directory = Path.Combine(Path.GetTempPath(), "khan-baba-drive-merge-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        var target = Path.Combine(directory, "khan_baba_pos.db");
        File.Copy(source, target);
        File.Delete(source);
        return target;
    }

    [Fact]
    public async Task DriveMergeCreatesConflictAndKeepWindowsPreservesLocalStock()
    {
        var path = await CreateDriveMergeFixtureAsync();
        try
        {
            await AddProductAsync(path, "Local Sugar", "CURRENT-1");
            var merge = new DriveSnapshotMergeService();
            var snapshot = CreateDriveProductSnapshot("Remote Sugar", 1, new string('a', 64));

            var result = await merge.MergeAsync(snapshot, "android-device", path,
                applyMasterState: false, detectConflicts: true);

            Assert.Equal(1, result.PendingConflicts);
            var conflicts = await merge.GetPendingConflictsAsync(path);
            var conflict = Assert.Single(conflicts);
            Assert.Equal("product", conflict.EntityType);

            await merge.ResolveConflictAsync(conflict.Id, useRemote: false, path);
            Assert.Empty(await merge.GetPendingConflictsAsync(path));

            await merge.MergeAsync(snapshot, "android-device", path,
                applyMasterState: false, detectConflicts: true);
            Assert.Empty(await merge.GetPendingConflictsAsync(path));

            await using var db = new SqliteConnection(new SqliteConnectionStringBuilder
            {
                DataSource = path, Mode = SqliteOpenMode.ReadOnly, Pooling = false
            }.ToString());
            await db.OpenAsync();
            await using var command = db.CreateCommand();
            command.CommandText = "SELECT quantity FROM products WHERE barcode='CURRENT-1';";
            Assert.Equal(3L, Convert.ToInt64(await command.ExecuteScalarAsync()));
        }
        finally
        {
            Directory.Delete(Path.GetDirectoryName(path)!, recursive: true);
        }
    }

    [Fact]
    public async Task DriveMergeAutomaticallyKeepsWindowsValueAndAuditsConflict()
    {
        var path = await CreateDriveMergeFixtureAsync();
        try
        {
            await AddProductAsync(path, "Local Sugar", "CURRENT-1");
            var merge = new DriveSnapshotMergeService();
            var snapshot = CreateDriveProductSnapshot("Remote Sugar", 1, new string('c', 64));

            var result = await merge.MergeAsync(snapshot, "android-device", path,
                applyMasterState: false, detectConflicts: true,
                autoResolveConflictsKeepWindows: true);

            Assert.Equal(0, result.PendingConflicts);
            Assert.True(result.SnapshotFullyAccepted);
            Assert.Empty(await merge.GetPendingConflictsAsync(path));

            await using var db = new SqliteConnection(new SqliteConnectionStringBuilder
            {
                DataSource = path, Mode = SqliteOpenMode.ReadOnly, Pooling = false
            }.ToString());
            await db.OpenAsync();
            await using var command = db.CreateCommand();
            command.CommandText = "SELECT quantity FROM products WHERE barcode='CURRENT-1';";
            Assert.Equal(3L, Convert.ToInt64(await command.ExecuteScalarAsync()));

            await using var audit = db.CreateCommand();
            audit.CommandText = "SELECT status || ':' || resolution FROM drive_sync_conflicts WHERE entity_type='product' AND entity_key='CURRENT-1' ORDER BY id DESC LIMIT 1;";
            Assert.Equal("resolved:keep_local", Convert.ToString(await audit.ExecuteScalarAsync()));
        }
        finally
        {
            Directory.Delete(Path.GetDirectoryName(path)!, recursive: true);
        }
    }

    [Fact]
    public async Task DriveMergeAppliesRemoteProductOnlyAfterAdminResolvesConflict()
    {
        var path = await CreateDriveMergeFixtureAsync();
        try
        {
            await AddProductAsync(path, "Local Sugar", "CURRENT-1");
            var merge = new DriveSnapshotMergeService();
            var snapshot = CreateDriveProductSnapshot("Remote Sugar", 1, new string('b', 64));

            var result = await merge.MergeAsync(snapshot, "android-device", path,
                applyMasterState: false, detectConflicts: true);
            Assert.Equal(1, result.PendingConflicts);

            var conflict = Assert.Single(await merge.GetPendingConflictsAsync(path));
            await merge.ResolveConflictAsync(conflict.Id, useRemote: true, path);
            Assert.Empty(await merge.GetPendingConflictsAsync(path));

            await using var db = new SqliteConnection(new SqliteConnectionStringBuilder
            {
                DataSource = path, Mode = SqliteOpenMode.ReadOnly, Pooling = false
            }.ToString());
            await db.OpenAsync();
            await using var command = db.CreateCommand();
            command.CommandText = "SELECT quantity FROM products WHERE barcode='CURRENT-1';";
            Assert.Equal(1L, Convert.ToInt64(await command.ExecuteScalarAsync()));
        }
        finally
        {
            Directory.Delete(Path.GetDirectoryName(path)!, recursive: true);
        }
    }


    [Fact]
    public async Task DriveSnapshotRoundTripImportsAllBusinessCollectionsMapsPartyAliasesAndIsIdempotent()
    {
        var directory = Path.Combine(Path.GetTempPath(), "khan-baba-drive-roundtrip-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        var sourceFixture = await CreateFixtureAsync();
        var targetFixture = await CreateFixtureAsync();
        var sourcePath = Path.Combine(directory, "source.db");
        var targetPath = Path.Combine(directory, "target.db");
        File.Copy(sourceFixture, sourcePath);
        File.Copy(targetFixture, targetPath);
        File.Delete(sourceFixture);
        File.Delete(targetFixture);

        try
        {
            long sourceCustomerId;
            long sourceSupplierId;
            long sourceProductId;
            long sourceSaleId;
            long sourceSaleItemId;
            long sourceReturnId;

            await using (var source = new SqliteConnection(new SqliteConnectionStringBuilder
            {
                DataSource = sourcePath, Pooling = false
            }.ToString()))
            {
                await source.OpenAsync();
                using var transaction = source.BeginTransaction();

                async Task<long> InsertAsync(string sql, params (string Name, object Value)[] values)
                {
                    await using var command = source.CreateCommand();
                    command.Transaction = transaction;
                    command.CommandText = sql;
                    foreach (var (name, value) in values) command.Parameters.AddWithValue(name, value);
                    return Convert.ToInt64(await command.ExecuteScalarAsync());
                }

                sourceProductId = await InsertAsync("""
                    INSERT INTO products(name,barcode,price,purchasePrice,wholesalePrice,damaged_quantity,quantity,is_active,stock_unit)
                    VALUES('Drive Roundtrip Tea','DRIVE-ROUND-1',20,10,18,0,8,1,'pcs');
                    SELECT last_insert_rowid();
                    """);
                sourceCustomerId = await InsertAsync("""
                    INSERT INTO parties(name,phone,type,customer_type,sync_id,balance)
                    VALUES('Drive Roundtrip Customer','03001234567','customer','Khata','remote-customer-sync',30);
                    SELECT last_insert_rowid();
                    """);
                sourceSupplierId = await InsertAsync("""
                    INSERT INTO parties(name,phone,type,customer_type,sync_id,balance)
                    VALUES('Drive Roundtrip Supplier','03007654321','supplier',NULL,'remote-supplier-sync',0);
                    SELECT last_insert_rowid();
                    """);
                sourceSaleId = await InsertAsync("""
                    INSERT INTO sales(total_amount,discount,final_amount,payment_type,customer_id,customer_type,received_amount,balance_due,sync_id,customer_sync_id,date)
                    VALUES(40,0,40,'Partial',$customer,'Khata',10,30,'remote-sale-sync','remote-customer-sync','2026-11-17 10:00:00');
                    SELECT last_insert_rowid();
                    """, ("$customer", sourceCustomerId));
                sourceSaleItemId = await InsertAsync("""
                    INSERT INTO sale_items(sale_id,product_id,barcode,product_name,quantity,sale_price,purchase_price,line_total,cost_total,sync_id,sale_sync_id,stock_unit)
                    VALUES($sale,$product,'DRIVE-ROUND-1','Drive Roundtrip Tea',2,20,10,40,20,'remote-sale-item-sync','remote-sale-sync','pcs');
                    SELECT last_insert_rowid();
                    """, ("$sale", sourceSaleId), ("$product", sourceProductId));
                await InsertAsync("""
                    INSERT INTO purchases(product_id,product_name,barcode,quantity,unit_cost,total_cost,supplier_id,sync_id,supplier_sync_id,date,unit_label,invoice_quantity,conversion_factor,base_unit,invoice_unit_cost)
                    VALUES($product,'Drive Roundtrip Tea','DRIVE-ROUND-1',4,10,40,$supplier,'remote-purchase-sync','remote-supplier-sync','2026-11-17 10:05:00','pcs',4,1,'pcs',10);
                    SELECT last_insert_rowid();
                    """, ("$product", sourceProductId), ("$supplier", sourceSupplierId));
                await InsertAsync("""
                    INSERT INTO khata_transactions(party_id,type,amount,note,date,sync_id,party_sync_id)
                    VALUES($customer,'receipt',10,'Drive roundtrip receipt','2026-11-17 10:06:00','remote-khata-sync','remote-customer-sync');
                    SELECT last_insert_rowid();
                    """, ("$customer", sourceCustomerId));
                await InsertAsync("""
                    INSERT INTO expenses(title,amount,date,sync_id)
                    VALUES('Drive roundtrip expense',5,'2026-11-17 10:07:00','remote-expense-sync');
                    SELECT last_insert_rowid();
                    """);
                await InsertAsync("""
                    INSERT INTO reminders(title,details,date,is_done,sync_id)
                    VALUES('Drive roundtrip reminder','Test reminder','2026-11-18 10:00:00',0,'remote-reminder-sync');
                    SELECT last_insert_rowid();
                    """);
                sourceReturnId = await InsertAsync("""
                    INSERT INTO sale_returns(sale_id,customer_id,reason,refund_method,refund_amount,date,sync_id,sale_sync_id,party_sync_id)
                    VALUES($sale,$customer,'Drive roundtrip test','Cash',5,'2026-11-17 10:08:00','remote-return-sync','remote-sale-sync','remote-customer-sync');
                    SELECT last_insert_rowid();
                    """, ("$sale", sourceSaleId), ("$customer", sourceCustomerId));
                await InsertAsync("""
                    INSERT INTO sale_return_items(return_id,sale_item_id,product_id,barcode,product_name,quantity,sale_price,purchase_price,line_total,cost_total,condition,sync_id,return_sync_id,sale_item_sync_id,stock_unit)
                    VALUES($return,$saleItem,$product,'DRIVE-ROUND-1','Drive Roundtrip Tea',1,20,10,20,10,'saleable','remote-return-item-sync','remote-return-sync','remote-sale-item-sync','pcs');
                    SELECT last_insert_rowid();
                    """, ("$return", sourceReturnId), ("$saleItem", sourceSaleItemId), ("$product", sourceProductId));
                await transaction.CommitAsync();
            }

            long targetCustomerId;
            await using (var target = new SqliteConnection(new SqliteConnectionStringBuilder
            {
                DataSource = targetPath, Pooling = false
            }.ToString()))
            {
                await target.OpenAsync();
                await using var command = target.CreateCommand();
                command.CommandText = """
                    INSERT INTO parties(name,phone,type,customer_type,sync_id,balance)
                    VALUES('Drive Roundtrip Customer','03001234567','customer','Khata','local-customer-sync',30);
                    SELECT last_insert_rowid();
                    """;
                targetCustomerId = Convert.ToInt64(await command.ExecuteScalarAsync());
            }

            var exported = await new DriveSnapshotExportService().ExportAsync(sourcePath);
            var snapshot = new ValidatedDriveSnapshot(
                "android-roundtrip-device", exported.Sha256, exported.Data, exported.Json);
            var service = new DriveSnapshotMergeService();

            var first = await service.MergeAsync(snapshot, snapshot.DeviceId, targetPath);
            Assert.True(first.SnapshotFullyAccepted);
            Assert.Equal(0, first.PendingConflicts);

            var second = await service.MergeAsync(snapshot, snapshot.DeviceId, targetPath);
            Assert.True(second.SnapshotFullyAccepted);

            await using var verify = new SqliteConnection(new SqliteConnectionStringBuilder
            {
                DataSource = targetPath, Mode = SqliteOpenMode.ReadOnly, Pooling = false
            }.ToString());
            await verify.OpenAsync();

            async Task<long> CountAsync(string table)
            {
                await using var command = verify.CreateCommand();
                command.CommandText = $"SELECT COUNT(*) FROM \"{table}\";";
                return Convert.ToInt64(await command.ExecuteScalarAsync());
            }

            Assert.Equal(1, await CountAsync("products"));
            Assert.Equal(2, await CountAsync("parties"));
            Assert.Equal(1, await CountAsync("sales"));
            Assert.Equal(1, await CountAsync("sale_items"));
            Assert.Equal(1, await CountAsync("purchases"));
            Assert.Equal(1, await CountAsync("khata_transactions"));
            Assert.Equal(1, await CountAsync("expenses"));
            Assert.Equal(1, await CountAsync("reminders"));
            Assert.Equal(1, await CountAsync("sale_returns"));
            Assert.Equal(1, await CountAsync("sale_return_items"));
            Assert.Equal(1, await CountAsync("drive_sync_aliases"));

            await using (var relations = verify.CreateCommand())
            {
                relations.CommandText = """
                    SELECT
                      (SELECT customer_id FROM sales WHERE sync_id='remote-sale-sync'),
                      (SELECT party_id FROM khata_transactions WHERE sync_id='remote-khata-sync'),
                      (SELECT supplier_id FROM purchases WHERE sync_id='remote-purchase-sync'),
                      (SELECT sale_item_id FROM sale_return_items WHERE sync_id='remote-return-item-sync'),
                      (SELECT id FROM sale_items WHERE sync_id='remote-sale-item-sync');
                    """;
                await using var reader = await relations.ExecuteReaderAsync();
                Assert.True(await reader.ReadAsync());
                Assert.Equal(targetCustomerId, reader.GetInt64(0));
                Assert.Equal(targetCustomerId, reader.GetInt64(1));
                Assert.True(reader.GetInt64(2) > 0);
                Assert.Equal(reader.GetInt64(4), reader.GetInt64(3));
            }
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }

}
