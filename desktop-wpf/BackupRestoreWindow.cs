using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using KhanBabaPos.Wpf.Data;
using KhanBabaPos.Wpf.Services;

namespace KhanBabaPos.Wpf;

public sealed class BackupRestoreWindow : Window
{
    private readonly DatabaseBackupService _service = new();
    private readonly ObservableCollection<BackupFileInfo> _backups = [];
    private readonly ListView _list = new() { MinHeight = 220 };
    private readonly TextBlock _status = new() { TextWrapping = TextWrapping.Wrap, Foreground = System.Windows.Media.Brushes.DimGray };

    public BackupRestoreWindow()
    {
        Title = "Backup & Restore | Khan Baba POS";
        Width = 760;
        Height = 560;
        MinWidth = 620;
        MinHeight = 460;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = System.Windows.Media.Brushes.WhiteSmoke;
        Content = BuildLayout();
        Loaded += async (_, _) => await RefreshAsync();
    }

    private UIElement BuildLayout()
    {
        var root = new DockPanel { Margin = new Thickness(20) };
        var title = new StackPanel { Margin = new Thickness(0, 0, 0, 14) };
        title.Children.Add(new TextBlock
        {
            Text = "Database Backup & Restore",
            FontSize = 24,
            FontWeight = FontWeights.Bold,
            Foreground = System.Windows.Media.Brushes.DarkSlateGray
        });
        title.Children.Add(new TextBlock
        {
            Text = "Backup makes a verified copy. Restore never overwrites the current database; it activates a verified staged copy and restarts the app.",
            TextWrapping = TextWrapping.Wrap,
            Foreground = System.Windows.Media.Brushes.DimGray,
            Margin = new Thickness(0, 5, 0, 0)
        });
        DockPanel.SetDock(title, Dock.Top);
        root.Children.Add(title);

        _list.ItemsSource = _backups;
        _list.DisplayMemberPath = "Name";
        _list.SelectionMode = SelectionMode.Single;
        DockPanel.SetDock(_list, Dock.Top);
        root.Children.Add(_list);

        var footer = new StackPanel { Margin = new Thickness(0, 12, 0, 0) };
        var buttons = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Right };
        var refresh = MakeButton("Refresh");
        refresh.Click += async (_, _) => await RefreshAsync();
        var backup = MakeButton("Create Backup Now");
        backup.Click += async (_, _) => await CreateBackupAsync();
        var restore = MakeButton("Restore from File");
        restore.Click += async (_, _) => await RestoreAsync();
        var openFolder = MakeButton("Open Backup Folder");
        openFolder.Click += (_, _) => OpenBackupFolder();
        buttons.Children.Add(refresh);
        buttons.Children.Add(backup);
        buttons.Children.Add(restore);
        buttons.Children.Add(openFolder);
        footer.Children.Add(buttons);
        _status.Margin = new Thickness(0, 10, 0, 0);
        footer.Children.Add(_status);
        DockPanel.SetDock(footer, Dock.Bottom);
        root.Children.Add(footer);
        return root;
    }

    private static Button MakeButton(string text) => new()
    {
        Content = text,
        Padding = new Thickness(12, 8, 12, 8),
        Margin = new Thickness(6, 0, 0, 0),
        Background = System.Windows.Media.Brushes.White,
        BorderBrush = System.Windows.Media.Brushes.LightGray,
        Cursor = System.Windows.Input.Cursors.Hand
    };

    private async Task RefreshAsync()
    {
        try
        {
            var dataDirectory = PosDatabasePath.GetDirectory();
            _backups.Clear();
            foreach (var backup in DatabaseBackupService.ListBackups(dataDirectory))
                _backups.Add(backup);
            _status.Text = $"{_backups.Count:N0} verified backup file(s) found. Current database: {PosDatabasePath.Resolve()}";
        }
        catch (Exception ex)
        {
            _status.Text = "Backup list load failed: " + ex.Message;
        }
        await Task.CompletedTask;
    }

    private async Task CreateBackupAsync()
    {
        try
        {
            var databasePath = PosDatabasePath.Resolve();
            var directory = Path.GetDirectoryName(databasePath)!;
            var backupPath = await _service.CreateBackupAsync(databasePath, Path.Combine(directory, "Backups"));
            await RefreshAsync();
            _status.Text = "Verified backup created: " + backupPath;
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "Backup failed", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private async Task RestoreAsync()
    {
        var dialog = new OpenFileDialog
        {
            Title = "Select a verified Khan Baba POS SQLite v18 backup",
            Filter = "Khan Baba POS database (*.db)|*.db|SQLite database (*.sqlite;*.sqlite3)|*.sqlite;*.sqlite3|All files (*.*)|*.*",
            CheckFileExists = true,
            Multiselect = false
        };
        if (dialog.ShowDialog(this) != true) return;

        if (MessageBox.Show(
                "Selected database ka schema v18 aur integrity verify hoga. Current database ki fresh backup banegi. Restore ek nayi file activate karega; current database overwrite/delete nahi hogi. Restore ke baad app band ho kar restart karni hogi. Continue?",
                "Confirm safe restore",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning) != MessageBoxResult.Yes)
            return;

        try
        {
            var currentPath = PosDatabasePath.Resolve();
            var directory = Path.GetDirectoryName(currentPath)!;
            var restoredPath = await _service.RestoreAsync(currentPath, dialog.FileName, directory);
            MessageBox.Show(
                "Restore verified and activated. Existing database aur backups mehfooz hain. App ab band hogi; dobara start karein.",
                "Restore ready",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            Application.Current.Shutdown();
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "Restore failed; current database pointer was not changed", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void OpenBackupFolder()
    {
        try
        {
            var directory = Path.Combine(PosDatabasePath.GetDirectory(), "Backups");
            Directory.CreateDirectory(directory);
            Process.Start(new ProcessStartInfo("explorer.exe", directory) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "Backup folder could not be opened", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }
}
