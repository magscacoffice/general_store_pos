using System.Collections.ObjectModel;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using KhanBabaPos.Wpf.Services;

namespace KhanBabaPos.Wpf;

public sealed class InventoryWindow : Window
{
    public ObservableCollection<InventoryProduct> Products { get; } = [];
    private readonly InventoryService _service = new();
    private readonly TextBox _search = new();
    private readonly CheckBox _showInactive = new() { Content = "Show inactive", IsChecked = true, VerticalAlignment = VerticalAlignment.Center };
    private readonly DataGrid _grid = new() { AutoGenerateColumns = false, IsReadOnly = true, CanUserAddRows = false,
        EnableRowVirtualization = true, EnableColumnVirtualization = true, RowHeight = 36, ColumnHeaderHeight = 36 };
    private readonly TextBlock _status = new() { VerticalAlignment = VerticalAlignment.Center, Foreground = System.Windows.Media.Brushes.DimGray };
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMilliseconds(250) };

    public InventoryWindow()
    {
        Title = "Inventory | Khan Baba POS";
        Width = 1180; Height = 760; MinWidth = 900; MinHeight = 580;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = System.Windows.Media.Brushes.WhiteSmoke;
        Content = BuildLayout();
        _grid.ItemsSource = Products;
        _search.TextChanged += (_, _) => { _timer.Stop(); _timer.Start(); };
        _showInactive.Checked += async (_, _) => await LoadAsync();
        _showInactive.Unchecked += async (_, _) => await LoadAsync();
        _timer.Tick += async (_, _) => { _timer.Stop(); await LoadAsync(); };
        Loaded += async (_, _) => await LoadAsync();
    }

    private UIElement BuildLayout()
    {
        var root = new DockPanel { Margin = new Thickness(20) };
        var header = new DockPanel { Margin = new Thickness(0,0,0,14), LastChildFill = false };
        var title = new StackPanel();
        title.Children.Add(new TextBlock { Text="Inventory", FontSize=25, FontWeight=FontWeights.Bold, Foreground=System.Windows.Media.Brushes.DarkSlateGray });
        title.Children.Add(new TextBlock { Text="Search, add, edit and manage products. Stock and history deletion rules are enforced.", Margin=new Thickness(0,4,0,0), Foreground=System.Windows.Media.Brushes.DimGray });
        header.Children.Add(title);
        var add = MakeButton("+ Add Product");
        add.Click += async (_, _) => await AddAsync();
        DockPanel.SetDock(add, Dock.Right); header.Children.Add(add);
        DockPanel.SetDock(header, Dock.Top); root.Children.Add(header);

        var toolbar = new DockPanel { Margin = new Thickness(0,0,0,12) };
        _search.Height=36; _search.MinWidth=240; _search.Padding=new Thickness(8,6,8,6);
        _search.ToolTip="Search by product name or barcode";
        toolbar.Children.Add(_search);
        DockPanel.SetDock(_showInactive, Dock.Right); _showInactive.Margin=new Thickness(16,0,16,0); toolbar.Children.Add(_showInactive);
        var refresh=MakeButton("Refresh"); refresh.Click+=async (_,_)=>await LoadAsync();
        DockPanel.SetDock(refresh,Dock.Right); toolbar.Children.Add(refresh);
        DockPanel.SetDock(toolbar,Dock.Top); root.Children.Add(toolbar);

        _grid.Columns.Add(new DataGridTextColumn { Header="Barcode", Binding=new System.Windows.Data.Binding("Barcode"), Width=130 });
        _grid.Columns.Add(new DataGridTextColumn { Header="Product", Binding=new System.Windows.Data.Binding("Name"), Width=new DataGridLength(1,DataGridLengthUnitType.Star) });
        _grid.Columns.Add(new DataGridTextColumn { Header="Stock", Binding=new System.Windows.Data.Binding("Quantity"), Width=70 });
        _grid.Columns.Add(new DataGridTextColumn { Header="Unit", Binding=new System.Windows.Data.Binding("StockUnit"), Width=65 });
        _grid.Columns.Add(new DataGridTextColumn { Header="Damaged", Binding=new System.Windows.Data.Binding("DamagedQuantity"), Width=75 });
        _grid.Columns.Add(new DataGridTextColumn { Header="Cost", Binding=new System.Windows.Data.Binding("PurchasePrice"){StringFormat="N2"}, Width=90 });
        _grid.Columns.Add(new DataGridTextColumn { Header="Sale Price", Binding=new System.Windows.Data.Binding("SalePrice"){StringFormat="N2"}, Width=95 });
        _grid.Columns.Add(new DataGridTextColumn { Header="Status", Binding=new System.Windows.Data.Binding("Status"), Width=80 });
        ScrollViewer.SetCanContentScroll(_grid, true);
        _grid.SetValue(VirtualizingPanel.IsVirtualizingProperty,true);
        _grid.SetValue(VirtualizingPanel.VirtualizationModeProperty,VirtualizationMode.Recycling);
        var footer = new DockPanel { Margin = new Thickness(0,10,0,0) };
        footer.Children.Add(_status);
        var actions = new StackPanel { Orientation=Orientation.Horizontal };
        var edit=MakeButton("Edit"); edit.Click+=async (_,_)=>await EditAsync();
        var toggle=MakeButton("Toggle Active"); toggle.Click+=async (_,_)=>await ToggleAsync();
        var delete=MakeButton("Delete"); delete.Click+=async (_,_)=>await DeleteAsync();
        actions.Children.Add(edit); actions.Children.Add(toggle); actions.Children.Add(delete);
        DockPanel.SetDock(actions,Dock.Right); footer.Children.Add(actions);
        DockPanel.SetDock(footer,Dock.Bottom); root.Children.Add(footer);
        DockPanel.SetDock(_grid,Dock.Top); root.Children.Add(_grid);
        return root;
    }

    private static Button MakeButton(string text) => new() {
        Content=text, Padding=new Thickness(12,8,12,8), Margin=new Thickness(6,0,0,0),
        Background=System.Windows.Media.Brushes.White, BorderBrush=System.Windows.Media.Brushes.LightGray,
        Cursor=System.Windows.Input.Cursors.Hand
    };

    private async Task LoadAsync()
    {
        try {
            var rows=await _service.GetProductsAsync(_search.Text);
            Products.Clear();
            foreach(var row in rows) if(_showInactive.IsChecked==true || row.IsActive) Products.Add(row);
            _status.Text=$"{Products.Count:N0} product(s)";
        } catch(Exception ex) { _status.Text="Inventory load failed: "+ex.Message; }
    }

    private async Task AddAsync()
    {
        var editor=new ProductEditorWindow() { Owner=this };
        if(editor.ShowDialog()!=true || editor.Product is null) return;
        try { await _service.CreateAsync(editor.Product); await LoadAsync(); _status.Text="Product added."; }
        catch(Exception ex) { MessageBox.Show(ex.Message,"Product could not be added",MessageBoxButton.OK,MessageBoxImage.Warning); }
    }

    private async Task EditAsync()
    {
        if(_grid.SelectedItem is not InventoryProduct selected) return;
        var editor=new ProductEditorWindow(selected) { Owner=this };
        if(editor.ShowDialog()!=true || editor.Product is null) return;
        try { await _service.UpdateAsync(selected.Id,editor.Product); await LoadAsync(); _status.Text="Product updated."; }
        catch(Exception ex) { MessageBox.Show(ex.Message,"Product could not be updated",MessageBoxButton.OK,MessageBoxImage.Warning); }
    }

    private async Task ToggleAsync()
    {
        if(_grid.SelectedItem is not InventoryProduct selected) return;
        var next=!selected.IsActive;
        if(MessageBox.Show($"'{selected.Name}' ko {(next?"Active":"Inactive")} karna hai?","Confirm",
            MessageBoxButton.YesNo,MessageBoxImage.Question)!=MessageBoxResult.Yes) return;
        try { await _service.SetActiveAsync(selected.Id,next); await LoadAsync(); }
        catch(Exception ex) { MessageBox.Show(ex.Message,"Status change failed",MessageBoxButton.OK,MessageBoxImage.Warning); }
    }

    private async Task DeleteAsync()
    {
        if(_grid.SelectedItem is not InventoryProduct selected) return;
        if(MessageBox.Show($"'{selected.Name}' delete karna hai? Stock ya sale/purchase history honay par delete allow nahi hoga.",
            "Confirm delete",MessageBoxButton.YesNo,MessageBoxImage.Warning)!=MessageBoxResult.Yes) return;
        try { await _service.DeleteAsync(selected.Id); await LoadAsync(); }
        catch(Exception ex) { MessageBox.Show(ex.Message,"Product could not be deleted",MessageBoxButton.OK,MessageBoxImage.Warning); }
    }
}

public sealed class ProductEditorWindow : Window
{
    private readonly TextBox _name=new(), _barcode=new(), _quantity=new(), _unit=new(), _purchase=new(), _sale=new();
    private readonly double _legacyWholesalePrice;
    private readonly TextBlock _barcodeStatus = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 3, 0, 0), FontSize = 11 };
    private readonly Button _saveButton = MakeButton("Save Product");
    private readonly DispatcherTimer _barcodeTimer = new() { Interval = TimeSpan.FromMilliseconds(250) };
    private readonly InventoryService _service = new();
    private readonly int? _existingId;
    public ProductMutation? Product { get; private set; }

    public ProductEditorWindow(InventoryProduct? existing=null)
    {
        _existingId = existing?.Id;
        _legacyWholesalePrice = existing?.WholesalePrice ?? 0;
        Title=existing is null?"Add Product":"Edit Product"; Width=440; Height=610; MinWidth=420;
        WindowStartupLocation=WindowStartupLocation.CenterOwner; ResizeMode=ResizeMode.NoResize;
        Background=System.Windows.Media.Brushes.WhiteSmoke;
        var panel=new StackPanel { Margin=new Thickness(22) };
        panel.Children.Add(new TextBlock { Text=Title, FontSize=23, FontWeight=FontWeights.Bold, Margin=new Thickness(0,0,0,14) });
        AddField(panel,"Barcode *",_barcode);
        panel.Children.Add(_barcodeStatus);
        AddField(panel,"Product name *",_name);
        AddField(panel,"Stock quantity *",_quantity);
        AddField(panel,"Stock unit *",_unit);
        AddField(panel,"Purchase price",_purchase);
        AddField(panel,"Retail sale price *",_sale);
        if(existing is null){_quantity.Text="0";_unit.Text="pcs";_purchase.Text="0";_sale.Text="0";}
        else {
            _name.Text=existing.Name;_barcode.Text=existing.Barcode;_quantity.Text=existing.Quantity.ToString(CultureInfo.InvariantCulture);
            _unit.Text=existing.StockUnit;_purchase.Text=existing.PurchasePrice.ToString(CultureInfo.InvariantCulture);
            _sale.Text=existing.SalePrice.ToString(CultureInfo.InvariantCulture);
            panel.Children.Add(new TextBlock { Text=$"Damaged stock preserved: {existing.DamagedQuantity}", Foreground=System.Windows.Media.Brushes.DimGray, Margin=new Thickness(0,8,0,0) });
        }
        var buttons=new StackPanel { Orientation=Orientation.Horizontal, HorizontalAlignment=HorizontalAlignment.Right, Margin=new Thickness(0,16,0,0) };
        var cancel=MakeButton("Cancel");cancel.Click+=(_,_)=>DialogResult=false;
        _saveButton.Click+=Save;
        buttons.Children.Add(cancel);buttons.Children.Add(_saveButton);panel.Children.Add(buttons);
        _barcode.TextChanged += (_, _) => { _barcodeTimer.Stop(); _barcodeTimer.Start(); };
        _barcodeTimer.Tick += async (_, _) => { _barcodeTimer.Stop(); await CheckBarcodeAsync(); };
        Closed += (_, _) => _barcodeTimer.Stop();
        Loaded += (_, _) => { if (_existingId is null) _barcode.Focus(); };
        Content=new ScrollViewer { Content=panel, VerticalScrollBarVisibility=ScrollBarVisibility.Auto };
    }

    private static void AddField(Panel panel,string label,TextBox box)
    {
        panel.Children.Add(new TextBlock { Text=label, Foreground=System.Windows.Media.Brushes.DimGray, Margin=new Thickness(0,8,0,3) });
        box.Height=34;box.Padding=new Thickness(8,6,8,6);panel.Children.Add(box);
    }

    private static Button MakeButton(string text)=>new(){Content=text,Padding=new Thickness(12,8,12,8),Margin=new Thickness(6,0,0,0)};

    private async Task CheckBarcodeAsync()
    {
        var barcode = _barcode.Text.Trim();
        if (barcode.Length == 0)
        {
            _barcodeStatus.Text = string.Empty;
            _saveButton.IsEnabled = true;
            return;
        }
        try
        {
            var owner = await _service.FindBarcodeOwnerAsync(barcode, _existingId);
            if (!string.Equals(barcode, _barcode.Text.Trim(), StringComparison.OrdinalIgnoreCase)) return;
            if (owner is null)
            {
                _barcodeStatus.Text = "Barcode available.";
                _barcodeStatus.Foreground = System.Windows.Media.Brushes.SeaGreen;
                _saveButton.IsEnabled = true;
            }
            else
            {
                _barcodeStatus.Text = $"This barcode is already assigned to '{owner}'.";
                _barcodeStatus.Foreground = System.Windows.Media.Brushes.Firebrick;
                _saveButton.IsEnabled = false;
            }
        }
        catch (Exception ex)
        {
            _barcodeStatus.Text = "Barcode check failed: " + ex.Message;
            _barcodeStatus.Foreground = System.Windows.Media.Brushes.Firebrick;
            _saveButton.IsEnabled = false;
        }
    }

    private void Save(object sender,RoutedEventArgs e)
    {
        var name=_name.Text.Trim();var barcode=_barcode.Text.Trim();var unit=_unit.Text.Trim().ToLowerInvariant();
        if(name.Length==0||barcode.Length==0||unit.Length==0){MessageBox.Show("Barcode, Name aur Stock Unit lazmi hain.");return;}
        if(!_saveButton.IsEnabled){MessageBox.Show("Barcode duplicate hai ya verify nahi ho saka. Pehle barcode check complete karein.");return;}
        if(name.Length>17){MessageBox.Show("Product name 80mm bill ke liye maximum 17 characters ka ho sakta hai.");return;}
        if(!int.TryParse(_quantity.Text,NumberStyles.Integer,CultureInfo.InvariantCulture,out var qty)||qty<0||
           !double.TryParse(_purchase.Text,NumberStyles.Number,CultureInfo.InvariantCulture,out var cost)||!double.IsFinite(cost)||cost<0||
           !double.TryParse(_sale.Text,NumberStyles.Number,CultureInfo.InvariantCulture,out var price)||!double.IsFinite(price)||price<0){
            MessageBox.Show("Stock aur prices valid non-negative numbers honi chahiye.");return;
        }
        Product=new ProductMutation(name,barcode,qty,unit,cost,price,_legacyWholesalePrice);DialogResult=true;
    }
}
