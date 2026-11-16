using System.IO;
using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;

namespace KhanBabaPos.Wpf.Services;

/// <summary>Creates a fresh verified copy before the Drive exporter repairs legacy sync IDs.</summary>
internal static class DatabaseBackupServiceForDrive
{
    public static async Task CreateBeforeIdentityRepairAsync(
        string databasePath, CancellationToken cancellationToken)
    {
        AccessService.RequireCurrentAdmin();
        await PosDatabaseSchemaVerifier.VerifyAsync(databasePath, cancellationToken);
        var directory = Path.Combine(Path.GetDirectoryName(databasePath)!, "Backups");
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory,
            $"khan_baba_pos_before_drive_ids_{DateTime.UtcNow:yyyyMMdd_HHmmss}_{Guid.NewGuid():N}.db");
        await using var source = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = databasePath, Mode = SqliteOpenMode.ReadOnly, Pooling = false
        }.ToString());
        await using var destination = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = path, Mode = SqliteOpenMode.ReadWriteCreate, Pooling = false
        }.ToString());
        await source.OpenAsync(cancellationToken);
        await destination.OpenAsync(cancellationToken);
        source.BackupDatabase(destination);
        await destination.CloseAsync();
        await PosDatabaseSchemaVerifier.VerifyAsync(path, cancellationToken);
        var hash = await DatabaseBackupService.ComputeSha256Async(path, cancellationToken);
        await File.WriteAllTextAsync(path + ".sha256", hash, cancellationToken);
    }
}
