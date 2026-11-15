using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using KhanBabaPos.Wpf.Services;
namespace KhanBabaPos.Wpf;
public sealed class SaleReturnWindow:Window
{
 readonly SaleReturnService service=new();readonly SaleHistoryRecord sale;readonly ObservableCollection<ReturnLineView> rows=[];
 readonly TextBox reason=new(){Padding=new Thickness(8),MinWidth=300};readonly ComboBox method=new(){MinWidth=130,Padding=new Thickness(6)};
 readonly DataGrid grid=new(){AutoGenerateColumns=false,CanUserAddRows=false,RowHeight=36};
 readonly TextBlock status=new(){Foreground=System.Windows.Media.Brushes.DimGray};
 public SaleReturnWindow(SaleHistoryRecord sale){this.sale=sale;Title=$"Process Return | Bill #{sale.SaleId}";Width=1120;Height=700;MinWidth=900;MinHeight=560;WindowStartupLocation=WindowStartupLocation.CenterOwner;Background=System.Windows.Media.Brushes.WhiteSmoke;Content=Layout();Loaded+=async(_,_)=>await LoadAsync();}
 UIElement Layout(){var root=new DockPanel{Margin=new Thickness(18)};var header=new StackPanel{Margin=new Thickness(0,0,0,12)};header.Children.Add(new TextBlock{Text=$"Return Bill #{sale.SaleId}",FontSize=23,FontWeight=FontWeights.Bold});header.Children.Add(new TextBlock{Text=$"{sale.CustomerName} • {sale.Date} • Original net Rs. {sale.FinalAmount:N2}",Margin=new Thickness(0,4,0,0)});DockPanel.SetDock(header,Dock.Top);root.Children.Add(header);
 var top=new WrapPanel{Margin=new Thickness(0,0,0,10),VerticalAlignment=VerticalAlignment.Center};top.Children.Add(new TextBlock{Text="Reason",VerticalAlignment=VerticalAlignment.Center,Margin=new Thickness(0,0,6,0)});top.Children.Add(reason);top.Children.Add(new TextBlock{Text="Refund method",VerticalAlignment=VerticalAlignment.Center,Margin=new Thickness(14,0,6,0)});method.Items.Add("Cash");if(sale.CustomerType!="Walk-in")method.Items.Add("Khata");method.SelectedIndex=0;top.Children.Add(method);DockPanel.SetDock(top,Dock.Top);root.Children.Add(top);
 grid.IsReadOnly=false;grid.Columns.Add(new DataGridTextColumn{Header="Product",Binding=new System.Windows.Data.Binding("ProductName"),IsReadOnly=true,Width=new DataGridLength(1,DataGridLengthUnitType.Star)});grid.Columns.Add(new DataGridTextColumn{Header="Sold",Binding=new System.Windows.Data.Binding("SoldQuantity"),IsReadOnly=true,Width=65});grid.Columns.Add(new DataGridTextColumn{Header="Returned",Binding=new System.Windows.Data.Binding("ReturnedQuantity"),IsReadOnly=true,Width=80});grid.Columns.Add(new DataGridTextColumn{Header="Available",Binding=new System.Windows.Data.Binding("RemainingQuantity"),IsReadOnly=true,Width=80});grid.Columns.Add(new DataGridTextColumn{Header="Rate",Binding=new System.Windows.Data.Binding("SalePrice"){StringFormat="N2"},IsReadOnly=true,Width=90});grid.Columns.Add(new DataGridTextColumn{Header="Return Qty",Binding=new System.Windows.Data.Binding("ReturnQuantity"){UpdateSourceTrigger=System.Windows.Data.UpdateSourceTrigger.PropertyChanged},Width=95});grid.Columns.Add(new DataGridComboBoxColumn{Header="Condition",ItemsSource=new[]{"saleable","damaged"},SelectedItemBinding=new System.Windows.Data.Binding("Condition"),Width=110});grid.ItemsSource=rows;
 var footer=new DockPanel{Margin=new Thickness(0,10,0,0)};DockPanel.SetDock(status,Dock.Left);footer.Children.Add(status);var actions=new StackPanel{Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right};var cancel=Btn("Cancel");cancel.Click+=(_,_)=>DialogResult=false;var save=Btn("Process Return");save.Click+=async(_,_)=>await SaveAsync();actions.Children.Add(cancel);actions.Children.Add(save);DockPanel.SetDock(actions,Dock.Right);footer.Children.Add(actions);DockPanel.SetDock(footer,Dock.Bottom);root.Children.Add(footer);root.Children.Add(grid);return root;}
 static Button Btn(string s)=>new(){Content=s,Padding=new Thickness(12,8,12,8),Margin=new Thickness(0,0,8,0)};
 async Task LoadAsync(){try{var items=await service.GetReturnableItemsAsync(sale.SaleId);rows.Clear();foreach(var x in items)rows.Add(new ReturnLineView(x));status.Text=$"{rows.Count} sold item(s) • Enter return quantities";}catch(Exception e){status.Text="Return items load failed: "+e.Message;}}
 async Task SaveAsync(){grid.CommitEdit(DataGridEditingUnit.Cell,true);grid.CommitEdit(DataGridEditingUnit.Row,true);if(string.IsNullOrWhiteSpace(reason.Text)){status.Text="Return reason is required.";return;}var selected=rows.Where(x=>x.ReturnQuantity>0).ToList();if(selected.Count==0){status.Text="Enter at least one return quantity.";return;}foreach(var x in selected)if(x.ReturnQuantity>x.RemainingQuantity){status.Text=$"Return quantity exceeds available quantity for {x.ProductName}.";return;}try{var result=await service.RecordAsync(sale.SaleId,reason.Text,method.SelectedItem?.ToString()??"Cash",selected.Select(x=>new SaleReturnLineInput(x.SaleItemId,x.ReturnQuantity,x.Condition)).ToList());MessageBox.Show($"Return #{result.ReturnId} saved. Refund amount: Rs. {result.RefundAmount:N2}","Return saved",MessageBoxButton.OK,MessageBoxImage.Information);DialogResult=true;}catch(Exception e){MessageBox.Show(e.Message,"Return could not be processed",MessageBoxButton.OK,MessageBoxImage.Warning);}}
}
public sealed class ReturnLineView:INotifyPropertyChanged
{
 readonly ReturnableSaleItem item;int qty;string condition="saleable";
 public ReturnLineView(ReturnableSaleItem item){this.item=item;}
 public int SaleItemId=>item.SaleItemId;public string ProductName=>item.ProductName;public int SoldQuantity=>item.SoldQuantity;public int ReturnedQuantity=>item.ReturnedQuantity;public int RemainingQuantity=>item.RemainingQuantity;public double SalePrice=>item.SalePrice;
 public int ReturnQuantity{get=>qty;set{qty=Math.Max(0,value);OnChanged();}}
 public string Condition{get=>condition;set{condition=value;OnChanged();}}
 public event PropertyChangedEventHandler? PropertyChanged;void OnChanged([CallerMemberName]string? n=null)=>PropertyChanged?.Invoke(this,new PropertyChangedEventArgs(n));
}