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
