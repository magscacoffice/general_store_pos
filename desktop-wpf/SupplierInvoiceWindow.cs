using System.Collections.ObjectModel;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using KhanBabaPos.Wpf.Services;

namespace KhanBabaPos.Wpf;

public sealed class SupplierInvoiceWindow : Window
{
    private readonly PartyService _parties = new();
    private readonly InventoryService _inventory = new();
    private readonly PurchaseService _purchases = new();
    private readonly ComboBox _supplier = new() { MinWidth = 260, DisplayMemberPath = "Name" };
    private readonly TextBox _invoiceNumber = new() { MinWidth = 180 };
    private readonly DatePicker _invoiceDate = new() { SelectedDate = DateTime.Today, MinWidth = 150 };
    private readonly TextBox _invoiceTotal = new() { Text = "0" };
    private readonly TextBox _discount = new() { Text = "0" };
    private readonly TextBox _tax = new() { Text = "0" };
    private readonly TextBox _paid = new() { Text = "0" };
    private readonly ComboBox _product = new() { MinWidth = 240, DisplayMemberPath = "Name" };
    private readonly TextBox _newName = new();
    private readonly TextBox _newBarcode = new();
    private readonly TextBox _invoiceQuantity = new() { Text = "1" };
    private readonly TextBox _conversion = new() { Text = "1" };
    private readonly TextBox _stockQuantity = new() { Text = "1" };
    private readonly TextBox _invoiceUnit = new() { Text = "pcs" };
    private readonly TextBox _baseUnit = new() { Text = "pcs" };
    private readonly TextBox _unitCost = new() { Text = "0" };
    private readonly TextBox _lineTotal = new();
    private readonly TextBox _salePrice = new();
    private readonly ObservableCollection<PurchaseInvoiceLineDraft> _lines = [];
    private readonly DataGrid _grid = new() { AutoGenerateColumns = false, IsReadOnly = true, CanUserAddRows = false, RowHeight = 32 };
    private readonly TextBlock _status = new() { Foreground = Brushes.DimGray };
    private IReadOnlyList<PartyRow> _supplierRows = [];
    private IReadOnlyList<InventoryProduct> _products = [];

    public SupplierInvoiceWindow()
    {
        Title = "New Supplier Invoice | Khan Baba POS";
        Width = 1240; Height = 850; MinWidth = 1000; MinHeight = 700;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = Brushes.WhiteSmoke;
        _grid.ItemsSource = _lines;
        ConfigureGrid();
        _product.SelectionChanged += (_, _) => ProductSelected();
        Content = BuildLayout();
        Loaded += async (_, _) => await LoadLookupsAsync();
    }

    private void ConfigureGrid()
    {
        _grid.Columns.Add(new DataGridTextColumn { Header = "Product", Binding = new System.Windows.Data.Binding("DisplayName"), Width = new DataGridLength(1, DataGridLengthUnitType.Star) });
        _grid.Columns.Add(new DataGridTextColumn { Header = "Invoice Qty", Binding = new System.Windows.Data.Binding("InvoiceQuantity"), Width = 85 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "Invoice Unit", Binding = new System.Windows.Data.Binding("UnitLabel"), Width = 85 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "Factor", Binding = new System.Windows.Data.Binding("ConversionFactor"), Width = 65 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "Stock Qty", Binding = new System.Windows.Data.Binding("Quantity"), Width = 75 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "Stock Unit", Binding = new System.Windows.Data.Binding("BaseUnit"), Width = 80 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "Unit Rate", Binding = new System.Windows.Data.Binding("UnitCost") { StringFormat = "N2" }, Width = 90 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "Line Total", Binding = new System.Windows.Data.Binding("LineTotal") { StringFormat = "N2" }, Width = 95 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "Retail Price", Binding = new System.Windows.Data.Binding("SalePrice") { StringFormat = "N2" }, Width = 95 });
    }

    private UIElement BuildLayout()
    {
        var root = new DockPanel { Margin = new Thickness(18) };
        var heading = new StackPanel { Margin = new Thickness(0, 0, 0, 12) };
        heading.Children.Add(new TextBlock { Text = "Supplier Invoice", FontSize = 24, FontWeight = FontWeights.Bold, Foreground = Brushes.DarkSlateGray });
        heading.Children.Add(new TextBlock { Text = "Invoice stock, discounts, tax, payment and supplier payable are saved together.", Foreground = Brushes.DimGray, Margin = new Thickness(0, 4, 0, 0) });
        DockPanel.SetDock(heading, Dock.Top); root.Children.Add(heading);

        var footer = new StackPanel { Margin = new Thickness(0, 10, 0, 0) };
        DockPanel.SetDock(footer, Dock.Bottom);
        footer.Children.Add(_status);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 8, 0, 0) };
        var cancel = Button("Cancel"); cancel.Click += (_, _) => DialogResult = false;
        var save = Button("Post Invoice"); save.Click += async (_, _) => await SaveAsync();
        buttons.Children.Add(cancel); buttons.Children.Add(save); footer.Children.Add(buttons);
        root.Children.Add(footer);

        var scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        var body = new StackPanel();
        body.Children.Add(Section("Invoice details", GridFields(
            ("Supplier *", _supplier), ("Invoice Number *", _invoiceNumber), ("Invoice Date *", _invoiceDate),
            ("Invoice Total (Rs.) *", _invoiceTotal), ("Discount (Rs.)", _discount), ("Tax (Rs.)", _tax), ("Paid Amount (Rs.)", _paid))));
        body.Children.Add(Section("Invoice item entry", GridFields(
            ("Existing Product", _product), ("New Product Name (if new)", _newName), ("New Product Barcode (if new)", _newBarcode),
            ("Invoice Quantity", _invoiceQuantity), ("Pack Conversion Factor", _conversion), ("Stock Quantity", _stockQuantity),
            ("Invoice Unit", _invoiceUnit), ("Stock Unit", _baseUnit), ("Invoice Unit Cost (Rs.)", _unitCost),
            ("Line Total (optional)", _lineTotal), ("Retail Sale Price (optional)", _salePrice))));
        var add = Button("Add Item to Invoice"); add.HorizontalAlignment = HorizontalAlignment.Left; add.Click += (_, _) => AddLine();
        body.Children.Add(add);
        body.Children.Add(new TextBlock { Text = "Invoice items", FontSize = 17, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 14, 0, 7) });
        var border = new Border { BorderBrush = new SolidColorBrush(Color.FromRgb(220, 229, 224)), BorderThickness = new Thickness(1), Background = Brushes.White, MinHeight = 190, Child = _grid };
        body.Children.Add(border);
        scroll.Content = body; root.Children.Add(scroll);
        return root;
    }

    private static UIElement Section(string title, UIElement content)
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 0, 12) };
        panel.Children.Add(new TextBlock { Text = title, FontSize = 17, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 7) });
        panel.Children.Add(content);
        return panel;
    }

    private static UIElement GridFields(params (string Label, Control Control)[] fields)
    {
        var grid = new Grid { Margin = new Thickness(0, 0, 0, 8) };
        for (var i = 0; i < 4; i++) grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var rows = (fields.Length + 3) / 4;
        for (var i = 0; i < rows; i++) grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        for (var i = 0; i < fields.Length; i++)
        {
            var column = i % 4; var row = i / 4;
            var stack = new StackPanel { Margin = new Thickness(0, 0, 10, 8) };
            stack.Children.Add(new TextBlock { Text = fields[i].Label, Margin = new Thickness(0, 0, 0, 4), FontWeight = FontWeights.SemiBold });
            fields[i].Control.Margin = new Thickness(0);
            fields[i].Control.Height = 34;
            stack.Children.Add(fields[i].Control);
            Grid.SetColumn(stack, column); Grid.SetRow(stack, row); grid.Children.Add(stack);
        }
        return grid;
    }

    private static Button Button(string text) => new() { Content = text, Padding = new Thickness(14, 8, 14, 8), Margin = new Thickness(8, 0, 0, 0) };

    private async Task LoadLookupsAsync()
    {
        try
        {
            _supplierRows = await _parties.GetAsync("supplier");
            _products = await _inventory.GetProductsAsync();
            _supplier.ItemsSource = _supplierRows;
            _product.ItemsSource = _products;
            if (_supplierRows.Count == 1) _supplier.SelectedIndex = 0;
            if (_products.Count > 0) _product.SelectedIndex = 0;
        }
        catch (Exception ex) { _status.Text = "Supplier/product list load failed: " + ex.Message; }
    }

    private void ProductSelected()
    {
        if (_product.SelectedItem is not InventoryProduct item) return;
        _baseUnit.Text = string.IsNullOrWhiteSpace(item.StockUnit) ? "pcs" : item.StockUnit;
        _invoiceUnit.Text = _baseUnit.Text;
        _unitCost.Text = item.PurchasePrice.ToString(CultureInfo.InvariantCulture);
        _stockQuantity.Text = _invoiceQuantity.Text;
        _conversion.Text = "1";
    }

    private void AddLine()
    {
        var product = _product.SelectedItem as InventoryProduct;
        if (product is null &&
            (string.IsNullOrWhiteSpace(_newName.Text) || string.IsNullOrWhiteSpace(_newBarcode.Text)))
        {
            _status.Text = "Existing product select karein ya new product ka name aur barcode enter karein.";
            return;
        }
        if (!TryNumber(_invoiceQuantity.Text, out var invoiceQty) || invoiceQty <= 0 ||
            !TryNumber(_conversion.Text, out var factor) || factor <= 0 ||
            !int.TryParse(_stockQuantity.Text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var stockQty) || stockQty <= 0 ||
            !TryNumber(_unitCost.Text, out var unitCost) || unitCost < 0)
        {
            _status.Text = "Invoice quantity, conversion, stock quantity aur unit cost valid enter karein.";
            return;
        }
        var converted = invoiceQty * factor;
        if (!double.IsFinite(converted) || Math.Abs(converted - stockQty) > 0.000001)
        {
            _status.Text = "Invoice quantity × conversion factor stock quantity ke barabar hona chahiye.";
            return;
        }
        double? lineTotal = null;
        if (!string.IsNullOrWhiteSpace(_lineTotal.Text))
        {
            if (!TryNumber(_lineTotal.Text, out var value) || value < 0) { _status.Text = "Line total valid enter karein."; return; }
            lineTotal = value;
        }
        double? salePrice = null;
        if (!string.IsNullOrWhiteSpace(_salePrice.Text))
        {
            if (!TryNumber(_salePrice.Text, out var value) || value < 0) { _status.Text = "Retail sale price valid enter karein."; return; }
            salePrice = value;
        }
        var baseUnit = _baseUnit.Text.Trim();
        if (baseUnit.Length == 0) { _status.Text = "Stock unit zaroor enter karein."; return; }
        _lines.Add(new PurchaseInvoiceLineDraft(
            product?.Id, product?.Name ?? _newName.Text.Trim(), product?.Barcode ?? _newBarcode.Text.Trim(),
            (int)stockQty, invoiceQty, factor, unitCost, _invoiceUnit.Text.Trim(), baseUnit, salePrice,
            lineTotal));
        _newName.Clear(); _newBarcode.Clear(); _lineTotal.Clear(); _salePrice.Clear();
        _status.Text = $"{_lines.Count} invoice item(s) ready.";
    }

    private async Task SaveAsync()
    {
        if (_supplier.SelectedItem is not PartyRow supplier) { _status.Text = "Supplier select karein. Pehle Parties mein supplier add karein."; return; }
        if (_invoiceDate.SelectedDate is null) { _status.Text = "Invoice date select karein."; return; }
        if (!TryNumber(_invoiceTotal.Text, out var total) || !TryNumber(_discount.Text, out var discount) ||
            !TryNumber(_tax.Text, out var tax) || !TryNumber(_paid.Text, out var paid))
        { _status.Text = "Invoice total, discount, tax aur paid amount valid enter karein."; return; }
        if (_lines.Count == 0) { _status.Text = "Invoice mein kam az kam aik item add karein."; return; }
        try
        {
            IsEnabled = false;
            var request = new PurchaseInvoiceRequest(supplier.Id, _invoiceNumber.Text, _invoiceDate.SelectedDate.Value,
                total, discount, tax, paid, _lines.Select(x => x.ToInput()).ToArray());
            await _purchases.RecordInvoiceAsync(request);
            DialogResult = true;
        }
        catch (Exception ex)
        {
            _status.Text = ex.Message;
            IsEnabled = true;
        }
    }

    private static bool TryNumber(string value, out double number) =>
        double.TryParse(value, NumberStyles.Number, CultureInfo.InvariantCulture, out number) && double.IsFinite(number);

    private sealed record PurchaseInvoiceLineDraft(int? ProductId, string Name, string Barcode, int Quantity,
        double InvoiceQuantity, double ConversionFactor, double UnitCost, string UnitLabel, string BaseUnit,
        double? SalePrice, double? LineTotal)
    {
        public string DisplayName => Name + (ProductId is null ? " (new)" : "");
        public PurchaseInvoiceLineInput ToInput() => new(ProductId, ProductId is null ? Name : null,
            ProductId is null ? Barcode : null, Quantity, InvoiceQuantity, ConversionFactor, UnitCost,
            UnitLabel, BaseUnit, SalePrice, LineTotal);
    }
}
