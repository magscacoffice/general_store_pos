using KhanBabaPos.Wpf.Services;
using Xunit;

namespace KhanBabaPos.Wpf.Tests;

public sealed class GoogleDriveAuthServiceTests
{
    [Fact]
    public void UsesTheOwnerCreatedWindowsDesktopOAuthClient()
    {
        Assert.Equal(
            "707319476515-vtdi3s5vn0tudh3ihnppco14kkrgtk78.apps.googleusercontent.com",
            GoogleDriveAuthService.DesktopClientId);
    }

    [Fact]
    public void AuthorizationCodeExchangeUsesPKCEAndDoesNotSendAClientSecret()
    {
        var form = GoogleDriveAuthService.CreateAuthorizationCodeTokenForm(
            "test-code", "test-code-verifier", "http://127.0.0.1:54321/");

        Assert.Equal(GoogleDriveAuthService.DesktopClientId, form["client_id"]);
        Assert.Equal("authorization_code", form["grant_type"]);
        Assert.Equal("test-code", form["code"]);
        Assert.Equal("test-code-verifier", form["code_verifier"]);
        Assert.Equal("http://127.0.0.1:54321/", form["redirect_uri"]);
        Assert.DoesNotContain("client_secret", form.Keys);
    }

    [Fact]
    public void RefreshExchangeUsesInstalledAppClientWithoutAClientSecret()
    {
        var form = GoogleDriveAuthService.CreateRefreshTokenForm("test-refresh-token");

        Assert.Equal(GoogleDriveAuthService.DesktopClientId, form["client_id"]);
        Assert.Equal("refresh_token", form["grant_type"]);
        Assert.Equal("test-refresh-token", form["refresh_token"]);
        Assert.DoesNotContain("client_secret", form.Keys);
    }

    [Fact]
    public void TokenCacheIsVersionedPerOAuthClientAndDoesNotReuseTheLegacyCacheName()
    {
        var current = GoogleDriveAuthService.GetTokenCacheFileName(GoogleDriveAuthService.DesktopClientId);
        var repeated = GoogleDriveAuthService.GetTokenCacheFileName(GoogleDriveAuthService.DesktopClientId);
        var priorClient = GoogleDriveAuthService.GetTokenCacheFileName(
            "707319476515-viu9eqvkacootsu2eooa4eon2oeheab2.apps.googleusercontent.com");

        Assert.Equal(current, repeated);
        Assert.NotEqual(current, priorClient);
        Assert.NotEqual("drive_tokens.dat", current);
        Assert.EndsWith(".dat", current);
    }
}
