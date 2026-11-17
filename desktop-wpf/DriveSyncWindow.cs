using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;
using KhanBabaPos.Wpf.Services;

namespace KhanBabaPos.Wpf;

public sealed class DriveSyncWindow : Window
{
    private readonly AccessService _access;
    private readonly WindowsDriveSyncService _sync;
    private readonly ObservableCollection<DriveConflictRow> _conflicts = [];
    private readonly TextBlock _status = new() { TextWrapping = TextWrapping.Wrap, Foreground = new SolidColorBrush(Color.FromRgb(42, 83, 66)) };
    private readonly DataGrid _grid = new() { AutoGenerateColumns = false, IsReadOnly = true, SelectionMode = DataGridSelectionMode.Single, Height = 330, Margin = new Thickness(0, 12, 0, 12) };
    private readonly TextBox _localPayload = new() { IsReadOnly = true, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, MinHeight = 130 };
    private readonly TextBox _remotePayload = new() { IsReadOnly = true, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, MinHeight = 130 };

    public DriveSyncWindow(WindowsDriveSyncService sync, AccessService access)
    {
        _sync = sync;
        _access = access;
        _access.RequireAdmin();
        Title = "Google Drive Sync & Conflict Review";
        Width = 1100;
        Height = 820;
        MinWidth = 900;
        MinHeight = 650;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = new SolidColorBrush(Color.FromRgb(243, 246, 244));
        _grid.ItemsSource = _conflicts;
        AddColumn("ID", "Id", 65);
        AddColumn("Source device", "SourceDeviceId", 180);
        AddColumn("Type", "EntityType", 130);
        AddColumn("Record key", "EntityKey", 220);
        AddColumn("Created", "CreatedAt", 220);
        _grid.SelectionChanged += (_, _) => ShowSelectedPayloads();
        _sync.StatusChanged += Sync_StatusChanged;

        var root = new StackPanel { Margin = new Thickness(18) };
        root.Children.Add(new TextBlock { Text = "Google Drive — Windows Master", FontSize = 22, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Color.FromRgb(23, 59, 50)) });
        root.Children.Add(new TextBlock { Text = _sync.IsEnabled
            ? "Windows local database master rahega. Doosre device ke stock/account conflicts par explicit faisla zaroori hai."
            : "Google Drive upload, download, auto-sync aur conflict resolution filhal band hain. Full v18 safety validation aur owner approval ke baad hi enable honge.",
            TextWrapping = TextWrapping.Wrap, Foreground = Brushes.DimGray, Margin = new Thickness(0, 5, 0, 10) });
        root.Children.Add(_status);

        var actions = new WrapPanel { Margin = new Thickness(0, 12, 0, 0) };
        var connect = Action("Connect & Sync", Connect_Click);
        connect.IsEnabled = _sync.IsEnabled;
        actions.Children.Add(connect);
        var syncNow = Action("Sync Now", Sync_Click);
        syncNow.IsEnabled = _sync.IsEnabled;
        actions.Children.Add(syncNow);
        actions.Children.Add(Action("Refresh Conflicts", Refresh_Click));
        actions.Children.Add(Action("Disconnect Drive", Disconnect_Click));
        root.Children.Add(actions);
        root.Children.Add(new TextBlock { Text = "Pending conflicts — local record aur remote record compare karein", FontWeight = FontWeights.Bold, Margin = new Thickness(0, 16, 0, 0) });
        root.Children.Add(_grid);

        var payloadGrid = new Grid { Margin = new Thickness(0, 0, 0, 10) };
        payloadGrid.ColumnDefinitions.Add(new ColumnDefinition());
        payloadGrid.ColumnDefinitions.Add(new ColumnDefinition());
        var localPanel = new StackPanel { Margin = new Thickness(0, 0, 8, 0) };
        localPanel.Children.Add(new TextBlock { Text = "WINDOWS (KEEP LOCAL)", FontWeight = FontWeights.Bold, Margin = new Thickness(0, 0, 0, 5) });
        localPanel.Children.Add(_localPayload);
        var remotePanel = new StackPanel { Margin = new Thickness(8, 0, 0, 0) };
        remotePanel.Children.Add(new TextBlock { Text = "OTHER DEVICE (REMOTE)", FontWeight = FontWeights.Bold, Margin = new Thickness(0, 0, 0, 5) });
        remotePanel.Children.Add(_remotePayload);
        payloadGrid.Children.Add(localPanel);
        Grid.SetColumn(remotePanel, 1);
        payloadGrid.Children.Add(remotePanel);
        root.Children.Add(payloadGrid);

        var resolutions = new WrapPanel();
        var keepWindows = Action("Keep Windows", KeepWindows_Click);
        keepWindows.IsEnabled = _sync.IsEnabled;
        resolutions.Children.Add(keepWindows);
        var useRemote = Action("Use Other Device", UseRemote_Click);
        useRemote.IsEnabled = _sync.IsEnabled;
        resolutions.Children.Add(useRemote);
        root.Children.Add(resolutions);
        Content = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = root };
        Loaded += async (_, _) => await RefreshConflictsAsync();
        Closed += (_, _) => _sync.StatusChanged -= Sync_StatusChanged;
    }

    private void AddColumn(string header, string binding, double width) =>
        _grid.Columns.Add(new DataGridTextColumn { Header = header, Binding = new Binding(binding), Width = width });

    private static Button Action(string label, RoutedEventHandler handler)
    {
        var button = new Button { Content = label, Padding = new Thickness(12, 8, 12, 8), Margin = new Thickness(0, 0, 8, 8), FontWeight = FontWeights.SemiBold };
        button.Click += handler;
        return button;
    }

    private DriveConflictRow? Selected => _grid.SelectedItem as DriveConflictRow;

    private void Sync_StatusChanged()
    {
        if (!Dispatcher.CheckAccess())
        {
            _ = Dispatcher.InvokeAsync(Sync_StatusChanged);
            return;
        }
        _status.Text = _sync.Status;
    }

    private async void Connect_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureAdmin()) return;
        await RunAsync(() => _sync.ConnectAndSyncAsync());
        await RefreshConflictsAsync();
    }

    private async void Sync_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureAdmin()) return;
        await RunAsync(() => _sync.SyncNowAsync());
        await RefreshConflictsAsync();
    }

    private async void Refresh_Click(object sender, RoutedEventArgs e) => await RefreshConflictsAsync();

    private async void Disconnect_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureAdmin()) return;
        if (MessageBox.Show("Google Drive disconnect karna hai? Local POS aur database par koi asar nahi hoga.",
                Title, MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        await RunAsync(async () => { await _sync.DisconnectAsync(); return new DriveSyncSummary(0, 0, 0, DateTimeOffset.UtcNow); });
    }

    private async void KeepWindows_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureAdmin() || Selected is not { } conflict) return;
        await ResolveAsync(conflict, useRemote: false);
    }

    private async void UseRemote_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureAdmin() || Selected is not { } conflict) return;
        if (MessageBox.Show("Remote device ki value apply karni hai? Is se selected Windows record update/delete ho sakta hai. Pehle se safety backup mojood hona zaroori hai.",
                Title, MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        await ResolveAsync(conflict, useRemote: true);
    }

    private async Task ResolveAsync(DriveConflictRow conflict, bool useRemote)
    {
        try
        {
            _access.RequireAdmin();
            await _sync.ResolveConflictAsync(conflict.Id, useRemote);
            await RefreshConflictsAsync();
            _status.Text = _sync.Status;
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, Title, MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private async Task RefreshConflictsAsync()
    {
        try
        {
            _access.RequireAdmin();
            _conflicts.Clear();
            foreach (var conflict in await _sync.GetPendingConflictsAsync()) _conflicts.Add(conflict);
            _status.Text = _sync.Status + $"  |  Pending conflicts: {_conflicts.Count}";
            if (_conflicts.Count == 0) { _localPayload.Clear(); _remotePayload.Clear(); }
        }
        catch (Exception ex)
        {
            _status.Text = ex.Message;
        }
    }

    private void ShowSelectedPayloads()
    {
        _localPayload.Text = Selected?.LocalPayload ?? "";
        _remotePayload.Text = Selected?.RemotePayload ?? "";
    }

    private async Task RunAsync(Func<Task<DriveSyncSummary>> action)
    {
        try
        {
            _access.RequireAdmin();
            _status.Text = "Please wait...";
            var summary = await action();
            _status.Text = _sync.Status + $"  |  Imported: {summary.ImportedDeviceSnapshots}, skipped: {summary.SkippedProcessedSnapshots}, conflicts: {summary.PendingConflicts}";
        }
        catch (Exception ex)
        {
            _status.Text = _sync.Status;
            MessageBox.Show(ex.Message, Title, MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private bool EnsureAdmin()
    {
        try { _access.RequireAdmin(); return true; }
        catch (UnauthorizedAccessException ex)
        {
            MessageBox.Show(ex.Message, Title, MessageBoxButton.OK, MessageBoxImage.Warning);
            return false;
        }
    }
}
