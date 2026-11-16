using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using KhanBabaPos.Wpf.Services;

namespace KhanBabaPos.Wpf;

public sealed class LoginWindow : Window
{
    private readonly AccessService _access;
    private readonly TextBox _username = new() { MinWidth = 260, Padding = new Thickness(9) };
    private readonly TextBox _displayName = new() { MinWidth = 260, Padding = new Thickness(9) };
    private readonly PasswordBox _password = new() { MinWidth = 260, Padding = new Thickness(9) };
    private readonly PasswordBox _confirm = new() { MinWidth = 260, Padding = new Thickness(9) };
    private readonly TextBlock _displayNameLabel = new() { Text = "Admin ka naam", Margin = new Thickness(0, 10, 0, 4) };
    private readonly TextBlock _confirmLabel = new() { Text = "Confirm password", Margin = new Thickness(0, 10, 0, 4) };
    private readonly TextBlock _message = new() { Foreground = Brushes.Firebrick, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 0) };
    private readonly Button _submit = new() { Content = "Login", Padding = new Thickness(12, 9, 12, 9), Margin = new Thickness(0, 18, 0, 0), MinWidth = 120 };
    private readonly bool _setupMode;

    public AccessSession? Session { get; private set; }

    public LoginWindow(AccessService access)
    {
        _access = access;
        _setupMode = access.RequiresFirstRunSetup;
        Title = _setupMode ? "Khan Baba POS — First-time Admin Setup" : "Khan Baba POS — Login";
        Width = 430;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = new SolidColorBrush(Color.FromRgb(243, 246, 244));

        _submit.Content = _setupMode ? "Create Admin & Continue" : "Login";
        _submit.Click += Submit_Click;
        _password.KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Enter) Submit_Click(this, new RoutedEventArgs()); };
        _username.Text = Environment.UserName;

        var panel = new StackPanel { Margin = new Thickness(30) };
        panel.Children.Add(new TextBlock { Text = "KHAN BABA GENERAL STORE", FontSize = 21, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Color.FromRgb(23, 59, 50)) });
        panel.Children.Add(new TextBlock { Text = _setupMode ? "Pehli dafa Admin account banayein" : "Apne staff account se login karein", Foreground = Brushes.DimGray, Margin = new Thickness(0, 5, 0, 18) });
        panel.Children.Add(new TextBlock { Text = "Username", Margin = new Thickness(0, 0, 0, 4) });
        panel.Children.Add(_username);
        _displayNameLabel.Visibility = _setupMode ? Visibility.Visible : Visibility.Collapsed;
        panel.Children.Add(_displayNameLabel);
        _displayName.Visibility = _setupMode ? Visibility.Visible : Visibility.Collapsed;
        panel.Children.Add(_displayName);
        panel.Children.Add(new TextBlock { Text = "Password", Margin = new Thickness(0, 10, 0, 4) });
        panel.Children.Add(_password);
        _confirmLabel.Visibility = _setupMode ? Visibility.Visible : Visibility.Collapsed;
        panel.Children.Add(_confirmLabel);
        _confirm.Visibility = _setupMode ? Visibility.Visible : Visibility.Collapsed;
        panel.Children.Add(_confirm);
        panel.Children.Add(_message);
        panel.Children.Add(_submit);
        Content = new Border { Background = Brushes.White, CornerRadius = new CornerRadius(12), Padding = new Thickness(4), Child = panel };
    }

    private void Submit_Click(object? sender, RoutedEventArgs e)
    {
        try
        {
            Session = _setupMode
                ? _access.ProvisionFirstAdmin(_username.Text, _displayName.Text, MatchPasswords())
                : _access.Authenticate(_username.Text, _password.Password);
            DialogResult = true;
        }
        catch (Exception ex) when (ex is ArgumentException or InvalidOperationException or UnauthorizedAccessException or System.Security.Cryptography.CryptographicException or IOException)
        {
            _message.Text = ex.Message;
        }
    }

    private string MatchPasswords()
    {
        if (_password.Password != _confirm.Password)
            throw new ArgumentException("Dono passwords match nahi karte.");
        return _password.Password;
    }
}
