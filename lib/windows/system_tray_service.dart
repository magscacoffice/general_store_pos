import 'dart:async';
import 'dart:io';

import 'package:tray_manager/tray_manager.dart';

import 'pos_windows.dart';

class PosSystemTrayService {
  PosSystemTrayService._();

  static TrayIcon? _trayIcon;
  static Menu? _contextMenu;
  static MenuItem? _newSaleItem;
  static MenuItem? _showDashboardItem;
  static MenuItem? _exitItem;

  static bool get isInitialized => _trayIcon != null;

  static Future<void> initialize() async {
    if (!Platform.isWindows || _trayIcon != null) return;

    final icon = TrayIcon.create();
    if (icon == null) {
      throw StateError('Windows system tray icon could not be created.');
    }

    final menu = Menu.create();
    if (menu == null) {
      icon.dispose();
      throw StateError('Windows system tray menu could not be created.');
    }

    final newSale = MenuItem.createWithLabelAndType(
      'New Sale',
      MenuItemType.normal,
    );
    final showDashboard = MenuItem.createWithLabelAndType(
      'Show Dashboard',
      MenuItemType.normal,
    );
    final exitItem = MenuItem.createWithLabelAndType(
      'Exit POS',
      MenuItemType.normal,
    );
    if (newSale == null || showDashboard == null || exitItem == null) {
      icon.dispose();
      throw StateError('Windows system tray menu items could not be created.');
    }

    newSale.addListener((event) {
      if (event is MenuItemClickedEvent) {
        unawaited(PosWindows.openSale());
      }
    });
    showDashboard.addListener((event) {
      if (event is MenuItemClickedEvent) {
        unawaited(PosWindows.openDashboard());
      }
    });
    exitItem.addListener((event) {
      if (event is MenuItemClickedEvent) {
        exit(0);
      }
    });

    menu.addItem(newSale);
    menu.addSeparator();
    menu.addItem(showDashboard);
    menu.addSeparator();
    menu.addItem(exitItem);

    icon.icon = ImageAsset.fromAsset('web/icons/Icon-192.png');
    icon.setTooltip('Khan Baba General Store POS');
    icon.setContextMenu(menu);
    icon.setContextMenuTrigger(ContextMenuTrigger.rightClicked);
    icon.addListener((event) {
      if (event is TrayIconClickedEvent) {
        unawaited(PosWindows.openSale());
      }
    });
    icon.setVisible(true);

    _trayIcon = icon;
    _contextMenu = menu;
    _newSaleItem = newSale;
    _showDashboardItem = showDashboard;
    _exitItem = exitItem;
  }

  static void dispose() {
    _trayIcon?.dispose();
    _trayIcon = null;
    _contextMenu = null;
    _newSaleItem = null;
    _showDashboardItem = null;
    _exitItem = null;
  }
}
