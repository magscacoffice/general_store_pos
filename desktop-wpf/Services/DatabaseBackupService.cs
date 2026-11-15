using System.IO;
using System.Globalization;
using System.Security.Cryptography;
using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;

namespace KhanBabaPos.Wpf.Services;

/// <summary>
/// Creates verified copies and restores to a new database file. The live file is
/// never overwritten; restore activates a verified staged file via .active_database.
/// </summary>
public sealed class DatabaseBackupService
{
    public async Task<string> CreateBackupAsync(
        string databasePath,
        string backupDirectory,
        CancellationToken cancellationToken = default)
    {
        await PosDatabaseSchemaVerifier.VerifyAsync(databasePath, cancellationToken);
        Directory.CreateDirectory(backupDirectory);
        var name = $"khan_baba_pos_backup_{DateTime.Now:yyyyMMdd_HHmmss}_{Guid.NewGuid():N}.db";
        var destination = Path.Combine(backupDirectory, name);
        await CopyDatabaseAsync(databasePath, destination, cancellationToken);
        await PosDatabaseSchemaVerifier.VerifyAsync(destination, cancellationToken);
        var hash = await ComputeSha256Async(destination, cancellationToken);
        await File.WriteAllTextAsync(destination + ".sha256", hash, cancellationToken);
        return destination;
    }

    public async Task<string> RestoreAsync(
        string currentDatabasePath,
        string selectedBackupPath,
        string dataDirectory,
        CancellationToken cancellationToken = default)
    {
        if (!File.Exists(currentDatabasePath))
            throw new FileNotFoundException("Current POS database was not found; restore was not started.", currentDatabasePath);
        if (!File.Exists(selectedBackupPath))
            throw new FileNotFoundException("Selected backup file was not found.", selectedBackupPath);
        if (string.Equals(Path.GetFullPath(currentDatabasePath), Path.GetFullPath(selectedBackupPath),
                StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Current live database cannot be selected as its own restore source.");

        await PosDatabaseSchemaVerifier.VerifyAsync(currentDatabasePath, cancellationToken);
        await PosDatabaseSchemaVerifier.VerifyAsync(selectedBackupPath, cancellationToken);
        var sidecarPath = selectedBackupPath + ".sha256";
        if (File.Exists(sidecarPath))
        {
            var expectedHash = (await File.ReadAllTextAsync(sidecarPath, cancellationToken)).Trim();
            var actualHash = await ComputeSha256Async(selectedBackupPath, cancellationToken);
            if (expectedHash.Length != 64 ||
                !CryptographicOperations.FixedTimeEquals(
                    Convert.FromHexString(expectedHash), Convert.FromHexString(actualHash)))
                throw new InvalidDataException("Selected backup SHA-256 verification failed. Active database was not changed.");
        }

        // A fresh, verified backup of the current database is mandatory before pointer change.
        await CreateBackupAsync(currentDatabasePath, Path.Combine(dataDirectory, "Backups"), cancellationToken);

        var stagedName = $"khan_baba_pos_restored_{DateTime.Now:yyyyMMdd_HHmmss}_{Guid.NewGuid():N}.db";
        var stagedPath = Path.Combine(dataDirectory, stagedName);
        var sourceHashBefore = await ComputeSha256Async(selectedBackupPath, cancellationToken);
        await CopyDatabaseAsync(selectedBackupPath, stagedPath, cancellationToken);
        await PosDatabaseSchemaVerifier.VerifyAsync(stagedPath, cancellationToken);
        var sourceHashAfter = await ComputeSha256Async(selectedBackupPath, cancellationToken);
        if (!CryptographicOperations.FixedTimeEquals(
                Convert.FromHexString(sourceHashBefore), Convert.FromHexString(sourceHashAfter)))
            throw new IOException("Selected backup changed while restore was being staged.");

        var pointer = Path.Combine(dataDirectory, ".active_database");
        var temporaryPointer = pointer + "." + Guid.NewGuid().ToString("N") + ".tmp";
        await File.WriteAllTextAsync(temporaryPointer, stagedName, cancellationToken);
        File.Move(temporaryPointer, pointer, overwrite: true);
        return stagedPath;
    }

    public static IReadOnlyList<BackupFileInfo> ListBackups(string dataDirectory)
    {
        var directory = Path.Combine(dataDirectory, "Backups");
        if (!Directory.Exists(directory)) return [];
        return Directory.EnumerateFiles(directory, "*.db")
            .Select(path => new FileInfo(path))
            .OrderByDescending(file => file.LastWriteTimeUtc)
            .Select(file => new BackupFileInfo(file.FullName, file.Name, file.Length, file.LastWriteTime))
            .ToArray();
    }

    public static async Task<string> ComputeSha256Async(string path, CancellationToken cancellationToken = default)
    {
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read,
            bufferSize: 81920, useAsync: true);
        return Convert.ToHexString(await SHA256.HashDataAsync(stream, cancellationToken));
    }

    private static async Task CopyDatabaseAsync(
        string sourcePath,
        string destinationPath,
        CancellationToken cancellationToken)
    {
        await using var source = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = sourcePath,
            Mode = SqliteOpenMode.ReadOnly,
            Pooling = false
        }.ToString());
        await using var destination = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = destinationPath,
            Mode = SqliteOpenMode.ReadWriteCreate,
            Pooling = false
        }.ToString());
        await source.OpenAsync(cancellationToken);
        await destination.OpenAsync(cancellationToken);
        source.BackupDatabase(destination);
        await destination.CloseAsync();
    }
}

public sealed record BackupFileInfo(string Path, string Name, long SizeBytes, DateTime LastModified)
{
    public string DisplaySize => SizeBytes < 1024 * 1024
        ? (SizeBytes / 1024d).ToString("N1", CultureInfo.InvariantCulture) + " KB"
        : (SizeBytes / (1024d * 1024d)).ToString("N1", CultureInfo.InvariantCulture) + " MB";
}
