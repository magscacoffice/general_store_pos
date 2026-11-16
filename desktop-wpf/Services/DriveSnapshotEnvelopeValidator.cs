using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace KhanBabaPos.Wpf.Services;

/// <summary>
/// Validates the Android schema-v2 Drive envelope before any database mutation.
/// Hashes are calculated over the compact data object, not the outer envelope.
/// </summary>
public static class DriveSnapshotEnvelopeValidator
{
    private static readonly string[] RequiredCollections =
    [
        "products", "parties", "sales", "sale_items", "purchases",
        "khata_transactions", "expenses", "reminders", "sale_returns",
        "sale_return_items", "tombstones"
    ];

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        WriteIndented = false,
        Converters = { new DartCompatibleDoubleConverter() }
    };

    public static ValidatedDriveSnapshot ValidateDeviceEnvelope(string json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object ||
            !root.TryGetProperty("schemaVersion", out var version) ||
            version.GetInt32() != 2)
            throw new FormatException("Unsupported Google Drive device envelope version.");

        var deviceId = RequiredString(root, "deviceId");
        var expectedHash = RequiredString(root, "snapshotHash");
        if (!root.TryGetProperty("data", out var data) || data.ValueKind != JsonValueKind.Object)
            throw new FormatException("Google Drive envelope data is missing or invalid.");

        var snapshot = ConvertElement(data) as Dictionary<string, object?>
            ?? throw new FormatException("Google Drive snapshot data must be an object.");
        ValidateCollections(snapshot);
        var compactJson = JsonSerializer.Serialize(snapshot, JsonOptions);
        var actualHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(compactJson)))
            .ToLowerInvariant();
        if (!CryptographicOperations.FixedTimeEquals(
                Encoding.ASCII.GetBytes(expectedHash.ToLowerInvariant()),
                Encoding.ASCII.GetBytes(actualHash)))
            throw new FormatException("Google Drive device snapshot checksum mismatch.");

        return new ValidatedDriveSnapshot(deviceId, expectedHash.ToLowerInvariant(), snapshot, compactJson);
    }

    public static ValidatedDriveSnapshot ValidateMasterEnvelope(string json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object ||
            !root.TryGetProperty("schemaVersion", out var version) ||
            version.GetInt32() != 2)
            throw new FormatException("Unsupported Google Drive master envelope version.");

        _ = RequiredString(root, "masterDeviceId");
        if (!root.TryGetProperty("processedSnapshots", out var processed) ||
            processed.ValueKind != JsonValueKind.Object)
            throw new FormatException("Master processedSnapshots manifest is missing.");
        foreach (var entry in processed.EnumerateObject())
        {
            if (string.IsNullOrWhiteSpace(entry.Name) ||
                entry.Value.ValueKind != JsonValueKind.String ||
                string.IsNullOrWhiteSpace(entry.Value.GetString()))
                throw new FormatException("Master processedSnapshots manifest contains an invalid entry.");
        }

        // Master uses the same data/hash contract as a device envelope.
        var normalized = new Dictionary<string, object?>
        {
            ["schemaVersion"] = 2,
            ["deviceId"] = "windows-master",
            ["snapshotHash"] = RequiredString(root, "snapshotHash"),
            ["data"] = root.TryGetProperty("data", out var data)
                ? ConvertElement(data)
                : throw new FormatException("Master snapshot data is missing.")
        };
        return ValidateDeviceEnvelope(JsonSerializer.Serialize(normalized, JsonOptions));
    }

    private static void ValidateCollections(Dictionary<string, object?> data)
    {
        foreach (var name in RequiredCollections)
        {
            if (!data.TryGetValue(name, out var value) || value is not List<object?>)
                throw new FormatException($"Cloud snapshot collection is missing or invalid: {name}");
        }
    }

    private static string RequiredString(JsonElement root, string name)
    {
        if (!root.TryGetProperty(name, out var value) ||
            value.ValueKind != JsonValueKind.String ||
            string.IsNullOrWhiteSpace(value.GetString()))
            throw new FormatException($"Google Drive envelope field '{name}' is missing or invalid.");
        return value.GetString()!;
    }

    private static object? ConvertElement(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.Object => value.EnumerateObject().ToDictionary(
            item => item.Name, item => ConvertElement(item.Value), StringComparer.Ordinal),
        JsonValueKind.Array => value.EnumerateArray().Select(ConvertElement).ToList(),
        JsonValueKind.String => value.GetString(),
        JsonValueKind.Number when value.TryGetInt64(out var integer) => integer,
        JsonValueKind.Number => value.GetDouble(),
        JsonValueKind.True => true,
        JsonValueKind.False => false,
        JsonValueKind.Null => null,
        _ => throw new FormatException("Unsupported JSON value in Google Drive snapshot.")
    };
}

public sealed record ValidatedDriveSnapshot(
    string DeviceId,
    string SnapshotHash,
    IReadOnlyDictionary<string, object?> Data,
    string CompactJson);
