using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using KhanBabaPos.Wpf.Services;

namespace KhanBabaPos.Wpf;

public partial class MainWindow : Window
{
    public ObservableCollection<CartLine> CartLines { get; } = [];
    public ObservableCollection<CustomerLookup> Customers { get; } = [];
    public ObservableCollection<PendingBillSnapshot> PendingBills { get; } = [];

    private readonly ProductLookupService _products = new();
    private readonly CustomerLookupService _customers = new();
    private readonly SalePostingService _sales;
    private readonly AccessService _access;
    private readonly AccessSession _session;
    private readonly WindowsDriveSyncService _driveSync;
    private IReadOnlyList<CustomerLookup> _allCustomers = [];
    private readonly PendingBillService _pendingBills = new();
    private readonly DispatcherTimer _searchTimer;
    private readonly DispatcherTimer _pendingSaveTimer;
    private CancellationTokenSource? _searchCts;
    private string _activeBillId = Guid.NewGuid().ToString("N");
    private bool _suppressPersistence;
    private bool _suppressPendingSelection;
    private bool _checkoutInProgress;
    private int? _recalledSaleId;

    public MainWindow(AccessService access, AccessSession session)
    {
        _access = access;
        _session = session;
        _sales = new SalePostingService(access);
        _driveSync = new WindowsDriveSyncService(access);
        _driveSync.StartAutoSync();
        Closed += (_, _) => _driveSync.StopAutoSync();
        InitializeComponent();
        DataContext = this;

        SaleTypeBox.Items.Add("Walk-in");
        SaleTypeBox.Items.Add("Khata");
        SaleTypeBox.Items.Add("Wholesale");
        SaleTypeBox.SelectedItem = "Walk-in";

        PaymentModeBox.Items.Add("Cash");
        PaymentModeBox.Items.Add("Credit");
        PaymentModeBox.Items.Add("Partial");
        PaymentModeBox.SelectedIndex = 0;
        DiscountModeBox.Items.Add("Rupe");
        DiscountModeBox.Items.Add("FeeSad (%)");
        DiscountModeBox.SelectedIndex = 0;

        CartLines.CollectionChanged += (_, args) =>
        {
            if (args.NewItems is not null)
                foreach (CartLine line in args.NewItems) line.PropertyChanged += CartLine_PropertyChanged;
            if (args.OldItems is not null)
                foreach (CartLine line in args.OldItems) line.PropertyChanged -= CartLine_PropertyChanged;
            RefreshTotals();
            SchedulePendingSave();
        };

        _searchTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(180) };
        _searchTimer.Tick += async (_, _) =>
        {
            _searchTimer.Stop();
            await SearchProductsAsync(ScannerBox.Text.Trim());
        };

        _pendingSaveTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(350) };
        _pendingSaveTimer.Tick += async (_, _) =>
        {
            _pendingSaveTimer.Stop();
            await PersistActiveBillAsync();
        };
    }

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        try
        {
            await _products.VerifyDatabaseAsync();
            DatabaseStatusText.Text = "Existing SQLite v18 verified";
            DatabaseStatusText.Foreground = Brushes.SeaGreen;
            SearchStatusText.Text = "Database ready. Scan or search an item.";

            _allCustomers = await _customers.GetCustomersAsync();
            ApplyCustomerTypeFilter();
            CustomerBox.SelectedValue = 0;

            var pending = await _pendingBills.GetAllAsync();
            if (pending.Count > 0)
            {
                _suppressPendingSelection = true;
                PendingBills.Clear();
                foreach (var bill in pending) PendingBills.Add(bill);
                _suppressPendingSelection = false;
                RestoreBill(pending[0]);
            }
            else
            {
                _activeBillId = Guid.NewGuid().ToString("N");
                await RefreshPendingBillsAsync();
            }
        }
        catch (Exception ex)
        {
            DatabaseStatusText.Text = "Database unavailable";
            DatabaseStatusText.Foreground = Brushes.Firebrick;
            SearchStatusText.Text = ex.Message;
        }
        RefreshTotals();
        FocusScanner();
        _ = CheckForUpdatesOnStartupAsync();
    }

    private async Task CheckForUpdatesOnStartupAsync()
    {
        try
        {
            var updater = new NativeUpdateService();
            var update = await updater.CheckForUpdateAsync();
            if (update is null) return;

            UpdateButton.Content = $"⬆ Update {update.Version} available";
            UpdateButton.Background = new SolidColorBrush(Color.FromRgb(220, 239, 226));
            UpdateButton.Foreground = new SolidColorBrush(Color.FromRgb(23, 75, 49));
            UpdateStatusText.Text = "A newer Windows version is available. Admin can open Check for Updates.";
            UpdateStatusText.Foreground = Brushes.SeaGreen;

            // Persist the last notified stable version so startup does not repeat the same popup.
            var notificationDirectory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "KhanBabaPOS");
            Directory.CreateDirectory(notificationDirectory);
            var notificationFile = Path.Combine(notificationDirectory, "last-notified-version.txt");
            var lastNotified = File.Exists(notificationFile)
                ? (await File.ReadAllTextAsync(notificationFile)).Trim()
                : string.Empty;
            var versionText = update.Version.ToString();
            if (!string.Equals(lastNotified, versionText, StringComparison.OrdinalIgnoreCase))
            {
                MessageBox.Show(
                    $"Khan Baba POS ka naya stable version {versionText} available hai.\\n\\n{update.ReleaseNotes}\\n\\nInstaller download/install tab tak disabled rahega jab tak production signing certificate configure nahi hota.",
                    "Khan Baba POS — Update Available",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
                await File.WriteAllTextAsync(notificationFile, versionText);
            }
        }
        catch (Exception ex)
        {
            // Update checks are best-effort and must never block offline billing.
            UpdateStatusText.Text = "Update check unavailable (offline or release not published).";
            UpdateStatusText.Foreground = Brushes.Gray;
            System.Diagnostics.Debug.WriteLine("Khan Baba update check: " + ex.Message);
        }
    }

    private void ApplyCustomerTypeFilter()
    {
        var type = SaleTypeBox.SelectedItem?.ToString() ?? "Walk-in";
        Customers.Clear();
        if (type == "Walk-in")
        {
            Customers.Add(new CustomerLookup(0, "Walk-in Customer", string.Empty, 0, "Walk-in"));
            CustomerBox.SelectedValue = 0;
            return;
        }

        foreach (var customer in _allCustomers.Where(x =>
                     string.Equals(x.CustomerType, type, StringComparison.OrdinalIgnoreCase)))
            Customers.Add(customer);
        CustomerBox.SelectedValue = null;
    }

    private void SaleTypeBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_suppressPersistence)
        {
            ApplyCustomerTypeFilter();
            return;
        }
        if (CartLines.Count > 0 && e.RemovedItems.Count > 0)
        {
            _suppressPersistence = true;
            SaleTypeBox.SelectedItem = e.RemovedItems[0];
            _suppressPersistence = false;
            SearchStatusText.Text = "Customer type change karne se pehle cart clear karein.";
            return;
        }
        ApplyCustomerTypeFilter();
        RefreshTotals();
        SchedulePendingSave();
    }

    private void FocusScanner()
    {
        SuggestionsPopup.IsOpen = false;
        ScannerBox.Focus();
        Keyboard.Focus(ScannerBox);
        ScannerBox.CaretIndex = ScannerBox.Text.Length;
    }

    private void Window_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        // Cashier shortcuts are handled at the window level so they work from
        // the scanner, grid and payment controls without requiring mouse clicks.
        if (e.Key == Key.F2)
        {
            FocusScanner();
            e.Handled = true;
        }
        else if (e.Key == Key.F4)
        {
            CustomerBox.Focus();
            CustomerBox.IsDropDownOpen = true;
            e.Handled = true;
        }
        else if (e.Key == Key.F5 && !_checkoutInProgress)
        {
            _ = CreateNewBillAsync();
            e.Handled = true;
        }
        else if (e.Key == Key.F6)
        {
            DiscountValueBox.Focus();
            DiscountValueBox.SelectAll();
            e.Handled = true;
        }
        else if (e.Key == Key.F7)
        {
            PartialAmountBox.Focus();
            PartialAmountBox.SelectAll();
            e.Handled = true;
        }
        else if (e.Key == Key.F8)
        {
            PaymentModeBox.Focus();
            PaymentModeBox.IsDropDownOpen = true;
            e.Handled = true;
        }
        else if (e.Key == Key.F9 || (e.Key == Key.P && Keyboard.Modifiers == ModifierKeys.Control))
        {
            PrintCurrentBill_Click(this, new RoutedEventArgs());
            e.Handled = true;
        }
        else if (e.Key == Key.F10 && !_checkoutInProgress)
        {
            Checkout_Click(this, new RoutedEventArgs());
            e.Handled = true;
        }
        else if (e.Key == Key.Escape)
        {
            if (SuggestionsList.IsKeyboardFocusWithin)
            {
                FocusScanner();
                e.Handled = true;
            }
        }
    }

    private void ScannerBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        _searchTimer.Stop();
        _searchCts?.Cancel();
        SuggestionsPopup.IsOpen = false;
        SuggestionsList.ItemsSource = null;
        if (string.IsNullOrWhiteSpace(ScannerBox.Text))
        {
            SearchStatusText.Text = "Ready for barcode scan.";
            return;
        }
        SearchStatusText.Text = "Searching products…";
        _searchTimer.Start();
    }

    private async Task SearchProductsAsync(string query)
    {
        _searchCts?.Cancel();
        _searchCts?.Dispose();
        _searchCts = new CancellationTokenSource();
        var token = _searchCts.Token;
        try
        {
            var results = await _products.SearchAsync(query, token);
            if (token.IsCancellationRequested || !string.Equals(query, ScannerBox.Text.Trim(), StringComparison.Ordinal))
                return;
            SuggestionsList.ItemsSource = results;
            SuggestionsPopup.IsOpen = results.Count > 0;
            SearchStatusText.Text = results.Count == 0
                ? "No matching product found."
                : $"{results.Count} matching product(s). Press Enter to add the highlighted result.";
            if (results.Count > 0) SuggestionsList.SelectedIndex = 0;
        }
        catch (OperationCanceledException) { }
        catch (Exception ex) { SearchStatusText.Text = "Product search failed: " + ex.Message; }
    }

    private async void ScannerBox_KeyDown(object sender, KeyEventArgs e)
    {
        if ((e.Key == Key.Down || e.Key == Key.Up) && SuggestionsList.Items.Count > 0)
        {
            SuggestionsPopup.IsOpen = true;
            SuggestionsList.SelectedIndex = e.Key == Key.Down
                ? Math.Clamp(SuggestionsList.SelectedIndex < 0 ? 0 : SuggestionsList.SelectedIndex, 0, SuggestionsList.Items.Count - 1)
                : SuggestionsList.Items.Count - 1;
            SuggestionsList.Focus();
            SuggestionsList.ScrollIntoView(SuggestionsList.SelectedItem);
            e.Handled = true;
            return;
        }
        if (e.Key != Key.Enter) return;
        e.Handled = true;
        var query = ScannerBox.Text.Trim();
        if (query.Length == 0) return;
        try
        {
            var exact = await _products.FindExactBarcodeAsync(query);
            if (exact is not null)
            {
                AddProduct(exact);
                return;
            }
            if (SuggestionsList.SelectedItem is ProductLookup selected)
            {
                AddProduct(selected);
                return;
            }
            await SearchProductsAsync(query);
            if (SuggestionsList.Items.Count > 0 && SuggestionsList.Items[0] is ProductLookup first)
                AddProduct(first);
        }
        catch (Exception ex) { SearchStatusText.Text = "Scan lookup failed: " + ex.Message; }
    }

    private void SuggestionsList_SelectionChanged(object sender, SelectionChangedEventArgs e) { }

    private void SuggestionsList_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter && SuggestionsList.SelectedItem is ProductLookup selected)
        {
            AddProduct(selected);
            e.Handled = true;
        }
        else if (e.Key == Key.Escape)
        {
            FocusScanner();
            e.Handled = true;
        }
    }

    private void SuggestionsList_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (SuggestionsList.SelectedItem is ProductLookup selected) AddProduct(selected);
    }

    private void CartLine_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        RefreshTotals();
        SchedulePendingSave();
    }

    private void AddProduct(ProductLookup product)
    {
        var existing = CartLines.FirstOrDefault(x => string.Equals(x.Barcode, product.Barcode, StringComparison.Ordinal));
        var inCart = existing?.Quantity ?? 0;
        if (product.Quantity <= inCart)
        {
            SearchStatusText.Text = $"Available stock is only {product.Quantity} {product.StockUnit}.";
            FocusScanner();
            return;
        }

        var isWholesale = SaleTypeBox.SelectedItem?.ToString() == "Wholesale";
        var chosenPrice = isWholesale && product.WholesalePrice > 0 ? product.WholesalePrice : product.Price;
        var safePrice = Math.Max(chosenPrice, product.PurchasePrice);
        if (existing is null)
            CartLines.Add(new CartLine(product.Name, product.Barcode, safePrice, 1,
                product.PurchasePrice, product.StockUnit, product.Quantity));
        else
            existing.Quantity = Math.Min(existing.Quantity + 1, product.Quantity);

        ScannerBox.Clear();
        SuggestionsPopup.IsOpen = false;
        SuggestionsList.ItemsSource = null;
        SearchStatusText.Text = $"{product.Name} added. Scan the next item.";
        RefreshTotals();
        FocusScanner();
    }

    private double Subtotal => CartLines.Sum(x => x.LineTotal);
    private double DiscountValue => double.TryParse(DiscountValueBox.Text, NumberStyles.Number,
        CultureInfo.InvariantCulture, out var value) ? value : 0;
    private bool IsPercentageDiscount => DiscountModeBox.SelectedIndex == 1;
    private double CalculatedDiscount => IsPercentageDiscount ? Subtotal * DiscountValue / 100d : DiscountValue;
    private double FinalTotal => Math.Max(0d, Subtotal - CalculatedDiscount);

    private void RefreshTotals()
    {
        if (SubtotalText is null) return;
        SubtotalText.Text = $"Rs. {Subtotal:N2}";
        FinalTotalText.Text = $"Rs. {FinalTotal:N2}";
        DiscountPreviewText.Text = $"Discount: Rs. {CalculatedDiscount:N2}";
        CartCountText.Text = $"{CartLines.Sum(x => x.Quantity)} units • {CartLines.Count} lines";
        CheckoutButton.IsEnabled = CartLines.Count > 0 && !_checkoutInProgress;
        PrintBillButton.IsEnabled = CartLines.Count > 0 && !_checkoutInProgress;
        var saleType = SaleTypeBox.SelectedItem?.ToString() ?? "Walk-in";
        var walkIn = saleType == "Walk-in";
        if (CartGrid.Columns.Count > 3)
            CartGrid.Columns[3].IsReadOnly = saleType != "Wholesale";
        PaymentModeBox.IsEnabled = !walkIn;
        if (walkIn && PaymentModeBox.SelectedItem?.ToString() != "Cash")
            PaymentModeBox.SelectedItem = "Cash";
        PartialAmountBox.Visibility = PaymentModeBox.SelectedItem?.ToString() == "Partial"
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void CheckoutFields_TextChanged(object sender, TextChangedEventArgs e)
    {
        RefreshTotals();
        SchedulePendingSave();
    }

    private void CheckoutFields_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        RefreshTotals();
        SchedulePendingSave();
    }

    private void CustomerBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        RefreshTotals();
        SchedulePendingSave();
    }

    private void PaymentModeBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        RefreshTotals();
        SchedulePendingSave();
    }

    private void SchedulePendingSave()
    {
        if (_suppressPersistence || _checkoutInProgress || !IsLoaded) return;
        _pendingSaveTimer.Stop();
        _pendingSaveTimer.Start();
    }

    private async Task PersistActiveBillAsync()
    {
        if (_suppressPersistence || _checkoutInProgress || !IsLoaded) return;
        try
        {
            if (CartLines.Count == 0)
            {
                await _pendingBills.DeleteAsync(_activeBillId);
            }
            else
            {
                var snapshot = new PendingBillSnapshot(
                    _activeBillId,
                    BillLabel(_activeBillId),
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture),
                    CartLines.Select(x => new PendingBillLine(x.Barcode, x.Name, x.Price, x.Quantity,
                        x.PurchasePrice, x.StockUnit)).ToList(),
                    SelectedCustomerId,
                    SaleTypeBox.SelectedItem?.ToString() ?? "Walk-in",
                    PaymentModeBox.SelectedItem?.ToString() ?? "Cash",
                    DiscountValue,
                    IsPercentageDiscount,
                    PartialAmountBox.Text);
                await _pendingBills.SaveAsync(snapshot);
            }
            await RefreshPendingBillsAsync();
        }
        catch (Exception ex)
        {
            SearchStatusText.Text = "Pending bill save failed: " + ex.Message;
        }
    }

    private int? SelectedCustomerId
    {
        get
        {
            if (SaleTypeBox.SelectedItem?.ToString() != "Walk-in" && CustomerBox.SelectedValue is int id && id > 0) return id;
            return null;
        }
    }

    private string BillLabel(string billId) => "Bill #" +
        (billId.Length > 4 ? billId[^4..] : billId);

    private async Task RefreshPendingBillsAsync()
    {
        var selectedId = _activeBillId;
        var pending = await _pendingBills.GetAllAsync();
        _suppressPendingSelection = true;
        PendingBills.Clear();
        foreach (var bill in pending) PendingBills.Add(bill);
        PendingBillsBox.SelectedValue = selectedId;
        _suppressPendingSelection = false;
    }

    private void RestoreBill(PendingBillSnapshot bill)
    {
        _suppressPersistence = true;
        _activeBillId = bill.BillId;
        CartLines.Clear();
        foreach (var line in bill.Cart)
            CartLines.Add(new CartLine(line.Name, line.Barcode, line.SalePrice, line.Quantity,
                line.PurchasePrice, line.StockUnit, int.MaxValue));
        SaleTypeBox.SelectedItem = bill.SelectedSaleType;
        ApplyCustomerTypeFilter();
        CustomerBox.SelectedValue = bill.SelectedCustomerId ?? 0;
        PaymentModeBox.SelectedItem = bill.CustomerPaymentMode;
        DiscountModeBox.SelectedIndex = bill.IsPercentageDiscount ? 1 : 0;
        DiscountValueBox.Text = bill.OverallDiscount.ToString(CultureInfo.InvariantCulture);
        PartialAmountBox.Text = bill.ReceivedAmount;
        _suppressPersistence = false;
        _suppressPendingSelection = true;
        PendingBillsBox.SelectedValue = bill.BillId;
        _suppressPendingSelection = false;
        RefreshTotals();
        FocusScanner();
    }

    private async void PendingBillsBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_suppressPendingSelection || PendingBillsBox.SelectedItem is not PendingBillSnapshot selected ||
            selected.BillId == _activeBillId) return;
        await PersistActiveBillAsync();
        RestoreBill(selected);
    }

    private async Task CreateNewBillAsync()
    {
        if (_checkoutInProgress) return;
        await PersistActiveBillAsync();
        _suppressPersistence = true;
        _activeBillId = Guid.NewGuid().ToString("N");
        _recalledSaleId = null;
        CartLines.Clear();
        SaleTypeBox.SelectedItem = "Walk-in";
        ApplyCustomerTypeFilter();
        CustomerBox.SelectedValue = 0;
        PaymentModeBox.SelectedItem = "Cash";
        DiscountModeBox.SelectedIndex = 0;
        DiscountValueBox.Text = "0";
        PartialAmountBox.Clear();
        _suppressPersistence = false;
        await RefreshPendingBillsAsync();
        SearchStatusText.Text = "New bill ready.";
        RefreshTotals();
        FocusScanner();
    }

    private async void NewSale_Click(object sender, RoutedEventArgs e) => await CreateNewBillAsync();

    private void RemoveSelected_Click(object sender, RoutedEventArgs e)
    {
        if (CartGrid.SelectedItem is CartLine selected) CartLines.Remove(selected);
        FocusScanner();
    }

    private void ClearBill_Click(object sender, RoutedEventArgs e)
    {
        CartLines.Clear();
        FocusScanner();
    }

    private async void PrintCurrentBill_Click(object sender, RoutedEventArgs e)
    {
        if (CartLines.Count == 0)
        {
            MessageBox.Show("Print/Preview ke liye pehle bill mein item add karein.",
                "Current Bill", MessageBoxButton.OK, MessageBoxImage.Information);
            FocusScanner();
            return;
        }

        if (!double.TryParse(DiscountValueBox.Text, NumberStyles.Number,
                CultureInfo.InvariantCulture, out var discountValue) ||
            !double.IsFinite(discountValue) || discountValue < 0 ||
            (IsPercentageDiscount && discountValue > 100) ||
            (!IsPercentageDiscount && discountValue > Subtotal))
        {
            MessageBox.Show("Bill discount ki value check karein.",
                "Current Bill", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var paymentMode = PaymentModeBox.SelectedItem?.ToString() ?? "Cash";
        var received = paymentMode switch
        {
            "Cash" => FinalTotal,
            "Partial" when double.TryParse(PartialAmountBox.Text, NumberStyles.Number,
                CultureInfo.InvariantCulture, out var partial) && double.IsFinite(partial) && partial >= 0 => partial,
            _ => 0d
        };
        if (paymentMode == "Partial" && (received <= 0 || received >= FinalTotal))
        {
            MessageBox.Show("Partial received amount zero se zyada aur net total se kam hona chahiye.",
                "Current Bill", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var customerName = CustomerBox.SelectedItem is CustomerLookup customer
            ? customer.Name
            : "Walk-in Customer";
        var sale = new SaleHistoryRecord(
            0,
            DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture),
            customerName,
            SaleTypeBox.SelectedItem?.ToString() ?? "Walk-in",
            paymentMode,
            Subtotal,
            CalculatedDiscount,
            FinalTotal,
            received,
            Math.Max(0d, FinalTotal - received),
            "Local Windows User",
            0,
            0,
            SelectedCustomerId);
        var items = CartLines.Select((line, index) => new SaleHistoryItem(
            index + 1,
            line.Barcode,
            line.Name,
            line.Quantity,
            line.StockUnit,
            line.Price,
            line.PurchasePrice,
            line.LineTotal,
            line.PurchasePrice * line.Quantity)).ToList();

        // Persist the current draft before opening print preview. This is still a
        // pending bill only; stock and the sales ledger change only on Complete Sale.
        await PersistActiveBillAsync();
        new PrinterInvoiceWindow(sale, items, printImmediately: true) { Owner = this }.ShowDialog();
        FocusScanner();
    }


    private async void RecallBill_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            _access.RequireRole(AccessRole.Admin, AccessRole.Salesman);
            // Preserve the active unsaved cart as a pending bill before replacing it with a recalled invoice.
            await PersistActiveBillAsync();
            var history = new SalesHistoryService();
            var records = await history.GetSalesAsync();
            if (records.Count == 0)
            {
                MessageBox.Show("Abhi koi saved bill mojood nahi.", "Recall Bill", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            var grid = new DataGrid
            {
                ItemsSource = records,
                AutoGenerateColumns = true,
                IsReadOnly = true,
                SelectionMode = DataGridSelectionMode.Single,
                SelectionUnit = DataGridSelectionUnit.FullRow,
                Margin = new Thickness(10)
            };
            var dialog = new Window
            {
                Title = "Recall / Recent Bills",
                Width = 1050,
                Height = 620,
                MinWidth = 760,
                MinHeight = 420,
                WindowStartupLocation = WindowStartupLocation.CenterOwner,
                Owner = this,
                Background = Brushes.White
            };
            var panel = new DockPanel();
            var select = new Button { Content = "Recall Selected Bill", Padding = new Thickness(14, 9, 14, 9), Margin = new Thickness(10), HorizontalAlignment = HorizontalAlignment.Right };
            select.Click += (_, _) =>
            {
                if (grid.SelectedItem is SaleHistoryRecord) dialog.DialogResult = true;
                else MessageBox.Show("Pehle bill select karein.", "Recall Bill", MessageBoxButton.OK, MessageBoxImage.Information);
            };
            DockPanel.SetDock(select, Dock.Bottom);
            panel.Children.Add(select);
            panel.Children.Add(grid);
            dialog.Content = panel;
            if (dialog.ShowDialog() != true || grid.SelectedItem is not SaleHistoryRecord selected) return;

            var items = await history.GetSaleItemsAsync(selected.SaleId);
            if (items.Count == 0) throw new InvalidOperationException("Selected bill mein items nahi milay.");
            _activeBillId = Guid.NewGuid().ToString("N");
            _suppressPersistence = true;
            CartLines.Clear();
            foreach (var item in items)
                CartLines.Add(new CartLine(item.ProductName, item.Barcode, item.SalePrice, item.Quantity,
                    item.PurchasePrice, item.StockUnit, int.MaxValue));
            SaleTypeBox.SelectedItem = selected.CustomerType;
            ApplyCustomerTypeFilter();
            CustomerBox.SelectedValue = selected.CustomerId ?? 0;
            PaymentModeBox.SelectedItem = selected.PaymentType == "Khata" ? "Credit" :
                selected.PaymentType == "Partial" ? "Partial" : "Cash";
            PartialAmountBox.Text = selected.Received.ToString(CultureInfo.InvariantCulture);
            DiscountModeBox.SelectedItem = "Rupe";
            DiscountValueBox.Text = selected.Discount.ToString(CultureInfo.InvariantCulture);
            _recalledSaleId = selected.SaleId;
            _suppressPersistence = false;
            RefreshTotals();
            SearchStatusText.Text = $"Bill #{selected.SaleId} recalled. Checkout par Update Existing ya Save as New choose karein.";
            FocusScanner();
        }
        catch (Exception ex)
        {
            _suppressPersistence = false;
            MessageBox.Show(ex.Message, "Recall Bill", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private async void Checkout_Click(object sender, RoutedEventArgs e)
    {
        try { _access.RequireRole(AccessRole.Admin, AccessRole.Salesman); }
        catch (UnauthorizedAccessException ex) { MessageBox.Show(ex.Message, "Login required", MessageBoxButton.OK, MessageBoxImage.Warning); return; }
        if (_checkoutInProgress || CartLines.Count == 0) return;
        try
        {
            var subtotal = Subtotal;
            if (!double.TryParse(DiscountValueBox.Text, NumberStyles.Number, CultureInfo.InvariantCulture, out var discountValue) ||
                !double.IsFinite(discountValue) || discountValue < 0 ||
                (IsPercentageDiscount && discountValue > 100) ||
                (!IsPercentageDiscount && discountValue > subtotal))
                throw new InvalidOperationException(IsPercentageDiscount
                    ? "Discount 0 se 100 percent ke darmiyan hona chahiye."
                    : "Discount subtotal se zyada nahi ho sakta.");

            double? partial = null;
            if (PaymentModeBox.SelectedItem?.ToString() == "Partial")
            {
                if (!double.TryParse(PartialAmountBox.Text, NumberStyles.Number, CultureInfo.InvariantCulture, out var parsed))
                    throw new InvalidOperationException("Partial received amount enter karein.");
                partial = parsed;
            }

            _checkoutInProgress = true;
            RefreshTotals();
            var request = new SaleCheckoutRequest(
                CartLines.Select(x => new SaleLineInput(x.Barcode, x.Quantity, x.Price)).ToList(),
                SelectedCustomerId,
                PaymentModeBox.SelectedItem?.ToString() ?? "Cash",
                partial,
                discountValue,
                IsPercentageDiscount,
                SaleTypeBox.SelectedItem?.ToString() ?? "Walk-in",
                _session.DisplayName,
                _session.UserId);
            SalePostingResult result;
            if (_recalledSaleId is not null)
            {
                var choice = MessageBox.Show(
                    $"Bill #{_recalledSaleId} recall hua hai.\n\nYes = Existing bill update\nNo = Save as New Bill\nCancel = Wapas",
                    "Recall Bill", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
                if (choice == MessageBoxResult.Cancel) return;
                result = choice == MessageBoxResult.Yes
                    ? await _sales.UpdateSaleFromRecallAsync(_recalledSaleId.Value, request)
                    : await _sales.CompleteSaleAsync(request);
            }
            else result = await _sales.CompleteSaleAsync(request);
            await _pendingBills.DeleteAsync(_activeBillId);

            _suppressPersistence = true;
            CartLines.Clear();
            _recalledSaleId = null;
            _activeBillId = Guid.NewGuid().ToString("N");
            SaleTypeBox.SelectedItem = "Walk-in";
            ApplyCustomerTypeFilter();
            CustomerBox.SelectedValue = 0;
            PaymentModeBox.SelectedItem = "Cash";
            DiscountModeBox.SelectedIndex = 0;
            DiscountValueBox.Text = "0";
            PartialAmountBox.Clear();
            _suppressPersistence = false;
            await RefreshPendingBillsAsync();

            MessageBox.Show(
                $"Sale #{result.SaleId} successfully saved.\nNet total: Rs. {result.FinalAmount:N2}\nReceived: Rs. {result.ReceivedAmount:N2}\nBalance: Rs. {result.BalanceDue:N2}",
                "Khan Baba POS", MessageBoxButton.OK, MessageBoxImage.Information);
            SearchStatusText.Text = $"Sale #{result.SaleId} saved successfully.";
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "Sale could not be completed", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        finally
        {
            _checkoutInProgress = false;
            RefreshTotals();
            FocusScanner();
        }
    }

    private void Khata_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureAdminAccess()) return;
        var khata = new KhataWindow { Owner = this };
        khata.ShowDialog();
        FocusScanner();
    }

    private void SalesHistory_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureAdminAccess()) return;
        var history = new SalesHistoryWindow { Owner = this };
        history.ShowDialog();
        FocusScanner();
    }

    private void Inventory_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureAdminAccess()) return;
        var inventory = new InventoryWindow { Owner = this };
        inventory.ShowDialog();
        FocusScanner();
    }

    private void Reports_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureAdminAccess()) return;
        var reports = new SalesReportsWindow { Owner = this };
        reports.ShowDialog();
        FocusScanner();
    }

    private void Expenses_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureAdminAccess()) return;
        var expenses = new ExpensesWindow { Owner = this };
        expenses.ShowDialog();
        FocusScanner();
    }

    private void Reminders_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureAdminAccess()) return;
        var reminders = new RemindersWindow { Owner = this };
        reminders.ShowDialog();
        FocusScanner();
    }

    private void Purchases_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureAdminAccess()) return;
        var purchases = new PurchasesWindow { Owner = this };
        purchases.ShowDialog();
        FocusScanner();
    }

    private void ProfitLoss_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureAdminAccess()) return;
        var report = new ProfitLossWindow { Owner = this };
        report.ShowDialog();
        FocusScanner();
    }

    private void Parties_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureAdminAccess()) return;
        var parties = new PartiesWindow { Owner = this };
        parties.ShowDialog();
        FocusScanner();
    }

    private async Task FlushActiveBillBeforeRestoreAsync()
    {
        if (CartLines.Count == 0)
        {
            await _pendingBills.DeleteAsync(_activeBillId);
            return;
        }

        var snapshot = new PendingBillSnapshot(
            _activeBillId,
            BillLabel(_activeBillId),
            DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture),
            CartLines.Select(x => new PendingBillLine(x.Barcode, x.Name, x.Price, x.Quantity,
                x.PurchasePrice, x.StockUnit)).ToList(),
            SelectedCustomerId,
            SaleTypeBox.SelectedItem?.ToString() ?? "Walk-in",
            PaymentModeBox.SelectedItem?.ToString() ?? "Cash",
            DiscountValue,
            IsPercentageDiscount,
            PartialAmountBox.Text);
        await _pendingBills.SaveAsync(snapshot);
    }

    private async void BackupRestore_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureAdminAccess()) return;
        try
        {
            await FlushActiveBillBeforeRestoreAsync();
            var window = new BackupRestoreWindow { Owner = this };
            window.ShowDialog();
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "Backup & Restore", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        FocusScanner();
    }

    private async void Logout_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show("Logout karna hai? Current bill save kar diya jayega.", "Logout", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        try { await FlushActiveBillBeforeRestoreAsync(); }
        catch (Exception ex) { MessageBox.Show(ex.Message, "Logout", MessageBoxButton.OK, MessageBoxImage.Warning); return; }
        _access.Logout();
        var login = new LoginWindow(_access);
        if (login.ShowDialog() == true && login.Session is not null)
        {
            var next = new MainWindow(_access, login.Session);
            Application.Current.MainWindow = next;
            next.Show();
        }
        else Application.Current.Shutdown();
        Close();
    }

    private async void CheckUpdates_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureAdminAccess()) return;
        var updater = new NativeUpdateService();
        try
        {
            var update = await updater.CheckForUpdateAsync();
            if (update is null)
            {
                MessageBox.Show("Apka POS latest release par hai.", "Software Update", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            var message = $"New version {update.Version} available hai.\\n\\n{update.ReleaseNotes}";
            if (!updater.CanInstallSignedUpdates)
            {
                MessageBox.Show(message + "\\n\\nDownload/install filhal disabled hai jab tak production code-signing certificate configure nahi hota.", "Update available — installation pending", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            if (MessageBox.Show(message + "\\n\\nUpdate install karna hai?", "Software Update", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
            var progress = new Progress<NativeUpdateProgress>(value =>
            {
                UpdateStatusText.Text = $"Verified installer download: {value.Percentage:0}%";
            });
            UpdateButton.IsEnabled = false;
            try
            {
                await updater.DownloadAndStartInstallerAsync(update, progress);
                Application.Current.Shutdown();
            }
            finally
            {
                UpdateButton.IsEnabled = true;
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "Software Update", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void DriveSync_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureAdminAccess()) return;
        new DriveSyncWindow(_driveSync, _access) { Owner = this }.ShowDialog();
        FocusScanner();
    }

    private void Staff_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureAdminAccess()) return;
        new StaffManagementWindow(_access) { Owner = this }.ShowDialog();
        FocusScanner();
    }

    private bool EnsureAdminAccess()
    {
        try { _access.RequireAdmin(); return true; }
        catch (UnauthorizedAccessException ex)
        {
            MessageBox.Show(ex.Message, "Access denied", MessageBoxButton.OK, MessageBoxImage.Warning);
            return false;
        }
    }

    private void ComingSoon_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureAdminAccess()) return;
        MessageBox.Show("This WPF module is not implemented yet. Android app remains unchanged.",
            "Khan Baba POS", MessageBoxButton.OK, MessageBoxImage.Information);
        FocusScanner();
    }
}

public sealed class CartLine : INotifyPropertyChanged
{
    private int _quantity;
    public string Name { get; }
    public string Barcode { get; }
    private double _price;
    public double Price
    {
        get => _price;
        set
        {
            if (!double.IsFinite(value)) return;
            _price = Math.Max(value, PurchasePrice);
            OnPropertyChanged();
            OnPropertyChanged(nameof(LineTotal));
        }
    }
    public double PurchasePrice { get; }
    public string StockUnit { get; }
    public int AvailableStock { get; }
    public int Quantity
    {
        get => _quantity;
        set
        {
            _quantity = Math.Clamp(value, 1, Math.Max(1, AvailableStock));
            OnPropertyChanged();
            OnPropertyChanged(nameof(LineTotal));
        }
    }
    public double LineTotal => Price * Quantity;

    public CartLine(string name, string barcode, double price, int quantity,
        double purchasePrice, string stockUnit, int availableStock)
    {
        Name = name;
        Barcode = barcode;
        _price = Math.Max(price, purchasePrice);
        PurchasePrice = purchasePrice;
        StockUnit = stockUnit;
        AvailableStock = availableStock;
        _quantity = Math.Clamp(quantity, 1, Math.Max(1, availableStock));
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
