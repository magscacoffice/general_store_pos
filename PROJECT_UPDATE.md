# Khan Baba POS — Windows Native WPF Migration Roadmap

> **Migration scope:** Replace the **Windows Desktop client only** with a native C#/.NET WPF application. Android remains Flutter and continues to use the existing SQLite database format and approved sync workflows.
> **Strict UI framework rule:** Use **WPF (Windows Presentation Foundation)** only. **Do not use WinUI 3, Windows App SDK, MAUI, a web wrapper, or Flutter Windows.**
> **Windows platform retirement:** Flutter Windows runner and its GitHub build/release workflow are being removed. Android Flutter remains the supported Flutter client; all future Windows UI, hardware, sync, and release work belongs in `desktop-wpf/`.
> **Repository:** https://github.com/magscacoffice/general_store_pos
> **Audited base / integration:** `main` at `2dbbf9ee4e89a29b69726ac33531c0b15c5f13de` (2026-11-15); WPF source and tracker updates are on `integration/wpf-mainline` and Draft PR #5, not yet merged to main.
> **Planning status:** Native WPF and Android Flutter billing now both include distinct Walk-in/Khata/Wholesale account handling, wholesale-rate defaults and per-item Wholesale price editing. WPF Release build/schema tests and Android analysis/regression tests, including Wholesale cash/partial ledger and Drive snapshot round-trip coverage, passed on the latest integration commit (Actions #150 and #266). WPF transaction parity, Drive sync/auth, real-device and physical Windows acceptance remain pending.

## Immediate owner priority — Windows cashier-first operation (2026-11-16)

Owner wants Windows WPF to remain usable for daily billing while other Windows modules are completed incrementally later. Android Flutter must remain untouched.

- [x] Keep the Windows New Sale workspace as the cashier landing screen, scanner-focused after startup and after adding each product.
- [x] Preserve repeated barcode behaviour: add the next unit to the existing cart line, bounded by available stock.
- [x] Preserve draft/pending bill autosave in the existing SQLite v18 `pending_bills` table; starting another bill first saves the active draft. Completed checkout is posted transactionally to the existing `sales`, `sale_items`, stock and Khata tables by `SalePostingService`.
- [x] Add visible Print Bill action in the New Sale workspace; persist the current draft before opening the print preview. Draft printing is read-only and must not deduct stock or post a sale.
- [x] Add cashier keyboard shortcuts at the window level: F2 scanner, F4 customer, F5 new bill, F6 discount, F7 received amount, F8 payment mode, F9 print/preview, F10 complete sale; Ctrl+P also opens print/preview.
- [x] Add F9 / Ctrl+P thermal receipt shortcut inside Printer & Invoice window; F9 from New Sale now sends the current draft directly to the saved preferred printer. If no preferred printer is configured/available, the printer window remains open for selection. Physical printer output still requires a Windows PC and BC-86AC acceptance test.
- [x] Add a non-blocking startup update check and an in-app update-available indicator; offline or failed update checks must never block New Sale or local billing.
- [ ] **Signed updater release gate:** `NativeUpdateService` checks the latest GitHub Release and validates the release manifest, SHA-256 and Authenticode publisher. Download/install remains intentionally disabled until the owner provides the production code-signing certificate and its trusted thumbprint is pinned. Do not install unsigned or untrusted packages.
- [ ] Publish a versioned Windows installer and `khan-baba-release.json` manifest as GitHub Release assets after Windows runtime tests, code signing, checksum generation and installer/data-preservation tests pass. Only then can the app notify, download and install future feature updates safely.
- [ ] Verify F2/F4/F5/F6/F7/F8/F9/F10 and Ctrl+P on a real Windows cashier PC; verify barcode scanner focus and the saved default printer with the physical SpeedX SP60D and Black Copper BC-86AC.
- [ ] Confirm startup update notification against a real published test release; confirm offline startup does not delay billing.
- [x] Windows Release build, WPF regression tests, self-contained win-x64 publish and artifact upload passed on GitHub Actions run #390 (2026-11-16). Artifact: `KhanBabaPOS-Windows-x64-390` (artifact ID `14222191243`, expires 2026-12-16); run: https://github.com/magscacoffice/general_store_pos/actions/runs/43857899968. This is an unsigned test artifact, not a signed production installer. Do not merge Draft PR #5 or declare production-ready until the independent migration, sync, auth, printer and owner acceptance gates are passed.

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
| `customer_history_screen.dart` | `CustomerLedgerWindow` in `KhataWindow.cs` | Full ledger copy/print-to-PDF and selected-period item statement (sales and returns) source implemented; target Windows PDF/print acceptance pending |
| `history_screen.dart` | `SalesHistoryWindow.cs` | Sales history search and invoice detail source implemented; full reprint/return navigation acceptance remains pending |
| `sales_report_screen.dart` | `SalesReportsWindow.cs`, `Services/SalesReportService.cs` | Date filters and report summary source implemented; report parity tests remain pending |
| `profit_loss_screen.dart` | `ProfitLossWindow.cs`, `Services/ProfitLossService.cs` | Existing income/cost/expense and profit calculation source implemented; parity test remains pending |
| `expense_screen.dart` | `ExpensesWindow.cs`, `Services/ExpenseService.cs` | Expense create/list and totals source implemented |
| `sale_return_screen.dart` | `SaleReturnWindow.cs`, `Services/SaleReturnService.cs` | Return/refund transaction source implemented; disposable-database integration tests remain pending |
| `return_history_screen.dart` | `Views/ReturnHistoryWindow.xaml` | Return list, details and audit trail |
| `reminders_screen.dart` | `RemindersWindow.cs`, `Services/ReminderService.cs` | Reminder create/list/complete source implemented |
| `salesmen_management_screen.dart` | WPF staff/access window — pending | Preserve existing role/access rules; do not invent a new local identity model or Firebase business sync |
| `printer_screen.dart` | `PrinterInvoiceWindow.cs`, `Services/PrinterSettingsService.cs` | Printer queue selection/persistence, 80mm ESC/POS test/receipt source, invoice preview and PDF save/open implemented; physical BC-86AC acceptance pending |
| `backup_screen.dart` | `BackupRestoreWindow.cs`, `Services/DatabaseBackupService.cs` | Verified backup and staged restore with SHA-256, schema validation and atomic active-pointer switch implemented and tested |
| `cloud_sync_screen.dart` | WPF Cloud Sync window/service — implemented in source | Native Drive connection/sync window, pending-conflict comparison and Keep Windows / Use Other Device actions added; target-PC Google OAuth and offline acceptance remain pending |
| `drive_sync_service.dart` | WPF Drive snapshot service — implemented in source | OAuth/DPAPI token storage, Drive v3 upload/download, stable device identity, schema-v2 hash validation, pre-merge backups, Windows-master manifest, transactional merge, 2-minute retry scheduler and conflict UI added; real-account/runtime acceptance remains pending |
| `update_manager.dart`, `windows/windows_update_service.dart` | `Services/NativeUpdateService.cs` | GitHub Release detection, signed manifest/SHA-256/Authenticode validation and staged installer launch; production signing certificate remains a hard gate |
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
| 2026-11-15 | Transplanted 31 reviewed WPF application source files onto `integration/wpf-mainline`, based on current `main`. Preserved main's newer SQLite v18 foundation/schema tests, WPF workflow, Android source and sync changes. | `1e835c8` | Integrated source branch created. |
| 2026-11-15 | Added WPF Walk-in/Khata/Wholesale account handling, editable/default wholesale pricing and same-account cash/credit/partial receipt posting; fixed exact barcode lookup column mapping. Reconciled the completed work and remaining acceptance gates in this tracker. | `3d19aeb` | .NET 10 Release build and WPF regression tests passed in Actions #254; latest branch WPF validation #257 and Android validation #327 also passed. |
| 2026-11-15 | Consolidated remaining WPF cloud sync/auth/update, Windows hardware/UI/PDF acceptance, and residual Flutter Windows cleanup items into the canonical Pending Updates section; clarified that earlier roadmap checklists are specification history, not a second live task list. | `e3ee5fc` | Pending list reconciled; only unfinished tasks remain pending. |

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

### [URGENT — 2026-11-16] Billing calculations, New Sale and Windows test artifact

- [ ] **Billing calculation audit and completion:** compare WPF checkout with the existing Flutter implementation using the same disposable schema-v18 database and test fixtures. Verify line totals (quantity × rate), subtotal, fixed discount, percentage discount, net/final total, cash received, credit/partial received amount, balance due, customer/Khata ledger entries, stock deduction and transaction rollback. Preserve existing discount behaviour and all Walk-in/Khata/Wholesale customer types.
- [ ] **Resolve cashier calculation inconsistencies:** reconcile checkout validation with bill preview/receipt calculations, especially Partial payment boundary rules; ensure displayed received/balance values match the values actually posted to SQLite.
- [ ] **New Sale acceptance:** verify New Sale button and F5 create a clean pending bill without losing the previous bill; scanner focus returns after adding an item and after checkout; repeated barcode scans increment the same cart line; pending bills restore customer type, customer, payment mode, discount mode/value and partial received amount.
- [ ] **Regression tests:** add/verify automated tests for the above calculations and New Sale/cart/pending-bill behaviour. Do not mark this work complete from a successful compile alone.
- [ ] **Windows artifact:** produce a self-contained Windows x64 WPF test artifact from this integration branch after Release build and tests pass. Artifact is for owner testing only; unsigned and not a production release. Keep the existing installer/signing and real-PC acceptance gates separate.

<!-- This is the canonical live task list. The earlier roadmap sections describe requirements/architecture; Completed Updates records finished work. Source implementation, automated validation and target-device acceptance are tracked separately. CI build alone never completes hardware/UI acceptance. -->

### [Windows] Native WPF cashier and inventory

- [ ] Verify the WPF cashier and inventory workflows on a real Windows PC using a disposable copy of the real SQLite v18 database.
- [ ] Validate immediate duplicate-barcode warning using Android camera scanning and the WPF keyboard-wedge scanner on real devices.
- [ ] Validate SpeedX SP60D keyboard-wedge scanner responsiveness and inventory performance on the target computer.
- [ ] Complete responsive visual/interaction acceptance at 980×650, 1280×720, maximized and resized states.

### [Windows] Khata, sales history and transaction workflows

- [ ] Verify all transaction totals, discount (including percentage), received amounts, customer balances, payment history and stock movements against Android behaviour. Do not alter the existing discount feature.
- [ ] Complete on-device Android acceptance for Wholesale creation, manual/default pricing, cash/credit/partial receipts, outstanding balance and Drive snapshot restore. Keep real user data backed up before reclassifying any existing account.

### [Windows] Printer and invoice

- [ ] Verify saved-printer restoration and unavailable-queue behaviour across Windows application restarts.
- [ ] Verify PDF save/open/share on the target Windows PC.
- [ ] Physically test Black Copper BC-86AC 80mm USB printer: alignment, margins, header/total sizing, final-line clipping, cutter and paper feed.
- [ ] Record responsive visual/interaction acceptance, keyboard focus, hover, clipping and independent preview scrolling.

### [Windows] Data safety, authentication and sync

- [ ] Complete full version-18 schema/constraint and Flutter transaction-method audit before production write enablement.
- [x] Implemented native Windows-master Drive snapshot sync in source: Windows device snapshot upload, other-device snapshot download/hash verification, per-device verified pre-merge backup, idempotent processing manifest, transactional merge, master snapshot upload, conflict status and 2-minute offline retry. Firebase/Firestore business-data sync remains excluded. [ ] Real Google account and target-PC acceptance remain pending.
- [ ] Complete Windows authentication, existing role/access parity and safe update flow; verify OAuth configuration without committing secrets.
- [ ] Complete Windows startup, recovery and restore-pointer validation without creating or replacing the live database.

### [Windows] Flutter Windows retirement and final cutover

- [ ] Audit and remove remaining Flutter Windows-only UI/window lifecycle hooks in reminders, profit/loss, purchases, inventory, sale returns, backup, cloud sync and sales. Preserve Android workflows and shared Drive-sync/database logic.
- [x] Native WPF update checker source implemented: GitHub latest stable release endpoint, installed-version comparison, one notification per version, manual check and release notes. Real release-feed acceptance remains pending.
- [x] Native WPF updater source now validates safe .exe asset names, HTTPS GitHub release URLs, declared file size (500 MB cap), SHA-256 and pinned Authenticode; downloads to a unique temporary file with progress/retry, verifies before atomic staging under LocalAppData\\KhanBabaPOS\\Updates, and launches the installer without touching the live app/database/settings/backups. Production download remains disabled until the owner certificate thumbprint is pinned.
- [ ] Verify full-ledger and period-statement PDF/print on Windows, including date boundaries, Unicode customer/product names and Microsoft Print to PDF.
- [ ] Verify WPF scrollbar visibility/hit targets, combined scan/search focus, modal keyboard navigation and responsive layouts on the target PC.
- [ ] Complete target-Windows runtime, visual, scanner and printer acceptance.
- [ ] Owner signs off physical cashier acceptance before Windows cutover.
- [ ] Merge to main only after all required automated and owner acceptance gates pass. Do not create or publish an APK, EXE, installer or release artifact while pending tasks remain.

## New notes from user (2026-11-16)

- [ ] **Immediate priority: billing calculations + New Sale + Windows artifact.** Owner requested that remaining essential billing calculations and the New Sale cashier workflow be completed first, then a Windows x64 WPF test artifact be generated. This priority does not authorize removing the current discount/percentage-discount behaviour, changing SQLite schema, restoring Flutter Windows, or introducing WinUI 3.
- [x] **Initial source audit:** MainWindow.xaml.cs already contains the New Sale button handler, F5 shortcut, pending-bill persistence/restore, scanner focus handling and duplicate-barcode quantity increment. SalePostingService.cs already contains transactional sale posting, fixed/percentage discount arithmetic, stock deduction and customer Khata/receipt/balance updates. These are source observations only; they are not owner acceptance or calculation parity proof.
- [x] **Partial-payment preview validation aligned:** draft bill preview now rejects zero, exact-total and over-total Partial receipts, matching both WPF checkout and Flutter checkout (received amount must be greater than zero and strictly less than the final bill total). [ ] Automated regression coverage and a fresh Release build/test are still required.
- [x] **Artifact workflow configured:** the latest validation run 43849520403 completed Release build and WPF tests successfully but had no artifact. The integration branch now adds self-contained win-x64 publish, ZIP packaging, TEST-INSTRUCTIONS.txt and a 30-day Actions artifact upload to build-wpf.yml. [ ] A new Actions run must pass and the uploaded artifact must be verified before sharing its download link.
- [ ] **Acceptance still required:** calculations must be compared with Flutter using a disposable copy of the real schema-v18 database; target Windows scanner, printer, runtime, data safety and physical cashier acceptance remain separate gates.

## New notes from user (2026-11-13)


## Additional Windows and sync notes from user (2026-11-13)

- [x] **WPF Google Drive periodic auto-sync — native source port added.** The WPF app starts a 2-minute scheduler only when an Admin session and saved Drive credentials are present; it pauses when offline or when the Admin session expires, and retries on a later tick. Device upload, master download direction, conflicts, status and error feedback are wired. [ ] Target-PC runtime/OAuth/offline acceptance remains pending. Android Drive sync remains separate.
- [ ] **WPF startup/cloud status — native implementation pending.** Previous Flutter Windows status UI was retired with the Flutter Windows runner. Native WPF startup must distinguish offline, missing Drive credentials, first sync pending, previous successful sync and sync failure while keeping local POS availability explicit.
- [ ] Verify WPF scrollbar thumb visibility, hit targets and clipping on the target Windows PC.
- [ ] **Native WPF UI audit and acceptance — pending.** The previous Windows UI audit and fixes applied to the retired Flutter Windows client and cannot be counted as WPF completion. The native WPF source has been reviewed for basic layout and build correctness, but a full screen-by-screen audit is still required for 980×650 minimum size, resizing, keyboard/focus, long-list scrolling, modal dialogs, printer preview, scanner input and native Windows rendering. The supplier-invoice camera/Gemini OCR workflow remains Android-only by design.
- [ ] Validate the combined scan/search input and scanner focus on the target Windows PC.

## Khata customer ledger and shareable statements note from user (2026-11-13)

- [ ] **WPF full-ledger PDF/print acceptance — pending.** Verify Unicode customer/product names and Microsoft Print to PDF output on the target Windows PC.
- [ ] **WPF period-statement PDF/print acceptance — pending.** Verify date boundaries, Unicode rendering and Microsoft Print to PDF on target Windows.

## Automatic app-update notifications and in-app download note from user (2026-11-13)

- [x] **Native WPF update checker and notification — source implemented.** WPF checks GitHub's latest stable release, compares installed version, stores a one-time notification marker and exposes manual Check for Updates with release notes. Real published-release/old-version acceptance remains pending.
- [x] **WPF stable release detection and update prompt — source implemented.** Startup check is best-effort/offline-safe; manual check and one-time notification are present. Target-PC release-feed validation remains pending.
- [x] **WPF package download and checksum verification — source implemented.** Includes download progress, transient retry, strict release asset URL/name, declared size limit and SHA-256 verification. Production download is still disabled pending certificate pin.
- [x] **WPF update staging/installer handoff — source implemented.** Verified installer is staged separately in LocalAppData\\KhanBabaPOS\\Updates and launched; live executable/database/settings/backups are not overwritten by the updater. Signed release and upgrade/uninstall acceptance remain pending.
- [ ] **Release metadata and platform assets lookup — end-to-end validation pending.** Android release metadata/download code exists; native WPF package channel does not yet exist. Ensure stable releases publish correct compatible assets and checksums; exclude failed/draft/prerelease builds and verify installed-old-version upgrade on both platforms.

## Bugs

<!-- Copy this template for each new bug. -->

### Historical bug: Flutter Windows black screen (superseded by native WPF migration)
- **Screen / feature:** Retired Flutter Windows runner startup/dashboard.
- **Historical reproduction:** Build #20 reportedly showed a black window while the process remained running.
- **Status:** The Flutter Windows runner has since been removed. This historical Flutter bug is not treated as a current WPF defect and must not be marked fixed by assumption.
- **Remaining validation:** Launch the native WPF application on the target Windows PC and verify first-frame rendering, database startup, login/access flow and dashboard navigation. Record any new WPF failure separately with a current screenshot/log.

**Bug report karne ka demo template (nayi report ke liye copy karein):**
- **Screen / feature:** [screen ka naam]
- **Steps to reproduce:** [1, 2, 3]
- **Expected result:** [kya hona chahiye]
- **Actual result:** [asal mein kya hua]
- **Screenshot / video:** [agar ho]

## Ideas / Future Improvements

Future improvements: add new ideas here when the owner requests them.


| 2026-11-16 | Added Windows-only offline Admin/Salesman authentication: first-run Admin setup, PBKDF2-SHA256 credential hashing, DPAPI CurrentUser-protected credential/audit store, staff create/disable/password reset, last-Admin protection, login/logout, lockout, sliding session expiry, MainWindow Admin navigation gates and authenticated sale attribution. Added authentication and cashier-identity tests; disabled automatic portable test-package publishing while production tasks remain pending. | Auth implementation commits through `2f2bc1e`; CI run `43831153534` | .NET 10 WPF Release build and all WPF tests passed. Target-PC login/role acceptance and remaining service-level authorization audit are still pending. |

| 2026-11-16 | Added WPF transactional SQLite v18 Drive merge engine: product/party conflict detection, stable party aliases, idempotent append-only sales/purchases/Khata/returns/expenses/reminders, tombstone conflict handling, safe deletion guards, explicit Keep Windows / Use Other Device resolution and pending conflict retrieval. Added disposable-v18 tests for product conflict resolution and stocked-product delete protection. | Merge service commit `7ecd4ca`; tests commit `eab672a`; Actions run `43832118175` | WPF Release build and all tests passed. Full merge-path matrix, Drive v3 orchestration, sync UI, auto-sync/offline retry and owner acceptance remain pending. |

| 2026-11-16 | Added native WPF Google Drive Windows-master orchestration and UI: stable DPAPI device ID, upload/download ordering, snapshot validation, per-device backup filenames in master manifest, 2-minute Admin-only auto-sync with offline retry, conflict review and explicit resolution. Added per-user Inno Setup installer source, release updater check, SHA-256/Authenticode verification and manual-only installer compile workflow. | Drive service/UI commits `0b6335d`, `24214c1`, `bec0ab3`, `90a75b4`, `a118a27`, `b5e5514`; updater/installer commits `e5142b7`, `1986085`, `74bf4b8`, `7eddf4e`, `d2a1646`, `b3fadc5`; CI run `43833814298` | WPF Release build and all WPF tests passed. No installer or release artifact was published. Real Google OAuth/device acceptance, full merge parity matrix, installer compilation/signing, certificate pin and upgrade/uninstall acceptance remain pending. |

## Completed Updates

<!-- Sirf woh kaam yahan likhein jo waqai complete/verify hua ho. Completed items are moved here so the Pending Updates section contains only unfinished work. -->

- [x] **WPF New Sale pre-checkout receipt preview/print — source implemented and CI build/tests passed.** Added a visible Print / Preview action for the current in-progress cart. It creates a draft-only receipt model and opens the existing printer/receipt window without posting a sale, deducting stock, or changing Khata balances. Draft receipts are labelled `DRAFT PREVIEW` rather than a saved bill number. WPF Release build passed with 0 warnings/errors and 19 tests passed in Actions run `43827515492` (commit `0f2ca7bc1c840b9a03aacd10c31f94d8a7ad15dc`). Owner must still verify actual draft output/thermal printing on the target PC.
- [x] **WPF product search dropdown and keyboard selection — source implemented and CI build/tests passed.** Matching products appear in a dropdown anchored under the scan/search box; Up/Down arrows move keyboard focus into the results and Enter adds the highlighted product. Existing exact-barcode-first lookup and repeat-scan cart increment behaviour are retained. WPF Release build passed with 0 warnings/errors and 19 tests passed in Actions run `43827515492` (commit `0f2ca7bc1c840b9a03aacd10c31f94d8a7ad15dc`). Owner must still verify actual keyboard/scanner interaction on the target PC.
- [x] **WPF cashier right-pane scrolling — source adjusted, target-screen verification pending.** The payment/discount/summary pane now requests a persistently visible vertical scrollbar and disables horizontal scrolling so lower controls remain reachable on shorter screens.

- [x] **WPF Wholesale account workflow** — added separate Walk-in/Khata/Wholesale selection, customer-account type filtering and creation/reclassification, saved wholesale-rate defaults, editable per-item wholesale rates with purchase-cost floor, and Cash/Credit/Partial posting to the same account/ledger. Existing fixed and percentage discount handling remains unchanged; transaction tests cover receipts, balances, payment history, stock deduction and account-type mismatch rollback.
- [x] **WPF exact barcode lookup compatibility** — fixed the exact-scan query to return the wholesale-price column in the same order expected by the product mapper; this prevents a runtime reader-index failure on barcode scans after adding wholesale pricing.
- [x] **Latest integration validation** — native WPF .NET 10 Release build and regression suite passed in Actions #257; Android validation/regression passed in #327. Both were validation-only; no APK, EXE or release artifact was published.
- [x] **WPF cashier and inventory source** — dashboard-hosted billing, scanner focus, exact barcode lookup/product suggestions, repeat-scan quantity increments, pending bills/autosave, searchable inventory, add/edit/active status and protected delete source implemented.
- [x] **WPF transaction and business screens** — sales history/invoice details, Khata ledger/receipts, sale posting, purchases, returns/refunds, expenses, reminders, reports and profit/loss source integrated. Disposable SQLite v18 tests passed for sale, purchase, return, receipt, report and profit/loss flows.
- [x] **WPF printer/invoice source** — saved printer selection, compact queue list, 80mm ESC/POS receipt/test print, preview, PDF save/open and receipt configuration implemented. Physical BC-86AC acceptance remains pending.
- [x] **WPF backup and restore safety** — verified SQLite v18 backup with SHA-256 sidecar, staged restore, atomic active-database pointer switch, active-bill flush, live-file preservation and corrupt-sidecar rejection all covered by passing disposable-database tests.
- [x] **WPF Khata statements** — full ledger copy/print-to-PDF and separate date-range item statement including sales/returns implemented; query regression and WPF build passed.
- [x] **WPF native shell usability** — combined scan/search input, foreground-only safe scanner fallback and consistent visible vertical scrollbar theme implemented. Target Windows visual/scanner acceptance remains pending.
- [x] **WPF inventory duplicate-barcode protection** — barcode-first auto-focus, debounced exact duplicate lookup, duplicate Save blocking, existing-product edit exception and service-level uniqueness checks implemented; CRUD/tombstone/protected-delete regression tests passed (Actions #245).
- [x] **Android sales and account parity** — Wholesale customer classification, account reclassification, saved wholesale rates, manual per-item rate, cash/credit/partial same-account ledger receipts, Drive snapshot preservation and regression tests passed.
- [x] **Android sales history and reports** — invoice detail and custom date-range/daily business summaries implemented and retained.
- [x] **Android Khata statements** — full shareable ledger and selected-period item statement implemented.
- [x] **Android supplier invoice workflow** — camera capture, printed-text OCR, editable review/confirm, duplicate-posting guard, source-image retention and owner-approved Gemini handwriting option implemented; OCR never posts stock without review.
- [x] **Android app update workflow** — update checker, stable release prompt, APK download/checksum verification and Android installer handoff implemented. Windows-native updater remains pending.
- [x] **Flutter Windows retirement and WPF branch integration** — Flutter Windows runner/workflow retired; WPF source transplanted onto current-main-based integration branch; old diverged PR #4 closed and current-main Draft PR #5 opened.
- [x] **WPF CI and regression suite** — .NET 10 Release build plus schema, sale, purchase, return, Khata, report, profit/loss, backup/restore and inventory barcode/CRUD tests passed in Actions #169, #181, #186, #198, #205, #226 and #245; Android validation/regression passed in #266, #285, #292, #307 and #316.

### Historical completed updates before the native WPF migration

- [x] **Flutter backup restore database-lock fix** — historical Flutter client fix using an alternate restored database file and the active-database marker. Native WPF now has its own separately tested backup/restore implementation. Commit: ad235ff873cd620a775f8a3fe3a51e8359b61878.
- [x] **Flutter Windows OAuth client-secret handling** — historical code added GOOGLE_WINDOWS_CLIENT_SECRET support to the retired Flutter Windows auth flow. This is not a native WPF Drive OAuth implementation; WPF sync/auth remains pending. Commit: 1c9fe93cb66e7367666227db63545721901cf4e2.
- [x] **Android Build #150 APK compilation/release** — historical APK published as v1.0.0-build150 (commit 16187c3). Its final FCM notification step failed. No new APK/EXE/release artifacts are being created while current pending tasks remain.
- [x] **PROJECT_UPDATE.md tracking file created** — original tracker created on main (commit 2c2409275da6a2518a1ca6b676605867e130a25d).

## Important Project Rules

1. This file applies **only** to Khan Baba General Store POS.
2. Do not modify the Akhtar & Sons Karyana Store or Educators School Management repositories while working on this project.
3. Review the existing code and related features before changing anything.
4. Do not remove or change existing behaviour unless the request explicitly requires it.
5. Preserve the existing discount and percentage behaviour unless explicitly instructed otherwise.
6. For cart item sale-price edits, enforce the purchase-cost floor where that rule applies.
7. Keep Windows POS local/offline; do not add Firebase to the Windows build unless explicitly requested.
8. Prefer one consolidated final commit/push after the requested work and review, rather than frequent small commits. Squash the integration PR when it is approved for merge.
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
| 2026-11-15 | Added WPF sales-report/profit-loss integration test covering percentage discounts, returns, purchases, expenses, and net profit reconciliation. | Service commits `00a173d`, `3b214cd`; test commit `cc3cf1f`; Actions #205 | WPF Release build and all 11 tests passed. |
| 2026-11-15 | Added WPF shareable full Khata ledger and selected-period item statement (sales/returns), with Unicode-capable Windows print/PDF flow; added consistent native scrollbar theme. | Khata service/UI commits `a2b78a2`, `a081536`, `7efa622`, `95a14c5`, `6098cc3`; scrollbar commit `3d0c4a5`; Actions #216/#226 | Query tests and native WPF build passed; target Windows print/visual acceptance pending. |
| 2026-11-15 | Added immediate WPF inventory duplicate-barcode lookup, barcode-first editor focus, duplicate Save blocking, existing-product edit exception and inventory CRUD/tombstone regression tests. | Inventory commits `4319944`, `c1eb8bf`, `2cc9144`, `edf6b3f`, `ee5389c`, `60b526c`; Actions #245 | WPF Release build and all 15 tests passed. Android validation #316 also passed. |
| 2026-11-15 | Moved all implemented tasks out of Pending Updates into Completed Updates; verified the remaining Pending section contains only unfinished acceptance and integration tasks. | Tracker cleanup commit `0e5a23f`; latest PR head `5832635`; Actions #250/#252/#321/#323 | Latest WPF Release build/tests and Android validation both passed; PR #5 is clean/mergeable but remains Draft. |
| 2026-11-15 | Historical pre-migration Flutter Windows correction: removed unsupported Window.getSize usage and retained the old runner's 1280×720 startup/980×650 minimum. The Flutter Windows runner was later retired; this is not a WPF validation result. | Historical Flutter Windows correction | Superseded by native WPF migration; target WPF startup test remains pending. |
| 2026-11-15 | Pre-migration cleanup: clarified Walk-in/Khata/Wholesale semantics, removed retired Flutter Windows desktop packages and activation code, and updated the migration roadmap. | `ee6df2b`, `6133c52`, `e056dcb` | Flutter Windows target subsequently retired; native WPF source is tracked separately above. |
| 2026-11-13 | Added sample update, previously reported Windows bug, verified completed items, and validation follow-ups | This file update | Done |
| 2026-11-13 | Created project tracking file | `2c2409275da6a2518a1ca6b676605867e130a25d` | Done |
| 2026-11-16 | Added native WPF Google OAuth/PKCE with DPAPI token storage, Google Drive v3 transport and a schema-v2 SQLite snapshot exporter with pre-repair safety backup and stable-reference repair. | Commits `352befc`, `b37b5af`, `11793f0`, `4650bd8`, `5e62050`, `9f43ea1` | WPF Release build passed in validation run `43805757277`; snapshot-export integration test passed as part of 14 WPF tests in run `43806387092`; Android validation run `43806273015` passed on the docs-only successor commit. Cross-platform golden-hash verification remains pending. Full master merge/conflict/tombstone/auto-sync and UI integration remain pending. |
| 2026-11-16 | Retired Flutter Windows sale-window, pending-bill lifecycle and keyboard/window event code from `sales_screen.dart`; preserved Android billing/scanning and the shared SQLite pending-bill table used by WPF. | Pending consolidated commit | Android validation required; legacy Drive-sync compatibility shim intentionally retained until native WPF sync replaces its call sites. |
| 2026-11-16 | Removed legacy Flutter Windows sales-screen presentation branches (desktop DataTable cart, split-pane cashier layout and desktop AppBar controls); retained Android billing panels and existing sale calculations. | Pending consolidated commit | Android validation required; remaining legacy bill/window lifecycle cleanup is still pending. |
| 2026-11-14 | Historical Flutter Windows POS #68 passed; old desktop scrollbar/startup-status, receipt, autocomplete and lazy-inventory work was implemented before the Flutter Windows runner was retired. Optional Gemini handwriting OCR is Android-only and remains active. | Historical Flutter Windows build #68 | Not counted as native WPF acceptance; WPF UI, scanner and printer verification remain pending. |

## Scanner hardware and supplier-invoice capture clarification (2026-11-13)

- [x] **Scanner support is model-agnostic.** User clarified that Windows should consider any installed/connected scanner; do not hard-code Speed X SP9260 or any VID/PID. Generic USB keyboard-wedge scanners work when the New Sale scan field is focused. Safe minimized-app capture remains pending unless a dedicated scanner interface is available.
- [x] **Supplier invoice capture device confirmed — Android/mobile camera.**** Supplier purchase/inventory invoices will be scanned or photographed using the **mobile phone camera**. The intended workflow is camera capture followed by OCR-assisted extraction and an editable review/confirmation step before posting purchase, stock, or supplier-account changes. This is separate from the model-agnostic Windows USB barcode-scanner workflow.

## User-approved scope update — 2026-11-14

### Native WPF Google Drive implementation progress — 2026-11-16

- [x] Added native Windows Google OAuth loopback authorization with PKCE, refresh-token handling and current-user DPAPI-encrypted token storage.
- [x] Added Google Drive v3 transport for the existing `Khan Baba POS` folder, paginated file listing, JSON download, and JSON create/update.
- [x] Added a schema-v2 snapshot exporter for the existing SQLite v18 database. It excludes device-local integer IDs, preserves stable sync IDs/barcode keys, computes a SHA-256 digest, and creates a verified safety copy before repairing missing legacy sync IDs/foreign references.
- [x] Added a disposable schema-v18 integration test for snapshot v2 structure, local-ID exclusion, stable customer-reference repair, pre-repair backup and SHA-256 self-consistency (14 WPF tests passed in run `43806387092`).
- [ ] Verify byte-for-byte snapshot hash compatibility against Android's Dart JSON encoding using cross-platform golden fixtures.
- [ ] Port Windows-master reconciliation: process Android device snapshots idempotently, merge append-only sales/purchases/Khata/returns/expenses/reminders, detect product-stock and account-balance conflicts, and preserve aliases/tombstones.
- [ ] Add master manifest processed-snapshot/pre-merge-backup tracking, conflict review/resolution, Android master-approval download, offline status, connectivity-triggered and periodic sync, and retry/recovery.
- [ ] Integrate Drive connect/sync/status/disconnect controls into WPF and test with a separate Google account and disposable databases. Physical Windows acceptance remains pending.

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
- [x] Removed the remaining Flutter Windows-only sales cart DataTable, split-pane cashier body, desktop AppBar actions and Windows-specific AppBar styling. Android customer, cart, discount and checkout panels remain in the shared Flutter sales screen.
- [x] Retired Flutter Windows sale-window and pending-bill lifecycle hooks from `sales_screen.dart`; removed Windows keyboard/window event handling and kept Android scanner, product search, cart, discounts and checkout flow. The shared `pending_bills` SQLite table/service remains available to native WPF; the `PosWindows` compatibility shim remains because the legacy Flutter Drive-sync implementation still references it.
- [ ] Complete native WPF Google Drive snapshot sync and recovery before removing the obsolete Flutter `PosWindows` compatibility shim and Flutter-only Windows Drive backup calls.

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
- [x] Added and ran a representative SQLite v18 fixture test proving the verifier accepts the Flutter schema and rejects altered/missing constraints without modifying the database (latest fixture suite in WPF validation).


## Work log — 2026-11-15 (continued)

- Removed the retired Windows-specific AppBar colours, title-bar heights, back-navigation helper and other simple presentation-only properties from 16 Flutter screens in four grouped commits (`4fdd5b1`, `b4aab02`, `2a6ea9d`, `87e1a1a`). Android AppBar behaviour is retained.
- Updated the WPF README to describe the expanded read-only schema verifier accurately.
- Android validation passed on earlier commits in this cleanup series; the latest grouped commit's Android analyzer/test and POS regression workflows are still running. No APK, EXE or release artifacts are published.


## Verified validation and cleanup update — 2026-11-15

- Android validation-only workflow passed on latest `main` commit `9a517947895be59a9dd57ede7bb4dce44684d6c5` (run `43717393043`).
- POS sync and invoice conversion regression tests passed on the same commit (run `43717393051`).
- These runs did not publish APK, EXE, or release artifacts.
- The latest scanner/printer and four FAB cleanup commits are now recorded above as completed. Remaining Flutter Windows branches are still explicitly pending; the Windows-master Drive sync and database path branches are shared data behaviour and must not be removed merely because they mention Windows.

## Work log — 2026-11-16 (Drive protocol validation)

- [x] Added native WPF DriveSnapshotEnvelopeValidator to validate schema-v2 device envelopes before any database merge: required metadata, all 11 required collections, and SHA-256 integrity over the compact data payload.
- [x] Added Windows-master envelope validation for masterDeviceId, processed-snapshot manifest entries, and the same schema-v2 data/hash contract.
- [x] Added three protocol tests: valid Android envelope + tamper rejection, missing-collection rejection, and valid Windows master manifest acceptance.
- [x] Windows WPF CI passed for the merge engine and initial tests in run `43832118175`: Release build and all tests successful.
- [x] Implement native SQLite v18 reconciliation engine source porting Android DBHelper.mergeDriveSnapshot: stable party aliases, product/party conflicts, append-only sales/purchases/Khata/returns/expenses/reminders, tombstones and explicit Keep Windows / Use Other Device resolution. No schema version or Android table layout changed.
- [x] Implemented WPF Drive v3 Windows-master orchestration: list/download device envelopes, verify hashes, create verified pre-merge backups, merge device data, persist processedSnapshots/preMergeBackups and upload the updated master envelope for Android clients. [ ] Real Google Drive account testing and end-to-end Android/Windows acceptance remain pending.
- [ ] Expand transactional integration tests to all merge paths, idempotency/duplicate snapshots, missing foreign references, party aliases/re-adds, rollback and backup recovery using disposable schema-v18 databases. Initial product conflict and protected product-delete tests pass.
- [x] Added WPF conflict review, connection/sync status, offline/retry scheduling and explicit user-visible errors. [ ] Physical Windows runtime, real Google OAuth and multi-device acceptance remain separate pending gates.
## Work log — 2026-11-16 (Drive envelope validation CI fix)

- [x] Fixed WPF test compile failure by making the shared Dart-compatible JSON double converter public for the protocol test fixture.
- [x] Windows WPF CI passed on commit `4b42cdcf47ec63986e2c85db509fc51e4623e1b7`: Release build succeeded; 17 tests passed, 0 failed, 0 skipped (run `43811531846`).
- [x] Android validation passed on preceding source-equivalent commit `0bc0a5b78b21daf09351a7af0546ea799e2e7648` (run `43811259207`); latest converter visibility change is WPF-only.
- [x] Added transactional SQLite v18 merge/conflict/tombstone engine source; Drive imports remain disabled until orchestration, full regression coverage and target-PC acceptance are complete.
## Work log — 2026-11-16 (WPF master manifest foundation)

- [x] Added `DriveMasterManifest` matching Android master envelope fields: `masterDeviceId`, `processedSnapshots`, `preMergeBackups`, `data`, `snapshotHash`, and `updatedAt`.
- [x] Added idempotent processed-hash lookup/mark/pending operations and backup filename tracking; cloud manifest rejects local absolute backup paths to avoid leaking Windows profile paths.
- [x] Added round-trip and manifest-state tests; latest WPF and Android CI for commit `167f276a0b9e4bd7c5b34bf9bdb02cbb2e0a2c08` is running (run IDs `43811887867`, `43811887929`).
- [x] Merge engine and initial product conflict/tombstone tests were added after the manifest foundation; Release build and tests passed in run `43832118175`.
- [ ] Finish Drive v3 orchestration, sync/conflict UI, 1–5 minute auto-sync/offline retry and target-PC acceptance. The merge engine and initial conflict/tombstone tests are implemented; broad parity tests remain pending.

## 2026-11-16 — Portable Windows test packaging

- [x] Added `.github/workflows/publish-wpf-test.yml` on `integration/wpf-mainline`. It builds and runs the WPF regression tests, then publishes a self-contained Windows x64 portable ZIP as a 30-day GitHub Actions artifact. It is explicitly labelled TEST ONLY and does not create a production release or installer.
- [x] Packaging workflow run `43813441172` completed successfully on `integration/wpf-mainline` at commit `5d0e40b9c9310bc83b47d00724d06b6749dadff5`: WPF Release build succeeded with 0 warnings and 0 errors; 19 tests passed, 0 failed, 0 skipped; self-contained win-x64 publish, ZIP packaging and artifact upload all succeeded.
- [x] Downloaded and inspected the uploaded package contents: `KhanBabaPos.Wpf.exe`, `KhanBabaPos.Wpf.pdb`, and `TEST-INSTRUCTIONS.txt` are present. Artifact: `KhanBabaPOS-Windows-Test-win-x64` (artifact ID `14201611017`; expires 2026-12-16). The portable ZIP has been verified structurally, not launched on the owner's Windows laptop.
- [x] Owner launched the portable WPF test build on the target Windows PC and supplied a screenshot showing the New Sale screen and `Existing SQLite v18 verified` status. First-window startup and database detection are confirmed; this does not yet verify navigation, transactions, or hardware.
- [ ] Complete target-PC basic navigation and responsive layout acceptance using a disposable SQLite v18 database copy. Keep the live store database and existing backups untouched.
- [ ] Keep Google Drive sync/reconciliation, Windows authentication/role parity, native updater/production installer, end-to-end feature parity, physical scanner/printer acceptance and owner sign-off as production cutover gates.


## Windows local authentication decision — 2026-11-16

- [x] Owner approved the recommended Windows-only local authentication direction. Android Flutter/Firebase authentication remains unchanged; Windows login will work offline and will not require Firebase.
- [x] Implement first-run Admin account provisioning with a forced password setup; no default password is shipped. Login UI requires the owner to create the first Admin password.
- [x] Store local credential verifier using versioned PBKDF2-HMAC-SHA256 (310,000 iterations, random 16-byte salt) and protect the local credential/audit store with Windows DPAPI CurrentUser scope. No plaintext password is stored.
- [x] Add local user lifecycle: Admin can create/disable/reset staff accounts; roles are Admin and Salesman; disabling the last active Admin is blocked.
- [ ] Complete role authorization in every mutating data service. MainWindow navigation/actions are Admin-gated, staff management is Admin-gated, and sale posting verifies the active session and records its actual user ID/display name in existing salesman_uid/salesman_name fields. Audit remaining service entry points before marking role parity complete.
- [x] Add login/logout, five-failure temporary lockout, 30-minute sliding session expiry and protected audit events. Login works offline and credentials are scoped to the current Windows account via DPAPI.
- [x] Add automated tests for first-run provisioning, password verification, role denial, disabled users, last-Admin protection, session expiry and sale attribution. WPF Release build and tests passed in GitHub Actions run 43831153534 (commit 2f2bc1e). [ ] Target-PC login/role acceptance remains required.
- [x] Added the transactional SQLite v18 merge/conflict/tombstone engine and explicit resolution methods; initial disposable-database tests verify product conflict resolution and protection against deleting a stocked product. [ ] Complete the full Android-parity test matrix and target-PC acceptance before enabling Drive imports.
- [x] Added per-user x64 Inno Setup installer source, separate user-data/backups preservation paths, GitHub-release update check, SHA-256 and Authenticode verification logic, a manual-only installer compilation workflow and update-check UI. No installer/release artifact was published. [ ] Compile and test installer/upgrade/uninstall, obtain the production signing certificate, pin its thumbprint, sign installer/releases, and complete owner acceptance. Updater installation intentionally remains disabled until the publisher pin is configured.

## Work log — 2026-11-16 (installer workflow correction)

- [x] Inspected latest branch head `d89ca686100bbc141eb8415099f2058f96ab6c85`: native WPF Release build and 28 regression tests passed in installer-validation run `43844243858`; installer compilation failed because the push event supplied an empty `inputs.version`, overriding the Inno Setup script's default and leaving `AppVersion` blank.
- [x] Correct the installer workflow to use a validated PowerShell fallback version (`1.0.0`) when no manual input is supplied.
- [x] Make installer compilation/test-artifact upload manual-only; regular WPF build/test validation remains in `build-wpf.yml`. No production installer or release is published by this change.
- [x] Refresh the WPF README to reflect the implemented Drive reconciliation/orchestration foundation and the intentionally paused remote imports.

## Work log — 2026-11-16 (WPF build warning cleanup)

- [x] Changed the intentionally disabled Drive import gate from a compile-time constant to a read-only runtime field. Import behaviour remains disabled, but the compiler no longer treats the guarded merge path as unreachable; no sync safety gate was enabled or relaxed.


## Work log — 2026-11-16 (Windows role-boundary regression coverage)

- [x] Audited WPF data-mutation service entry points: Admin-only operations enforce the role inside the service layer; cashier sale posting, pending-bill operations and receipt printing explicitly permit Admin/Salesman as intended.
- [x] Added a Windows regression test proving a logged-in Salesman is rejected by expense, reminder, party/customer-type, Khata receipt, purchase, sale-return, backup/restore and printer-settings mutation entry points before database/file operations begin.
- [x] Windows WPF CI passed with the Salesman mutation-boundary regression test (run `43850825344`); physical Windows account/role acceptance remains a separate gate.


## Work log — 2026-11-16 (sale-return quantity integrity)

- [x] Found and fixed a duplicate-line validation gap: repeated entries for the same original sale item are now cumulatively checked against the sold quantity within one return transaction.
- [x] Reject zero/negative return quantities and unsupported return conditions instead of silently treating them as saleable.
- [x] Require stock and customer-balance updates to affect exactly one row so a stale reference cannot silently produce an incomplete return.
- [x] Added a regression test proving an over-quantity duplicate-line return is rejected and the return header/items, stock and Khata balance all remain unchanged.
- [ ] Run Windows WPF CI and confirm the full regression suite.


## Work log — 2026-11-16 (deterministic Windows test isolation)

- [x] The first sale-return regression run compiled cleanly and passed the new duplicate-line rollback test, but exposed an existing test-suite race: separate test classes mutate the process-wide AccessService test session while Drive merge tests require Admin.
- [x] Disabled xUnit test parallelization for this Windows integration test assembly because the application intentionally uses a single process-wide authenticated session. This keeps the tests representative and removes cross-test authentication races without changing production session behaviour.
- [x] Re-ran Windows WPF CI after test isolation; 30 tests passed, 0 failed, 0 skipped (run `43851872671`).


## Work log — 2026-11-16 (Windows supplier invoice transaction)

- [x] Added a WPF-side supplier invoice posting service matching the Android schema-v18 invoice contract: supplier, normalized invoice number/date, invoice discount/tax, paid amount, balance due, item pack conversion and invoice-level cost allocation.
- [x] Stock updates, purchase rows, supplier payable balance and supplier purchase/payment ledger entries are committed in one SQLite transaction.
- [x] Duplicate supplier invoice numbers are rejected; invalid pack conversions, mismatched stock units, missing suppliers/products, and retail prices below allocated cost are rejected before commit.
- [x] Added regression tests for a converted pack invoice with partial payment and for duplicate/invalid invoice rollback.
- [x] Windows WPF CI passed on commit `96b0f153123ba09ed13ae02602fab326321a3b07` (run `43852607335`): Release build succeeded with 0 warnings and 0 errors; 32 tests passed, 0 failed, 0 skipped.
- [ ] Add the desktop invoice-entry UI and supplier invoice history/ledger presentation after service tests pass.


## Work log — 2026-11-16 (supplier invoice desktop UI)

- [x] Added a WPF supplier invoice dialog supporting multiple invoice lines, existing/new products, invoice unit-to-stock conversion, unit rates, optional line totals and retail sale price.
- [x] Added supplier and invoice metadata entry, invoice discount/tax, paid amount and automatic due balance posting through the transactional invoice service.
- [x] Expanded purchase history to display supplier, invoice number, invoice total, paid and outstanding amounts.
- [ ] Run WPF Release build and all regression tests for the new desktop UI. Mobile OCR/camera capture has not been ported to Windows.


## Work log — 2026-11-16 (Owner instruction: complete remaining Khan Baba POS work)

- [ ] **Status: Pending.** Owner ki nayi hidayat: "Jab tak main Windows wala ready artifact try karta hun, aap is app ko ab mukamal kren." Is ka matlab hai ke `integration/wpf-mainline` par Khan Baba POS ke tamam baqi software/development tasks ka audit karke unhein complete karna hai, bina Windows artifact ki owner-side testing ka intezar kiye.
- [ ] Sab se pehle tamam pending items, incomplete implementations, build/test failures, platform parity gaps aur release blockers ka source-code aur CI ki bunyaad par audit karna hai. Existing completed features ko dobara ya ghair-zaroori tor par change nahi karna.
- [ ] Har task ke liye pehle se mojood requirements aur safety conditions barqarar rakhni hain. Android Flutter aur Windows native C#/.NET WPF dono ko maintain karna hai; Windows ke liye WinUI 3 ya Flutter Windows UI dobara introduce nahi karni.
- [ ] Offline-first SQLite schema, sales, stock, purchases, supplier invoices, returns, Khata, customer balances, discounts, payments, backup/restore, printer/scanner workflows aur existing sync/outbox contracts ko preserve karna hai. Windows Google Drive import/sync filhal disabled hi rahe jab tak us ke tamam safety gates pass na hon.
- [ ] Pehle se approved "Recall Bill / Edit Previous Bill" feature abhi pending hai: Android aur WPF dono mein Recent/Recall Bills, saved bill items/customer/time details, safe edit/overwrite aur Save as New Bill. Overwrite sirf us bill par mumkin ho jahan return record ya baad ki Khata receipt/payment na ho; warna sirf Save as New Bill. Stock aur Khata ki tabdeeliyan aik SQLite transaction mein hon, failure par original bill mehfooz rahe, discount aur 80mm ESC/POS print flow preserve rahe. Is feature par code se pehle detailed audit aur schema verification lazmi hai.
- [ ] Supplier invoice desktop UI ke baad WPF Release build aur tamam regression tests chalane hain; CI result aur test counts isi log mein record karne hain.
- [ ] Har implementation se pehle us feature ki tamam user requirements aur acceptance/safety conditions isi `PROJECT_UPDATE.md` mein Roman Urdu mein darj karni hain. Documentation-first commit ke baad hi code changes shuru hon. Har implementation ke baad status aur asal test/build results update karne hain.
- [ ] Koi live store database, real customer/accounting record ya production backup development test ke liye use/modify nahi karna. Tests disposable database copies par chalane hain.
- [ ] Owner-side physical Windows laptop, scanner, printer, real backup/restore aur operational acceptance ko software CI se alag pending gates ke tor par report karna hai; inhein bina owner verification ke Completed nahi kehna.
- [ ] Is broad completion instruction ki implementation abhi shuru nahi hui; yeh entry sirf scope aur work order record karti hai.


## Work log — 2026-11-16 (Initial remaining-work source audit)

- [x] Latest working branch `integration/wpf-mainline` aur canonical `PROJECT_UPDATE.md` verify ki. `update.md` duplicate create nahi ki.
- [x] Android `lib/history_screen.dart` inspect ki: existing Sales History bill details load/reprint aur sale-return flows hain; approved Recall/Edit Previous Bill overwrite workflow nazar nahi aaya.
- [x] Android `lib/db_helper.dart` mein schema-v18 sale, sale_items, sale_returns, sale_return_items aur khata_transactions contracts ka initial inspection kiya. Sale posting mein sale aur Khata ledger rows transaction mein banti hain; Recall implementation se pehle receipt/return linkage aur sync delete/tombstone contract ki mazeed verification zaroori hai.
- [x] WPF `SalesHistoryService.cs` read-only history aur sale item retrieval deta hai; WPF MainWindow mein Recall Bill selection/edit workflow abhi maujood nahi. WPF `SalePostingService` filhal new sale posting karta hai.
- [x] Supplier invoice desktop dialog aur purchase history UI source mein mojood hain. Is UI ke baad ka required WPF Release build aur full regression test result abhi documentation mein Pending hai.
- [ ] **Pending — Recall Bill / Edit Previous Bill:** dono platforms par feature implementation aur transactional regression tests abhi baqi hain.
- [ ] **Pending — latest WPF validation:** supplier invoice UI ke baad Release build + complete tests ka naya successful CI result abhi verify nahi hua.
- [ ] **Pending — environment limitation:** is session mein Codespaces terminal/workspace ka live connection available nahi mila; GitHub source read/write mumkin hai, lekin is waqt local `dotnet` / `flutter` commands run karke code changes compile/test karna mumkin nahi. Bina build/test ke unverified code commit nahi kiya jayega.


## Work order update — 2026-11-16 (Owner ne darmiyani build/test filhal skip karne ki ijazat di)

- [ ] **Status: In Progress.** Owner ki wazeh hidayat: "Code aur is ka test/build bhi filhal chhor do. Bas code likhte jao. Aakhir mein jab commit/push karenge, tab errors dekh kar fix karenge. Abhi code mukammal karo."
- [ ] Is liye implementation ke darmiyan har choti tabdeeli ke baad build/test chalana zaroori nahi. Pehle tamam agreed code changes mukammal karne hain; phir aik consolidated review, build aur tests commit/push se pehle ya us waqt available environment mein chalaye jayenge.
- [ ] Yeh ijazat accounting/data safety ko bypass karne ki ijazat nahi: Recall Bill overwrite ke liye return ya baad ki Khata receipt/payment ki pabandi, stock aur Khata ki aik SQLite transaction, rollback par original bill ki hifazat, sync/outbox identity aur existing discount/printing behavior preserve karna lazmi hai.
- [ ] Agar local terminal ya CI run available na ho to tests skip hone ki wajah sachai se note karni hai; test pass hone ka dawa nahi karna.


## Work log — 2026-11-16 (Recall / Recent Bills — initial implementation)

- [x] Android `DBHelper.updateSaleFromRecall(...)` add kiya: original bill ko SQLite transaction mein update karta hai, purana stock reverse karke edited cart ka stock validate/deduct karta hai, sale/items update karta hai, Khata ledger aur party balance adjust karta hai, aur Android sync queue mein updated rows/tombstones queue karta hai.
- [x] Android POS screen par `Recall Bills` action add kiya: recent saved bills se bill select karke items, customer, payment mode aur stored discount amount cart mein load hotay hain.
- [x] Android checkout par recalled bill ke liye `Update Existing Bill` aur `Save as New Bill` ka choice add kiya. Save as New Bill existing `completeSale` flow use karta hai; successful save/update ke baad existing receipt printing flow chalta hai.
- [x] Android overwrite service return record aur original checkout receipt ke ilawa kisi bhi customer receipt/payment history ko dekh kar overwrite rokta hai; customer change bhi existing bill par block hai. Transaction fail ho to SQLite rollback hota hai.
- [x] Windows WPF `SalePostingService.UpdateSaleFromRecallAsync(...)` add kiya: backup/schema verification ke baad SQLite transaction mein return/payment safety, stock restore/validation, sale/items update, Khata ledger aur party balance adjustment karta hai.
- [x] WPF `SalesHistoryService` mein recall dialog ke liye customer ID expose ki aur POS screen par `Recall Bills` button/dialog add kiya. Checkout par existing bill update ya new bill save ka option diya.
- [x] Windows mein recalled bill ko update karne ke waqt original customer aur customer type change karna allowed nahi; return ya extra receipt/payment record ho to update block hota hai aur Save as New Bill option available rehta hai.
- [ ] **Validation Pending:** owner ki hidayat ke mutabiq darmiyani build/tests skip kiye gaye. Android Flutter analysis/build, WPF Release build aur regression tests consolidated final pass mein chalane hain. Is waqt in changes ko tested/pass ya production-ready declare nahi kiya ja raha.
- [ ] **Code review pending:** consolidated compile review mein schema column names, sync tombstones, customer/payment edge cases, return/payment lock checks, discount calculations aur printing flow verify karne hain. Koi test result abhi available nahi.


## Work item — Native WPF update notification refinement (2026-11-16)

- [ ] **Status: Pending.** WPF app startup par latest stable GitHub release check honi chahiye; draft/prerelease ko ignore karna hai. Installed version se naya version ho to UI mein update status aur release notes show hon.
- [ ] Har version ke liye notification sirf aik martaba show ho; same version ke liye har app restart par popup spam na ho. Manual "Check for Updates" hamesha current status dikha sake.
- [ ] Download/install tabhi allow ho jab manifest SHA-256 aur Windows Authenticode signature pinned production certificate se verify ho. Certificate/thumbprint absent ho to download/install ko disabled hi rakhna hai aur user ko clear status dena hai.
- [ ] Update ke dauran database, settings, invoice files aur backups ko touch nahi karna. Latest-version selection ko GitHub stable release endpoint tak mahdood rakhna hai.


## Work log — 2026-11-16 (Native WPF update notification refinement)

- [x] Startup update checker ab naye stable release milne par version aur release notes ke sath notification dikhata hai.
- [x] LocalAppData mein last-notified version save hota hai; aik hi version ka popup har restart par repeat nahi hota.
- [x] Existing manual Check for Updates action barqarar hai.
- [x] Installer/download tab tak disabled hai jab tak production signing certificate thumbprint configure nahi hota; SHA-256 aur Authenticode verification gates ko bypass nahi kiya.
- [ ] Build/CI validation final consolidated pass mein pending hai. Real release feed, one-time popup aur signed installer handoff target PC par verify karna baqi hai.


## Work log — 2026-11-16 (Recall workflow follow-up)

- [x] Android aur WPF dono mein Recall mode se bahar nikalne ke liye explicit New Bill action/flow add kiya; naya bill shuru karne par recalled invoice ID reset hoti hai, taa-ke agla checkout ghalti se purana bill overwrite na kare.
- [x] Android overwrite se pehle original customer account aur customer type ko dobara verify karta hai; existing bill par customer/type change allowed nahi.
- [x] WPF history model mein customer ID include ki, taa-ke recalled bill sahi customer account ke sath load ho aur draft receipt model bhi compatible rahe.
- [x] WPF startup par stable update notification per-version aik martaba show karne ka logic add kiya; last-notified version LocalAppData mein store hota hai.
- [ ] **Pending:** in tamam latest changes ka consolidated source review, Flutter analyze/build, WPF Release build aur regression tests. Owner ke kehne par abhi intermediate validation nahi chalayi gayi.


## Consolidated progress — 2026-11-16

- [x] Android Recall Bill UI, transactional overwrite service, Save as New Bill path aur explicit New Bill action source mein add kar diye gaye.
- [x] WPF Recall Bill selection dialog, history customer ID, transactional overwrite service, Save as New Bill path aur explicit New Sale reset source mein add kar diye gaye.
- [x] WPF startup par stable update notification per-version one-time display ke liye LocalAppData marker add kiya; manual update check aur signed-installer safety gate barqarar hai.
- [x] Recall ke waqt WPF ka existing active pending cart pehle persist hota hai; recalled bill ke liye naya pending-bill identity use hota hai.
- [ ] **Overall project completion abhi In Progress hai.** Repo mein mazeed pending code/acceptance items mojood hain: Google Drive v3 orchestration/reconciliation (remote import disabled), native updater download/progress/installer signing, WPF full-ledger/period-statement PDF validation, complete screen-by-screen responsive audit, schema/calculation parity, scanner/printer physical acceptance, supplier invoice UI ke baad CI, aur target-PC/owner sign-off.
- [ ] Owner ki hidayat ke mutabiq abhi intermediate build/test run nahi hua. Android aur WPF ke tamam latest code changes final consolidated pass tak unverified hain. Koi production-ready ya tested claim nahi kiya ja raha.
- [ ] Live business database ya production backup ko touch nahi kiya gaya.


## Owner workflow instruction — commit, push aur GitHub Actions cadence (2026-11-17)

- [x] Owner ki wazeh hidayat: har choti code update ko alag commit/push karna zaroori nahi; pehle aisa karna ghair-zaroori tha aur is se GitHub Actions workflows bhi be-wajah trigger ho rahe thay.
- [x] Development ke darmiyan related code changes ko working set mein jama rakha jaye. Har choti edit, minor fix ya file change par commit/push na kiya jaye.
- [x] Ek feature/module ya logically related kaam mukammal hone par changes ka consolidated review karke aik grouped commit banaya jaye.
- [x] GitHub Actions sirf meaningful milestone, consolidated validation, ya final build/artifact ki zaroorat par chalaya jaye. Har minor update par workflow trigger na kiya jaye.
- [x] Final validation se pehle tamam related pending code changes ko aik sath review kiya jaye; phir munasib consolidated commit/push aur required build/tests run kiye jayen.
- [x] Agar kisi urgent fix, collaboration ya backup ke liye beech mein commit/push waqai zaroori ho to pehle us ki wajah wazeh ho; warna changes ko group kiya jaye.
- [x] Yeh cadence project ke tamam future sessions aur WPF/Android implementation work par apply hoti hai. Owner ki alag explicit hidayat is par priority rakhegi.


## Work log — 2026-11-17 (Recall billing parity source fixes)

- [x] Native WPF updater ko harden kiya: path-traversal safe asset-name check, HTTPS GitHub release URL restriction, asset size validation, 3-attempt transient retry, download progress, temporary staging, SHA-256 + pinned Authenticode verification aur verified installer ka separate Updates folder mein handoff. Production thumbprint blank hi hai, is liye download/install disabled rahega.

- [x] Owner ki safety hidayat ke mutabiq WPF Google Drive ka sirf remote import nahi, balkeh upload/download/manual sync/auto-sync aur conflict resolution bhi default se disabled kar diya. UI par paused status aur disabled sync/resolution controls dikhte hain; local POS offline kaam karta rahega. Regression test source mein add hai. Is gate ko owner acceptance ke baghair enable nahi karna.

- [x] WPF Recall service ko disposable database path inject karne ke qabil banaya (existing production overload wahi active DB resolve karta hai); Windows regression tests source mein add kiye gaye: edited subtotal/percentage discount/received/Khata balance/stock update, pehli receipt allowed, baad ki receipt par rejection aur stock unchanged. [ ] Test execution final consolidated validation mein pending hai.

- [x] Recall ke liye disposable SQLite integration tests source mein add kiye: edited cart ka final total/discount/received/balance/stock/ledger reconciliation, pehle ki receipt par safe overwrite, aur baad ki receipt par overwrite rejection + rollback assertions. [ ] Flutter test execution abhi consolidated validation ke liye pending hai.

- [x] Android Recall overwrite ab edited cart ka subtotal aur saved discount amount se final total dobara calculate karta hai; purane invoice ka final_amount edited bill par reuse nahi hota.
- [x] Android aur WPF dono mein Recall overwrite guard ab usi customer ki original sale ke baad wali extra Khata receipt ko check karta hai. Original bill se pehle ki receipt history be-wajah overwrite ko block nahi karti; original checkout receipt apni note identity se exclude rehti hai.
- [ ] **Validation Pending:** disposable SQLite v18 fixture par Cash, Credit, Partial, fixed/percentage discount, prior receipt, later receipt, return block, stock rollback aur Khata balance cases ki cross-platform regression tests; Flutter analyze/test aur WPF Release build/test consolidated run mein chalane hain.
- [ ] Drive snapshot/Android sync parity aur real-device cashier acceptance alag pending gates rahenge. Is source-only fix ko tested ya production-ready nahi kaha ja raha.


## Work log — 2026-11-17 (Android Recall disposable-database regression coverage)

- [x] Added `test/recall_bill_test.dart` using a fresh temporary SQLite database per test; live store data and production backups are not used.
- [x] Coverage added for edited subtotal/discount/final total/received amount/Khata balance/ledger/stock reconciliation, earlier receipt allowed, later receipt blocked with rollback, and return-record overwrite block.
- [ ] Flutter test execution and analyzer validation are pending the consolidated Android validation run. These source tests are not yet reported as passing.
- [ ] Before Drive snapshot imports are re-enabled, the append-only merge contract must be extended/tested for recalled sale updates and replaced sale-item identities; Windows Drive sync remains fully disabled until the owner safety gate is cleared.
