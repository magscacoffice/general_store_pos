using System.IO;
using System.Net.NetworkInformation;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Windows.Threading;
using KhanBabaPos.Wpf.Data;

namespace KhanBabaPos.Wpf.Services;

/// <summary>
/// Native Windows-master Drive v2 protocol orchestration. Uploads this Windows
/// device snapshot, imports other device snapshots transactionally, then publishes
/// the master manifest/snapshot. No Firebase or Android authentication is used.
/// </summary>
public sealed class WindowsDriveSyncService
{
    private static readonly byte[] DeviceEntropy = Encoding.UTF8.GetBytes("KhanBabaPOS.Windows.DriveDeviceId.v1");
    // Owner explicitly approved enabling Windows-master Google Drive sync.
    // All imports still pass envelope/hash/schema validation and transactional
    // merge; a verified pre-merge backup is required before any import.
    private static readonly bool EnableDriveSync = true;
    private static readonly bool EnableDeviceSnapshotImports = true;
    private readonly AccessService _access;
    private readonly GoogleDriveAuthService _auth = new();
    private readonly GoogleDriveApiClient _drive;
    private readonly DriveSnapshotExportService _export = new();
    private readonly DriveSnapshotMergeService _merge = new();
    private readonly DatabaseBackupService _backups = new();
    private readonly SemaphoreSlim _syncGate = new(1, 1);
    private DispatcherTimer? _timer;

    public bool IsEnabled => EnableDriveSync;
    public string Status { get; private set; } =
        "Google Drive is enabled. Connect as Admin to start the Windows-master sync.";
    public string? LastError { get; private set; }
    public DateTimeOffset? LastSyncAtUtc { get; private set; }
    public bool HasSavedCredentials => _auth.HasSavedCredentials;
    public event Action? StatusChanged;

    public WindowsDriveSyncService(AccessService access)
    {
        _access = access ?? throw new ArgumentNullException(nameof(access));
        _drive = new GoogleDriveApiClient(_auth);
    }

    public async Task<DriveSyncSummary> ConnectAndSyncAsync(string? databasePath = null, CancellationToken cancellationToken = default)
    {
        _access.RequireAdmin();
        EnsureDriveSyncEnabled();
        await _auth.GetAccessTokenAsync(promptForLogin: true, cancellationToken);
        StartAutoSync();
        return await SyncNowAsync(databasePath, cancellationToken);
    }

    public async Task<DriveSyncSummary> SyncNowAsync(string? databasePath = null, CancellationToken cancellationToken = default)
    {
        _access.RequireAdmin();
        EnsureDriveSyncEnabled();
        await _syncGate.WaitAsync(cancellationToken);
        try
        {
            var path = databasePath ?? PosDatabasePath.Resolve(requireExisting: true);
            SetStatus("Connecting to Google Drive...");
            LastError = null;
            await _auth.GetAccessTokenAsync(promptForLogin: false, cancellationToken);
            var folderId = await _drive.EnsureFolderAsync(cancellationToken);
            var deviceId = GetOrCreateDeviceId();

            SetStatus("Preparing Windows device snapshot...");
            var localSnapshot = await _export.ExportAsync(path, cancellationToken);
            var deviceEnvelope = new
            {
                schemaVersion = 2,
                deviceId,
                snapshotHash = localSnapshot.Sha256,
                data = localSnapshot.Data,
                uploadedAt = DateTimeOffset.UtcNow.ToString("O")
            };

            var files = await _drive.ListFilesAsync(folderId, cancellationToken);
            await _drive.UploadJsonAsync(folderId, $"device_{deviceId}.json", deviceEnvelope, files, cancellationToken);
            files = await _drive.ListFilesAsync(folderId, cancellationToken);

            var masterFile = files.FirstOrDefault(x => x.Name == "master_snapshot.json");
            var manifest = masterFile is null
                ? DriveMasterManifest.Empty(deviceId)
                : await DownloadManifestAsync(masterFile.Id, cancellationToken);

            var imported = 0;
            var skipped = 0;
            var pendingConflicts = 0;
            var backupDirectory = Path.Combine(Path.GetDirectoryName(path)!, "Backups");
            Directory.CreateDirectory(backupDirectory);

            if (EnableDeviceSnapshotImports)
            {
                foreach (var file in files.Where(x =>
                             x.Name.StartsWith("device_", StringComparison.Ordinal) &&
                             x.Name.EndsWith(".json", StringComparison.Ordinal) &&
                             x.Name != $"device_{deviceId}.json"))
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    SetStatus($"Checking {file.Name}...");
                    using var document = await _drive.DownloadJsonAsync(file.Id, cancellationToken);
                    var validated = DriveSnapshotEnvelopeValidator.ValidateDeviceEnvelope(document.RootElement.GetRawText());
                    if (manifest.IsProcessed(validated.DeviceId, validated.SnapshotHash))
                    {
                        skipped++;
                        continue;
                    }
    
                    var backupName = manifest.GetPreMergeBackup(validated.DeviceId);
                    var backupPath = string.IsNullOrWhiteSpace(backupName)
                        ? null
                        : Path.Combine(backupDirectory, backupName);
                    var backupVerified = backupPath is not null &&
                                         await _backups.IsVerifiedBackupAsync(backupPath, cancellationToken);
                    var backupMatchesSnapshot = manifest.HasPreMergeBackupForSnapshot(
                        validated.DeviceId, validated.SnapshotHash);
                    if (!backupVerified || !backupMatchesSnapshot)
                    {
                        SetStatus($"Creating verified safety backup before importing {validated.DeviceId}...");
                        var createdBackupPath = await _backups.CreateBackupAsync(path, backupDirectory, cancellationToken);
                        manifest.SetPreMergeBackup(validated.DeviceId,
                            Path.GetFileName(createdBackupPath), validated.SnapshotHash);
                    }
    
                    SetStatus($"Merging records from {validated.DeviceId}...");
                    var result = await _merge.MergeAsync(validated, validated.DeviceId, path,
                        applyMasterState: false, detectConflicts: true, cancellationToken);
                    imported++;
                    pendingConflicts += result.PendingConflicts;
                    if (result.SnapshotFullyAccepted)
                        manifest.MarkProcessed(validated.DeviceId, validated.SnapshotHash);
                    else
                        manifest.MarkPending(validated.DeviceId);
                }
    
            }
            else
            {
                skipped = files.Count(x => x.Name.StartsWith("device_", StringComparison.Ordinal) &&
                    x.Name.EndsWith(".json", StringComparison.Ordinal) && x.Name != $"device_{deviceId}.json");
            }


            SetStatus("Publishing updated Windows master snapshot...");
            var masterSnapshot = await _export.ExportAsync(path, cancellationToken);
            using var masterData = JsonDocument.Parse(masterSnapshot.Json);
            var masterJson = manifest.ToJson(masterData.RootElement, masterSnapshot.Sha256, DateTimeOffset.UtcNow);
            using var masterDocument = JsonDocument.Parse(masterJson);
            files = await _drive.ListFilesAsync(folderId, cancellationToken);
            await _drive.UploadJsonAsync(folderId, "master_snapshot.json", masterDocument.RootElement, files, cancellationToken);

            LastSyncAtUtc = DateTimeOffset.UtcNow;
            LastError = null;
            var remaining = await _merge.GetPendingConflictsAsync(path, cancellationToken);
            pendingConflicts = remaining.Count;
            var summary = new DriveSyncSummary(imported, skipped, pendingConflicts, LastSyncAtUtc.Value);
            SetStatus(pendingConflicts > 0
                    ? $"Windows master synced. {pendingConflicts} conflict(s) require Admin review."
                    : $"Windows master synced successfully at {LastSyncAtUtc.Value.LocalDateTime:t}.");
            return summary;
        }
        catch (Exception ex)
        {
            LastError = ex.Message;
            SetStatus("Google Drive sync failed: " + ex.Message);
            throw;
        }
        finally
        {
            _syncGate.Release();
        }
    }

    public async Task<IReadOnlyList<DriveConflictRow>> GetPendingConflictsAsync(string? databasePath = null, CancellationToken cancellationToken = default)
    {
        _access.RequireAdmin();
        return await _merge.GetPendingConflictsAsync(databasePath ?? PosDatabasePath.Resolve(requireExisting: true), cancellationToken);
    }

    public async Task ResolveConflictAsync(long conflictId, bool useRemote, string? databasePath = null, CancellationToken cancellationToken = default)
    {
        _access.RequireAdmin();
        EnsureDriveSyncEnabled();
        await _merge.ResolveConflictAsync(conflictId, useRemote,
            databasePath ?? PosDatabasePath.Resolve(requireExisting: true), cancellationToken);
        var count = (await GetPendingConflictsAsync(databasePath, cancellationToken)).Count;
        SetStatus(count == 0 ? "All Drive conflicts resolved." : $"{count} Drive conflict(s) still need review.");
    }

    public async Task DisconnectAsync(CancellationToken cancellationToken = default)
    {
        _access.RequireAdmin();
        StopAutoSync();
        await _auth.DisconnectAsync(cancellationToken);
        LastError = null;
        SetStatus("Google Drive disconnected. POS remains available offline.");
    }

    public void StartAutoSync()
    {
        if (!EnableDriveSync)
        {
            StopAutoSync();
            SetStatus("Google Drive is enabled; connect as Admin to authorize sync. Local POS remains available offline.");
            return;
        }
        if (!HasSavedCredentials || _timer is not null || _access.CurrentSession?.Role != AccessRole.Admin) return;
        _timer = new DispatcherTimer { Interval = TimeSpan.FromMinutes(2) };
        _timer.Tick += async (_, _) =>
        {
            if (_access.CurrentSession?.Role != AccessRole.Admin) { StopAutoSync(); SetStatus("Admin session expired — Drive auto-sync paused."); return; }
            if (_syncGate.CurrentCount == 0) return;
            if (!NetworkInterface.GetIsNetworkAvailable())
            {
                SetStatus("Offline — local POS available; Drive sync will retry.");
                return;
            }
            try { await SyncNowAsync(); }
            catch { /* LastError and Status are exposed to the sync window. */ }
        };
        _timer.Start();
    }

    public void StopAutoSync()
    {
        if (_timer is null) return;
        _timer.Stop();
        _timer = null;
    }

    private async Task<DriveMasterManifest> DownloadManifestAsync(string fileId, CancellationToken cancellationToken)
    {
        using var document = await _drive.DownloadJsonAsync(fileId, cancellationToken);
        return DriveMasterManifest.Parse(document.RootElement.GetRawText());
    }

    private static string GetOrCreateDeviceId()
    {
        var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "KhanBabaPOS");
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, "drive_device_id.dat");
        if (File.Exists(path))
        {
            var clear = ProtectedData.Unprotect(File.ReadAllBytes(path), DeviceEntropy, DataProtectionScope.CurrentUser);
            var saved = Encoding.UTF8.GetString(clear).Trim();
            if (Guid.TryParseExact(saved, "N", out _)) return saved;
            throw new InvalidDataException("Windows Drive device ID file is invalid. Do not delete it until a safety backup is made.");
        }

        var id = Guid.NewGuid().ToString("N");
        var encrypted = ProtectedData.Protect(Encoding.UTF8.GetBytes(id), DeviceEntropy, DataProtectionScope.CurrentUser);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        File.WriteAllBytes(temporary, encrypted);
        File.Move(temporary, path);
        return id;
    }

    private static void EnsureDriveSyncEnabled()
    {
        if (!EnableDriveSync)
            throw new InvalidOperationException("Google Drive sync is disabled in this build.");
    }

    private void SetStatus(string value)
    {
        Status = value;
        StatusChanged?.Invoke();
    }
}

public sealed record DriveSyncSummary(int ImportedDeviceSnapshots, int SkippedProcessedSnapshots,
    int PendingConflicts, DateTimeOffset SyncedAtUtc);
