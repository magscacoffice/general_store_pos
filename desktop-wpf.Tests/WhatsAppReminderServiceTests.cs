using KhanBabaPos.Wpf.Services;
using Xunit;

namespace KhanBabaPos.Wpf.Tests;

public sealed class WhatsAppReminderServiceTests
{
    [Theory]
    [InlineData("03001234567", "923001234567")]
    [InlineData("+92 300 1234567", "923001234567")]
    [InlineData("0092-300-1234567", "923001234567")]
    [InlineData("3001234567", "923001234567")]
    public void NormalizesPakistaniMobileNumbers(string input, string expected) =>
        Assert.Equal(expected, WhatsAppReminderService.NormalizePakistaniPhone(input));

    [Theory]
    [InlineData("")]
    [InlineData("123")]
    [InlineData("abcdefghijk")]
    public void RejectsInvalidPhoneNumbers(string input) =>
        Assert.Throws<InvalidOperationException>(() => WhatsAppReminderService.NormalizePakistaniPhone(input));

    [Fact]
    public void ReminderMessageIncludesCustomerAndOutstandingBalance()
    {
        var message = WhatsAppReminderService.BuildMessage("Ali Store", 1250.5);
        Assert.Contains("Ali Store", message);
        Assert.Contains("1,250.50", message);
    }
}

public sealed class NativeUpdateServiceTests
{
    [Fact]
    public void UpdateComparisonUsesVersionOrdering()
    {
        Assert.True(NativeUpdateService.IsUpdateAvailable(new Version(1, 2, 0), new Version(1, 3, 0)));
        Assert.False(NativeUpdateService.IsUpdateAvailable(new Version(1, 3, 0), new Version(1, 3, 0)));
        Assert.False(NativeUpdateService.IsUpdateAvailable(new Version(1, 4, 0), new Version(1, 3, 0)));
    }

    [Fact]
    public void UpdateDownloadDirectoryIsUnderLocalApplicationData()
    {
        var expected = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "KhanBabaPOS", "Updates");
        Assert.Equal(Path.GetFullPath(expected), Path.GetFullPath(NativeUpdateService.GetUpdateDirectory()));
    }

    [Theory]
    [InlineData("KhanBabaPOS-Setup.exe", true)]
    [InlineData("../unsafe.exe", false)]
    [InlineData("folder\\\\setup.exe", false)]
    [InlineData("setup.zip", false)]
    public void InstallerAssetNameMustBeSafe(string name, bool expected) =>
        Assert.Equal(expected, NativeUpdateService.IsSafeInstallerAssetName(name));
}
