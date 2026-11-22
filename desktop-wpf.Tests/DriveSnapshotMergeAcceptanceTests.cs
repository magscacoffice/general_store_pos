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
}
