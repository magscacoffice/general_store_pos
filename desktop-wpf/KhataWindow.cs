using System.Collections.ObjectModel;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using KhanBabaPos.Wpf.Services;

namespace KhanBabaPos.Wpf;

public sealed class KhataWindow:Window
{
    public ObservableCollection<KhataCustomer> Customers{get;}=[];
    private readonly KhataService _service=new();
    private readonly TextBox _search=new();
    private readonly DataGrid _grid=new(){AutoGenerateColumns=false,IsReadOnly=true,CanUserAddRows=false,EnableRowVirtualization=true,EnableColumnVirtualization=true,RowHeight=36};
    private readonly TextBlock _status=new(){VerticalAlignment=VerticalAlignment.Center};

    public KhataWindow(){
        Title="Customer Khata | Khan Baba POS";Width=1050;Height=700;MinWidth=850;MinHeight=540;
        WindowStartupLocation=WindowStartupLocation.CenterOwner;Background=System.Windows.Media.Brushes.WhiteSmoke;
        Content=BuildLayout();_grid.ItemsSource=Customers;Loaded+=async(_,_)=>await LoadAsync();
        _search.TextChanged+=async(_,_)=>await LoadAsync();
    }

    private UIElement BuildLayout(){
        var root=new DockPanel{Margin=new Thickness(20)};
        var header=new DockPanel{LastChildFill=false,Margin=new Thickness(0,0,0,14)};
        var title=new StackPanel();
        title.Children.Add(new TextBlock{Text="Customer Khata",FontSize=25,FontWeight=FontWeights.Bold});
        title.Children.Add(new TextBlock{Text="Outstanding balances and receipt ledger for Khata customers.",Foreground=System.Windows.Media.Brushes.DimGray,Margin=new Thickness(0,4,0,0)});
        header.Children.Add(title);
        var refresh=Btn("Refresh");refresh.Click+=async(_,_)=>await LoadAsync();DockPanel.SetDock(refresh,Dock.Right);header.Children.Add(refresh);
        DockPanel.SetDock(header,Dock.Top);root.Children.Add(header);

        var toolbar=new DockPanel{LastChildFill=false,Margin=new Thickness(0,0,0,12)};
        _search.Width=300;_search.Height=36;_search.Padding=new Thickness(8,6,8,6);_search.ToolTip="Search customer name or phone";toolbar.Children.Add(_search);
        var ledger=Btn("View Ledger");ledger.Click+=async(_,_)=>await OpenLedgerAsync();DockPanel.SetDock(ledger,Dock.Right);toolbar.Children.Add(ledger);
        var receipt=Btn("Record Receipt");receipt.Click+=async(_,_)=>await ReceiptAsync();DockPanel.SetDock(receipt,Dock.Right);toolbar.Children.Add(receipt);
        DockPanel.SetDock(toolbar,Dock.Top);root.Children.Add(toolbar);

        _grid.Columns.Add(new DataGridTextColumn{Header="Customer",Binding=new System.Windows.Data.Binding("Name"),Width=new DataGridLength(1,DataGridLengthUnitType.Star)});
        _grid.Columns.Add(new DataGridTextColumn{Header="Phone",Binding=new System.Windows.Data.Binding("Phone"),Width=150});
        _grid.Columns.Add(new DataGridTextColumn{Header="Outstanding Balance",Binding=new System.Windows.Data.Binding("Balance"){StringFormat="N2"},Width=180});
        _grid.MouseDoubleClick+=async(_,_)=>await OpenLedgerAsync();
        _grid.SetValue(VirtualizingPanel.IsVirtualizingProperty,true);
        _grid.SetValue(VirtualizingPanel.VirtualizationModeProperty,VirtualizationMode.Recycling);
        ScrollViewer.SetCanContentScroll(_grid,true);
        var footer=new DockPanel{Margin=new Thickness(0,10,0,0)};footer.Children.Add(_status);
        DockPanel.SetDock(footer,Dock.Bottom);root.Children.Add(footer);
        root.Children.Add(_grid);
        return root;
    }

    private static Button Btn(string text)=>new(){Content=text,Padding=new Thickness(12,8,12,8),Margin=new Thickness(6,0,0,0)};
    private async Task LoadAsync(){
        try{var rows=await _service.GetCustomersAsync(_search.Text);Customers.Clear();foreach(var row in rows)Customers.Add(row);_status.Text=$"{Customers.Count:N0} Khata customer(s)";}
        catch(Exception ex){_status.Text="Khata load failed: "+ex.Message;}
    }
    private async Task OpenLedgerAsync(){
        if(_grid.SelectedItem is not KhataCustomer customer)return;
        try{var ledger=await _service.GetLedgerAsync(customer.Id);new CustomerLedgerWindow(customer,ledger,_service){Owner=this}.ShowDialog();await LoadAsync();}
        catch(Exception ex){MessageBox.Show(ex.Message,"Ledger unavailable",MessageBoxButton.OK,MessageBoxImage.Warning);}
    }
    private async Task ReceiptAsync(){
        if(_grid.SelectedItem is not KhataCustomer customer)return;
        var input=ReceiptInputWindow.Show(this,customer);
        if(input is null)return;
        try{await _service.RecordReceiptAsync(customer.Id,input.Value.Amount,input.Value.Note);await LoadAsync();}
        catch(Exception ex){MessageBox.Show(ex.Message,"Receipt could not be saved",MessageBoxButton.OK,MessageBoxImage.Warning);}
    }
}

public sealed class CustomerLedgerWindow:Window
{
    private readonly KhataCustomer _customer;
    private readonly KhataService _service;
    private readonly ObservableCollection<KhataEntry> _entries;
    private readonly TextBlock _balanceText=new();
    private double _balance;
    public CustomerLedgerWindow(KhataCustomer customer,IReadOnlyList<KhataEntry> entries,KhataService service){
        _customer=customer;_balance=customer.Balance;_service=service;_entries=new ObservableCollection<KhataEntry>(entries);
        Title=$"Khata Ledger | {customer.Name}";Width=980;Height=680;MinWidth=760;MinHeight=520;
        WindowStartupLocation=WindowStartupLocation.CenterOwner;Background=System.Windows.Media.Brushes.WhiteSmoke;
        Content=BuildLayout();
    }
    private UIElement BuildLayout(){
        var root=new DockPanel{Margin=new Thickness(20)};
        var header=new StackPanel{Margin=new Thickness(0,0,0,14)};
        header.Children.Add(new TextBlock{Text=_customer.Name,FontSize=23,FontWeight=FontWeights.Bold});
        header.Children.Add(new TextBlock{Text=$"Phone: {_customer.Phone}",Margin=new Thickness(0,5,0,0)});
        _balanceText.Text=$"Outstanding: Rs. {_balance:N2}";
        _balanceText.Margin=new Thickness(0,4,0,0);
        header.Children.Add(_balanceText);
        DockPanel.SetDock(header,Dock.Top);root.Children.Add(header);
        var grid=new DataGrid{AutoGenerateColumns=false,IsReadOnly=true,CanUserAddRows=false,ItemsSource=_entries,RowHeight=36};
        grid.Columns.Add(new DataGridTextColumn{Header="Date",Binding=new System.Windows.Data.Binding("Date"),Width=160});
        grid.Columns.Add(new DataGridTextColumn{Header="Type",Binding=new System.Windows.Data.Binding("Type"),Width=140});
        grid.Columns.Add(new DataGridTextColumn{Header="Amount",Binding=new System.Windows.Data.Binding("Amount"){StringFormat="N2"},Width=130});
        grid.Columns.Add(new DataGridTextColumn{Header="Note",Binding=new System.Windows.Data.Binding("Note"),Width=new DataGridLength(1,DataGridLengthUnitType.Star)});
        var footer=new StackPanel{Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right,Margin=new Thickness(0,12,0,0)};
        var receipt=new Button{Content="Record Receipt",Padding=new Thickness(14,8,14,8),Margin=new Thickness(0,0,8,0)};
        receipt.Click+=async(_,_)=>await ReceiptAsync();footer.Children.Add(receipt);
        var close=new Button{Content="Close",Padding=new Thickness(14,8,14,8)};close.Click+=(_,_)=>Close();footer.Children.Add(close);
        DockPanel.SetDock(footer,Dock.Bottom);root.Children.Add(footer);
        root.Children.Add(grid);Content=root;return root;
    }
    private async Task ReceiptAsync(){
        var input=ReceiptInputWindow.Show(this,_customer with { Balance=_balance });if(input is null)return;
        try{
            await _service.RecordReceiptAsync(_customer.Id,input.Value.Amount,input.Value.Note);
            _balance=Math.Max(0,_balance-input.Value.Amount);
            _balanceText.Text=$"Outstanding: Rs. {_balance:N2}";
            var latest=await _service.GetLedgerAsync(_customer.Id);_entries.Clear();foreach(var entry in latest)_entries.Add(entry);
            MessageBox.Show("Receipt saved; customer balance reduced.","Khata",MessageBoxButton.OK,MessageBoxImage.Information);
        }catch(Exception ex){MessageBox.Show(ex.Message,"Receipt could not be saved",MessageBoxButton.OK,MessageBoxImage.Warning);}
    }
}

internal sealed class ReceiptInputWindow:Window
{
    private readonly TextBox _amount=new(),_note=new();
    private (double Amount,string Note)? _result;
    private ReceiptInputWindow(KhataCustomer customer){
        Title="Record Khata Receipt";Width=400;Height=340;WindowStartupLocation=WindowStartupLocation.CenterOwner;
        WindowStyle=WindowStyle.ToolWindow;ResizeMode=ResizeMode.NoResize;
        var panel=new StackPanel{Margin=new Thickness(20)};
        panel.Children.Add(new TextBlock{Text=$"Receipt: {customer.Name}",FontSize=18,FontWeight=FontWeights.Bold,Margin=new Thickness(0,0,0,12)});
        panel.Children.Add(new TextBlock{Text=$"Outstanding: Rs. {customer.Balance:N2}"});
        panel.Children.Add(new TextBlock{Text="Amount (Rs.) *",Margin=new Thickness(0,12,0,4)});_amount.Height=34;_amount.Padding=new Thickness(8);panel.Children.Add(_amount);
        panel.Children.Add(new TextBlock{Text="Note",Margin=new Thickness(0,12,0,4)});_note.Height=34;_note.Padding=new Thickness(8);panel.Children.Add(_note);
        var buttons=new StackPanel{Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right,Margin=new Thickness(0,16,0,0)};
        var cancel=new Button{Content="Cancel",Padding=new Thickness(12,8,12,8),Margin=new Thickness(0,0,8,0)};cancel.Click+=(_,_)=>Close();
        var save=new Button{Content="Save Receipt",Padding=new Thickness(12,8,12,8)};save.Click+=Save_Click;
        buttons.Children.Add(cancel);buttons.Children.Add(save);panel.Children.Add(buttons);Content=panel;
    }
    private void Save_Click(object sender,RoutedEventArgs e){
        if(!double.TryParse(_amount.Text,NumberStyles.Number,CultureInfo.InvariantCulture,out var amount)||!double.IsFinite(amount)||amount<=0){
            MessageBox.Show("Valid receipt amount enter karein.");return;
        }
        _result=(amount,_note.Text.Trim());Close();
    }
    public static (double Amount,string Note)? Show(Window owner,KhataCustomer customer){
        var dialog=new ReceiptInputWindow(customer){Owner=owner};dialog.ShowDialog();return dialog._result;
    }
}
