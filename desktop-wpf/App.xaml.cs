using System.Windows;
using KhanBabaPos.Wpf.Services;

namespace KhanBabaPos.Wpf;

public partial class App : Application
{
    private AccessService? _access;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        ShutdownMode = ShutdownMode.OnExplicitShutdown;
        try
        {
            _access = new AccessService();
            AccessService.RegisterProcess(_access);
            var login = new LoginWindow(_access);
            if (login.ShowDialog() != true || login.Session is null)
            {
                Shutdown();
                return;
            }
            var main = new MainWindow(_access, login.Session);
            MainWindow = main;
            main.Show();
            ShutdownMode = ShutdownMode.OnMainWindowClose;
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "Khan Baba POS startup", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(-1);
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        if (_access is not null)
        {
            _access.Logout();
            AccessService.ClearProcess(_access);
        }
        base.OnExit(e);
    }
}
