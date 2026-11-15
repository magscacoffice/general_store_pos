using System.Collections.ObjectModel;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using KhanBabaPos.Wpf.Services;
namespace KhanBabaPos.Wpf;
public sealed class ExpensesWindow:Window
{
 readonly ExpenseService service=new();readonly ObservableCollection<ExpenseRow> rows=[];
 readonly DataGrid grid=new(){AutoGenerateColumns=false,IsReadOnly=true,CanUserAddRows=false,EnableRowVirtualization=true,RowHeight=36};
 readonly TextBlock total=new(){FontSize=18,FontWeight=FontWeights.Bold};readonly TextBlock status=new(){Foreground=Brushes.DimGray};
 public ExpensesWindow(){Title="Expenses | Khan Baba POS";Width=1050;Height=700;MinWidth=850;MinHeight=540;WindowStartupLocation=WindowStartupLocation.CenterOwner;Background=Brushes.WhiteSmoke;grid.ItemsSource=rows;Configure();Content=Layout();Loaded+=async(_,_)=>await LoadAsync();}
 void Configure(){grid.Columns.Add(new DataGridTextColumn{Header="Expense Description",Binding=new System.Windows.Data.Binding("Title"),Width=new DataGridLength(1,DataGridLengthUnitType.Star)});grid.Columns.Add(new DataGridTextColumn{Header="Date / Time",Binding=new System.Windows.Data.Binding("Date"),Width=190});grid.Columns.Add(new DataGridTextColumn{Header="Amount (Rs.)",Binding=new System.Windows.Data.Binding("Amount"){StringFormat="N2"},Width=150});grid.SetValue(VirtualizingPanel.IsVirtualizingProperty,true);grid.SetValue(VirtualizingPanel.VirtualizationModeProperty,VirtualizationMode.Recycling);ScrollViewer.SetCanContentScroll(grid,true);}
 UIElement Layout(){var root=new DockPanel{Margin=new Thickness(20)};var header=new DockPanel{LastChildFill=false,Margin=new Thickness(0,0,0,14)};var title=new StackPanel();title.Children.Add(new TextBlock{Text="Expense Register",FontSize=25,FontWeight=FontWeights.Bold,Foreground=Brushes.DarkSlateGray});title.Children.Add(new TextBlock{Text="Record and review day-to-day store expenses.",Foreground=Brushes.DimGray,Margin=new Thickness(0,4,0,0)});header.Children.Add(title);var add=Btn("Add Expense");add.Click+=async(_,_)=>await AddAsync();DockPanel.SetDock(add,Dock.Right);header.Children.Add(add);DockPanel.SetDock(header,Dock.Top);root.Children.Add(header);
 var summary=new Border{Background=Brushes.White,BorderBrush=new SolidColorBrush(Color.FromRgb(220,229,224)),BorderThickness=new Thickness(1),CornerRadius=new CornerRadius(8),Padding=new Thickness(14),Margin=new Thickness(0,0,0,12)};var line=new DockPanel();line.Children.Add(new TextBlock{Text="All recorded expenses",VerticalAlignment=VerticalAlignment.Center,Foreground=Brushes.DimGray});DockPanel.SetDock(total,Dock.Right);line.Children.Add(total);summary.Child=line;DockPanel.SetDock(summary,Dock.Top);root.Children.Add(summary);
 DockPanel.SetDock(status,Dock.Bottom);status.Margin=new Thickness(0,8,0,0);root.Children.Add(status);root.Children.Add(grid);return root;}
 static Button Btn(string s)=>new(){Content=s,Padding=new Thickness(12,8,12,8),Margin=new Thickness(8,0,0,0)};
 async Task LoadAsync(){try{var data=await service.GetAllAsync();rows.Clear();foreach(var x in data)rows.Add(x);total.Text=$"Rs. {rows.Sum(x=>x.Amount):N2}";status.Text=$"{rows.Count:N0} expense entry/entries";}catch(Exception e){status.Text="Expenses load failed: "+e.Message;}}
 async Task AddAsync(){var dialog=new AddExpenseDialog{Owner=this};if(dialog.ShowDialog()!=true)return;try{await service.AddAsync(dialog.ExpenseTitle,dialog.Amount);await LoadAsync();status.Text="Expense saved successfully.";}catch(Exception e){MessageBox.Show(e.Message,"Expense could not be saved",MessageBoxButton.OK,MessageBoxImage.Warning);}}
}
internal sealed class AddExpenseDialog:Window
{
 readonly TextBox title=new(){Padding=new Thickness(8),MinWidth=280};readonly TextBox amount=new(){Padding=new Thickness(8),MinWidth=280};
 public string ExpenseTitle=>title.Text.Trim();public double Amount{get;private set;}
 public AddExpenseDialog(){Title="Add New Expense";Width=420;Height=300;WindowStartupLocation=WindowStartupLocation.CenterOwner;ResizeMode=ResizeMode.NoResize;var p=new StackPanel{Margin=new Thickness(20)};p.Children.Add(new TextBlock{Text="Expense reason / title"});p.Children.Add(title);p.Children.Add(new TextBlock{Text="Amount (Rs.)",Margin=new Thickness(0,12,0,4)});p.Children.Add(amount);var actions=new StackPanel{Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right,Margin=new Thickness(0,18,0,0)};var cancel=new Button{Content="Cancel",Padding=new Thickness(12,7,12,7),Margin=new Thickness(0,0,8,0)};cancel.Click+=(_,_)=>DialogResult=false;var save=new Button{Content="Save",Padding=new Thickness(12,7,12,7)};save.Click+=(_,_)=>Save();actions.Children.Add(cancel);actions.Children.Add(save);p.Children.Add(actions);Content=p;}
 void Save(){if(string.IsNullOrWhiteSpace(title.Text)||!double.TryParse(amount.Text,NumberStyles.Number,CultureInfo.InvariantCulture,out var value)||!double.IsFinite(value)||value<=0){MessageBox.Show("Title aur positive valid amount darj karein.","Invalid expense",MessageBoxButton.OK,MessageBoxImage.Warning);return;}Amount=value;DialogResult=true;}
}