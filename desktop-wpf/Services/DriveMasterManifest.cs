using System.IO;
using System.Text.Json;

namespace KhanBabaPos.Wpf.Services;

/// <summary>
/// Deterministic Windows-master manifest state matching the Android Drive protocol.
/// It tracks accepted device snapshot hashes and local pre-merge backup filenames.
/// </summary>
public sealed class DriveMasterManifest
{
    private readonly Dictionary<string, string> _processedSnapshots;
    private readonly Dictionary<string, string> _preMergeBackups;
    private readonly Dictionary<string, string> _preMergeBackupHashes;

    private DriveMasterManifest(string masterDeviceId, Dictionary<string, string> processedSnapshots,
        Dictionary<string, string> preMergeBackups, Dictionary<string, string> preMergeBackupHashes)
    {
        MasterDeviceId = masterDeviceId;
        _processedSnapshots = processedSnapshots;
        _preMergeBackups = preMergeBackups;
        _preMergeBackupHashes = preMergeBackupHashes;
    }

    public string MasterDeviceId { get; }
    public IReadOnlyDictionary<string, string> ProcessedSnapshots => _processedSnapshots;
    public IReadOnlyDictionary<string, string> PreMergeBackups => _preMergeBackups;
    public IReadOnlyDictionary<string, string> PreMergeBackupHashes => _preMergeBackupHashes;

    public static DriveMasterManifest Empty(string masterDeviceId)
    {
        if (string.IsNullOrWhiteSpace(masterDeviceId))
            throw new ArgumentException("Master device ID is required.", nameof(masterDeviceId));
        return new DriveMasterManifest(masterDeviceId, new(StringComparer.Ordinal),
            new(StringComparer.Ordinal), new(StringComparer.Ordinal));
    }

    public static DriveMasterManifest Parse(string json)
    {
        _ = DriveSnapshotEnvelopeValidator.ValidateMasterEnvelope(json);
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        var masterId = root.GetProperty("masterDeviceId").GetString()!;
        var processed = ReadStringMap(root, "processedSnapshots");
        var backups = ReadStringMap(root, "preMergeBackups");
        var backupHashes = ReadStringMap(root, "preMergeBackupHashes");
        foreach (var (deviceId, hash) in backupHashes)
        {
            if (string.IsNullOrWhiteSpace(deviceId) || !IsValidHash(hash))
                throw new FormatException("Master preMergeBackupHashes must contain valid device IDs and SHA-256 hashes.");
        }
        foreach (var (deviceId, fileName) in backups)
        {
            if (string.IsNullOrWhiteSpace(deviceId) || string.IsNullOrWhiteSpace(fileName) ||
                Path.GetFileName(fileName) != fileName || fileName is "." or "..")
                throw new FormatException("Master preMergeBackups must contain safe backup filenames only.");
        }
        return new DriveMasterManifest(masterId, processed, backups, backupHashes);
    }

    public bool IsProcessed(string deviceId, string snapshotHash) =>
        _processedSnapshots.TryGetValue(deviceId, out var processedHash) &&
        string.Equals(processedHash, snapshotHash, StringComparison.OrdinalIgnoreCase);

    public void MarkProcessed(string deviceId, string snapshotHash)
    {
        RequireKey(deviceId, nameof(deviceId));
        RequireHash(snapshotHash);
        _processedSnapshots[deviceId] = snapshotHash.ToLowerInvariant();
    }

    public void MarkPending(string deviceId)
    {
        RequireKey(deviceId, nameof(deviceId));
        _processedSnapshots.Remove(deviceId);
    }

    public string? GetPreMergeBackup(string deviceId) =>
        _preMergeBackups.TryGetValue(deviceId, out var fileName) ? fileName : null;

    public string? GetPreMergeBackupHash(string deviceId) =>
        _preMergeBackupHashes.TryGetValue(deviceId, out var hash) ? hash : null;

    public bool HasPreMergeBackupForSnapshot(string deviceId, string snapshotHash) =>
        _preMergeBackupHashes.TryGetValue(deviceId, out var hash) &&
        string.Equals(hash, snapshotHash, StringComparison.OrdinalIgnoreCase);

    public void SetPreMergeBackup(string deviceId, string fileName, string? snapshotHash = null)
    {
        RequireKey(deviceId, nameof(deviceId));
        if (string.IsNullOrWhiteSpace(fileName) || Path.GetFileName(fileName) != fileName || fileName is "." or "..")
            throw new ArgumentException("Only a backup filename, not a local path, may be stored in the cloud manifest.", nameof(fileName));
        if (snapshotHash is not null) RequireHash(snapshotHash);
        _preMergeBackups[deviceId] = fileName;
        if (snapshotHash is not null)
            _preMergeBackupHashes[deviceId] = snapshotHash.ToLowerInvariant();
    }

    public string ToJson(JsonElement masterData, string snapshotHash, DateTimeOffset updatedAtUtc)
    {
        RequireHash(snapshotHash);
        if (masterData.ValueKind != JsonValueKind.Object)
            throw new ArgumentException("Master snapshot data must be a JSON object.", nameof(masterData));
        var envelope = new
        {
            schemaVersion = 2,
            masterDeviceId = MasterDeviceId,
            processedSnapshots = _processedSnapshots,
            preMergeBackups = _preMergeBackups,
            preMergeBackupHashes = _preMergeBackupHashes,
            data = masterData,
            snapshotHash = snapshotHash.ToLowerInvariant(),
            updatedAt = updatedAtUtc.ToUniversalTime().ToString("O")
        };
        var json = JsonSerializer.Serialize(envelope);
        _ = DriveSnapshotEnvelopeValidator.ValidateMasterEnvelope(json);
        return json;
    }

    private static Dictionary<string, string> ReadStringMap(JsonElement root, string name)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        if (!root.TryGetProperty(name, out var map) || map.ValueKind != JsonValueKind.Object) return result;
        foreach (var item in map.EnumerateObject())
        {
            if (item.Value.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(item.Value.GetString()))
                throw new FormatException($"Master manifest '{name}' contains an invalid entry.");
            result[item.Name] = item.Value.GetString()!;
        }
        return result;
    }

    private static void RequireKey(string value, string parameterName)
    {
        if (string.IsNullOrWhiteSpace(value)) throw new ArgumentException("Manifest key is required.", parameterName);
    }

    private static bool IsValidHash(string value) =>
        value.Length == 64 && value.All(Uri.IsHexDigit);

    private static void RequireHash(string value)
    {
        if (!IsValidHash(value))
            throw new ArgumentException("Snapshot hash must be a 64-character SHA-256 hexadecimal value.", nameof(value));
    }
}
