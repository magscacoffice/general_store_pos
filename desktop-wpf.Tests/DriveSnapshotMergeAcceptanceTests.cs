using KhanBabaPos.Wpf.Services;
using Xunit;

namespace KhanBabaPos.Wpf.Tests;

public sealed class DriveSnapshotMergeAcceptanceTests
{
    [Fact]
    public void AcceptsSnapshotWhenNoConflictsOrDeferredRecordsRemain()
    {
        Assert.True(DriveSnapshotMergeService.IsSnapshotFullyAccepted(0, 0));
    }

    [Theory]
    [InlineData(1, 0)]
    [InlineData(0, 1)]
    [InlineData(2, 3)]
    public void KeepsSnapshotPendingWhenConflictsOrDeferredRecordsRemain(
        int pendingConflicts, int deferredRecords)
    {
        Assert.False(DriveSnapshotMergeService.IsSnapshotFullyAccepted(
            pendingConflicts, deferredRecords));
    }

    [Theory]
    [InlineData(null, null, false)]
    [InlineData("", null, false)]
    [InlineData("remote-party", 42L, false)]
    [InlineData("remote-party", null, true)]
    public void DetectsMissingRequiredPartyReference(
        string? remotePartySyncId, long? localPartyId, bool expected)
    {
        Assert.Equal(expected, DriveSnapshotMergeService.IsMissingRequiredPartyReference(
            remotePartySyncId, localPartyId));
    }

    [Theory]
    [InlineData(null, true)]
    [InlineData("", true)]
    [InlineData("   ", true)]
    [InlineData("stable-sync-id", false)]
    public void DetectsMissingStableIds(string? syncId, bool expected)
    {
        Assert.Equal(expected, DriveSnapshotMergeService.IsMissingStableId(syncId));
    }
}
