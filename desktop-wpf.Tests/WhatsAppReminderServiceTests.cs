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

    [Theory]
    [InlineData("v1.0.0-build225", "1.0.0")]
    [InlineData("1.2.3-build7", "1.2.3")]
    [InlineData("V2.4.6-build17", "2.4.6")]
    [InlineData("v1.2.3", "1.2.3")]
    [InlineData("1.2.3.4", "1.2.3.4")]
    public void ReleaseTagsAcceptProductVersionAndOptionalBuildSuffix(string tag, string expected)
    {
        Assert.True(NativeUpdateService.TryParseReleaseTag(tag, out var parsed));
        Assert.Equal(new Version(expected), parsed);
    }

    [Theory]
    [InlineData("")]
    [InlineData("build225")]
    [InlineData("v1.0.0-build")]
    [InlineData("v1.0.0-beta1")]
    [InlineData("v1.0.0-build225-extra")]
    [InlineData("v1.0-build225")]
    [InlineData("v1.0.0.1-build225")]
    public void ReleaseTagRejectsUnsupportedOrMalformedSuffixes(string tag)
    {
        Assert.False(NativeUpdateService.TryParseReleaseTag(tag, out _));
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
