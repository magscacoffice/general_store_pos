using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using KhanBabaPos.Wpf.Services;

namespace KhanBabaPos.Wpf;

public partial class MainWindow : Window
{
    public ObservableCollection<CartLine> CartLines { get; } = [];
    private readonly ProductLookupService _products = new();
    private readonly DispatcherTimer _searchTimer;
    private CancellationTokenSource? _searchCts;

    public MainWindow()
    {
        InitializeComponent();
        DataContext = this;
        CartLines.CollectionChanged += (_, args) =>\n        {\n            if (args.NewItems is not null)\n                foreach (CartLine line in args.NewItems) line.PropertyChanged += CartLine_PropertyChanged;\n            if (args.OldItems is not null)\n                foreach (CartLine line in args.OldItems) line.PropertyChanged -= CartLine_PropertyChanged;\n            RefreshTotals();\n        };
        _searchTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(180) };
        _searchTimer.Tick += async (_, _) => { _searchTimer.Stop(); await SearchProductsAsync(ScannerBox.Text.Trim()); };
    }

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        try
        {
            await _products.VerifyDatabaseAsync();
            DatabaseStatusText.Text = "Existing SQLite v18 verified";
            DatabaseStatusText.Foreground = System.Windows.Media.Brushes.SeaGreen;
            SearchStatusText.Text = "Database ready. Scan or search an item.";
        }
        catch (Exception ex)
        {
            DatabaseStatusText.Text = "Database unavailable";
            DatabaseStatusText.Foreground = System.Windows.Media.Brushes.Firebrick;
            SearchStatusText.Text = ex.Message;
        }
        FocusScanner();
    }

    private void FocusScanner()
    {
        ScannerBox.Focus();
        Keyboard.Focus(ScannerBox);
        ScannerBox.CaretIndex = ScannerBox.Text.Length;
    }

    private void ScannerBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        _searchTimer.Stop();
        if (string.IsNullOrWhiteSpace(ScannerBox.Text))
        {
            SuggestionsList.ItemsSource = null;
            SearchStatusText.Text = "Ready for barcode scan.";
            return;
        }
        _searchTimer.Start();
    }

    private async Task SearchProductsAsync(string query)
    {
        _searchCts?.Cancel(); _searchCts?.Dispose(); _searchCts = new CancellationTokenSource();
        try
        {
            var results = await _products.SearchAsync(query, _searchCts.Token);
            SuggestionsList.ItemsSource = results;
            SearchStatusText.Text = results.Count == 0 ? "No matching product found." : $"{results.Count} matching product(s). Press Enter to add the highlighted result.";
            if (results.Count > 0) SuggestionsList.SelectedIndex = 0;
        }
        catch (OperationCanceledException) { }
        catch (Exception ex) { SearchStatusText.Text = "Product search failed: " + ex.Message; }
    }

    private async void ScannerBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Down && SuggestionsList.Items.Count > 0)
        {
            SuggestionsList.Focus(); SuggestionsList.SelectedIndex = 0; e.Handled = true; return;
        }
        if (e.Key != Key.Enter) return;
        e.Handled = true;
        var query = ScannerBox.Text.Trim();
        if (query.Length == 0) return;
        try
        {
            var exact = await _products.FindExactBarcodeAsync(query);
            if (exact is not null) { AddProduct(exact); return; }
            if (SuggestionsList.SelectedItem is ProductLookup selected) { AddProduct(selected); return; }
            await SearchProductsAsync(query);
            if (SuggestionsList.Items.Count > 0 && SuggestionsList.Items[0] is ProductLookup first) AddProduct(first);
        }
        catch (Exception ex) { SearchStatusText.Text = "Scan lookup failed: " + ex.Message; }
    }

    private void SuggestionsList_SelectionChanged(object sender, SelectionChangedEventArgs e) { }\n\n    private void SuggestionsList_KeyDown(object sender, KeyEventArgs e)\n    {\n        if (e.Key == Key.Enter && SuggestionsList.SelectedItem is ProductLookup selected)\n        { AddProduct(selected); e.Handled = true; }\n        else if (e.Key == Key.Escape) { FocusScanner(); e.Handled = true; }\n    }\n\n    private void SuggestionsList_MouseDoubleClick(object sender, MouseButtonEventArgs e)\n    {\n        if (SuggestionsList.SelectedItem is ProductLookup selected) AddProduct(selected);\n    }\n\n    private void CartLine_PropertyChanged(object? sender, PropertyChangedEventArgs e) => RefreshTotals();

    private void AddProduct(ProductLookup product)
    {
        var existing = CartLines.FirstOrDefault(x => x.ProductId == product.Id);
        if (existing is null) CartLines.Add(new CartLine(product.Id, product.Name, product.Barcode, product.Price, 1));
        else existing.Quantity++;
        ScannerBox.Clear(); SuggestionsList.ItemsSource = null;
        SearchStatusText.Text = $"{product.Name} added. Scan the next item.";
        RefreshTotals(); FocusScanner();
    }

    private void RefreshTotals()
    {
        SubtotalText.Text = $"Rs. {CartLines.Sum(x => x.LineTotal):N2}";
        CartCountText.Text = $"{CartLines.Sum(x => x.Quantity)} units • {CartLines.Count} lines";
    }

    private void NewSale_Click(object sender, RoutedEventArgs e) { CartLines.Clear(); ScannerBox.Clear(); SearchStatusText.Text = "New temporary bill started."; FocusScanner(); }
    private void RemoveSelected_Click(object sender, RoutedEventArgs e) { if (CartGrid.SelectedItem is CartLine selected) CartLines.Remove(selected); FocusScanner(); }
    private void ClearBill_Click(object sender, RoutedEventArgs e) { CartLines.Clear(); FocusScanner(); }
    private void ComingSoon_Click(object sender, RoutedEventArgs e)
    {
        MessageBox.Show("This WPF module is not implemented yet. Android app remains unchanged.", "Khan Baba POS", MessageBoxButton.OK, MessageBoxImage.Information);
        FocusScanner();
    }
}

public sealed class CartLine : INotifyPropertyChanged
{
    private int _quantity;
    public int ProductId { get; }
    public string Name { get; }
    public string Barcode { get; }
    public double Price { get; }
    public int Quantity { get => _quantity; set { _quantity = Math.Max(1, value); OnPropertyChanged(); OnPropertyChanged(nameof(LineTotal)); } }
    public double LineTotal => Price * Quantity;
    public CartLine(int productId, string name, string barcode, double price, int quantity) { ProductId = productId; Name = name; Barcode = barcode; Price = price; _quantity = quantity; }
    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}