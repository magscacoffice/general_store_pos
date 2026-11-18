using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Reflection;
using System.Text.Json;

namespace KhanBabaPos.Wpf.Services;

/// <summary>
/// Checks stable GitHub releases and installs only a hash-matching, Authenticode-signed
/// per-user installer from the pinned Khan Baba publisher. Installation remains
/// disabled until the owner supplies and pins the production signing certificate.
/// </summary>
public sealed class NativeUpdateService
{
    private const string ReleaseApi = "https://api.github.com/repos/magscacoffice/general_store_pos/releases/latest";
    private const string ManifestAssetName = "khan-baba-release.json";
    private const long MaxInstallerSizeBytes = 500L * 1024 * 1024;
    // Configure only after the owner supplies the production code-signing certificate.
    private const string TrustedPublisherThumbprint = "";
    private static readonly HttpClient Http = CreateClient();

    public bool CanInstallSignedUpdates => !string.IsNullOrWhiteSpace(TrustedPublisherThumbprint);

    public static Version GetInstalledVersion() =>
        Assembly.GetEntryAssembly()?.GetName().Version ?? new Version(1, 0, 0, 0);

    public static bool IsUpdateAvailable(Version installed, Version latest) =>
        latest > installed;

    public async Task<Version> GetLatestVersionAsync(CancellationToken cancellationToken = default)
    {
        using var response = await Http.GetAsync(ReleaseApi, cancellationToken);
        response.EnsureSuccessStatusCode();
        using var release = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
        var tag = release.RootElement.GetProperty("tag_name").GetString() ?? "";
        if (!Version.TryParse(tag.TrimStart('v', 'V'), out var version))
            throw new InvalidDataException("Latest GitHub release tag is not a valid version.");
        return version;
    }

    public async Task<NativeUpdateInfo?> CheckForUpdateAsync(CancellationToken cancellationToken = default)
    {
        using var response = await Http.GetAsync(ReleaseApi, cancellationToken);
        response.EnsureSuccessStatusCode();
        using var release = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
        var root = release.RootElement;
        var tag = root.GetProperty("tag_name").GetString() ?? "";
        if (!Version.TryParse(tag.TrimStart('v', 'V'), out var latestVersion))
            throw new InvalidDataException("Latest GitHub release tag is not a valid version.");
        var currentVersion = GetInstalledVersion();
        if (latestVersion <= currentVersion) return null;

        var assets = root.GetProperty("assets").EnumerateArray().ToArray();
        var manifestAsset = assets.FirstOrDefault(x => x.GetProperty("name").GetString() == ManifestAssetName);
        if (manifestAsset.ValueKind == JsonValueKind.Undefined)
            throw new InvalidDataException("Release is missing its signed update manifest.");
        var manifestUrl = ValidateReleaseAssetUrl(
            manifestAsset.GetProperty("browser_download_url").GetString() ?? "");

        using var manifestResponse = await Http.GetAsync(manifestUrl, cancellationToken);
        manifestResponse.EnsureSuccessStatusCode();
        using var manifest = JsonDocument.Parse(await manifestResponse.Content.ReadAsStringAsync(cancellationToken));
        var data = manifest.RootElement;
        var versionText = data.GetProperty("version").GetString() ?? "";
        if (!Version.TryParse(versionText, out var manifestVersion) || manifestVersion != latestVersion)
            throw new InvalidDataException("Release manifest version does not match the GitHub release tag.");

        var installerName = data.GetProperty("installerAsset").GetString() ?? "";
        if (!IsSafeInstallerAssetName(installerName))
            throw new InvalidDataException("Release manifest contains an unsafe installer filename.");
        var sha256 = data.GetProperty("sha256").GetString() ?? "";
        var thumbprint = NormalizeThumbprint(data.GetProperty("publisherThumbprint").GetString() ?? "");
        if (sha256.Length != 64 || !sha256.All(Uri.IsHexDigit) ||
            thumbprint.Length != 40 || !thumbprint.All(Uri.IsHexDigit))
            throw new InvalidDataException("Release manifest contains invalid installer metadata.");

        var installerAsset = assets.FirstOrDefault(x => x.GetProperty("name").GetString() == installerName);
        if (installerAsset.ValueKind == JsonValueKind.Undefined)
            throw new InvalidDataException("Release installer asset was not found.");
        var installerUrl = ValidateReleaseAssetUrl(
            installerAsset.GetProperty("browser_download_url").GetString() ?? "");
        var installerSize = installerAsset.GetProperty("size").GetInt64();
        if (installerSize <= 0 || installerSize > MaxInstallerSizeBytes)
            throw new InvalidDataException("Release installer size is missing or exceeds the 500 MB safety limit.");

        return new NativeUpdateInfo(latestVersion, installerName, installerUrl.AbsoluteUri,
            sha256.ToLowerInvariant(), thumbprint,
            root.TryGetProperty("body", out var body) ? body.GetString() ?? "" : "",
            installerSize);
    }

    public async Task<string> DownloadVerifiedInstallerAsync(
        NativeUpdateInfo update, IProgress<NativeUpdateProgress>? progress = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(update);
        if (!CanInstallSignedUpdates)
            throw new InvalidOperationException("Updater abhi disabled hai: production code-signing certificate ka thumbprint configure nahi hua.");
        var pinned = NormalizeThumbprint(TrustedPublisherThumbprint);
        if (!string.Equals(update.PublisherThumbprint, pinned, StringComparison.OrdinalIgnoreCase))
            throw new CryptographicException("Update publisher certificate trusted Khan Baba certificate se match nahi karta.");
        if (!IsSafeInstallerAssetName(update.InstallerAssetName) ||
            update.InstallerSizeBytes <= 0 || update.InstallerSizeBytes > MaxInstallerSizeBytes)
            throw new InvalidDataException("Installer filename ya size safety validation pass nahi hui.");
        _ = ValidateReleaseAssetUrl(update.InstallerUrl);
        if (update.Sha256.Length != 64 || !update.Sha256.All(Uri.IsHexDigit))
            throw new InvalidDataException("Installer SHA-256 metadata is invalid.");

        var directory = GetUpdateDirectory();
        Directory.CreateDirectory(directory);
        var finalName = $"{Path.GetFileNameWithoutExtension(update.InstallerAssetName)}-{update.Version}.exe";
        var installerPath = Path.GetFullPath(Path.Combine(directory, finalName));
        string? stagedPath = null;
        try
        {
            Exception? lastError = null;
            for (var attempt = 1; attempt <= 3; attempt++)
            {
                stagedPath = Path.Combine(directory, $".{Guid.NewGuid():N}.download");
                try
                {
                    await DownloadOnceAsync(update, stagedPath, progress, cancellationToken);
                    var actualHash = await ComputeSha256Async(stagedPath, cancellationToken);
                    if (!CryptographicOperations.FixedTimeEquals(
                            Convert.FromHexString(actualHash), Convert.FromHexString(update.Sha256)))
                        throw new CryptographicException("Downloaded installer SHA-256 check failed.");
                    VerifyAuthenticodeSignature(stagedPath, pinned);
                    File.Move(stagedPath, installerPath, overwrite: true);
                    stagedPath = null;
                    lastError = null;
                    break;
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
                catch (Exception ex) when (IsTransientDownloadFailure(ex) && attempt < 3)
                {
                    lastError = ex;
                    TryDelete(stagedPath);
                    stagedPath = null;
                    await Task.Delay(TimeSpan.FromSeconds(attempt), cancellationToken);
                }
            }
            if (lastError is not null)
                throw new IOException("Installer download failed after three attempts.", lastError);
            if (!File.Exists(installerPath))
                throw new IOException("Verified installer could not be staged.");
            return installerPath;
        }
        finally
        {
            if (stagedPath is not null) TryDelete(stagedPath);
        }
    }

    public void LaunchDownloadedInstaller(string installerPath)
    {
        if (!CanInstallSignedUpdates)
            throw new InvalidOperationException("Updater abhi disabled hai: production code-signing certificate ka thumbprint configure nahi hua.");
        var directory = Path.GetFullPath(GetUpdateDirectory()) + Path.DirectorySeparatorChar;
        var fullPath = Path.GetFullPath(installerPath);
        if (!fullPath.StartsWith(directory, StringComparison.OrdinalIgnoreCase) || !File.Exists(fullPath))
            throw new InvalidOperationException("Installer path Khan Baba Updates folder ke andar maujood verified file ka nahi hai.");
        VerifyAuthenticodeSignature(fullPath, NormalizeThumbprint(TrustedPublisherThumbprint));
        var start = new ProcessStartInfo(fullPath)
        {
            UseShellExecute = true,
            Verb = "open",
            Arguments = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-"
        };
        if (Process.Start(start) is null)
            throw new InvalidOperationException("Installer process could not be started.");
    }

    public Task DownloadAndStartInstallerAsync(
        NativeUpdateInfo update, CancellationToken cancellationToken = default) =>
        DownloadAndStartInstallerCoreAsync(update, null, cancellationToken);

    public Task DownloadAndStartInstallerAsync(
        NativeUpdateInfo update, IProgress<NativeUpdateProgress> progress,
        CancellationToken cancellationToken = default) =>
        DownloadAndStartInstallerCoreAsync(update, progress, cancellationToken);

    private async Task DownloadAndStartInstallerCoreAsync(
        NativeUpdateInfo update, IProgress<NativeUpdateProgress>? progress,
        CancellationToken cancellationToken)
    {
        var path = await DownloadVerifiedInstallerAsync(update, progress, cancellationToken);
        LaunchDownloadedInstaller(path);
    }

    public static string GetUpdateDirectory() =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "KhanBabaPOS", "Updates");

    public static bool IsSafeInstallerAssetName(string value) =>
        !string.IsNullOrWhiteSpace(value) &&
        value is not ("." or "..") &&
        string.Equals(Path.GetFileName(value), value, StringComparison.Ordinal) &&
        !value.Contains('/') && !value.Contains('\\') &&
        value.IndexOfAny(Path.GetInvalidFileNameChars()) < 0 &&
        value.EndsWith(".exe", StringComparison.OrdinalIgnoreCase);

    private static Uri ValidateReleaseAssetUrl(string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) ||
            uri.Scheme != Uri.UriSchemeHttps ||
            !string.Equals(uri.Host, "github.com", StringComparison.OrdinalIgnoreCase) ||
            !uri.AbsolutePath.StartsWith(
                "/magscacoffice/general_store_pos/releases/download/",
                StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Installer URL must be an HTTPS asset from the Khan Baba POS GitHub Releases page.");
        return uri;
    }

    private static async Task DownloadOnceAsync(
        NativeUpdateInfo update, string destination,
        IProgress<NativeUpdateProgress>? progress, CancellationToken cancellationToken)
    {
        using var response = await Http.GetAsync(
            update.InstallerUrl, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        response.EnsureSuccessStatusCode();
        if (response.Content.Headers.ContentLength is long responseLength &&
            responseLength != update.InstallerSizeBytes)
            throw new InvalidDataException("GitHub installer size does not match release metadata.");

        await using var input = await response.Content.ReadAsStreamAsync(cancellationToken);
        await using var output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write,
            FileShare.None, 81920, FileOptions.Asynchronous | FileOptions.SequentialScan);
        var buffer = new byte[81920];
        long downloaded = 0;
        while (true)
        {
            var read = await input.ReadAsync(buffer, cancellationToken);
            if (read == 0) break;
            downloaded += read;
            if (downloaded > update.InstallerSizeBytes || downloaded > MaxInstallerSizeBytes)
                throw new InvalidDataException("Downloaded installer exceeds its declared size.");
            await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
            progress?.Report(new NativeUpdateProgress(downloaded, update.InstallerSizeBytes));
        }
        await output.FlushAsync(cancellationToken);
        if (downloaded != update.InstallerSizeBytes)
            throw new InvalidDataException("Downloaded installer is incomplete; the declared file size does not match.");
    }

    private static bool IsTransientDownloadFailure(Exception ex) =>
        ex is HttpRequestException or TaskCanceledException ||
        (ex is IOException && ex is not InvalidDataException);

    private static async Task<string> ComputeSha256Async(string path, CancellationToken cancellationToken)
    {
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read,
            81920, FileOptions.Asynchronous | FileOptions.SequentialScan);
        return Convert.ToHexString(await SHA256.HashDataAsync(stream, cancellationToken)).ToLowerInvariant();
    }

    private static void TryDelete(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return;
        try { if (File.Exists(path)) File.Delete(path); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
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
    string Sha256, string PublisherThumbprint, string ReleaseNotes, long InstallerSizeBytes = 0);

public sealed record NativeUpdateProgress(long BytesDownloaded, long TotalBytes)
{
    public double Percentage => TotalBytes <= 0 ? 0 : Math.Clamp(BytesDownloaded * 100d / TotalBytes, 0d, 100d);
}
