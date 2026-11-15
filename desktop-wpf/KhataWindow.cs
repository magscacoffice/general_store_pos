using System.Collections.ObjectModel;
using System.Globalization;
using System.Text;
using System.Windows.Documents;
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
        try{var ledger=await _service.GetLedgerAsync(customer.Id,customer.Balance);new CustomerLedgerWindow(customer,ledger,_service){Owner=this}.ShowDialog();await LoadAsync();}
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
    private readonly DatePicker _from=new(){SelectedDate=DateTime.Today,Width=130};
    private readonly DatePicker _to=new(){SelectedDate=DateTime.Today,Width=130};
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
        grid.Columns.Add(new DataGridTextColumn{Header="Date / Time",Binding=new System.Windows.Data.Binding("Date"),Width=160});
        grid.Columns.Add(new DataGridTextColumn{Header="Description",Binding=new System.Windows.Data.Binding("Description"),Width=new DataGridLength(1,DataGridLengthUnitType.Star)});
        grid.Columns.Add(new DataGridTextColumn{Header="Type",Binding=new System.Windows.Data.Binding("TypeLabel"),Width=140});
        grid.Columns.Add(new DataGridTextColumn{Header="Debit",Binding=new System.Windows.Data.Binding("Debit"){StringFormat="N2"},Width=100});
        grid.Columns.Add(new DataGridTextColumn{Header="Credit",Binding=new System.Windows.Data.Binding("Credit"){StringFormat="N2"},Width=100});
        grid.Columns.Add(new DataGridTextColumn{Header="Balance",Binding=new System.Windows.Data.Binding("RunningBalance"){StringFormat="N2"},Width=110});
        var footer=new StackPanel{Margin=new Thickness(0,12,0,0)};
        var period=new WrapPanel{VerticalAlignment=VerticalAlignment.Center,Margin=new Thickness(0,0,0,8)};
        period.Children.Add(new TextBlock{Text="Statement From",VerticalAlignment=VerticalAlignment.Center,Margin=new Thickness(0,0,6,0)});
        period.Children.Add(_from);
        period.Children.Add(new TextBlock{Text="To",VerticalAlignment=VerticalAlignment.Center,Margin=new Thickness(12,0,6,0)});
        period.Children.Add(_to);
        var periodPdf=new Button{Content="Save Period Statement PDF",Padding=new Thickness(12,8,12,8),Margin=new Thickness(10,0,0,0)};
        periodPdf.Click+=async(_,_)=>await ExportPeriodStatementAsync();period.Children.Add(periodPdf);
        footer.Children.Add(period);
        var actions=new WrapPanel{HorizontalAlignment=HorizontalAlignment.Right};
        var copy=new Button{Content="Copy Full Ledger",Padding=new Thickness(12,8,12,8),Margin=new Thickness(0,0,8,0)};
        copy.Click+=(_,_)=>CopyLedger();actions.Children.Add(copy);
        var ledgerPdf=new Button{Content="Save Full Ledger PDF",Padding=new Thickness(12,8,12,8),Margin=new Thickness(0,0,8,0)};
        ledgerPdf.Click+=async(_,_)=>await SaveLedgerPdfAsync();actions.Children.Add(ledgerPdf);
        var receipt=new Button{Content="Record Receipt",Padding=new Thickness(14,8,14,8),Margin=new Thickness(0,0,8,0)};
        receipt.Click+=async(_,_)=>await ReceiptAsync();actions.Children.Add(receipt);
        var close=new Button{Content="Close",Padding=new Thickness(14,8,14,8)};close.Click+=(_,_)=>Close();actions.Children.Add(close);
        footer.Children.Add(actions);
        DockPanel.SetDock(footer,Dock.Bottom);root.Children.Add(footer);
        root.Children.Add(grid);Content=root;return root;
    }
    private string BuildLedgerText()
    {
        var text = new StringBuilder();
        text.AppendLine("KHAN BABA GENERAL STORE");
        text.AppendLine("CUSTOMER KHATA LEDGER");
        text.AppendLine($"Customer: {_customer.Name}");
        text.AppendLine($"Phone: {_customer.Phone}");
        text.AppendLine($"Generated: {DateTime.Now:dd/MM/yyyy HH:mm}");
        text.AppendLine($"Outstanding Balance: Rs. {_balance:N2}");
        text.AppendLine(new string('-', 100));
        text.AppendLine("Date / Time | Description | Debit | Credit | Balance");
        foreach (var entry in _entries)
            text.AppendLine($"{entry.Date} | {entry.Description} | {entry.Debit:N2} | {entry.Credit:N2} | {entry.RunningBalance:N2}");
        text.AppendLine(new string('-', 100));
        text.AppendLine($"Current Outstanding: Rs. {_balance:N2}");
        return text.ToString();
    }

    private void CopyLedger()
    {
        Clipboard.SetText(BuildLedgerText());
        MessageBox.Show("Full customer ledger copied. Paste it into WhatsApp or another sharing app.",
            "Khata Statement", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private Task SaveLedgerPdfAsync()
    {
        PrintStatement("Full Customer Khata Ledger", BuildLedgerText());
        return Task.CompletedTask;
    }

    private void PrintStatement(string title, string content)
    {
        var document = new FlowDocument
        {
            FontFamily = new System.Windows.Media.FontFamily("Segoe UI"),
            FontSize = 10,
            PagePadding = new Thickness(40),
            PageWidth = 793.7,
            PageHeight = 1122.5,
            ColumnWidth = 700
        };
        foreach (var line in content.Replace("\\r", string.Empty).Split('\\n'))
            document.Blocks.Add(new Paragraph(new Run(line))
            {
                Margin = new Thickness(0, 0, 0, 3),
                LineHeight = 15
            });

        var printDialog = new PrintDialog();
        if (printDialog.ShowDialog() == true)
            printDialog.PrintDocument(((IDocumentPaginatorSource)document).DocumentPaginator, title);
    }

    private async Task ExportPeriodStatementAsync()
    {
        if (_from.SelectedDate is null || _to.SelectedDate is null || _from.SelectedDate.Value > _to.SelectedDate.Value)
        {
            MessageBox.Show("Select a valid From and To date range.", "Khata Statement",
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        try
        {
            var lines = await _service.GetStatementAsync(_customer.Id, _from.SelectedDate.Value, _to.SelectedDate.Value);
            if (lines.Count == 0)
            {
                MessageBox.Show("Selected period mein koi sale ya return record nahi mila.", "Khata Statement",
                    MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            var text = new StringBuilder();
            text.AppendLine("KHAN BABA GENERAL STORE");
            text.AppendLine("CUSTOMER ITEM STATEMENT");
            text.AppendLine($"Customer: {_customer.Name}");
            text.AppendLine($"Phone: {_customer.Phone}");
            text.AppendLine($"Period: {_from.SelectedDate:dd/MM/yyyy} to {_to.SelectedDate:dd/MM/yyyy}");
            text.AppendLine(new string('-', 100));
            text.AppendLine("Date | Bill | Type | Product | Qty | Rate | Net Amount | Payment / Note");
            var totalSales = 0d;
            var totalReturns = 0d;
            foreach (var line in lines)
            {
                if (line.EntryType == "Sale") totalSales += line.Amount;
                else totalReturns += -line.Amount;
                text.AppendLine($"{line.Date} | #{line.BillId:D6} | {line.EntryType} | {line.ProductName} | {line.Quantity} {line.StockUnit} | {line.Rate:N2} | {line.Amount:N2} | {line.PaymentType} {line.Note}");
            }
            text.AppendLine(new string('-', 100));
            text.AppendLine($"Net sales: Rs. {totalSales:N2}");
            text.AppendLine($"Returns/refunds: Rs. {totalReturns:N2}");
            text.AppendLine($"Net item total: Rs. {lines.Sum(x => x.Amount):N2}");

            PrintStatement("Customer Item Statement", text.ToString());
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "Period statement export failed", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private async Task ReceiptAsync(){
        var input=ReceiptInputWindow.Show(this,_customer with { Balance=_balance });if(input is null)return;
        try{
            await _service.RecordReceiptAsync(_customer.Id,input.Value.Amount,input.Value.Note);
            _balance=Math.Max(0,_balance-input.Value.Amount);
            _balanceText.Text=$"Outstanding: Rs. {_balance:N2}";
            var latest=await _service.GetLedgerAsync(_customer.Id,_balance);_entries.Clear();foreach(var entry in latest)_entries.Add(entry);
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
