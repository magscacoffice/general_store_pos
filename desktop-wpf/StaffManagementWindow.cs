using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using KhanBabaPos.Wpf.Services;

namespace KhanBabaPos.Wpf;

public sealed class StaffManagementWindow : Window
{
    private readonly AccessService _access;
    private readonly ObservableCollection<StaffAccount> _staff = [];
    private readonly DataGrid _grid = new() { AutoGenerateColumns = true, IsReadOnly = true, Height = 230, Margin = new Thickness(0, 0, 0, 12) };
    private readonly TextBox _username = new() { MinWidth = 150 };
    private readonly TextBox _name = new() { MinWidth = 180 };
    private readonly PasswordBox _password = new() { MinWidth = 180 };
    private readonly ComboBox _role = new() { MinWidth = 120 };

    public StaffManagementWindow(AccessService access)
    {
        _access = access;
        _access.RequireAdmin();
        Title = "Staff & Access Management";
        Width = 850;
        Height = 620;
        MinWidth = 760;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        _grid.ItemsSource = _staff;
        _role.ItemsSource = Enum.GetValues<AccessRole>();
        _role.SelectedItem = AccessRole.Salesman;

        var root = new StackPanel { Margin = new Thickness(18) };
        root.Children.Add(new TextBlock { Text = "Staff accounts", FontSize = 22, FontWeight = FontWeights.Bold, Margin = new Thickness(0, 0, 0, 12) });
        root.Children.Add(_grid);
        root.Children.Add(new TextBlock { Text = "Naya staff account", FontWeight = FontWeights.Bold, Margin = new Thickness(0, 4, 0, 8) });
        root.Children.Add(new WrapPanel { Children = { Field("Username", _username), Field("Display name", _name), Field("Password", _password), Field("Role", _role) } });
        var actions = new WrapPanel { Margin = new Thickness(0, 12, 0, 0) };
        actions.Children.Add(Action("Create staff", Create_Click));
        actions.Children.Add(Action("Reset selected password", Reset_Click));
        actions.Children.Add(Action("Enable / Disable selected", Toggle_Click));
        actions.Children.Add(Action("Refresh", (_, _) => Refresh()));
        root.Children.Add(actions);
        Content = root;
        Loaded += (_, _) => Refresh();
    }

    private static StackPanel Field(string label, Control control)
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 10, 0) };
        panel.Children.Add(new TextBlock { Text = label, Margin = new Thickness(0, 0, 0, 4) });
        panel.Children.Add(control);
        return panel;
    }

    private static Button Action(string label, RoutedEventHandler click)
    {
        var button = new Button { Content = label, Margin = new Thickness(0, 0, 8, 8), Padding = new Thickness(10, 7, 10, 7) };
        button.Click += click;
        return button;
    }

    private StaffAccount? Selected => _grid.SelectedItem as StaffAccount;

    private void Refresh()
    {
        _access.RequireAdmin();
        _staff.Clear();
        foreach (var user in _access.ListStaff()) _staff.Add(user);
    }

    private void Create_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            _access.CreateStaff(_username.Text, _name.Text, _password.Password,
                _role.SelectedItem is AccessRole role ? role : AccessRole.Salesman);
            _username.Clear(); _name.Clear(); _password.Clear();
            Refresh();
        }
        catch (Exception ex) { MessageBox.Show(ex.Message, Title, MessageBoxButton.OK, MessageBoxImage.Warning); }
    }

    private void Reset_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            if (Selected is not { } user) throw new InvalidOperationException("Pehle staff select karein.");
            var prompt = new PasswordBox { MinWidth = 240, Padding = new Thickness(8) };
            var dialog = new Window { Title = "New password", Content = prompt, SizeToContent = SizeToContent.WidthAndHeight, WindowStartupLocation = WindowStartupLocation.CenterOwner, Owner = this };
            if (dialog.ShowDialog() == true) _access.ResetPassword(user.Id, prompt.Password);
        }
        catch (Exception ex) { MessageBox.Show(ex.Message, Title, MessageBoxButton.OK, MessageBoxImage.Warning); }
    }

    private void Toggle_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            if (Selected is not { } user) throw new InvalidOperationException("Pehle staff select karein.");
            _access.SetEnabled(user.Id, !user.Enabled);
            Refresh();
        }
        catch (Exception ex) { MessageBox.Show(ex.Message, Title, MessageBoxButton.OK, MessageBoxImage.Warning); }
    }
}
