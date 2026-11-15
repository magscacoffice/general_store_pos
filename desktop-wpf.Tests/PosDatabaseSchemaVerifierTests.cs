using System.Security.Cryptography;
using System.Text.RegularExpressions;
using Microsoft.Data.Sqlite;
using Xunit;
using KhanBabaPos.Wpf.Data;
using KhanBabaPos.Wpf.Services;

namespace KhanBabaPos.Wpf.Tests;

public sealed class PosDatabaseSchemaVerifierTests
{
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
                INSERT INTO products
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
            var service = new SalePostingService();
            var partial = await service.CompleteSaleAsync(
                new SaleCheckoutRequest(
                    [new SaleLineInput("WPF-WH-1", 2, 18)],
                    customerId,
                    "Partial",
                    10,
                    10,
                    true,
                    "Wholesale",
                    "WPF Test Cashier"),
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
                    "WPF Test Cashier"),
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
    public async Task WpfWholesaleSaleRejectsKhataAccountBeforeChangingStock()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            var customerId = await SeedSaleAccountAsync(path, "Khata", 5);
            var service = new SalePostingService();
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
    public async Task WpfKhataReceiptReducesOutstandingBalanceAndRejectsOverpayment()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            var customerId = await SeedSaleAccountAsync(path, "Khata", 5);
            await new SalePostingService().CompleteSaleAsync(
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
            var sale = await new SalePostingService().CompleteSaleAsync(
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
    public async Task WpfSalesReportAndProfitLossIncludeDiscountsReturnsPurchasesAndExpenses()
    {
        var path = await CreateDisposableDatabaseAsync();
        var directory = Path.GetDirectoryName(path)!;
        try
        {
            var customerId = await SeedSaleAccountAsync(path, "Wholesale", 10);
            var sale = await new SalePostingService().CompleteSaleAsync(
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
            await new SalePostingService().CompleteSaleAsync(
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
}
