# Khan Baba POS — Windows Native WPF Migration Roadmap

> **Migration scope:** Replace the **Windows Desktop client only** with a native C#/.NET WPF application. Android remains Flutter and continues to use the existing SQLite database format and approved sync workflows.
> **Strict UI framework rule:** Use **WPF (Windows Presentation Foundation)** only. **Do not use WinUI 3, Windows App SDK, MAUI, a web wrapper, or Flutter Windows.**
> **Windows platform retirement:** Flutter Windows runner and its GitHub build/release workflow are being removed. Android Flutter remains the supported Flutter client; all future Windows UI, hardware, sync, and release work belongs in `desktop-wpf/`.
> **Repository:** https://github.com/magscacoffice/general_store_pos
> **Audited base / integration:** `main` at `2dbbf9ee4e89a29b69726ac33531c0b15c5f13de` (2026-11-15); WPF source and tracker updates are on `integration/wpf-mainline` and Draft PR #5, not yet merged to main.
> **Planning status:** Native WPF and Android Flutter billing now both include distinct Walk-in/Khata/Wholesale account handling, wholesale-rate defaults and per-item Wholesale price editing. WPF Release build/schema tests and Android analysis/regression tests, including Wholesale cash/partial ledger and Drive snapshot round-trip coverage, passed on the latest integration commit (Actions #150 and #266). WPF transaction parity, Drive sync/auth, real-device and physical Windows acceptance remain pending.

## 1. Non-negotiable compatibility rules

- [x] Keep Android's Flutter implementation, Android validation workflow, and existing mobile user experience intact; Android analyzer and test validation passed after the test harness fix.
- [ ] Build and complete the separate native Windows application under `desktop-wpf/`. Flutter Android (`lib/` + `android/`) and shared database logic must remain intact. The Flutter Windows runner/UI and its build/release workflow have been explicitly retired and must not be restored.
- [ ] Preserve business behaviour: sale posting, stock movements, purchase posting, returns, discounts (including percentage discounts), received amounts, customer balances/Khata ledger, profit calculations, invoice totals, and all existing validation rules.
- [ ] Preserve all three customer types: Walk-in, Khata, and Wholesale. Customer type is separate from payment method. Wholesale customers may pay cash, credit, or partially; every received amount must be recorded against the same wholesale customer's account/Khata, update the outstanding balance, and retain transaction/payment history. Do not make Wholesale cash-only or remove the existing option.
- [ ] Do not change database table/column names, IDs, SQLite file location, schema version, sync identifiers, tombstone semantics, or existing backup format without a separately reviewed migration and Android compatibility proof.
- [ ] Windows remains local-first and uses the existing Windows-master Google Drive snapshot workflow. Do not add Firebase/Firestore business-data sync to Windows.
- [ ] No network dependency for ordinary sales, inventory, purchases, returns, printing, reports, or local login/access flow. Internet is only used for the already-approved Drive sync and update checks when available.
- [ ] Preserve the existing database at `%LOCALAPPDATA%\\KhanBabaPOS\\Data\\khan_baba_pos.db` and the `.active_database` restore pointer behaviour. Never overwrite or delete the live database as a side effect of installation/update.
- [ ] Build a migration/import validation utility and take a verified backup before the WPF application first opens or writes to the existing database.
- [ ] No production feature is marked complete until it is implemented, built, tested against a copy of the real schema, and its parity with Flutter is verified.

## 2. Deep audit — repository inventory

The Android client remains Flutter/Dart. The current-main-based integration branch adds the separate native `desktop-wpf/` Windows client and `desktop-wpf.Tests/`; this branch is pending Draft PR #5 and is not yet merged. The Flutter Windows runner and Windows-specific build/release workflow have been retired. Current GitHub Actions validate Android source/tests, POS sync/invoice tests and native WPF build/schema/transaction tests without publishing release artifacts.

### 2.1 Flutter screens and current WPF implementation / remaining targets

| Existing Flutter file / feature | WPF implementation or remaining target | Responsibilities to preserve |
|---|---|---|
| `main.dart`, `auth_gate.dart`, `login_screen.dart` | `App.xaml`, `App.xaml.cs`, `MainWindow.xaml`; Login/access/role parity remains pending | Startup shell exists; implement approved local/offline access and role checks without introducing Firebase business sync |
| `dashboard_screen.dart` | `MainWindow.xaml`, `MainWindow.xaml.cs` | Initial native navigation shell and dashboard-hosted cashier workspace exist; full role-aware navigation/status parity remains pending |
| `sales_screen.dart` | `MainWindow.xaml`, `MainWindow.xaml.cs`, `Services/SalePostingService.cs` | Native cashier source, pending bills, Walk-in/Khata/Wholesale, discounts, price edits and transactional posting implemented; broader parity acceptance remains pending |
| `inventory_screen.dart` | `InventoryWindow.cs`, `Services/InventoryService.cs` | Product CRUD/search, barcode uniqueness, retail/wholesale rates, stock, damaged quantity, active status and stock unit source implemented |
| `scanner_screen.dart` | `MainWindow.xaml.cs` keyboard-wedge scanner input; dedicated `ScannerWindow` remains pending | Barcode keyboard input and search are implemented; camera/serial scanner adapter and physical SpeedX SP60D testing remain pending |
| `purchase_screen.dart` | `PurchasesWindow.cs`, `Services/PurchaseService.cs` | Searchable purchase/stock entry source implemented; invoice/ledger/stock integration tests remain pending |
| `supplier_invoice_capture_screen.dart` | `Views/SupplierInvoiceReviewWindow.xaml` (Windows scope gated) | Existing invoice review/conversion/posting rules; mobile camera/ML Kit capture stays Android-only unless a separately approved Windows document-input design is added |
| `party_screen.dart` | `PartiesWindow.cs`, `Services/PartyService.cs` | Customer/supplier list, creation, Khata/Wholesale account classification and reclassification source implemented |
| `customer_khata_screen.dart` | `KhataWindow.cs`, `Services/KhataService.cs` | Customer balance/ledger/receipt source implemented; broader parity tests remain pending |
| `customer_history_screen.dart` | `Views/CustomerStatementWindow.xaml` | Per-customer sales/receipts/ledger history, date-range statement and PDF/export |
| `history_screen.dart` | `SalesHistoryWindow.cs` | Sales history search and invoice detail source implemented; full reprint/return navigation acceptance remains pending |
| `sales_report_screen.dart` | `SalesReportsWindow.cs`, `Services/SalesReportService.cs` | Date filters and report summary source implemented; report parity tests remain pending |
| `profit_loss_screen.dart` | `ProfitLossWindow.cs`, `Services/ProfitLossService.cs` | Existing income/cost/expense and profit calculation source implemented; parity test remains pending |
| `expense_screen.dart` | `ExpensesWindow.cs`, `Services/ExpenseService.cs` | Expense create/list and totals source implemented |
| `sale_return_screen.dart` | `SaleReturnWindow.cs`, `Services/SaleReturnService.cs` | Return/refund transaction source implemented; disposable-database integration tests remain pending |
| `return_history_screen.dart` | `Views/ReturnHistoryWindow.xaml` | Return list, details and audit trail |
| `reminders_screen.dart` | `RemindersWindow.cs`, `Services/ReminderService.cs` | Reminder create/list/complete source implemented |
| `salesmen_management_screen.dart` | `Views/StaffManagementWindow.xaml` | Existing admin/role-gated staff management; preserve current auth dependency and do not silently replace it with a new identity model |
| `printer_screen.dart` | `PrinterInvoiceWindow.cs`, `Services/PrinterSettingsService.cs` | Printer queue selection/persistence, 80mm ESC/POS test/receipt source, invoice preview and PDF save/open implemented; physical BC-86AC acceptance pending |
| `backup_screen.dart` | `BackupRestoreWindow.cs`, `Services/DatabaseBackupService.cs` | Verified backup and staged restore with SHA-256, schema validation and atomic active-pointer switch implemented and tested |
| `cloud_sync_screen.dart` | WPF Cloud Sync window/service — pending | Port the existing Google Drive Windows-master protocol, sync status and conflict review; no Firebase/Firestore business sync |
| `drive_sync_service.dart` | WPF Drive snapshot service — pending | OAuth, secure token storage, snapshot hashing, upload/download, Windows-master merge, conflict/tombstone rules and auto-sync |
| `update_manager.dart`, `windows/windows_update_service.dart` | `Services/UpdateService.cs`, `Views/UpdateDialog.xaml` | Stable release detection, checksum verification, staged update and safe restart without touching user data |
| `windows/system_tray_service.dart`, `windows/pos_windows.dart` | `Services/SystemTrayService.cs`, `Services/WindowCoordinator.cs` | Tray menu, dashboard and cashier window lifecycle, multiple pending bills, minimize/restore and close handling |
| `windows/desktop_theme.dart`, `windows/desktop_app_bar.dart` | `Themes/Colors.xaml`, `Themes/Controls.xaml`, `Styles/DataGrid.xaml` | Consistent desktop typography, controls, focus/hover states, scrolling and shared visual language |

### 2.2 Shared logic and supporting modules

- `db_helper.dart` (145 KB) is the central source of truth for SQLite schema, version-18 creation/upgrades, CRUD, atomic sale/purchase/return operations, customer balances, Khata transactions, reporting queries, pending bills and sync queue.
- `invoice_unit_converter.dart` defines canonical units, suggested conversions, integer stock quantity conversion and base-unit cost calculations. Port these rules with parity tests.
- `drive_sync_service.dart` and the Drive snapshot/conflict methods in `db_helper.dart` define a non-trivial two-way sync contract; port the contract rather than designing a new sync format.
- `gemini_invoice_ocr_service.dart` and the camera/ML Kit parts of `supplier_invoice_capture_screen.dart` are currently Android-oriented. They are not a reason to add an online OCR dependency to Windows. Windows OCR is out of initial scope unless explicitly approved.
- `update_manager.dart` contains Android update behaviour; `windows_update_service.dart` is the Windows-specific update reference. Preserve platform-specific install/update paths.
- `functions/index.js`, Firebase configuration and messaging are not to be repurposed as Windows business-data sync.

### 2.3 Existing automated tests to port or reproduce

- `test/invoice_unit_converter_test.dart`: unit conversion and base-unit cost.
- `test/supplier_invoice_conversion_test.dart`: SQLite purchase invoice posting, pack conversion, stock and supplier totals.
- `test/drive_sync_integration_test.dart`: snapshot import, sync conflict detection and conflict resolution.
- `test/widget_test.dart`: inspect for current startup/widget assumptions; WPF will have its own view-model/service tests and Windows UI smoke tests.
- GitHub Actions retain Android APK and POS sync/invoice tests and include a separate native WPF Windows build workflow. Do not restore a Flutter Windows build/package workflow.

## 3. Existing SQLite architecture — compatibility contract

### 3.1 Database file and version

- Current SQLite schema version: **18** (defined in `DBHelper.initDB()`).
- Windows data directory: `%LOCALAPPDATA%\\KhanBabaPOS\\Data` (with existing APPDATA/profile fallbacks if LOCALAPPDATA is not writable).
- Default database: `khan_baba_pos.db`.
- Restore activation: `.active_database` may point to a staged `khan_baba_pos_*.db` file. The WPF client must resolve and validate this pointer exactly and must not delete an open/live database.
- Flutter `sqflite_common_ffi` is used for desktop SQLite access. WPF will use Microsoft.Data.Sqlite through EF Core SQLite while retaining the exact existing database file and SQL schema.

### 3.2 Tables and key fields found in schema v18

| Table | Important columns / role |
|---|---|
| `products` | `id`, `name`, unique `barcode`, `price`, `purchasePrice`, `wholesalePrice` (persisted default wholesale unit rate; use as the default editable item rate for Wholesale customers when available), `damaged_quantity`, `quantity`, `is_active`, `stock_unit` |
| `sales` | `id`, `total_amount`, `discount`, `final_amount`, `payment_type`, `customer_id`, `salesman_uid`, `salesman_name`, `customer_type`, `received_amount`, `balance_due`, `sync_id`, `customer_sync_id`, `date` |
| `sale_items` | `id`, `sale_id`, `product_id`, `barcode`, `product_name`, `quantity`, `sale_price`, `purchase_price`, `line_total`, `cost_total`, `sync_id`, `sale_sync_id`, `stock_unit` |
| `parties` | `id`, `name`, `phone`, `type`, `customer_type`, `sync_id`, `balance` |
| `purchases` | Product/supplier references, quantity/cost/total/date, invoice group/number/date, invoice total/discount/tax/paid/balance, image path, invoice unit label/quantity, conversion factor, base unit and invoice-unit cost |
| `expenses` | `id`, `title`, `amount`, `date`, `sync_id` |
| `reminders` | `id`, `title`, `details`, `date`, `is_done`, `sync_id` |
| `khata_transactions` | `id`, `party_id`, `type`, `amount`, `note`, `date`, `sync_id`, `party_sync_id` |
| `sale_returns` | `id`, `sale_id`, `customer_id`, `reason`, `refund_method`, `refund_amount`, `date`, sync IDs |
| `sale_return_items` | Return/sale item/product references, barcode/name, quantity, sale/purchase price, line/cost totals, condition, sync IDs and stock unit |
| `sync_queue` | Collection/document key, operation, payload, created time, attempts and last error; unique collection/document pair |
| `khata_reminder_log` | Party + oldest due date + creation time; unique pair |
| `pending_bills` | `bill_id` primary key, label, serialized payload, updated time |
| `drive_sync_conflicts` | Source device, snapshot hash, entity type/key, local/remote payload, status, resolution and timestamps |
| `drive_sync_aliases` | Source device + remote sync ID mapped to local sync ID |
| `drive_sync_tombstones` | Deleted entity type/key/time/source device; unique entity pair |
| `drive_sync_ignored_tombstones` | Source device + entity type/key composite primary key |

**Important:** The table above is an inventory, not a substitute for the complete DDL. Before implementing EF Core entities, extract every column, nullability, default, unique constraint, index and migration step from the full version-18 DDL and `onUpgrade` path. Use explicit `ToTable`, `HasColumnName`, `HasColumnType`, key, index and default mappings. Do not let EF Core convention-based migrations rename or recreate the legacy tables.

### 3.3 Proposed data access design

- [x] Target framework: `net10.0-windows` WPF; confirmed the Windows GitHub Actions runner restores and builds this target successfully.
- [ ] EF Core SQLite for entity mapping/query composition, plus explicit parameterized SQL for operations whose exact transaction semantics must match the Flutter implementation.
- [ ] Map the existing tables in-place; do not create a second business database or a new schema namespace.
- [ ] Preserve SQLite integer primary keys, nullable foreign keys, REAL money fields, TEXT date representation, sync IDs and exact legacy column casing.
- [ ] Use `decimal` in C# domain calculations where appropriate, but serialize/write values to SQLite in a way that matches the existing Flutter double/REAL behaviour; prove rounding/formatting parity with golden tests before changing any persisted calculation.
- [ ] Implement atomic transaction services for sale + sale items + stock deduction + customer balance/Khata, purchase + stock/supplier balance, and returns + stock/refund/ledger.
- [x] Add a read-only database compatibility gate: inspect `PRAGMA user_version`, `sqlite_master`, table columns, primary keys, required defaults/NOT NULL constraints, unique constraints, `quick_check`, foreign-key integrity and active database pointer; support schema v18 without destructive upgrades. Representative database fixture testing remains a separate pending task.
- [ ] For future schema evolution, coordinate a versioned migration that remains readable by the Android version still in use. Do not advance schema version until a backward-compatibility strategy is approved.
- [ ] Preserve backup staging, checksums, pending-bill recovery and sync conflict/alias/tombstone tables.

## 4. Business feature parity checklist

- [ ] **Billing:** single dashboard cashier workspace; focused barcode/search field; multiple pending bills; create/switch/restore bill; repeat scan increments quantity; product autocomplete; quantity editing; sale-price validation; cart removal; checkout; receipt hand-off.
- [ ] **Discounts:** preserve fixed and percentage discount modes, existing calculations, validation, invoice display and stored `discount`/final values exactly. Never remove or reinterpret the current discount feature.
- [ ] **Customer/payment:** preserve Walk-in, Khata, and Wholesale customer types. Keep customer type separate from payment method. Wholesale supports cash, credit, and partial payments; record receipts against that same customer's Khata/account, update outstanding balance, and retain transaction/payment history.
- [ ] **Khata:** preserve customer balance, credit sale, partial/received payments, receipt history, ledger transactions, customer statement and due reminders exactly as implemented in the current source.
- [ ] **Inventory:** product create/edit/delete rules, barcode uniqueness, stock quantity, damaged quantity, active/inactive, stock units, low stock display, purchase-cost floor and sale stock deductions.
- [ ] **Purchases:** supplier association, invoice grouping/duplicate guard, discounts/tax/paid/balance fields, invoice-unit conversions, integer stock conversion, base-unit cost and review-before-posting.
- [ ] **Sales history and returns:** bill details/reprint, eligible return quantities, return reason/refund method, saleable/damaged condition, stock restoration and return history.
- [ ] **Reports:** sales range/grouping, profit/loss, expense totals and customer statements must match Flutter query results for the same database snapshot.
- [ ] **Reminders and staff:** preserve reminder status and role-gated staff management; no new permissions model without approval.
- [ ] **Backup/restore:** full database copy, integrity check, staged restore, active-file pointer, rollback and user-data preservation.
- [ ] **Offline operation:** all local POS workflows work without internet; sync status must never block local checkout.

## 5. Native WPF desktop UI/UX strategy

### 5.1 Overall shell

- [ ] Native WPF `ShellWindow` with standard Windows title bar/window controls, resizable/maximize/restore/minimize, sensible minimum size, DPI-aware layout and optional system tray.
- [ ] Persistent left navigation sidebar with icon + label, selected state, role-aware menu items and compact/collapsible option.
- [ ] Header/status strip for store name, current user/role, database status, sync status, printer status and update notification.
- [ ] Consistent theme resources, typography, spacing, accessible contrast, keyboard focus visuals, hover/pressed/disabled states and confirmation dialogs.
- [ ] No mobile-style cards as the primary way to navigate large desktop datasets. Use dense, sortable, filterable DataGrids with row selection and contextual actions.

### 5.2 Master-detail cashier screen

- [ ] Dashboard opens directly into the POS billing workspace, not an empty dashboard landing page.
- [ ] Left/master area: persistent scanner/search input, product suggestions, category/stock context and current bill item DataGrid.
- [ ] Right/detail area: customer/account selector, subtotal, discount controls, grand total, received amount/balance, payment action and checkout.
- [ ] Cart columns: barcode/item, quantity, unit, rate, discount where applicable, line amount; support keyboard edit and clear row selection.
- [ ] Scanner input receives focus when the cashier workspace opens and after a completed scan/product add, unless the user deliberately moves focus to another control.
- [ ] New Sale creates a fresh pending bill in the same workspace; pending bill switching is explicit and data-safe.
- [ ] F2: focus barcode/product search; F4: customer selection; F5: new bill (only when no destructive/active modal action conflicts); Esc: close current dialog/drop-down or cancel current transient action. Add shortcuts for quantity, discount and checkout only after conflict review and document them in Help.
- [ ] Enter selects the highlighted product suggestion; Up/Down navigate suggestions; repeated barcode scans increment the existing cart line quantity.
- [ ] Do not install a global keyboard hook. Generic USB HID/keyboard-wedge scanners type into the focused field; minimized/background scanner capture is not safe for a generic keyboard device.

### 5.3 Other windows

- [ ] Inventory, history, purchases, parties, Khata, reports, expenses, reminders and returns use compact toolbar + search/filter row + dense DataGrid + detail/edit dialog.
- [ ] Use master/detail split panels for customer statement, invoice preview and sync conflicts where it improves workflow.
- [ ] Use standard WPF DatePicker, ComboBox, validation templates and modal dialogs; retain all current validations and confirmation steps.
- [ ] Printer screen uses a responsive configuration/preview split: printer selection and paper/configuration on one side, independently scrollable 80mm receipt preview on the other.
- [ ] DataGrid columns should resize sensibly; avoid fixed widths that clip at 980×650. Provide empty/loading/error states and keyboard-accessible actions.

## 6. Hardware integration plan

### 6.1 USB barcode scanners

- [ ] Default: keyboard-wedge/HID scanner sends barcode characters and Enter into the focused POS scanner field. Configure robust suffix handling, debounce/scan completion and prevent ordinary manual typing from being misclassified as a scan.
- [ ] Maintain scanner focus within the active cashier workflow without stealing focus from another application or capturing unrelated keyboard input.
- [ ] Optional: serial/COM scanner adapter only for scanners explicitly configured as serial devices; enumerate ports, allow user selection and parse the device's configured terminator.
- [ ] Test SpeedX SP60D as one sample device, but do not hard-code its VID/PID; generic foreground HID remains model-independent.
- [ ] Background/minimized capture is not part of generic HID support. Only add it if a dedicated serial interface or documented vendor SDK is available and explicitly tested.

### 6.2 80mm ESC/POS thermal printing

- [ ] Use native Windows printer enumeration and Windows spooler APIs. Support normal installed Windows printer queues and a raw ESC/POS path when the printer/driver exposes it.
- [ ] Build receipt bytes independently of UI using an `EscPosReceiptBuilder`: initialize, code page/encoding, alignment, bold/size, columns, separators, totals, feed and cut commands.
- [ ] Preserve the current 80mm receipt format, store heading, bill metadata, single-row item descriptions, Qty/Description/Rate/Amount alignment, subtotal, discount, total/net amount, received and balance fields as applicable.
- [ ] Persist the user's chosen printer identifier in local settings. On restart, restore the exact saved printer; if missing, show unavailable/disconnected and require explicit reselection. Never silently switch printers or claim a connection that was not verified.
- [ ] Add print preview, test print, paper width/configuration and useful error reporting. Keep PDF save/preview/export separate from thermal print.
- [ ] Test with the user's Black Copper BC-86AC 80mm printer, including cutter, margins, final-line clipping, encoding, driver and paper alignment. A successful build is not proof of physical print correctness.

## 7. Google Drive sync, authentication and update architecture

- [ ] Port the existing Drive API folder/file/snapshot protocol exactly: device identity, schema version, snapshot hash/checksum, upload/download ordering, Windows-master semantics, pre-merge backup, idempotent processing, conflict records, alias mapping, tombstones and ignored tombstones.
- [ ] Keep the current conflict decision explicit: Keep Windows / Use Other Device. Do not silently overwrite newer records.
- [ ] Port two-minute periodic sync and connectivity-aware retry only after local database transaction locking and cancellation are safely designed for WPF.
- [ ] Store refresh/access credentials using Windows DPAPI or Windows Credential Manager; never store secrets in source, settings JSON or logs.
- [ ] Reuse the existing approved Google OAuth client/configuration and GitHub secret handling. Verify authorization-code flow and refresh-token behaviour on a real Windows machine.
- [ ] Windows business data stays in local SQLite + Drive snapshot; no Firebase/Firestore business-data sync is introduced.
- [ ] Port stable update detection, SHA-256 verification and staged update handoff. Installer/update must preserve SQLite, settings, invoice images and backups.
- [ ] Document online-only operations clearly; app must start and sell offline even if Google Drive/update endpoints are unavailable.

## 8. Proposed WPF solution structure

```text
desktop-wpf/
  KhanBabaPos.sln
  src/
    KhanBabaPos.App/
      App.xaml
      App.xaml.cs
      appsettings.json                 # non-secret defaults only
      Themes/
        Colors.xaml
        Typography.xaml
        Controls.xaml
        DataGrid.xaml
      Views/
        ShellWindow.xaml
        LoginWindow.xaml
        Controls/
          NavigationSidebar.xaml
          PosBillingView.xaml
          StatusBarView.xaml
        InventoryWindow.xaml
        SalesHistoryWindow.xaml
        SaleDetailsWindow.xaml
        PurchasesWindow.xaml
        PartiesWindow.xaml
        CustomerKhataWindow.xaml
        CustomerStatementWindow.xaml
        SalesReportsWindow.xaml
        ProfitLossWindow.xaml
        ExpensesWindow.xaml
        RemindersWindow.xaml
        SaleReturnWindow.xaml
        ReturnHistoryWindow.xaml
        PrinterInvoiceWindow.xaml
        BackupRestoreWindow.xaml
        CloudSyncWindow.xaml
        UpdateDialog.xaml
      ViewModels/
      Commands/
      Converters/
    KhanBabaPos.Domain/
      Entities/
      ValueObjects/
      Calculations/
      Contracts/
    KhanBabaPos.Infrastructure/
      Data/
        PosDbContext.cs
        Configurations/
        Sql/
        DatabasePathResolver.cs
      Repositories/
      Services/
        BarcodeScannerService.cs
        WindowsPrinterService.cs
        EscPosReceiptBuilder.cs
        DriveSyncService.cs
        BackupService.cs
        UpdateService.cs
        SystemTrayService.cs
        WindowCoordinator.cs
    KhanBabaPos.Tests/
      Unit/
      Database/
      Parity/
      Sync/
  scripts/
    inspect-existing-db.ps1
    verify-schema-v18.ps1
    compare-flutter-wpf-fixtures.ps1
```

NuGet package versions will be selected and pinned when scaffolding, after confirming .NET SDK/runner support. Expected core dependencies: Microsoft.EntityFrameworkCore.Sqlite, Microsoft.Extensions.Hosting/DependencyInjection/Logging, and a WPF MVVM command/property implementation. Prefer minimal dependencies and native Windows APIs for printer/tray integration.

## 9. Step-by-step file generation and execution order

1. [ ] **Plan and schema freeze:** complete the DDL/onUpgrade extraction; record table columns, indexes, defaults, unique constraints, sync payload shapes and current calculation fixtures.
2. [x] **WPF scaffold:** create the isolated .NET 10 WPF project, app startup, main cashier shell, build configuration and WPF CI validation. Logging/DI/host lifecycle and final app manifest remain part of startup hardening.
3. [x] **Domain models:** add explicit schema-v18 entity/table/column mappings for the existing POS tables. Additional sync value objects and transaction parity fixtures remain pending.
4. [ ] **SQLite infrastructure:** implement database path resolver + `.active_database`, schema-v18 compatibility check, EF Core mappings, raw SQL transaction layer, repository interfaces and backup-before-first-write safeguard.
5. [ ] **Calculation parity:** port invoice unit conversion, discount, sale totals, cost, stock, payment received/balance, profit/loss and return calculations; add golden tests against Flutter fixtures.
6. [ ] **Application services:** product/inventory, pending bills, sales/checkout, parties/Khata, purchases, expenses/reminders, reports and returns.
7. [ ] **ViewModels and commands:** Shell, login/access, billing, inventory, history, purchase, parties, Khata, reports, returns, printer, backup and sync.
8. [ ] **Theme and navigation:** WPF styles, sidebar, shell status, DataGrid templates, dialog/validation patterns, keyboard shortcuts and responsive window sizing.
9. [ ] **Cashier screen:** master-detail billing UI, focused barcode input, autocomplete, pending bills, discount controls, payment/checkout and transaction rollback/error states.
10. [ ] **Operational screens:** inventory, purchase, party, customer Khata/statement, sales history/details, reports, profit/loss, expenses, reminders and returns.
11. [ ] **Receipt/PDF:** 80mm ESC/POS builder, Windows spooler, persistent printer choice, invoice preview and PDF export.
12. [ ] **Backup/restore and Drive sync:** database-safe restore, OAuth, snapshot protocol, conflict resolution, auto-sync and retry/status UI.
13. [ ] **Window lifecycle and updates:** tray, multiple bill windows if parity requires, update checker, verified package download and safe restart.
14. [ ] **Automated parity and regression:** schema fixture tests, calculation parity, transaction atomicity, sync round-trip/conflict tests, printer byte-layout tests and WPF view-model tests.
15. [x] **CI validation:** add WPF .NET 10 build/schema-test workflow and Android Flutter analysis/test workflow on pull requests; retain the Android release workflow separately. [ ] Windows packaging/release channel and update-migration verification remain pending.
16. [ ] **Manual acceptance:** test on the target Windows laptop at 980×650, 1280×720, maximized/restored, scanner, BC-86AC printer, offline mode, Drive conflict and database restore.
17. [ ] **Cutover:** Flutter Windows retirement has already been explicitly approved and the Flutter Windows runner/build workflow have been removed. Make WPF the supported Windows client only after its full acceptance checklist passes; do not recreate a Flutter Windows rollback path.

## 10. Acceptance gates / completion definition

- [ ] Existing Windows SQLite database opens in WPF with every table and row intact; no destructive schema migration.
- [ ] Android Flutter app can still read data created by WPF, and WPF can read Android-synced snapshots.
- [ ] Same test fixture produces identical sale totals, discount, received amount, balance due, stock, Khata, purchase cost, returns and profit/loss in Flutter and WPF.
- [ ] Every screen listed in section 2.1 is implemented or explicitly classified as Android-only / approved out of Windows scope.
- [ ] Scanner workflow works without global keyboard capture; focus and manual keyboard use remain safe.
- [ ] 80mm receipts print correctly on the actual BC-86AC with no clipping/overlap and correct cutter behaviour.
- [ ] Backup/restore and Drive sync pass recovery/conflict tests without data loss.
- [x] Windows WPF CI build/schema tests and Android Flutter analysis/tests passed in Actions runs #147, #149, #265; expanded Wholesale snapshot round-trip regression is being rechecked in runs #150 and #266.
- [ ] Physical cashier acceptance is signed off by the owner before Windows cutover.

## 11. Audit limitations and open verification items

- [x] Repository tree and all 30 Dart source files/screens/services plus three existing test files and Windows workflow were inventoried/read at source level.
- [x] Database version, primary table DDL and Windows data path/active database pointer were inspected.
- [ ] Before entity generation, complete a line-by-line extraction of every version-18 column, every upgrade branch, every index/constraint and all business transaction methods in `db_helper.dart`; the file is large and must be treated as the final schema authority.
- [ ] Inspect full `auth_gate.dart`, `login_screen.dart`, `main.dart` startup sequence, `db_helper.dart` sync merge and transaction methods, and exact role/permission behaviour before porting.
- [ ] Confirm whether the WPF Windows client should retain the existing Windows multi-window New Sale behaviour or consolidate all bills into the dashboard cashier workspace. Default migration target is the current dashboard-hosted cashier workspace with pending bill tabs; preserve tray/multi-window only where it is still part of current user workflow.
- [ ] Confirm whether any camera-based barcode scanning is actually required on Windows; the current camera/ML Kit supplier invoice workflow is Android-specific.
- [ ] Confirm Windows printer driver/queue behaviour and whether the BC-86AC supports raw ESC/POS over the installed Windows driver/USB path.
- [ ] Confirm the current Windows Google OAuth client configuration and secrets are available to the WPF build/release environment; do not expose secrets in repository documentation.

## 12. Work log

| Date | Work summary | Commit / Build | Status |
|---|---|---|---|
| 2026-11-15 | Audited repository tree, Flutter screen/service inventory, SQLite v18 DDL and Windows data path; documented WPF-only migration architecture and staged plan. | `ee4bb4d` | Plan recorded. |
| 2026-11-15 | Added isolated .NET 10 WPF project, entity models and explicit table/column annotations for all 17 schema-v18 tables, EF Core context and key/index/default mappings, Windows data path and active restore pointer resolution, read-only schema verifier, and WPF CI workflow. No live database changed. | `05ff9ec` | Source committed; CI and schema parity tests pending. |
| 2026-11-15 | Retired the Flutter Windows target: removed the complete native `windows/` runner and `build-windows.yml`, removed the Windows-only startup path, tray/theme/update services and update prompt, and replaced desktop navigation helper implementations with no-op compatibility shims so they render no Windows-specific controls. Android Flutter remains the supported Flutter client; WPF is the only Windows application direction. | `583a9926c8390783bfbdf199fd8441362ba084d8` | Source committed. Android APK and POS tests are running for this commit; verify their final results before declaring validation complete. |
| 2026-11-15 | Transplanted 31 reviewed WPF application source files onto `integration/wpf-mainline`, based on current `main`. Preserved main's newer SQLite v18 foundation/schema tests, WPF workflow, Android source and sync changes; left tracker/README reconciliation for this integration commit. | `1e835c8` | Integrated source branch created; CI and functional acceptance pending. |

---

# Existing Flutter Project Tracker (preserved)

The previous Flutter project requirements, bugs, completed updates and work history are retained below for continuity. They remain applicable to Android and to any Windows feature that is not explicitly superseded by this WPF migration plan.

# Khan Baba POS — Project Updates

> **Purpose:** This file is the single place to write new requirements, bugs, and follow-up work for the Khan Baba General Store POS app.
> **Repository:** https://github.com/magscacoffice/general_store_pos

## Ongoing note-taking agreement

- User will report Khan Baba POS bugs, requirements, ideas, and observations naturally in this ChatGPT conversation; no special template or GitHub editing is required.
- Add each relevant new point to this file as it is reported, preserving its meaning and marking it as pending, bug, idea, or completed only when its status is clear.
- If a point is ambiguous, record the wording as reported and ask one concise clarification when needed; do not silently guess.
- Before starting a batch of implementation work, review this file and the relevant conversation context so earlier notes are not missed.
- Keep this agreement limited to the Khan Baba General Store POS repository.

## How to add an update

Mobile par is file ko Markdown editor mein khol kar neeche relevant section mein apni requirement likhein. Har nayi request ko alag checkbox ke saath add karein.

- Naya kaam: `- [ ]` use karein.
- Kaam mukammal hone ke baad hi `- [x]` mark karein.
- Agar koi masla ho to **Bugs** template fill karein.
- File GitHub par save/push karne ke baad ChatGPT ko kahen: **"Khan Baba POS ki PROJECT_UPDATE.md read karein aur pending updates par kaam shuru karein."**

> Note: File update hone se kaam automatically start nahi hota. ChatGPT ko kaam shuru karne ke liye aapka message zaroori hai.

## Pending Updates

<!-- Source implementation and target-device acceptance are tracked separately. CI build alone never completes hardware/UI acceptance. -->

### [Windows] Native WPF cashier and inventory

- [x] Integrated dashboard-hosted WPF cashier source: scanner-ready focus, exact barcode lookup, product suggestions, keyboard navigation, repeat-scan quantity increment, editable cart quantities, pending-bill switching and autosave.
- [x] Integrated WPF inventory window and service: searchable product list, product add/edit, active/inactive state, protected delete rules and virtualized DataGrid.
- [x] Added separate Walk-in / Khata / Wholesale customer-type selection, matching account filtering and pending-bill persistence.
- [x] Added Wholesale account creation and existing-account reclassification in WPF Parties, persisted product wholesale rates in Inventory, and used saved wholesale rate by default when adding a cart item.
- [x] Enabled per-item manual rate editing for Wholesale bills only; rate validation never allows a sale price below purchase cost.
- [x] WPF sale posting now stores the selected customer type and supports Cash, Credit and Partial Wholesale payments. Cash/partial receipts are posted against the same customer's Khata ledger and balance in the same transaction.
- [ ] Verify the WPF cashier and inventory workflows on a real Windows PC using a disposable copy of the real SQLite v18 database.
- [ ] Validate SpeedX SP60D keyboard-wedge scanner responsiveness and inventory performance on the target computer.
- [ ] Complete responsive visual/interaction acceptance at 980×650, 1280×720, maximized and resized states.

### [Windows] Khata, sales history and transaction workflows

- [x] Integrated WPF sales history search/date filters and read-only invoice details.
- [x] Integrated customer Khata customer search, balance list, ledger and receipt-posting source.
- [x] Integrated transactional sale-posting source with stock deduction, discount handling, payment modes and ledger updates.
- [x] Integrated searchable purchase/stock entry, expense register, reminders, customer/supplier list and profit/loss views.
- [x] Integrated sale-return/refund source with stock restoration and transaction handling.
- [x] .NET 10 WPF Release restore/build and the existing SQLite v18 schema verifier tests passed on the integrated source after correcting the disposable test fixture to disable SQLite connection pooling (Actions runs #130, #131, #147, #149 and #150).
- [x] Backup/restore safety integration test passed on a disposable schema-v18 database (Actions #169).
- [x] WPF sale-posting integration tests passed on disposable schema-v18 databases: Wholesale partial and full-cash receipts, same-account ledger, outstanding balance, stock deduction, 10% percentage-discount calculation, and mismatched account rejection/rollback (Actions #181).
- [x] WPF backup failure-path test passed: invalid SHA-256 sidecar is rejected without changing the current database or active pointer (Actions #186).
- [x] WPF purchase, sale-return/refund and Khata receipt integration tests passed on disposable SQLite v18 copies: purchase stock/cost/wholesale-rate floor, saleable/damaged return stock handling, Khata refund adjustments, receipt balance reduction and overpayment rejection (Actions #198).
- [ ] Add WPF sales-report and profit/loss calculation integration tests against disposable SQLite v18 copies.
- [ ] Verify all transaction totals, discount (including percentage), received amounts, customer balances, payment history and stock movements against Android behaviour. Do not alter the existing discount feature.
- [x] Restored Android Flutter Wholesale parity in billing: Walk-in/Khata/Wholesale are distinct; Wholesale supports Cash/Credit/Partial, saved wholesale product rate defaults, manual per-item rate edits, scanner defaults, and receipts/ledger history against the same account. Existing discount/percentage behaviour is unchanged.
- [x] Updated Android party creation/reclassification, sale transaction validation and Drive snapshot import/export paths to preserve customer_type instead of forcing every account to Khata. Existing accounts previously converted by the old schema upgrade can be reclassified from the customer account screen; the app does not guess their former type.
- [ ] Complete on-device Android acceptance for Wholesale creation, manual/default pricing, cash/credit/partial receipts, outstanding balance and Drive snapshot restore. Keep real user data backed up before reclassifying any existing account.

### [Windows] Printer and invoice

- [x] Integrated WPF printer/invoice source: Windows printer queue discovery, saved preferred printer, 80mm ESC/POS receipt builder, raw spooler output, test print, invoice/receipt preview, PDF save/open and receipt configuration.
- [x] Integrated compact printer list with queue availability and explicit Connect/Select action; unavailable saved printers are not silently replaced.
- [ ] Verify saved-printer restoration and unavailable-queue behaviour across Windows application restarts.
- [ ] Verify PDF save/open/share on the target Windows PC.
- [ ] Physically test Black Copper BC-86AC 80mm USB printer: alignment, margins, header/total sizing, final-line clipping, cutter and paper feed.
- [ ] Record responsive visual/interaction acceptance, keyboard focus, hover, clipping and independent preview scrolling.

### [Windows] Data safety, authentication and sync

- [x] Preserved current-main SQLite v18 entity/schema foundation, read-only schema verifier, database path resolver and existing schema compatibility tests during WPF source integration.
- [x] Preserved the current-main WPF CI workflow and Android validation workflow; preserved main-branch database/schema changes rather than overwriting them with the older feature branch.
- [ ] Complete full version-18 schema/constraint and Flutter transaction-method audit before production write enablement.
- [x] Added WPF Backup & Restore window/service: create verified SQLite v18 backups with SHA-256 sidecars; restore only to a new staged database file; verify schema before atomically switching `.active_database`; preserve the previous live database and flush the active cashier bill first.
- [x] New disposable-database backup/restore integration test passed in WPF Actions run #169; it confirms the old live database remains unchanged and the verified staged copy is activated through the pointer.
- [x] Added and passed failure-path coverage for a backup with an invalid SHA-256 sidecar; restore is rejected and the active pointer/current database remain unchanged (WPF Actions #186).
- [ ] Implement and verify Windows Google Drive snapshot sync using the existing Windows-master protocol, including upload/download direction, conflicts, retries, status and offline behaviour. No Firebase/Firestore business-data sync.
- [ ] Complete Windows authentication, existing role/access parity and safe update flow; verify OAuth configuration without committing secrets.
- [ ] Complete Windows startup, recovery and restore-pointer validation without creating or replacing the live database.

### [Windows] Flutter Windows retirement and final cutover

- [x] Flutter Windows runner and its Windows build/release workflow were retired on main; Android Flutter remains the supported Flutter client.
- [x] Transplanted the reviewed WPF application source from the diverged feature branch onto a fresh integration branch based on current main. The main-branch schema foundation, schema tests, README baseline and CI workflow were preserved.
- [x] Run WPF .NET 10 restore/build and schema tests on the integrated branch; Actions runs #130, #131, #147 and #149 passed. The latest expanded WPF/Android regression runs #150 and #266 also passed.
- [x] Review and reconcile the old draft PR #4: closed the diverged draft and replaced it with current-main-based Draft PR #5. Do not merge the old branch directly.
- [ ] Complete target-Windows runtime, visual, scanner and printer acceptance.
- [ ] Owner signs off physical cashier acceptance before Windows cutover.
- [ ] Merge to main only after all required automated and owner acceptance gates pass. Do not create or publish an APK, EXE, installer or release artifact while pending tasks remain.

## New notes from user (2026-11-13)


## Additional Windows and sync notes from user (2026-11-13)

- [x] **Google Drive periodic auto-sync — code implemented.** User currently experiences sync as manual and wants it to happen automatically at a practical interval, ideally every 1–5 minutes (or the safest/reliable interval supported by the app). Review upload/download direction, pending changes, conflict handling, retries, and status/error feedback so automatic sync does not silently overwrite newer data. The code now polls every 2 minutes and also reacts to connectivity changes; real-device two-way sync reliability and conflict/retry behaviour still require hands-on verification.
- [x] **Windows startup/cloud status — accurate local-first status implemented.** Startup now distinguishes unavailable internet, missing Google Drive credentials, pending first sync, and a saved previous sync. Local POS availability remains explicit; genuine offline state is not hidden.
- [x] **Windows lists — persistent desktop scrollbar theme implemented.** Windows theme now supplies visible, interactive scrollbars consistently; screens with custom DataTable scrollbars retain their local controls.
- [x] **Full Windows UI code audit and fixes — implemented.** Reviewed the Windows dashboard, New Sale, inventory, sales history/customer history, reports, purchases, expenses, parties, Khata, reminders, profit/loss, cloud sync, backup, returns, scanner, printer/settings and shared startup flows. Existing Windows-specific desktop layouts were checked against the 980×650 minimum window. Fixed the printer/invoice page's fixed-height overflow by making its Windows content vertically scrollable and giving the cart preview its own bounded viewport; removed the unsupported Bluetooth-printer discovery UI/call from Windows while preserving it on Android; renamed the Windows USB action/help text for a PC connection; standardized the receipt paper default to 80 mm on both Android and Windows in the follow-up receipt update; and changed the preview label to be paper-width neutral. The supplier-invoice camera/Gemini OCR workflow remains Android-only by design. No sales/inventory business rules or update-checker code were changed. **Remaining validation:** physical Windows run-through of every dialog, keyboard interaction, window resizing, actual USB printer discovery/printing and long-list scrolling is still required; source review alone cannot certify native plugin behaviour or visual rendering.
- [ ] **Windows minimized-app scanner capture — platform limitation / safe fallback retained.** Any ordinary USB HID/keyboard-wedge barcode scanner can type into the focused New Sale scan field; no scanner model or VID/PID is required for foreground operation. Generic Raw Input sink notifications cannot prevent the same keystrokes from reaching whichever other application is focused, so forwarding them while POS is minimized could leak barcode data and capture ordinary keyboard typing. The unsafe focus-stealing Raw Input activation has therefore been removed. Do not add a global keyboard hook or suppress all keyboard input. True background support requires a scanner exposed through a dedicated serial/COM interface, vendor SDK, or device-specific exclusive mode; support such an interface if one is available, otherwise retain the focused-New Sale fallback.
- [x] **Windows New Sale — combined scan/search input already implemented and verified in source.** One visible input accepts exact barcode scans and routes non-matching text into product search; the separate controller is used only by the search dialog, not as a second visible field.

## Cross-platform inventory duplicate-check note from user (2026-11-13)

- [x] **[Android + Windows] Immediate duplicate-barcode warning — code implemented.**** When adding a product, if the scanned barcode already belongs to a product in inventory, the app should detect and notify the user immediately at scan time (before the user spends time entering the rest of the product details). Current reported behaviour: the duplicate barcode is accepted during entry and only reported when the user presses Save, wasting time and entered work. Review and fix the barcode lookup/duplicate validation flow on both Android and Windows. Keep legitimate editing/updating of an existing product possible; distinguish an intentional edit from accidentally adding a duplicate new product. Add appropriate feedback and verify both platforms.

## Sales history / invoice detail note from user (2026-11-13)

- [x] **Sales History — invoice detail view — code implemented.**** When the user opens Sales History and taps/clicks an invoice, that invoice should open in a detail view. Show all items/products included in that sale and the relevant invoice details (such as quantities, rates, amounts, totals, date/time, bill number, customer/payment information where available). Review Android and Windows behaviour for consistency unless the existing platform design requires different layouts. The invoice detail must reflect the saved sale record and must not accidentally create or modify a sale.

## Reports / custom date-wise business summary note from user (2026-11-13)

- [x] **Reports — custom date-range report and daily breakdown — code implemented.**** The user should be able to choose any specific date (and ideally a custom from–to date range) and see what happened during that period. Include, at minimum:
  - Total sales for the selected date/period.
  - Total purchases for the selected date/period.
  - Total expenses for the selected date/period.
  - A clear date-wise daily breakdown when a range contains multiple days, so sales, purchases, and expenses can be reviewed for each individual day, not only as one combined total.
  - Relevant totals and a net summary where the underlying data supports it; clearly distinguish sales, purchases, and expenses rather than mixing them.
  Review Android and Windows report screens and keep figures consistent with saved transactions and the selected date boundaries.


## Khata customer ledger and shareable statements note from user (2026-11-13)

- [x] **Khata customer account — shareable complete ledger — code implemented.**** When the user opens/taps a Khata customer and views that customer's record, provide the full account ledger/history (all relevant transactions, purchases/charges, payments/receipts, dates, and running/outstanding balance where the saved data supports it) in a clear statement that can be shared with the customer.
- [x] **Khata customer account — selected-period shareable statement — code implemented.**** Provide an option to choose a specific date or custom from–to dates and generate a shareable statement showing what items/products that customer took during the selected period, with transaction dates and available quantities/rates/amounts and totals. The full overall ledger and the selective date-wise item statement should be separate, clearly labelled sharing options. Ensure the statement is based on the customer's saved records, respects date boundaries, and does not alter the account. Review Android and Windows for consistent functionality.

## Supplier invoice photo scanning / OCR to purchase-stock entry note from user (2026-11-13)

- [x] **Supplier purchase invoice — Android camera capture and printed-text OCR — code implemented.** The app captures invoice photos using the mobile camera and uses on-device ML Kit Latin text recognition to prefill printed invoice details. OCR output remains editable and must be reviewed before posting. Handwritten OCR remains a separate approval-gated item below.
- [x] **Supplier invoice — editable review and confirm before posting — code implemented.**** Show extracted values in an editable purchase-invoice review screen. Let the user correct OCR mistakes and map invoice item names to existing inventory products; provide a clear path to add a genuinely new product and resolve unit/pack-size conversions. Only after the user confirms should the app save the purchase, update stock, and update supplier/purchase balances according to existing purchase workflows. Never post uncertain OCR results directly to inventory.
- [x] **Handwritten invoice OCR — optional Gemini free-tier implementation added with owner approval (2026-11-14).** Android invoice review now offers an explicit “Read Handwriting with Gemini (Free Tier)” action using `gemini-2.5-flash-lite`. The owner supplies their own Google AI Studio API key in-app; it is stored with platform secure storage and is not committed to the repository. The image is sent only after a per-invoice confirmation. The result is editable and parsed into the existing review form; it never posts stock automatically. HTTP 429 stops the request with a free-tier-limit message and there is no paid-model fallback. **Important:** use an API key from a project with billing disabled; the app cannot independently verify a Google project's billing status. Google states free-tier submitted content may be used to improve its products, which is disclosed in the key dialog. Manual OCR correction/entry remains available.
- [x] **Supplier invoice — duplicate posting guard and source image retention — code implemented.**** Review a practical duplicate check using supplier + invoice number/date and/or invoice image/document fingerprint so the same bill is not accidentally entered twice. Where practical, retain the captured invoice image/PDF with the saved purchase record for later reference.
- [x] **Supplier invoice printed-text OCR feasibility and on-device approach — code implemented.**** Assess OCR/AI accuracy, offline versus internet requirements, privacy/cost, supported image/PDF formats, and Android/Windows capability. Do not assume handwritten OCR is fully automatic or promise zero manual work. Keep the Windows local/offline rule intact unless the user explicitly approves a cloud dependency; clarify any required online service before adopting it. Prefer a workflow that can fall back to manual review/entry.

## Automatic app-update notifications and in-app download note from user (2026-11-13)

- [x] **[Android + Windows] In-app update checker and notification — code implemented.**** Inspect the actual Flutter app source and both platform build/release workflows. Do not assume that publishing a GitHub release or uploading a build artifact automatically notifies installed apps.
- [x] **Stable release detection and update-available prompt — code implemented.**** On Android and Windows, periodically and/or on app launch check the configured official release channel, compare the installed app version/build with the latest compatible stable release, and show a clear in-app notification/banner (and native notification where supported) only when a newer update exists. Avoid repeated/spam notifications for the same version; provide a manual “Check for updates” action and useful release notes.
- [x] **User-initiated package download and checksum verification — code implemented.**** Let the user download the correct platform package from the official release source without manually browsing GitHub. Show download progress, failure/retry feedback, file size/version, and verify integrity (e.g. published checksum/signature where available) before offering installation/opening.
- [x] **Platform-specific update staging/installer handoff — code implemented.**** Android should download the compatible APK and guide the user through Android's package-installer flow and any required permission; do not silently install. Windows should download the correct portable update package and provide a safe replace/upgrade flow that preserves the local SQLite database, user data, settings, and offline operation. Never overwrite the running executable unsafely or delete user data.
- [x] **Release metadata and platform assets lookup — code implemented; end-to-end validation remains pending.**** Ensure every intended production update publishes version metadata/release notes and the correct Android and Windows assets to a stable release channel; exclude failed, draft, prerelease, or incompatible builds. Verify both platforms end-to-end with an installed older version detecting and downloading a newer release. Keep the Windows POS local/offline for business data; update checking/download may use internet only when available and must fail gracefully offline.

## Bugs

<!-- Copy this template for each new bug. -->

### Bug: Windows POS black screen (previously reported; needs fresh reproduction)
- **Screen / feature:** Windows portable app startup / dashboard.
- **Steps to reproduce:** Windows portable build ko launch karein. Historical report mein Build #20 par app window black rahi aur process background mein chalti rahi.
- **Expected result:** POS window par login/dashboard normal display ho.
- **Actual result:** Black screen report hui. Historical diagnostics mein Flutter engine/first Dart frame aur SQLite initialization ke logs aaye; ek diagnostic probe par `MissingPluginException` for `mobile_scanner` bhi report hua. Is exception ko root cause tab tak na samjhein jab tak reproduce aur isolate na ho.
- **Screenshot / video (optional):** Is bug ke liye current screenshot/video abhi record nahi.

**Bug report karne ka demo template (nayi report ke liye copy karein):**
- **Screen / feature:** [screen ka naam]
- **Steps to reproduce:** [1, 2, 3]
- **Expected result:** [kya hona chahiye]
- **Actual result:** [asal mein kya hua]
- **Screenshot / video:** [agar ho]

## Ideas / Future Improvements

Future improvements: add new ideas here when the owner requests them.

## Completed Updates

<!-- Sirf woh kaam yahan likhein jo waqai complete/verify hua ho. -->

- [x] **Native WPF implementation transplanted safely onto current main baseline** — 31 WPF source files integrated without overwriting current-main SQLite v18 foundation, schema tests, Android source or Drive sync code. Current-main-based Draft PR #5 opened; old diverged PR #4 closed.
- [x] **WPF Wholesale billing source** — distinct Walk-in/Khata/Wholesale type selector, account filtering/creation/reclassification, saved wholesale product rates, default rate application, Wholesale-only manual item-rate editing, and Cash/Credit/Partial receipt/ledger posting implemented.
- [x] **Android Wholesale parity source** — customer-type selector and account filtering, Wholesale account creation/reclassification, wholesale price in inventory, scanner/default rates, Wholesale-only per-item manual rates, and sale/ledger/sync preservation implemented. Existing discount feature left unchanged.
- [x] **Android Wholesale regression coverage added** — covers Wholesale partial and full-cash receipts, outstanding balance, same-account ledger history, type mismatch rejection and snapshot round-trip. Latest expanded regression and Drive snapshot round-trip tests passed in Actions #266.

- [x] **Backup restore database-lock fix** — restore process ko alternate restored database file aur `.active_database` marker use karne ke liye update kiya gaya. User ne restore successful hone ki tasdeeq ki. Commit: `ad235ff873cd620a775f8a3fe3a51e8359b61878`.
- [x] **Windows Google OAuth client-secret handling code** — Windows auth-code exchange aur refresh-token requests mein `GOOGLE_WINDOWS_CLIENT_SECRET` support add ki gayi aur Windows workflow mein Dart define wire kiya gaya. Commit: `1c9fe93cb66e7367666227db63545721901cf4e2`. **Note:** Code change complete hai; Windows app mein real sign-in/token-refresh validation abhi pending hai (upar Pending Updates dekhein).
- [x] **Android Build #150 APK compilation/release** — APK successfully compile aur GitHub release par publish hui. Commit: `16187c3`; release: `v1.0.0-build150`. **Note:** Is build ki final FCM notification step fail hui thi; notification workflow ko complete na samjhein.
- [x] **PROJECT_UPDATE.md tracking file created** — Khan Baba POS repo ke `main` branch par project update log create kiya gaya. Commit: `2c2409275da6a2518a1ca6b676605867e130a25d`.

## Important Project Rules

1. This file applies **only** to Khan Baba General Store POS.
2. Do not modify the Akhtar & Sons Karyana Store or Educators School Management repositories while working on this project.
3. Review the existing code and related features before changing anything.
4. Do not remove or change existing behaviour unless the request explicitly requires it.
5. Preserve the existing discount and percentage behaviour unless explicitly instructed otherwise.
6. For cart item sale-price edits, enforce the purchase-cost floor where that rule applies.
7. Keep Windows POS local/offline; do not add Firebase to the Windows build unless explicitly requested.
8. Prefer one consolidated final commit/push after the requested work and review, rather than frequent small commits.
9. The user may choose to skip automated testing and test manually. Clearly report which checks were and were not run; never claim an unrun test passed.
10. Do not mark an item complete until the code change is actually made. Include commit/build details when known.
11. If an update is unclear or conflicts with a previous requirement, ask one concise clarification before making a risky change.
12. Never put passwords, OAuth client secrets, API keys, or other credentials in this file. Use GitHub Secrets for sensitive values.

## Work Log

| Date | Work summary | Commit / Build | Status |
|---|---|---|---|
| 2026-11-15 | Integrated current-main-based WPF source and restored Walk-in/Khata/Wholesale support across WPF and Android. Added party reclassification, saved wholesale rates, editable Wholesale unit rates, same-account cash/partial receipt ledger handling and regression tests. | Integration branch commits through `85db064`; Draft PR #5 | WPF build/schema and Android analysis/tests passed on #147/#149/#150/#265/#266. No release artifacts created. |
| 2026-11-15 | Added WPF manual Backup & Restore: verified backups, staged restore to a new database file, atomic active-pointer switch, and active-bill flush. Added disposable SQLite v18 backup/restore test. | Commits `4aa3ae5` through `345e1cb`; Actions #169 | WPF Release build and backup/restore test passed; current live database is never overwritten. |
| 2026-11-15 | Added isolated WPF sale transaction tests for Wholesale partial/cash payments, ledger receipts, outstanding balance, stock deduction, percentage discount and customer-type mismatch rollback. | Sale service test injection commit `b3f5e78`; test commit `9a89678`; Actions #181 | WPF Release build and all tests passed. |
| 2026-11-15 | Added backup SHA-256 sidecar validation and failure-path test proving corrupt backups cannot change the active database pointer or current database. | Service commit `4d5f04c`; test commit `ee1b8ab`; Actions #186 | WPF Release build and all tests passed. |
| 2026-11-15 | Added WPF purchase, return/refund and Khata receipt integration tests, including stock/cost changes, Wholesale cost floor, saleable/damaged return stock and receipt overpayment protection. | Service commits `4b92b28`, `5b69d6d`, `70523d8`; test commit `7a279c5`; Actions #198 | WPF Release build and all tests passed. |
| 2026-11-15 | Compared current Windows desktop source with project tracker; fixed a Windows build blocker found in the previous push (unsupported Window.getSize call). The native runner's 1280×720 initial size is retained, and Dart now only sets the 980×650 minimum. | This correction commit | Windows build previously failed at lib/main.dart:256; corrected source now queued for CI rebuild. Physical desktop checks remain pending |
| 2026-11-15 | Corrected the WPF roadmap to preserve Walk-in/Khata/Wholesale semantics and the already-approved Flutter Windows retirement; clarified WPF README; removed unused Flutter desktop_multi_window/tray_manager/window_manager packages and WindowManager activation code from shared sales code. | `ee6df2b`, `6133c52`, `e056dcb` (plus documentation/dependency commits) | Android build and POS regression workflows are running; remaining Platform.isWindows UI branches still require audit; WPF feature implementation and physical acceptance remain pending |
|---|---|---|---|
| 2026-11-13 | Added sample update, previously reported Windows bug, verified completed items, and validation follow-ups | This file update | Done |
| 2026-11-13 | Created project tracking file | `2c2409275da6a2518a1ca6b676605867e130a25d` | Done |
| 2026-11-14 | Windows POS #68 passed; persistent Windows scrollbars and accurate startup sync/offline status implemented; optional Gemini free-tier handwriting OCR implemented; 80mm receipt, product-name cap, New Sale autocomplete, lazy inventory list and cashier startup optimization implemented | Pending final consolidated commit | Build/CI and physical printer validation pending; safe generic background scanner capture remains blocked by Windows keyboard-wedge input limitations |

## Scanner hardware and supplier-invoice capture clarification (2026-11-13)

- [x] **Scanner support is model-agnostic.** User clarified that Windows should consider any installed/connected scanner; do not hard-code Speed X SP9260 or any VID/PID. Generic USB keyboard-wedge scanners work when the New Sale scan field is focused. Safe minimized-app capture remains pending unless a dedicated scanner interface is available.
- [x] **Supplier invoice capture device confirmed — Android/mobile camera.**** Supplier purchase/inventory invoices will be scanned or photographed using the **mobile phone camera**. The intended workflow is camera capture followed by OCR-assisted extraction and an editable review/confirmation step before posting purchase, stock, or supplier-account changes. This is separate from the model-agnostic Windows USB barcode-scanner workflow.

## User-approved scope update — 2026-11-14

### Google Drive two-way sync
- Google Drive is the only Android business-data cloud provider after the first complete Firebase/Firestore business-data round-trip and a successful initial Drive upload.
- Firebase remains enabled for authentication/access checks and Firebase Messaging update notifications. Firestore inventory, sales, purchases, parties and Khata synchronization is paused after Drive cutover.
- Existing Android devices that already paired Drive must complete this migration automatically on the next app start. If the Firebase outbox cannot drain or the Drive upload fails, keep the previous provider state and do not cut over.
- Windows remains local-first and acts as the Drive master. Device snapshots are checksum-verified; processed snapshots are idempotent; conflicts require an explicit Keep Windows / Use Other Device decision.
- Drive snapshot schema v2 carries stock-unit and invoice conversion fields. Newer snapshots must not be silently imported by older app versions.

### Supplier invoice pack and stock-unit conversion
- Product stock quantities use an explicit stock unit (for example pcs, g, or ml).
- Invoice lines retain invoice quantity, invoice pack/unit, conversion factor, stock quantity, base stock unit, invoice-unit rate and base-unit cost.
- Known conversions may be suggested (dozen to pcs, kg to g, litre to ml); carton/box/pack size must be entered or verified by the user.
- Converted stock quantity must resolve to a whole number because the POS stock model uses integer quantities. The invoice is not posted until all lines and supplier totals are reviewed.
- Retail sale price must not be below the converted base-unit purchase cost. Duplicate supplier invoice numbers are rejected.

### Handwriting OCR status
- The current on-device ML Kit camera OCR is intended for printed Latin text and numeric fields.
- Photo-based handwritten invoice recognition is not enabled until the owner explicitly approves an online handwriting OCR service and its possible billing/data-transfer implications.


## Gemini invoice OCR implementation notes (2026-11-14)

- Gemini API key is entered by the owner in the Android app and stored using Flutter Secure Storage; no key is embedded in source, assets, build arguments, or GitHub Secrets.
- Model: `gemini-2.5-flash-lite`; image input is used only when the owner presses the explicit Gemini OCR button and confirms the upload.
- Free-tier use requires an AI Studio project with billing disabled. The client cannot prove billing status from an API response; never use a key attached to a paid/billing-enabled project for the free-only workflow.
- Google free-tier data-use disclosure is shown before saving the key. OCR results remain editable and purchase posting remains a separate user action.
- HTTP 429 is treated as a quota/rate-limit stop. No paid fallback, alternate paid model, or background retry is configured.


## Professional 80mm receipt layout and single-row item names (2026-11-14)

- [x] **[Android + Windows] Professional 80mm sales receipt layout — implemented in code.** Receipt text and PDF now use a consistent 80mm layout with centered KHAN BABA branding, left/right bill metadata, Qty/Description/Rate/Amount columns, separators, aligned totals, and emphasized Net Amount. Existing saved transaction amounts and discount calculations are unchanged. Physical BC-86AC print alignment remains to be checked.
- [x] **[Android + Windows] Every sale item prints on one row — implemented in code.** Item names/descriptions must never wrap onto a second line or push the following columns/rows out of alignment. The 80mm body uses a 45-character line at standard font with 2mm margins and fixed four-column widths; product names are limited to 17 characters in Inventory and camera/manual product entry, with Add/Edit form validation; legacy imports and synced records are not rejected by the database layer. Existing legacy names are not changed in storage and are safely truncated on the receipt line. Larger header/total font settings do not enlarge item rows. Physical printer verification remains pending. **Use 80mm as the receipt paper size on both Android and Windows**; do not retain a separate 58mm Android default. Keep printer-width configuration consistent across platforms where the printer supports it.


### Receipt paper-width clarification (2026-11-14)

- [x] **[Android + Windows] Standardize receipt paper size to 80mm on both platforms — implemented.** Android and Windows now default to 80mm; the 58mm choice has been removed from the print screen. USB ESC/POS and PDF page layout use 80mm. Confirm on the actual Android USB/OTG or Bluetooth printer.


## Flutter Windows retirement (2026-11-15)

- [x] Removed the Flutter Windows native runner directory and the Flutter Windows build/release workflow.
- [x] Removed the dedicated Windows theme, tray and update-notification services; Flutter startup no longer enters a Windows-only application path. The old desktop navigation helper is now a no-op shim for remaining shared-screen references.
- [x] Removed Windows desktop-navigation helper usage from shared Flutter screens. Android Flutter startup and Android build/test workflows are retained.
- [x] Removed the retired Flutter Windows presentation branches and malformed AppBar action block from `dashboard_screen.dart`; Android dashboard navigation and update/sync actions remain. (Commit `62756f8`; follow-up unused import cleanup `dc0562f`.)
- [x] Removed the Flutter Windows AppBar title-bar styling, desktop back-navigation helper, and related presentation-only settings from 16 shared Flutter screens; Android styling/navigation is now the only retained UI path in those AppBars. Commits `4fdd5b1`, `b4aab02`, `2a6ea9d`, `87e1a1a`.
- [x] Remove Flutter Windows-only AppBar styling/navigation helpers from 16 shared Flutter screens; Android AppBar behaviour retained (commits `4fdd5b1`, `b4aab02`, `2a6ea9d`, `87e1a1a`).
- [x] Remove obsolete Windows-only body layouts from the eight audited shared screens: expense, party, history, customer Khata, return history, sales report, customer history, and the dashboard; Android workflows retained (commits `37018d7`, `1a0c5af`, plus earlier dashboard commits).
- [x] Remove retired Windows printer-screen presentation branches while retaining Android USB/Bluetooth printer workflows (commits `0f8dc05`, `122e5c0`).
- [x] Remove retired Windows scanner-screen presentation branches while retaining Android camera scanning and generic mobile scanner guidance (commit `a92d02b`).
- [x] Remove Windows-only FAB variants from expense, reminders, party and inventory screens (commits `4f87791`, `a0413ef`, `dd2a929`, `9a51794`).
- [ ] Audit and remove remaining Flutter Windows-only layouts/window lifecycle hooks in reminders, profit/loss, purchases, inventory, sale returns, backup, cloud sync and sales. Preserve Android workflows and shared Drive-sync/database logic; do not delete shared data/sync paths.

- [ ] Complete WPF implementation, CI validation and physical Windows acceptance before declaring the native Windows client ready.


## Work log — 2026-11-15 (continued)

- Corrected the malformed DashboardScreen AppBar actions list that caused Android release compiler errors; removed retired Flutter Windows-specific dashboard styling, the Windows-only New Sale action, and Platform.isWindows presentation branches while preserving Android update, sync, navigation, and responsive layouts. Commit: 62756f8.
- Disabled automatic APK upload and GitHub Release publication in the Android workflow. It now runs Flutter analysis and tests only. Disabled WPF publish/upload-artifact steps; its workflow now performs restore/build validation only. This enforces the owner's instruction not to create APK/EXE release artifacts until every pending PROJECT_UPDATE.md item is complete. Workflow commits: 7d611a1, 39c1fc7.
- Latest Android analysis/test and WPF validation runs are pending at the time of this log. The earlier Android release run for 62756f8 was started before artifact publishing was disabled; the available GitHub integration does not expose a workflow-cancel action.
- SQLite v18 audit confirms 17 tables and the key uniqueness/composite-primary-key declarations in the Flutter onCreate DDL. The WPF verifier currently checks version and column presence only; it still needs integrity, primary-key, nullability/default, and unique-index verification before database compatibility can be considered complete.
- Remaining work is not marked complete: remove only obsolete Flutter Windows UI/window-management branches (preserve shared platform-specific data/sync behaviour), finish WPF implementation and tests, run CI checks, and obtain physical Windows/printer acceptance.


## Verified completed work — 2026-11-15

- [x] Android CI no longer publishes APK files or GitHub Releases automatically. The workflow runs source analysis and tests only; release publishing remains intentionally disabled until every pending project task is complete.
- [x] Native WPF CI no longer publishes or uploads EXE/build artifacts; it performs restore/build validation only.
- [x] WPF .NET 10 target support confirmed by a successful Windows runner build (workflow run `43715783750`, commit `3af3005`).
- [x] Fixed the Android dashboard syntax error and removed retired Flutter Windows dashboard-only presentation/actions. The mobile dashboard remains the supported Flutter UI.
- [x] Added an injectable home widget to `KhanBabaPOSApp` and changed the widget test to exercise the MaterialApp shell without requiring Firebase initialization or a live membership backend. The real production home remains `UpdateAwareHome(AuthGate())`.
- [x] Android analyzer and Flutter test suite pass with the isolated MaterialApp shell widget test (validation-only run `43716339983` / test run `43716185881`; no APK or release artifact was published).
- [x] Expanded the WPF SQLite v18 verifier to check `user_version`, `sqlite_master` table presence, `quick_check`, required columns, primary-key definitions, key default values, required unique constraints and `foreign_key_check`; Windows build passed in run `43716339961`.
- [ ] Add and run a representative SQLite v18 fixture test to prove the verifier accepts the real Flutter schema and rejects altered/missing constraints without modifying the database.


## Work log — 2026-11-15 (continued)

- Removed the retired Windows-specific AppBar colours, title-bar heights, back-navigation helper and other simple presentation-only properties from 16 Flutter screens in four grouped commits (`4fdd5b1`, `b4aab02`, `2a6ea9d`, `87e1a1a`). Android AppBar behaviour is retained.
- Updated the WPF README to describe the expanded read-only schema verifier accurately.
- Android validation passed on earlier commits in this cleanup series; the latest grouped commit's Android analyzer/test and POS regression workflows are still running. No APK, EXE or release artifacts are published.


## Verified validation and cleanup update — 2026-11-15

- Android validation-only workflow passed on latest `main` commit `9a517947895be59a9dd57ede7bb4dce44684d6c5` (run `43717393043`).
- POS sync and invoice conversion regression tests passed on the same commit (run `43717393051`).
- These runs did not publish APK, EXE, or release artifacts.
- The latest scanner/printer and four FAB cleanup commits are now recorded above as completed. Remaining Flutter Windows branches are still explicitly pending; the Windows-master Drive sync and database path branches are shared data behaviour and must not be removed merely because they mention Windows.
