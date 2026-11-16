using System.IO;
using System.Net.Http;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace KhanBabaPos.Wpf.Services;

/// <summary>
/// Google installed-app OAuth using loopback + PKCE. Refresh/access tokens are
/// encrypted for the current Windows user with DPAPI and never written in plain text.
/// </summary>
public sealed class GoogleDriveAuthService
{
    private const string ClientId = "707319476515-viu9eqvkacootsu2eooa4eon2oeheab2.apps.googleusercontent.com";
    private const string Scope = "https://www.googleapis.com/auth/drive.file";
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(25) };
    private readonly string _tokenPath;

    public GoogleDriveAuthService(string? tokenPath = null)
    {
        var directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "KhanBabaPOS");
        _tokenPath = tokenPath ?? Path.Combine(directory, "drive_tokens.dat");
    }

    public bool HasSavedCredentials => File.Exists(_tokenPath);

    public async Task<string> GetAccessTokenAsync(
        bool promptForLogin = false,
        CancellationToken cancellationToken = default)
    {
        var tokens = await ReadTokensAsync(cancellationToken);
        if (tokens is not null && tokens.ExpiresAtUtc > DateTimeOffset.UtcNow.AddMinutes(1))
            return tokens.AccessToken;

        if (tokens is not null && !string.IsNullOrWhiteSpace(tokens.RefreshToken))
        {
            try
            {
                var refreshed = await RefreshAsync(tokens.RefreshToken, cancellationToken);
                await SaveTokensAsync(refreshed with
                {
                    RefreshToken = string.IsNullOrWhiteSpace(refreshed.RefreshToken)
                        ? tokens.RefreshToken
                        : refreshed.RefreshToken
                }, cancellationToken);
                return refreshed.AccessToken;
            }
            catch when (promptForLogin)
            {
                // A revoked refresh token falls through to interactive consent.
            }
        }

        if (!promptForLogin)
            throw new InvalidOperationException(
                "Google Drive is not connected or its authorization expired. Connect Drive from POS settings.");

        var connected = await AuthorizeAsync(cancellationToken);
        await SaveTokensAsync(connected, cancellationToken);
        return connected.AccessToken;
    }

    public async Task DisconnectAsync(CancellationToken cancellationToken = default)
    {
        if (File.Exists(_tokenPath))
            await Task.Run(() => File.Delete(_tokenPath), cancellationToken);
    }

    private static async Task<DriveTokenSet> RefreshAsync(
        string refreshToken, CancellationToken cancellationToken)
    {
        var form = new Dictionary<string, string>
        {
            ["client_id"] = ClientId,
            ["refresh_token"] = refreshToken,
            ["grant_type"] = "refresh_token"
        };
        var secret = Environment.GetEnvironmentVariable("GOOGLE_WINDOWS_CLIENT_SECRET");
        if (!string.IsNullOrWhiteSpace(secret)) form["client_secret"] = secret;

        using var response = await Http.PostAsync(
            "https://oauth2.googleapis.com/token",
            new FormUrlEncodedContent(form), cancellationToken);
        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
            throw new HttpRequestException(
                $"Google token refresh failed ({(int)response.StatusCode}): {body}");
        return ParseTokenResponse(body);
    }

    private static async Task<DriveTokenSet> AuthorizeAsync(CancellationToken cancellationToken)
    {
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        var redirectUri = $"http://127.0.0.1:{port}/";
        var verifier = Base64Url(RandomNumberGenerator.GetBytes(64));
        var challenge = Base64Url(SHA256.HashData(Encoding.ASCII.GetBytes(verifier)));
        var state = Base64Url(RandomNumberGenerator.GetBytes(32));
        var query = new Dictionary<string, string>
        {
            ["client_id"] = ClientId,
            ["redirect_uri"] = redirectUri,
            ["response_type"] = "code",
            ["scope"] = Scope,
            ["code_challenge"] = challenge,
            ["code_challenge_method"] = "S256",
            ["state"] = state,
            ["access_type"] = "offline",
            ["prompt"] = "consent"
        };
        var authorizationUrl = "https://accounts.google.com/o/oauth2/v2/auth?" +
            string.Join("&", query.Select(x =>
                Uri.EscapeDataString(x.Key) + "=" + Uri.EscapeDataString(x.Value)));

        Process.Start(new ProcessStartInfo(authorizationUrl) { UseShellExecute = true });
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromMinutes(3));
        using var client = await listener.AcceptTcpClientAsync(timeout.Token);
        await using var stream = client.GetStream();
        using var reader = new StreamReader(stream, Encoding.ASCII, leaveOpen: true);
        var requestLine = await reader.ReadLineAsync(timeout.Token);
        string? header;
        do { header = await reader.ReadLineAsync(timeout.Token); }
        while (!string.IsNullOrEmpty(header));

        var requestTarget = requestLine?.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .ElementAtOrDefault(1);
        if (requestTarget is null || !Uri.TryCreate(new Uri(redirectUri), requestTarget, out var callback))
            throw new InvalidDataException("Google OAuth callback was malformed.");

        var callbackQuery = System.Web.HttpUtility.ParseQueryString(callback.Query);
        var code = callbackQuery["code"];
        var returnedState = callbackQuery["state"];
        var error = callbackQuery["error_description"] ?? callbackQuery["error"];
        var success = !string.IsNullOrWhiteSpace(code) &&
                      CryptographicOperations.FixedTimeEquals(
                          Encoding.UTF8.GetBytes(state),
                          Encoding.UTF8.GetBytes(returnedState ?? string.Empty));
        var html = success
            ? "<html><body><h3>Khan Baba POS connected.</h3><p>You can return to the POS application.</p></body></html>"
            : "<html><body><h3>Google Drive connection failed.</h3><p>You can close this tab and return to the POS application.</p></body></html>";
        var responseBytes = Encoding.UTF8.GetBytes(
            $"HTTP/1.1 {(success ? "200 OK" : "400 Bad Request")}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {Encoding.UTF8.GetByteCount(html)}\r\nConnection: close\r\n\r\n{html}");
        await stream.WriteAsync(responseBytes, timeout.Token);
        await stream.FlushAsync(timeout.Token);
        if (!success)
            throw new InvalidOperationException(error ?? "Google authorization was cancelled or returned an invalid state.");

        var form = new Dictionary<string, string>
        {
            ["client_id"] = ClientId,
            ["code"] = code!,
            ["code_verifier"] = verifier,
            ["grant_type"] = "authorization_code",
            ["redirect_uri"] = redirectUri
        };
        var secret = Environment.GetEnvironmentVariable("GOOGLE_WINDOWS_CLIENT_SECRET");
        if (!string.IsNullOrWhiteSpace(secret)) form["client_secret"] = secret;
        using var tokenResponse = await Http.PostAsync(
            "https://oauth2.googleapis.com/token",
            new FormUrlEncodedContent(form), cancellationToken);
        var tokenBody = await tokenResponse.Content.ReadAsStringAsync(cancellationToken);
        if (!tokenResponse.IsSuccessStatusCode)
            throw new HttpRequestException(
                $"Google authorization exchange failed ({(int)tokenResponse.StatusCode}): {tokenBody}");
        return ParseTokenResponse(tokenBody);
    }

    private async Task<DriveTokenSet?> ReadTokensAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(_tokenPath)) return null;
        var encrypted = await File.ReadAllBytesAsync(_tokenPath, cancellationToken);
        try
        {
            var clear = ProtectedData.Unprotect(encrypted, null, DataProtectionScope.CurrentUser);
            return JsonSerializer.Deserialize<DriveTokenSet>(clear);
        }
        catch (CryptographicException ex)
        {
            throw new InvalidDataException(
                "Saved Google Drive credentials could not be decrypted for this Windows account.", ex);
        }
    }

    private async Task SaveTokensAsync(DriveTokenSet tokens, CancellationToken cancellationToken)
    {
        var directory = Path.GetDirectoryName(_tokenPath)
            ?? throw new InvalidOperationException("Drive token directory could not be resolved.");
        Directory.CreateDirectory(directory);
        var clear = JsonSerializer.SerializeToUtf8Bytes(tokens);
        var encrypted = ProtectedData.Protect(clear, null, DataProtectionScope.CurrentUser);
        var temporary = _tokenPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        await File.WriteAllBytesAsync(temporary, encrypted, cancellationToken);
        File.Move(temporary, _tokenPath, overwrite: true);
    }

    private static DriveTokenSet ParseTokenResponse(string body)
    {
        using var document = JsonDocument.Parse(body);
        var root = document.RootElement;
        var access = root.TryGetProperty("access_token", out var accessElement)
            ? accessElement.GetString()
            : null;
        if (string.IsNullOrWhiteSpace(access))
            throw new InvalidDataException("Google did not return an access token.");
        var expires = root.TryGetProperty("expires_in", out var expiresElement) &&
                      expiresElement.TryGetInt32(out var seconds) ? seconds : 3600;
        var refresh = root.TryGetProperty("refresh_token", out var refreshElement)
            ? refreshElement.GetString()
            : null;
        return new DriveTokenSet(access, refresh, DateTimeOffset.UtcNow.AddSeconds(expires));
    }

    private static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private sealed record DriveTokenSet(
        [property: JsonPropertyName("accessToken")] string AccessToken,
        [property: JsonPropertyName("refreshToken")] string? RefreshToken,
        [property: JsonPropertyName("expiresAtUtc")] DateTimeOffset ExpiresAtUtc);
}

/// <summary>Minimal Drive v3 transport using the same folder/file naming as Android.</summary>
public sealed class GoogleDriveApiClient(GoogleDriveAuthService auth)
{
    private const string FolderName = "Khan Baba POS";
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(25) };

    public async Task<string> EnsureFolderAsync(CancellationToken cancellationToken = default)
    {
        var token = await auth.GetAccessTokenAsync(cancellationToken: cancellationToken);
        var query = Uri.EscapeDataString(
            $"name = '{FolderName}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false");
        using var response = await AuthorizedRequestAsync(
            HttpMethod.Get,
            $"https://www.googleapis.com/drive/v3/files?q={query}&spaces=drive&pageSize=100&fields=files(id,name,mimeType)",
            token, null, cancellationToken);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
        if (json.RootElement.TryGetProperty("files", out var files) &&
            files.ValueKind == JsonValueKind.Array && files.GetArrayLength() > 0)
            return files[0].GetProperty("id").GetString()!;

        var metadata = JsonSerializer.Serialize(new
        {
            name = FolderName,
            mimeType = "application/vnd.google-apps.folder"
        });
        using var created = await AuthorizedRequestAsync(
            HttpMethod.Post,
            "https://www.googleapis.com/drive/v3/files?fields=id,name",
            token, new StringContent(metadata, Encoding.UTF8, "application/json"), cancellationToken);
        using var createdJson = JsonDocument.Parse(await created.Content.ReadAsStringAsync(cancellationToken));
        return createdJson.RootElement.GetProperty("id").GetString()
            ?? throw new InvalidDataException("Google Drive did not return a folder ID.");
    }

    public async Task<IReadOnlyList<GoogleDriveFile>> ListFilesAsync(
        string folderId, CancellationToken cancellationToken = default)
    {
        var token = await auth.GetAccessTokenAsync(cancellationToken: cancellationToken);
        var result = new List<GoogleDriveFile>();
        string? pageToken = null;
        do
        {
            var query = Uri.EscapeDataString($"'{folderId}' in parents and trashed = false");
            var url = $"https://www.googleapis.com/drive/v3/files?q={query}&spaces=drive&pageSize=1000&fields=nextPageToken,files(id,name,mimeType,modifiedTime)";
            if (!string.IsNullOrEmpty(pageToken)) url += "&pageToken=" + Uri.EscapeDataString(pageToken);
            using var response = await AuthorizedRequestAsync(HttpMethod.Get, url, token, null, cancellationToken);
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
            if (json.RootElement.TryGetProperty("files", out var files))
                foreach (var file in files.EnumerateArray())
                    result.Add(new GoogleDriveFile(
                        file.GetProperty("id").GetString()!,
                        file.GetProperty("name").GetString()!,
                        file.TryGetProperty("mimeType", out var mime) ? mime.GetString() : null,
                        file.TryGetProperty("modifiedTime", out var modified) ? modified.GetString() : null));
            pageToken = json.RootElement.TryGetProperty("nextPageToken", out var next)
                ? next.GetString()
                : null;
        } while (!string.IsNullOrEmpty(pageToken));
        return result;
    }

    public async Task<JsonDocument> DownloadJsonAsync(
        string fileId, CancellationToken cancellationToken = default)
    {
        var token = await auth.GetAccessTokenAsync(cancellationToken: cancellationToken);
        using var response = await AuthorizedRequestAsync(
            HttpMethod.Get,
            $"https://www.googleapis.com/drive/v3/files/{Uri.EscapeDataString(fileId)}?alt=media",
            token, null, cancellationToken);
        return JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
    }

    public async Task UploadJsonAsync(
        string folderId,
        string fileName,
        object payload,
        IReadOnlyList<GoogleDriveFile> existingFiles,
        CancellationToken cancellationToken = default)
    {
        var token = await auth.GetAccessTokenAsync(cancellationToken: cancellationToken);
        var existing = existingFiles.FirstOrDefault(x => x.Name == fileName);
        string fileId;
        if (existing is not null)
        {
            fileId = existing.Id;
        }
        else
        {
            var metadata = JsonSerializer.Serialize(new
            {
                name = fileName,
                mimeType = "application/json",
                parents = new[] { folderId }
            });
            using var created = await AuthorizedRequestAsync(
                HttpMethod.Post,
                "https://www.googleapis.com/drive/v3/files?fields=id,name",
                token, new StringContent(metadata, Encoding.UTF8, "application/json"), cancellationToken);
            using var json = JsonDocument.Parse(await created.Content.ReadAsStringAsync(cancellationToken));
            fileId = json.RootElement.GetProperty("id").GetString()
                ?? throw new InvalidDataException("Google Drive did not return a file ID.");
        }

        var content = JsonSerializer.Serialize(payload);
        using var media = new StringContent(content, Encoding.UTF8, "application/json");
        using var upload = await AuthorizedRequestAsync(
            HttpMethod.Patch,
            $"https://www.googleapis.com/upload/drive/v3/files/{Uri.EscapeDataString(fileId)}?uploadType=media",
            token, media, cancellationToken);
    }

    private static async Task<HttpResponseMessage> AuthorizedRequestAsync(
        HttpMethod method, string url, string token, HttpContent? content,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(method, url)
        {
            Content = content
        };
        request.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
        var response = await Http.SendAsync(request, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            response.Dispose();
            throw new HttpRequestException(
                $"Google Drive API request failed ({(int)response.StatusCode}): {body}");
        }
        return response;
    }
}

public sealed record GoogleDriveFile(string Id, string Name, string? MimeType, string? ModifiedTime);
