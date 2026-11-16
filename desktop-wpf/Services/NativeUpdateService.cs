using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Reflection;
using System.Text.Json;

namespace KhanBabaPos.Wpf.Services;

/// <summary>
/// Checks GitHub releases and installs only a hash-matching, Authenticode-signed
/// per-user installer from the pinned Khan Baba publisher. Installation remains
/// disabled until the owner supplies and pins the production signing certificate.
/// </summary>
public sealed class NativeUpdateService
{
    private const string ReleaseApi = "https://api.github.com/repos/magscacoffice/general_store_pos/releases/latest";
    private const string ManifestAssetName = "khan-baba-release.json";
    // Configure only after the owner supplies the production code-signing certificate.
    private const string TrustedPublisherThumbprint = "";
    private static readonly HttpClient Http = CreateClient();

    public bool CanInstallSignedUpdates => !string.IsNullOrWhiteSpace(TrustedPublisherThumbprint);

    public async Task<NativeUpdateInfo?> CheckForUpdateAsync(CancellationToken cancellationToken = default)
    {
        using var response = await Http.GetAsync(ReleaseApi, cancellationToken);
        response.EnsureSuccessStatusCode();
        using var release = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
        var root = release.RootElement;
        var tag = root.GetProperty("tag_name").GetString() ?? "";
        if (!Version.TryParse(tag.TrimStart('v', 'V'), out var latestVersion))
            throw new InvalidDataException("Latest GitHub release tag is not a valid version.");
        var currentVersion = Assembly.GetEntryAssembly()?.GetName().Version ?? new Version(1, 0, 0, 0);
        if (latestVersion <= currentVersion) return null;

        var assets = root.GetProperty("assets").EnumerateArray().ToArray();
        var manifestAsset = assets.FirstOrDefault(x => x.GetProperty("name").GetString() == ManifestAssetName);
        if (manifestAsset.ValueKind == JsonValueKind.Undefined)
            throw new InvalidDataException("Release is missing its signed update manifest.");
        var manifestUrl = manifestAsset.GetProperty("browser_download_url").GetString()
            ?? throw new InvalidDataException("Release manifest download URL is missing.");
        using var manifestResponse = await Http.GetAsync(manifestUrl, cancellationToken);
        manifestResponse.EnsureSuccessStatusCode();
        using var manifest = JsonDocument.Parse(await manifestResponse.Content.ReadAsStringAsync(cancellationToken));
        var data = manifest.RootElement;
        var versionText = data.GetProperty("version").GetString() ?? "";
        if (!Version.TryParse(versionText, out var manifestVersion) || manifestVersion != latestVersion)
            throw new InvalidDataException("Release manifest version does not match the GitHub release tag.");

        var installerName = data.GetProperty("installerAsset").GetString() ?? "";
        var sha256 = data.GetProperty("sha256").GetString() ?? "";
        var thumbprint = NormalizeThumbprint(data.GetProperty("publisherThumbprint").GetString() ?? "");
        if (string.IsNullOrWhiteSpace(installerName) || sha256.Length != 64 || !sha256.All(Uri.IsHexDigit) ||
            thumbprint.Length != 40 || !thumbprint.All(Uri.IsHexDigit))
            throw new InvalidDataException("Release manifest contains invalid installer metadata.");
        var installerAsset = assets.FirstOrDefault(x => x.GetProperty("name").GetString() == installerName);
        if (installerAsset.ValueKind == JsonValueKind.Undefined)
            throw new InvalidDataException("Release installer asset was not found.");
        var installerUrl = installerAsset.GetProperty("browser_download_url").GetString()
            ?? throw new InvalidDataException("Release installer URL is missing.");
        return new NativeUpdateInfo(latestVersion, installerName, installerUrl, sha256.ToLowerInvariant(),
            thumbprint, root.TryGetProperty("body", out var body) ? body.GetString() ?? "" : "");
    }

    public async Task DownloadAndStartInstallerAsync(NativeUpdateInfo update, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(update);
        if (!CanInstallSignedUpdates)
            throw new InvalidOperationException("Updater abhi disabled hai: production code-signing certificate ka thumbprint configure nahi hua.");
        var pinned = NormalizeThumbprint(TrustedPublisherThumbprint);
        if (!string.Equals(update.PublisherThumbprint, pinned, StringComparison.OrdinalIgnoreCase))
            throw new CryptographicException("Update publisher certificate trusted Khan Baba certificate se match nahi karta.");

        var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "KhanBabaPOS", "Updates");
        Directory.CreateDirectory(directory);
        var installerPath = Path.Combine(directory, update.InstallerAssetName);
        using (var response = await Http.GetAsync(update.InstallerUrl, HttpCompletionOption.ResponseHeadersRead, cancellationToken))
        {
            response.EnsureSuccessStatusCode();
            await using var input = await response.Content.ReadAsStreamAsync(cancellationToken);
            await using var output = new FileStream(installerPath, FileMode.Create, FileAccess.Write, FileShare.None);
            await input.CopyToAsync(output, cancellationToken);
        }
        string actualHash;
        await using (var installerStream = File.OpenRead(installerPath))
            actualHash = Convert.ToHexString(await SHA256.HashDataAsync(installerStream, cancellationToken)).ToLowerInvariant();
        if (!CryptographicOperations.FixedTimeEquals(Convert.FromHexString(actualHash), Convert.FromHexString(update.Sha256)))
        {
            File.Delete(installerPath);
            throw new CryptographicException("Downloaded installer SHA-256 check failed.");
        }

        VerifyAuthenticodeSignature(installerPath, pinned);
        var start = new ProcessStartInfo(installerPath)
        {
            UseShellExecute = true,
            Verb = "open",
            Arguments = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-"
        };
        if (Process.Start(start) is null)
            throw new InvalidOperationException("Installer process could not be started.");
    }

    private static void VerifyAuthenticodeSignature(string path, string expectedThumbprint)
    {
        var escapedPath = path.Replace("'", "''", StringComparison.Ordinal);
        var script = "$s=Get-AuthenticodeSignature -LiteralPath '" + escapedPath +
                     "'; if ($s.Status -ne 'Valid' -or $null -eq $s.SignerCertificate -or " +
                     "$s.SignerCertificate.Thumbprint -ne '" + expectedThumbprint + "') { exit 31 }";
        var start = new ProcessStartInfo("powershell.exe")
        {
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardError = true, RedirectStandardOutput = true
        };
        start.ArgumentList.Add("-NoProfile");
        start.ArgumentList.Add("-NonInteractive");
        start.ArgumentList.Add("-Command");
        start.ArgumentList.Add(script);
        using var process = Process.Start(start)
            ?? throw new InvalidOperationException("Windows Authenticode verifier could not be started.");
        process.WaitForExit();
        if (process.ExitCode != 0)
            throw new CryptographicException("Installer Authenticode signature is invalid or is not signed by the pinned Khan Baba publisher.");
    }

    private static string NormalizeThumbprint(string value) =>
        new(value.Where(Uri.IsHexDigit).Select(char.ToUpperInvariant).ToArray());

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(3) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("KhanBabaPOS-WindowsUpdater/1.0");
        client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        return client;
    }
}

public sealed record NativeUpdateInfo(Version Version, string InstallerAssetName, string InstallerUrl,
    string Sha256, string PublisherThumbprint, string ReleaseNotes);
