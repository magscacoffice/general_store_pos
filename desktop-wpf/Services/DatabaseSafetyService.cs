using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;

namespace KhanBabaPos.Wpf.Services;

/// <summary>
/// Creates and verifies a one-time pre-WPF backup before the first WPF database write.
/// Existing backup files are never overwritten or deleted.
/// </summary>
public static class DatabaseSafetyService
{
    private const string MarkerName = ".wpf_initial_backup_verified";

    public static async Task<string> EnsureVerifiedBackupAsync(
        string databasePath, CancellationToken cancellationToken = default)
    {
        await PosDatabaseSchemaVerifier.VerifyAsync(databasePath, cancellationToken);
        var dataDirectory = Path.GetDirectoryName(databasePath)
            ?? throw new InvalidOperationException("Database directory could not be resolved.");
        var markerPath = Path.Combine(dataDirectory, MarkerName);

        if (File.Exists(markerPath))
        {
            try
            {
                var marker = JsonSerializer.Deserialize<BackupMarker>(
                    await File.ReadAllTextAsync(markerPath, cancellationToken));
                if (marker is not null && Path.GetFileName(marker.FileName) == marker.FileName)
                {
                    var existingBackup = Path.Combine(dataDirectory, "Backups", marker.FileName);
                    if (File.Exists(existingBackup) &&
                        await VerifyBackupAsync(existingBackup, marker.Sha256, cancellationToken))
                        return existingBackup;
                }
            }
            catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException)
            {
                // A missing/corrupt marker is repaired only after a new backup is fully verified.
            }
        }

        var backupDirectory = Path.Combine(dataDirectory, "Backups");
        Directory.CreateDirectory(backupDirectory);
        var fileName = $"khan_baba_pos_pre_wpf_{DateTime.Now:yyyyMMdd_HHmmss}_{Guid.NewGuid():N}.db";
        var backupPath = Path.Combine(backupDirectory, fileName);

        await using (var source = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = databasePath,
            Mode = SqliteOpenMode.ReadOnly,
            Pooling = false
        }.ToString()))
        await using (var destination = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = backupPath,
            Mode = SqliteOpenMode.ReadWriteCreate,
            Pooling = false
        }.ToString()))
        {
            await source.OpenAsync(cancellationToken);
            await destination.OpenAsync(cancellationToken);
            source.BackupDatabase(destination);
            await destination.CloseAsync();
        }

        var sha256 = await ComputeSha256Async(backupPath, cancellationToken);
        if (!await VerifyBackupAsync(backupPath, sha256, cancellationToken))
            throw new IOException("Pre-WPF backup verification failed. Database write was blocked.");

        var markerContent = JsonSerializer.Serialize(new BackupMarker(fileName, sha256, PosDatabaseSchemaVerifier.Version));
        var temporaryMarker = markerPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        await File.WriteAllTextAsync(temporaryMarker, markerContent, cancellationToken);
        File.Move(temporaryMarker, markerPath, overwrite: true);
        return backupPath;
    }

    private static async Task<bool> VerifyBackupAsync(
        string backupPath, string expectedSha256, CancellationToken cancellationToken)
    {
        try
        {
            await PosDatabaseSchemaVerifier.VerifyAsync(backupPath, cancellationToken);
            await using var connection = new SqliteConnection(new SqliteConnectionStringBuilder
            {
                DataSource = backupPath,
                Mode = SqliteOpenMode.ReadOnly,
                Pooling = false
            }.ToString());
            await connection.OpenAsync(cancellationToken);
            await using var integrity = connection.CreateCommand();
            integrity.CommandText = "PRAGMA integrity_check;";
            var result = Convert.ToString(await integrity.ExecuteScalarAsync(cancellationToken));
            if (!string.Equals(result, "ok", StringComparison.OrdinalIgnoreCase)) return false;
            var actualSha256 = await ComputeSha256Async(backupPath, cancellationToken);
            return CryptographicOperations.FixedTimeEquals(
                Convert.FromHexString(actualSha256), Convert.FromHexString(expectedSha256));
        }
        catch (Exception ex) when (ex is IOException or SqliteException or InvalidDataException or FormatException)
        {
            return false;
        }
    }

    private static async Task<string> ComputeSha256Async(string path, CancellationToken cancellationToken)
    {
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read,
            bufferSize: 81920, useAsync: true);
        var hash = await SHA256.HashDataAsync(stream, cancellationToken);
        return Convert.ToHexString(hash);
    }

    private sealed record BackupMarker(string FileName, string Sha256, int SchemaVersion);
}
