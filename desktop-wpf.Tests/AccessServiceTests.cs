using KhanBabaPos.Wpf.Services;
using Xunit;

namespace KhanBabaPos.Wpf.Tests;

public sealed class AccessServiceTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), "khan-baba-access-" + Guid.NewGuid().ToString("N"));
    private string StorePath => Path.Combine(_directory, "users.dat");

    public AccessServiceTests() => Directory.CreateDirectory(_directory);
    public void Dispose()
    {
        try { Directory.Delete(_directory, true); } catch { }
    }

    [Fact]
    public void FirstRunRequiresExplicitAdminProvisioningAndPersistsAcrossInstances()
    {
        var first = new AccessService(StorePath);
        Assert.True(first.RequiresFirstRunSetup);
        var session = first.ProvisionFirstAdmin("owner", "Store Owner", "StrongPass!2026");
        Assert.Equal(AccessRole.Admin, session.Role);
        Assert.False(new AccessService(StorePath).RequiresFirstRunSetup);
        Assert.Throws<InvalidOperationException>(() =>
            new AccessService(StorePath).ProvisionFirstAdmin("other", "Other", "StrongPass!2026"));
    }

    [Fact]
    public void PasswordVerificationAndDisabledAccountAreEnforced()
    {
        var service = new AccessService(StorePath);
        service.ProvisionFirstAdmin("owner", "Owner", "StrongPass!2026");
        service.Logout();
        Assert.Throws<UnauthorizedAccessException>(() => service.Authenticate("owner", "wrong-password"));
        Assert.Equal(AccessRole.Admin, service.Authenticate("OWNER", "StrongPass!2026").Role);
        service.Logout();
        service.Authenticate("owner", "StrongPass!2026");
        var salesman = service.CreateStaff("cashier", "Cashier One", "CashierPass!2026", AccessRole.Salesman);
        service.SetEnabled(salesman.Id, false);
        service.Logout();
        Assert.Throws<UnauthorizedAccessException>(() => service.Authenticate("cashier", "CashierPass!2026"));
    }

    [Fact]
    public void RoleChecksAndLastAdminProtectionAreEnforced()
    {
        var service = new AccessService(StorePath);
        service.ProvisionFirstAdmin("owner", "Owner", "StrongPass!2026");
        service.CreateStaff("cashier", "Cashier One", "CashierPass!2026", AccessRole.Salesman);
        service.Logout();
        service.Authenticate("cashier", "CashierPass!2026");
        Assert.Throws<UnauthorizedAccessException>(() => service.RequireAdmin());
        service.Logout();
        service.Authenticate("owner", "StrongPass!2026");
        var owner = service.ListStaff().Single(x => x.Username == "owner");
        Assert.Throws<InvalidOperationException>(() => service.SetEnabled(owner.Id, false));
    }

    [Fact]
    public void ExpiredSessionCannotAuthorizeAnyAction()
    {
        var service = new AccessService(StorePath, TimeSpan.FromMilliseconds(1));
        service.ProvisionFirstAdmin("owner", "Owner", "StrongPass!2026");
        Thread.Sleep(20);
        Assert.Throws<UnauthorizedAccessException>(() => service.RequireAdmin());
    }

    [Fact]
    public async Task SalePostingRejectsCashierIdentityThatDoesNotMatchAuthenticatedStaff()
    {
        var service = new AccessService(StorePath);
        var session = service.ProvisionFirstAdmin("owner", "Owner", "StrongPass!2026");
        var sales = new SalePostingService(service);
        var request = new SaleCheckoutRequest(
            [new SaleLineInput("B-1", 1, 10)], null, "Cash", null, 0, false,
            "Walk-in", "Someone Else", "different-user");
        await Assert.ThrowsAsync<UnauthorizedAccessException>(() => sales.CompleteSaleAsync(request, "unused-test-db.sqlite"));
    }

    [Fact]
    public void RepeatedFailuresApplyTemporaryLockout()
    {
        var service = new AccessService(StorePath);
        service.ProvisionFirstAdmin("owner", "Owner", "StrongPass!2026");
        service.Logout();
        for (var i = 0; i < 5; i++)
            Assert.Throws<UnauthorizedAccessException>(() => service.Authenticate("owner", "wrong-password"));
        var error = Assert.Throws<UnauthorizedAccessException>(() =>
            service.Authenticate("owner", "StrongPass!2026"));
        Assert.Contains("locked", error.Message, StringComparison.OrdinalIgnoreCase);
    }
}
