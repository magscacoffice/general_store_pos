using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;

namespace KhanBabaPos.Wpf.Services;

/// <summary>
/// Opens a prefilled WhatsApp chat only after the operator reviews the recipient and message.
/// The app never claims delivery; the operator must press Send inside WhatsApp.
/// </summary>
public static class WhatsAppReminderService
{
    public static string NormalizePakistaniPhone(string phone)
    {
        var digits = new string((phone ?? string.Empty).Where(char.IsDigit).ToArray());
        if (digits.StartsWith("0092", StringComparison.Ordinal)) digits = digits[2..];
        if (digits.StartsWith("0", StringComparison.Ordinal) && digits.Length == 11)
            digits = "92" + digits[1..];
        else if (digits.Length == 10 && digits.StartsWith("3", StringComparison.Ordinal))
            digits = "92" + digits;
        if (digits.Length is < 10 or > 15)
            throw new InvalidOperationException("Customer ka WhatsApp number valid international format mein mojood nahi.");
        return digits;
    }

    public static string BuildMessage(string customerName, double balance) =>
        $"Assalam-o-Alaikum {customerName}, Khan Baba General Store ki taraf se yaad-dihani hai ke apka baqi Khata balance Rs. {balance:N2} hai. Meharbani farma kar sahulat ke mutabiq payment kar dein. Shukriya.";

    public static bool ReviewAndOpen(Window owner, string customerName, string phone, double balance)
    {
        if (!double.IsFinite(balance) || balance <= 0)
            throw new InvalidOperationException("Is customer ka outstanding balance zero hai; reminder ki zaroorat nahi.");
        var recipient = NormalizePakistaniPhone(phone);
        var message = BuildMessage(customerName, balance);
        var dialog = new Window
        {
            Title = "Review WhatsApp Khata Reminder",
            Width = 520,
            Height = 430,
            MinWidth = 440,
            MinHeight = 360,
            Owner = owner,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.CanResize
        };
        var panel = new DockPanel { Margin = new Thickness(18) };
        var recipientText = new TextBlock
        {
            Text = $"Recipient: +{recipient}",
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 0, 0, 10)
        };
        DockPanel.SetDock(recipientText, Dock.Top);
        panel.Children.Add(recipientText);
        var messageBox = new TextBox
        {
            Text = message,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            MinHeight = 190,
            Padding = new Thickness(10)
        };
        panel.Children.Add(messageBox);
        var footer = new StackPanel { Margin = new Thickness(0, 12, 0, 0) };
        var note = new TextBlock
        {
            Text = "WhatsApp chat khulay gi. Message review kar ke WhatsApp mein Send dabayen; delivery app verify nahi kar sakti.",
            TextWrapping = TextWrapping.Wrap,
            Foreground = System.Windows.Media.Brushes.DimGray,
            Margin = new Thickness(0, 0, 0, 10)
        };
        footer.Children.Add(note);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var cancel = new Button { Content = "Cancel", Padding = new Thickness(14, 7, 14, 7), Margin = new Thickness(0, 0, 8, 0) };
        cancel.Click += (_, _) => dialog.DialogResult = false;
        var open = new Button { Content = "Open WhatsApp", Padding = new Thickness(14, 7, 14, 7) };
        open.Click += (_, _) =>
        {
            try
            {
                var url = $"https://wa.me/{recipient}?text={Uri.EscapeDataString(messageBox.Text)}";
                Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
                dialog.DialogResult = true;
            }
            catch (Exception ex)
            {
                MessageBox.Show(ex.Message, "WhatsApp could not be opened", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        };
        buttons.Children.Add(cancel);
        buttons.Children.Add(open);
        footer.Children.Add(buttons);
        DockPanel.SetDock(footer, Dock.Bottom);
        panel.Children.Add(footer);
        dialog.Content = panel;
        var opened = dialog.ShowDialog() == true;
        if (opened)
            MessageBox.Show("WhatsApp chat open kar di gayi hai. Message bhejne ke liye WhatsApp mein Send press karein.",
                "WhatsApp ready", MessageBoxButton.OK, MessageBoxImage.Information);
        return opened;
    }
}
