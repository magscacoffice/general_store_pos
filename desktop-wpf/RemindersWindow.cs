using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using KhanBabaPos.Wpf.Services;
namespace KhanBabaPos.Wpf;
public sealed class RemindersWindow:Window
{
 readonly ReminderService service=new();readonly ObservableCollection<ReminderRow> rows=[];
 readonly DataGrid grid=new(){AutoGenerateColumns=false,IsReadOnly=true,CanUserAddRows=false,EnableRowVirtualization=true,RowHeight=38};
 readonly TextBlock status=new(){Foreground=Brushes.DimGray};
 public RemindersWindow(){Title="Reminders | Khan Baba POS";Width=1100;Height=700;MinWidth=900;MinHeight=540;WindowStartupLocation=WindowStartupLocation.CenterOwner;Background=Brushes.WhiteSmoke;grid.ItemsSource=rows;Configure();Content=Layout();Loaded+=async(_,_)=>await LoadAsync();}
 void Configure(){grid.Columns.Add(new DataGridTextColumn{Header="Reminder",Binding=new System.Windows.Data.Binding("Title"),Width=220});grid.Columns.Add(new DataGridTextColumn{Header="Details",Binding=new System.Windows.Data.Binding("Details"),Width=new DataGridLength(1,DataGridLengthUnitType.Star)});grid.Columns.Add(new DataGridTextColumn{Header="Date",Binding=new System.Windows.Data.Binding("Date"),Width=140});grid.Columns.Add(new DataGridTextColumn{Header="Status",Binding=new System.Windows.Data.Binding("Status"),Width=120});grid.SetValue(VirtualizingPanel.IsVirtualizingProperty,true);grid.SetValue(VirtualizingPanel.VirtualizationModeProperty,VirtualizationMode.Recycling);ScrollViewer.SetCanContentScroll(grid,true);}
 UIElement Layout(){var root=new DockPanel{Margin=new Thickness(20)};var header=new DockPanel{LastChildFill=false,Margin=new Thickness(0,0,0,14)};var title=new StackPanel();title.Children.Add(new TextBlock{Text="Reminder Register",FontSize=25,FontWeight=FontWeights.Bold,Foreground=Brushes.DarkSlateGray});title.Children.Add(new TextBlock{Text="Store follow-ups and collection reminders.",Foreground=Brushes.DimGray,Margin=new Thickness(0,4,0,0)});header.Children.Add(title);var add=Btn("Add Reminder");add.Click+=async(_,_)=>await AddAsync();DockPanel.SetDock(add,Dock.Right);header.Children.Add(add);DockPanel.SetDock(header,Dock.Top);root.Children.Add(header);DockPanel.SetDock(status,Dock.Bottom);status.Margin=new Thickness(0,8,0,0);root.Children.Add(status);root.Children.Add(grid);return root;}
 static Button Btn(string s)=>new(){Content=s,Padding=new Thickness(12,8,12,8),Margin=new Thickness(8,0,0,0)};
 async Task LoadAsync(){try{var data=await service.GetAllAsync();rows.Clear();foreach(var x in data)rows.Add(x with{ });status.Text=$"{rows.Count} reminder(s) • {rows.Count(x=>!x.IsDone)} pending";}catch(Exception e){status.Text="Reminders load failed: "+e.Message;}}
 async Task AddAsync(){var dialog=new AddReminderDialog{Owner=this};if(dialog.ShowDialog()!=true)return;try{await service.AddAsync(dialog.ReminderTitle,dialog.Details);await LoadAsync();status.Text="Reminder saved successfully.";}catch(Exception e){MessageBox.Show(e.Message,"Reminder could not be saved",MessageBoxButton.OK,MessageBoxImage.Warning);}}
}
internal sealed class AddReminderDialog:Window
{
 readonly TextBox title=new(){Padding=new Thickness(8),MinWidth=280};readonly TextBox details=new(){Padding=new Thickness(8),MinWidth=280,AcceptsReturn=true,Height=80,TextWrapping=TextWrapping.Wrap};
 public string ReminderTitle=>title.Text.Trim();public string Details=>details.Text.Trim();
 public AddReminderDialog(){Title="Add Reminder";Width=430;Height=340;WindowStartupLocation=WindowStartupLocation.CenterOwner;ResizeMode=ResizeMode.NoResize;var p=new StackPanel{Margin=new Thickness(20)};p.Children.Add(new TextBlock{Text="Title *"});p.Children.Add(title);p.Children.Add(new TextBlock{Text="Details",Margin=new Thickness(0,12,0,4)});p.Children.Add(details);var actions=new StackPanel{Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right,Margin=new Thickness(0,18,0,0)};var cancel=new Button{Content="Cancel",Padding=new Thickness(12,7),Margin=new Thickness(0,0,8,0)};cancel.Click+=(_,_)=>DialogResult=false;var save=new Button{Content="Save",Padding=new Thickness(12,7)};save.Click+=(_,_)=>{if(string.IsNullOrWhiteSpace(title.Text)){MessageBox.Show("Reminder title zaroori hai.");return;}DialogResult=true;};actions.Children.Add(cancel);actions.Children.Add(save);p.Children.Add(actions);Content=p;}
}
