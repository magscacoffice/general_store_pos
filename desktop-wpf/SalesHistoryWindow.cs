using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using KhanBabaPos.Wpf.Services;

namespace KhanBabaPos.Wpf;

public sealed class SalesHistoryWindow : Window
{
    public ObservableCollection<SaleHistoryRecord> Sales { get; } = [];
    private readonly SalesHistoryService _service = new();
    private readonly TextBox _search = new();
    private readonly DatePicker _from = new();
    private readonly DatePicker _to = new();
    private readonly DataGrid _grid = new() { AutoGenerateColumns=false, IsReadOnly=true, CanUserAddRows=false,
        EnableRowVirtualization=true, EnableColumnVirtualization=true, RowHeight=36, ColumnHeaderHeight=36 };
    private readonly TextBlock _status = new() { VerticalAlignment=VerticalAlignment.Center };
    private readonly DispatcherTimer _timer = new() { Interval=TimeSpan.FromMilliseconds(250) };

    public SalesHistoryWindow()
    {
        Title="Sales History | Khan Baba POS"; Width=1240; Height=760; MinWidth=950; MinHeight=580;
        WindowStartupLocation=WindowStartupLocation.CenterOwner; Background=System.Windows.Media.Brushes.WhiteSmoke;
        Content=BuildLayout(); _grid.ItemsSource=Sales;
        _search.TextChanged+=(_,_)=>{_timer.Stop();_timer.Start();};
        _timer.Tick+=async(_,_)=>{_timer.Stop();await LoadAsync();};
        Loaded+=async(_,_)=>await LoadAsync();
    }

    private UIElement BuildLayout()
    {
        var root=new DockPanel { Margin=new Thickness(20) };
        var header=new DockPanel { LastChildFill=false, Margin=new Thickness(0,0,0,14) };
        var title=new StackPanel();
        title.Children.Add(new TextBlock{Text="Sales History",FontSize=25,FontWeight=FontWeights.Bold,Foreground=System.Windows.Media.Brushes.DarkSlateGray});
        title.Children.Add(new TextBlock{Text="Search invoices, review totals and open saved bill details.",Foreground=System.Windows.Media.Brushes.DimGray,Margin=new Thickness(0,4,0,0)});
        header.Children.Add(title);
        var refresh=Button("Refresh");refresh.Click+=async(_,_)=>await LoadAsync();DockPanel.SetDock(refresh,Dock.Right);header.Children.Add(refresh);
        DockPanel.SetDock(header,Dock.Top);root.Children.Add(header);

        var filters=new DockPanel{Margin=new Thickness(0,0,0,12)};
        _search.Width=300;_search.Height=36;_search.Padding=new Thickness(8,6,8,6);_search.ToolTip="Search bill number, customer, date or payment";
        filters.Children.Add(_search);
        var fromLabel=new TextBlock{Text="From",VerticalAlignment=VerticalAlignment.Center,Margin=new Thickness(14,0,5,0)};
        DockPanel.SetDock(fromLabel,Dock.Left);filters.Children.Add(fromLabel);
        _from.Width=135;DockPanel.SetDock(_from,Dock.Left);filters.Children.Add(_from);
        var toLabel=new TextBlock{Text="To",VerticalAlignment=VerticalAlignment.Center,Margin=new Thickness(14,0,5,0)};
        DockPanel.SetDock(toLabel,Dock.Left);filters.Children.Add(toLabel);
        _to.Width=135;DockPanel.SetDock(_to,Dock.Left);filters.Children.Add(_to);
        var apply=Button("Apply");apply.Click+=async(_,_)=>await LoadAsync();DockPanel.SetDock(apply,Dock.Right);filters.Children.Add(apply);
        DockPanel.SetDock(filters,Dock.Top);root.Children.Add(filters);

        _grid.Columns.Add(new DataGridTextColumn{Header="Bill #",Binding=new System.Windows.Data.Binding("SaleId"),Width=70});
        _grid.Columns.Add(new DataGridTextColumn{Header="Date / Time",Binding=new System.Windows.Data.Binding("Date"),Width=145});
        _grid.Columns.Add(new DataGridTextColumn{Header="Customer",Binding=new System.Windows.Data.Binding("CustomerName"),Width=new DataGridLength(1,DataGridLengthUnitType.Star)});
        _grid.Columns.Add(new DataGridTextColumn{Header="Type",Binding=new System.Windows.Data.Binding("CustomerType"),Width=80});
        _grid.Columns.Add(new DataGridTextColumn{Header="Payment",Binding=new System.Windows.Data.Binding("PaymentType"),Width=80});
        _grid.Columns.Add(new DataGridTextColumn{Header="Subtotal",Binding=new System.Windows.Data.Binding("Subtotal"){StringFormat="N2"},Width=95});
        _grid.Columns.Add(new DataGridTextColumn{Header="Discount",Binding=new System.Windows.Data.Binding("Discount"){StringFormat="N2"},Width=90});
        _grid.Columns.Add(new DataGridTextColumn{Header="Net",Binding=new System.Windows.Data.Binding("FinalAmount"){StringFormat="N2"},Width=95});
        _grid.Columns.Add(new DataGridTextColumn{Header="Received",Binding=new System.Windows.Data.Binding("Received"){StringFormat="N2"},Width=90});
        _grid.Columns.Add(new DataGridTextColumn{Header="Due",Binding=new System.Windows.Data.Binding("BalanceDue"){StringFormat="N2"},Width=85});
        _grid.Columns.Add(new DataGridTextColumn{Header="Returns",Binding=new System.Windows.Data.Binding("ReturnedAmount"){StringFormat="N2"},Width=85});
        _grid.MouseDoubleClick+=(_,_)=>OpenSelected();
        _grid.SetValue(VirtualizingPanel.IsVirtualizingProperty,true);
        _grid.SetValue(VirtualizingPanel.VirtualizationModeProperty,VirtualizationMode.Recycling);
        ScrollViewer.SetCanContentScroll(_grid,true);
        var footer=new DockPanel{Margin=new Thickness(0,10,0,0)};
        footer.Children.Add(_status);
        var view=Button("View Bill");view.Click+=(_,_)=>OpenSelected();DockPanel.SetDock(view,Dock.Right);footer.Children.Add(view);
        DockPanel.SetDock(footer,Dock.Bottom);root.Children.Add(footer);
        root.Children.Add(_grid);
        return root;
    }

    private static Button Button(string label)=>new(){Content=label,Padding=new Thickness(12,8,12,8),Margin=new Thickness(6,0,0,0)};
    private async Task LoadAsync()
    {
        try{
            var rows=await _service.GetSalesAsync(_search.Text,_from.SelectedDate,_to.SelectedDate);
            Sales.Clear();foreach(var row in rows)Sales.Add(row);
            _status.Text=$"{Sales.Count:N0} invoice(s)";
        }catch(Exception ex){_status.Text="Sales history load failed: "+ex.Message;}
    }
    private async void OpenSelected()
    {
        if(_grid.SelectedItem is not SaleHistoryRecord sale)return;
        try{
            var items=await _service.GetSaleItemsAsync(sale.SaleId);
            var details=new SaleDetailsWindow(sale,items){Owner=this};
            details.ShowDialog();
        }catch(Exception ex){MessageBox.Show(ex.Message,"Invoice details unavailable",MessageBoxButton.OK,MessageBoxImage.Warning);}
    }
}

public sealed class SaleDetailsWindow : Window
{
    public SaleDetailsWindow(SaleHistoryRecord sale,IReadOnlyList<SaleHistoryItem> items)
    {
        Title=$"Invoice #{sale.SaleId}";Width=900;Height=650;MinWidth=720;MinHeight=500;
        WindowStartupLocation=WindowStartupLocation.CenterOwner;Background=System.Windows.Media.Brushes.WhiteSmoke;
        var root=new DockPanel{Margin=new Thickness(20)};
        var summary=new StackPanel{Margin=new Thickness(0,0,0,14)};
        summary.Children.Add(new TextBlock{Text=$"Invoice #{sale.SaleId}  •  {sale.Date}",FontSize=21,FontWeight=FontWeights.Bold});
        summary.Children.Add(new TextBlock{Text=$"Customer: {sale.CustomerName}    Type: {sale.CustomerType}    Payment: {sale.PaymentType}",Margin=new Thickness(0,5,0,0)});
        summary.Children.Add(new TextBlock{Text=$"Subtotal: Rs. {sale.Subtotal:N2}    Discount: Rs. {sale.Discount:N2}    Net: Rs. {sale.FinalAmount:N2}",Margin=new Thickness(0,5,0,0),FontWeight=FontWeights.SemiBold});
        summary.Children.Add(new TextBlock{Text=$"Received: Rs. {sale.Received:N2}    Balance: Rs. {sale.BalanceDue:N2}    Returned: Rs. {sale.ReturnedAmount:N2}",Margin=new Thickness(0,4,0,0)});
        DockPanel.SetDock(summary,Dock.Top);root.Children.Add(summary);
        var grid=new DataGrid{AutoGenerateColumns=false,IsReadOnly=true,CanUserAddRows=false,ItemsSource=items,
            EnableRowVirtualization=true,EnableColumnVirtualization=true,RowHeight=36};
        grid.Columns.Add(new DataGridTextColumn{Header="Barcode",Binding=new System.Windows.Data.Binding("Barcode"),Width=130});
        grid.Columns.Add(new DataGridTextColumn{Header="Item",Binding=new System.Windows.Data.Binding("ProductName"),Width=new DataGridLength(1,DataGridLengthUnitType.Star)});
        grid.Columns.Add(new DataGridTextColumn{Header="Qty",Binding=new System.Windows.Data.Binding("Quantity"),Width=60});
        grid.Columns.Add(new DataGridTextColumn{Header="Unit",Binding=new System.Windows.Data.Binding("StockUnit"),Width=70});
        grid.Columns.Add(new DataGridTextColumn{Header="Rate",Binding=new System.Windows.Data.Binding("SalePrice"){StringFormat="N2"},Width=95});
        grid.Columns.Add(new DataGridTextColumn{Header="Amount",Binding=new System.Windows.Data.Binding("LineTotal"){StringFormat="N2"},Width=105});
        var footer=new StackPanel{Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right,Margin=new Thickness(0,12,0,0)};
        var close=new Button{Content="Close",Padding=new Thickness(14,8,14,8)};close.Click+=(_,_)=>Close();
        footer.Children.Add(close);DockPanel.SetDock(footer,Dock.Bottom);root.Children.Add(footer);
        root.Children.Add(grid);
        Content=root;
    }
}
