# Khan Baba POS — Windows Native WPF Migration Roadmap

> **Migration scope:** Replace the **Windows Desktop client only** with a native C#/.NET WPF application. Android remains Flutter and continues to use the existing SQLite database format and approved sync workflows.
> **Strict UI framework rule:** Use **WPF (Windows Presentation Foundation)** only. **Do not use WinUI 3, Windows App SDK, MAUI, a web wrapper, or Flutter Windows.**
> **Windows platform retirement:** Flutter Windows runner and its GitHub build/release workflow are being removed. Android Flutter remains the supported Flutter client; all future Windows UI, hardware, sync, and release work belongs in `desktop-wpf/`.
> **Repository:** https://github.com/magscacoffice/general_store_pos
> **Branch status (2026-11-22):** WPF migration PR #5 has been merged into `main`. The latest follow-up changes are grouped on `feature/complete-project-pendings` and are not merged yet; keep `main` stable until Android/WPF validation and owner acceptance are complete.
> **Current status (2026-11-22):** WPF migration is in `main`; the current follow-up branch now includes the cashier Save & Print/Save Only workflow, fixed 80mm receipt profile, per-user Gmail account UI, safe Khata archive, and Wholesale customer removal. WPF Release build passed with 0 warnings/0 errors and 93/93 tests on Actions run #45002502830; this was validation-only and uploaded no artifact. Android analyzer and full Flutter tests passed on both Windows and Ubuntu (Actions run #45003053357; 22/22 each). Real two-Gmail cross-device sync, SpeedX SP60D, BC-86AC, PDF/backup, display/DPI and final Flutter/WPF parity acceptance remain owner-side gates. Production updater install remains blocked until the owner provides a code-signing certificate/thumbprint. Current follow-up work stays on `feature/complete-project-pendings`; do not merge until validation and owner acceptance are complete.

## Immediate owner priority — Windows cashier-first operation (2026-11-16)

Owner wants Windows WPF to remain usable for daily billing while other Windows modules are completed incrementally later. Android Flutter must remain untouched.

- [x] Keep the Windows New Sale workspace as the cashier landing screen, scanner-focused after startup and after adding each product.
- [x] Preserve repeated barcode behaviour: add the next unit to the existing cart line, bounded by available stock.
- [x] Preserve draft/pending bill autosave in the existing SQLite v18 `pending_bills` table; starting another bill first saves the active draft. Completed checkout is posted transactionally to the existing `sales`, `sale_items`, stock and Khata tables by `SalePostingService`.
- [x] Add visible Print Bill action in the New Sale workspace; persist the current draft before opening the print preview. Draft printing is read-only and must not deduct stock or post a sale.
- [x] Add cashier keyboard shortcuts at the window level: F2 scanner, F4 customer, F5 new bill, F6 discount, F7 received amount, F8 payment mode, F9 print/preview, F10 complete sale; Ctrl+P also opens print/preview.
- [x] Cashier actions are separated: **F9 = Save & Print**, **F10 = Save Only**, and **Draft Preview** is read-only. Printer & Invoice retains F9/Ctrl+P thermal print shortcuts. Physical printer output still requires a Windows PC and BC-86AC acceptance test.
- [x] Add a non-blocking startup update check and an in-app update-available indicator; offline or failed update checks must never block New Sale or local billing.
- [ ] **Signed updater release gate:** `NativeUpdateService` checks the latest GitHub Release and validates the release manifest, SHA-256 and Authenticode publisher. Download/install remains intentionally disabled until the owner provides the production code-signing certificate and its trusted thumbprint is pinned. Do not install unsigned or untrusted packages.
- [ ] Publish a versioned Windows installer and `khan-baba-release.json` manifest as GitHub Release assets after Windows runtime tests, code signing, checksum generation and installer/data-preservation tests pass. Only then can the app notify, download and install future feature updates safely.
- [ ] Verify F2/F4/F5/F6/F7/F8/F9/F10 and Ctrl+P on a real Windows cashier PC; verify barcode scanner focus and the saved default printer with the physical SpeedX SP60D and Black Copper BC-86AC.
- [ ] Confirm startup update notification against a real published test release; confirm offline startup does not delay billing.
- [x] Windows Release build, WPF regression tests, self-contained win-x64 publish and artifact upload passed on GitHub Actions run #390 (2026-11-16). Artifact: `KhanBabaPOS-Windows-x64-390` (artifact ID `14222191243`, expires 2026-12-16); run: https://github.com/magscacoffice/general_store_pos/actions/runs/43857899968. This is an unsigned test artifact, not a signed production installer. Do not merge Draft PR #5 or declare production-ready until the independent migration, sync, auth, printer and owner acceptance gates are passed.

## 1. Non-negotiable compatibility rules

- [x] Keep Android's Flutter implementation, Android validation workflow, and existing mobile user experience intact; Android analyzer and test validation passed after the test harness fix.
- [x] Separate native Windows WPF application exists under `desktop-wpf/`; Release build and 93 WPF tests pass. Android Flutter and shared SQLite remain separate. Full target-PC acceptance and final cutover remain pending.
- [ ] Preserve business behaviour: sale posting, stock movements, purchase posting, returns, discounts (including percentage discounts), received amounts, customer balances/Khata ledger, profit calculations, invoice totals, and all existing validation rules.
- [x] Preserve Walk-in and Khata customer types. **Wholesale customer option is retired in both Android Flutter and Windows WPF**; legacy customer classifications are mapped to Khata while historical sales/ledger rows remain intact. Payment method remains separate and existing discount/percentage behavior is preserved.
- [x] No SQLite schema version, table/column names, IDs, database path, sync identifiers, tombstone semantics or backup format were changed by this follow-up.
- [x] Windows remains local-first and uses the existing Windows-master Google Drive snapshot workflow. No Firebase/Firestore business-data sync was added to Windows.
- [x] Ordinary sales, inventory, purchases, returns, printing, reports and local access remain local; network is used only for approved Drive sync and update checks.
- [x] WPF uses the existing `%LOCALAPPDATA%\\KhanBabaPOS\\Data\\khan_baba_pos.db` path and `.active_database` restore pointer; installer/update must not replace the live database.
- [x] WPF schema verification, staged restore, integrity/hash validation and verified backup-before-import safeguards are implemented and covered by tests.
- [ ] No production feature is marked complete until it is implemented, built, tested against a copy of the real schema, and its parity with Flutter is verified.

## 2. Deep audit — repository inventory

The Android client remains Flutter/Dart. The native `desktop-wpf/` Windows client and `desktop-wpf.Tests/` were merged through PR #5; the current follow-up branch carries additional changes pending review. The Flutter Windows runner and Windows-specific build/release workflow have been retired. Current GitHub Actions validate Android source/tests, POS sync/invoice tests and native WPF build/schema/transaction tests without publishing release artifacts.

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
| `salesmen_management_screen.dart` | `StaffManagementWindow.cs`, `Services/AccessService.cs` | Native staff/access source and role-gated mutation guards implemented; real cashier role/permissions acceptance remains pending |
| `printer_screen.dart` | `PrinterInvoiceWindow.cs`, `Services/PrinterSettingsService.cs` | Printer queue selection/persistence, 80mm ESC/POS test/receipt source, invoice preview and PDF save/open implemented; physical BC-86AC acceptance pending |
| `backup_screen.dart` | `BackupRestoreWindow.cs`, `Services/DatabaseBackupService.cs` | Verified backup and staged restore with SHA-256, schema validation and atomic active-pointer switch implemented and tested |
| `cloud_sync_screen.dart` | WPF Cloud Sync window/service — implemented in source | Native Drive connection/sync window, pending-conflict comparison and Keep Windows / Use Other Device actions added; target-PC Google OAuth and offline acceptance remain pending |
| `drive_sync_service.dart` | WPF Drive snapshot service — enabled in source | OAuth/DPAPI token storage, Drive v3 upload/download, stable device identity, schema-v2 hash validation, pre-merge backups, Windows-master manifest, transactional merge, 2-minute retry scheduler and conflict UI added; real-account/runtime acceptance remains pending |
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
- [x] Native WPF sale, purchase and return transaction services use SQLite transactions for linked stock/accounting updates; automated transaction tests pass.
- [x] Add a read-only database compatibility gate: inspect `PRAGMA user_version`, `sqlite_master`, table columns, primary keys, required defaults/NOT NULL constraints and indexes before opening the database for normal operations.
- [x] Keep the shared SQLite schema at version 18 for the current migration and sync follow-up; do not bump it unless a separately reviewed migration is required.

## Follow-up hardening — Windows Drive disconnect concurrency (2026-11-22)

- [x] Fixed a race in Windows Google Drive disconnect: stop the periodic timer, wait for any in-progress sync/merge to finish, create and verify the local safety backup, and only then revoke/delete OAuth credentials.
- [x] If backup creation/verification or disconnect is cancelled/fails while credentials remain, restart auto-sync rather than leaving a connected account silently paused.
- [ ] Run the WPF Release build and full test suite for this follow-up commit. Earlier validation (93/93 WPF tests and 0 build warnings/errors) applies to the preceding source revision, not this concurrency fix.
- [ ] Real Windows laptop and two-Gmail cross-device acceptance remains owner-side; no APK, ZIP, installer or release artifact is authorized.

## Follow-up hardening — WAL-safe restore rollback snapshot (2026-11-22)

- [x] Shared Android/Windows Backup & Restore screen now creates the pre-restore safety copy through SQLite `VACUUM INTO` while the live database connection is still open, so committed WAL transactions are included.
- [x] Opens the new safety snapshot read-only and requires `PRAGMA integrity_check = ok` before closing the live database or switching the active database pointer.
- [x] Removed the raw live `.db` file copy from this restore safety path; a failed snapshot/integrity check cancels restore before changing the active database.
- [ ] Re-run Android tests on Android/Linux and Windows runners, plus WPF Release build/tests, against the updated source. Earlier test counts apply to their recorded revisions only.
- [ ] Verify restore with a deliberately WAL-pending write and then test rollback/reopen on physical Android and Windows devices. No build artifacts generated.

## Follow-up hardening — deferred sync records are not marked processed (2026-11-22)

- [x] Windows-master merge now distinguishes intentional skips (for example, a tombstone/re-add conflict retained for Windows review) from records deferred because a required stable ID or parent record is missing.
- [x] A device snapshot is marked fully accepted only when it has **zero pending conflicts and zero deferred records**. This prevents missing-parent sales, sale items, purchases, Khata transactions, returns or return items from being silently abandoned as an already-processed snapshot.
- [x] Added focused WPF unit tests for the snapshot acceptance rule: fully complete snapshots are accepted; any pending conflict or deferred record keeps the snapshot pending.
- [ ] Run WPF Release build and all tests after these sync changes. Previous 93/93 result is from an earlier revision and is not evidence for this new code.
- [ ] Validate on real Android + Windows devices with out-of-order parent/child records, repeated polling, duplicate delivery and conflict resolution. No APK, ZIP, installer or other build artifact generated.

## Follow-up hardening — sync lifecycle serialization (2026-11-22)

- [x] Windows conflict resolution now uses the same sync gate as snapshot import/export and disconnect. A user-approved conflict choice can no longer race with a simultaneous sync merge and be overwritten by that merge.
- [x] Android Drive disconnect now blocks new sync attempts, waits for an in-flight connection/migration and active sync to finish, then creates and verifies the safety snapshot before deleting credentials.
- [x] If Android safety backup creation fails, credentials remain in place and auto-sync can resume after the disconnect gate is released.
- [x] Windows merge now defers sale items when either their parent sale or referenced product is missing, keeping the snapshot unaccepted for a later retry.
- [ ] Run current WPF Release build and unit tests after these changes; earlier workflow runs do not validate this latest revision.
- [ ] Run Flutter analyze/tests and physical Android + Windows paired-device scenarios, including connect/disconnect during active sync, repeated polling, out-of-order parent/child delivery and simultaneous conflict resolution.
- [ ] Confirm real-device retries complete deferred records and that duplicate deliveries remain idempotent. No APK, ZIP, installer or other build artifact generated.

## Validation results — sync lifecycle hardening (2026-11-22)

- [x] Windows WPF Release build passed with 0 warnings and 0 errors on commit c778aaf26c6f125fd488a717f69eb58468432bad.
- [x] WPF unit tests passed: 97 passed, 0 failed, 0 skipped on the same commit.
- [x] Flutter analyze passed for the changed sync/invoice files on commit 1e42e9150f71004b10a4f94f9d3fc6aa4f85be85.
- [x] Flutter tests passed on both Ubuntu and Windows: 22 passed on each runner, including the Android/Windows Drive reconciliation integration test.
- [ ] Physical-device validation is still required for actual Google OAuth, simultaneous Android/Windows network timing, disconnect during a real upload, and deferred-record retries against live Drive data.
- [ ] No APK, Windows ZIP, installer or other build artifact was generated. Changes remain on feature/complete-project-pendings; main was not merged.

## Repository-wide review — 2026-11-22 (PROJECT_UPDATE.md rules applied)

**Review branch:** `feature/complete-project-pendings`  
**Review baseline:** `4d2132f7e71c6c6cacc47387fc21c86f6c848287`  
**Scope inspected:** all 221 tracked paths from the recursive repository tree; Android Flutter screens/data/sync/backup, native WPF app/services, schema-v18 verifier and fixtures, Firebase rules/function, installer and GitHub Actions. This was a source review of the branch, not a live-database or physical-device test.

### Reconciled older findings

- [x] Android manual backup now creates a SQLite `VACUUM INTO` snapshot and validates integrity/required tables before export; restore rollback snapshot is created while the live connection is open and verified before the active DB pointer changes.
- [x] Android and WPF Drive connections now enforce a verified Gmail binding per local app data profile; disconnect does not clear the binding. Separate businesses still require isolated app data/database profiles and separate Gmail accounts.
- [x] Wholesale customer selection and the Wholesale-only product-rate editor have been removed from both clients; legacy database fields and old records remain for compatibility.
- [x] Latest recorded CI validation is WPF Release build 0 warnings/0 errors and 97/97 tests, plus Flutter analyze and 22/22 tests on both Ubuntu and Windows. No package artifact was produced.
- [ ] Physical Android/Windows paired-device, Google OAuth, printer, scanner, PDF, display/DPI and backup/restore acceptance remains owner-side.

### New source-level finding — Drive import dependency accounting

- [ ] **High — WPF Drive merge can accept an incomplete snapshot when a required supplier/customer reference is missing.** In `DriveSnapshotMergeService`, a purchase with a non-empty `supplier_sync_id` can currently be inserted with a null local `supplier_id` when the party cannot be resolved. A sale return can similarly be inserted with a non-empty `party_sync_id` but no matching local customer. These rows must be deferred so the snapshot remains pending and can retry after their parent is available.
- [ ] **Medium — expenses/reminders without stable sync IDs are silently skipped.** Their merge loop currently continues without incrementing the deferred counter. Such a snapshot can therefore be marked accepted even though those records were not imported. Missing IDs must count as deferred; duplicates with an existing ID remain normal idempotent skips.
- [ ] Add focused regression coverage using disposable schema-v18 databases or directly tested merge predicates. Verify the snapshot remains unaccepted and a subsequent retry imports the missing rows once the parent/stable ID is available.
- [ ] Re-run WPF Release build and the complete WPF test suite after the fix. Do not generate APK, ZIP, installer or release artifacts.

### Additional review observations

- [x] WPF uses installed-app OAuth loopback + PKCE, stores tokens using current-user DPAPI, and has a client-specific token cache. Historical notes requiring `GOOGLE_WINDOWS_CLIENT_SECRET` apply to the retired Flutter Windows implementation and are superseded by the native WPF OAuth implementation.
- [x] Windows Drive sync is currently enabled by the explicit owner-approved source flag; import is enabled and guarded by envelope/hash/schema validation plus a verified pre-merge backup. Historical notes saying Drive imports remain disabled are superseded by the later owner approval and implementation entries.
- [x] Windows restore stages a new database and atomically changes `.active_database`; Android restore similarly uses a staged file and pointer rollback. Existing live DB files are not overwritten in place.
- [ ] Production updater/installer remains blocked on the owner's code-signing certificate and pinned publisher thumbprint. The installer workflow is manual-only and can compile/upload an unsigned test installer only when explicitly dispatched; do not dispatch it without separate authorization.
- [ ] Full real-device cross-platform round-trip, account isolation, out-of-order record retry, duplicate delivery, revoked consent/offline recovery, hardware and owner sign-off remain open.
- [ ] Continue to follow the PassBook CLAUDE.md rules: document requirements first, surgical changes only, reproduce defects with tests, and report only validation actually run.

**Artifact rule:** This review and follow-up work do not authorize any APK, Windows ZIP, installer, release or other build artifact. Keep work on `feature/complete-project-pendings`; do not merge to `main`.

## Repository review follow-up — Drive record lifecycle and sale recall (2026-11-22)

### Fixed in source; validation in progress

- [x] WPF Drive merge now defers a purchase when its non-empty `supplier_sync_id` cannot be resolved locally. It no longer imports that purchase with a silently missing supplier link.
- [x] WPF Drive merge now defers a sale return when its non-empty `party_sync_id` cannot be resolved locally.
- [x] WPF Drive merge now increments the deferred-record count when an expense or reminder has no stable `sync_id`; the snapshot therefore cannot be marked fully accepted after silently skipping that row.
- [x] Added focused unit tests for required-party-reference and missing-stable-ID predicates in `DriveSnapshotMergeAcceptanceTests.cs`.
- [x] GitHub Actions run #471 passed on commit `474a5a79a5d5148f05b2e01d64b158df9198798d`: WPF Release build 0 warnings/0 errors; 105 tests passed, 0 failed, 0 skipped. Run: https://github.com/magscacoffice/general_store_pos/actions/runs/45008110801.
- [ ] These are predicate/acceptance tests, not a substitute for a real Drive import retry test with disposable schema-v18 databases and an out-of-order parent.

### Recalled-sale revision protocol — implemented; automated validation in progress

- [x] Android and Windows recalled-sale edit paths now create monotonic per-sale revision markers in the existing `drive_sync_tombstones` table. Revision keys use `sale_sync_id|revision`; no base schema version change is required.
- [x] Both edit paths emit sale-scoped deletion markers for replaced `sale_items` and sale-generated `khata_transactions`. Keys use `sale_sync_id|record_sync_id`, so an old marker cannot delete another bill's records.
- [x] Android snapshot export already includes the tombstone collection; Windows snapshot export includes the same table. Replacement sale-generated Khata rows are linked to their bill by `sale_ledger` tombstone keys (`sale_sync_id|ledger_sync_id`); no new snapshot fields or SQLite columns are introduced. The Windows master importer applies only an accepted sale revision, reconciles stock and due-balance deltas, replaces sale items, and applies linked ledger deletions.
- [x] Windows-master snapshots now reconcile existing sales on Android. Android replaces sale details and item rows only when applying the authoritative master snapshot; local sales with returns or changed customer links are protected.
- [x] Windows keeps a per-sale revision high-water mark. Older snapshots cannot roll a sale back or reintroduce replaced sale items/ledger entries. Ledger rows from a stale or rejected sale revision are not imported. Same-revision divergent edits create a conflict that follows the Windows-master keep-local policy.
- [x] Added WPF and Flutter integration coverage for recalled-sale edit, item replacement, stock delta, Khata balance delta, ledger deletion, repeated snapshot delivery, stale snapshot replay, and same-revision concurrent edits. Latest Flutter run #134 passed 23/23 tests on Ubuntu and Windows; latest WPF run #492 passed 106/106 tests.
- [ ] Physical Android/Windows paired-device testing is still required for online/offline edits, real Drive upload/download, and a return created between snapshots.
- [ ] Test the complete business cases with quantity increases/decreases, product substitutions, discounts, cash/partial/credit, later receipts, returns, rollback, duplicate deliveries and simultaneous edits on actual disposable databases/devices.
- [ ] Until physical-device acceptance and the remaining business-case matrix pass, Drive sync remains a development/acceptance feature rather than production-accepted accounting synchronization. The owner-approved source flag remains unchanged.

## Validation update — Drive dependency deferral fix (2026-11-22)

- [x] WPF Release build succeeded with 0 warnings and 0 errors.
- [x] WPF test suite passed: 105 passed, 0 failed, 0 skipped.
- [x] GitHub Actions run #471 validated commit `474a5a79a5d5148f05b2e01d64b158df9198798d`: https://github.com/magscacoffice/general_store_pos/actions/runs/45008110801
- [ ] Real Drive retry tests for unresolved supplier/customer references and missing stable IDs remain pending; current tests cover the predicates and acceptance decision only.
- [ ] The separate recalled-sale update/deletion protocol blocker remains unresolved and must be addressed before production Drive sync acceptance.

## Recalled-sale revision protocol — implementation and validation (2026-11-22)

- [x] No SQLite schema-version bump was required; the protocol uses the existing `drive_sync_tombstones` table and keeps schema-v18 compatibility.
- [x] Windows WPF Release build succeeded with 0 warnings and 0 errors on Actions run #472 (commit `aec503cc8fff6bd20865af9c28f3692fff73bf25`).
- [x] WPF test suite passed: 106 passed, 0 failed, 0 skipped. The new recalled-sale integration test passed for first import and repeated delivery.
- [x] Flutter sync/invoice workflow passed on commit `21c6f24bb6cafb305fb8291ee4aeaabe1b04a8cb`; both Ubuntu and Windows jobs succeeded.
- [x] Final WPF validation on commit `70d3352a77736672c101c6e4c223d9c62b014f96` succeeded: Release build 0 warnings/0 errors and 106/106 tests passed. Actions run: https://github.com/magscacoffice/general_store_pos/actions/runs/45009832493.
- [x] Added a focused Flutter integration test for Android applying a Windows-master recalled-sale revision, replacing invoice items and Khata ledger rows, and replaying the same snapshot without duplicates. Actions run #128 passed 23/23 tests on both Ubuntu and Windows: https://github.com/magscacoffice/general_store_pos/actions/runs/45009965919.

## Sale-linked ledger reconciliation and stale revision guards (2026-11-22)

- [x] Android and Windows recalled-sale edit paths emit `sale_ledger` tombstone links for each replacement credit/receipt row. Importers use these links to gate ledger entries against the accepted sale revision. The schema-v2 snapshot shape and SQLite schema v18 remain unchanged.
- [x] WPF and Android importers use the tombstone links to prevent ledger rows from a rejected/stale sale revision from being imported; no unknown columns are passed to SQLite.
- [x] Android master-state import now compares incoming and local sale revision high-water marks. A stale master revision or same-revision divergent bill is not allowed to replace local sale items; customer-linked returns and customer changes remain protected.
- [x] Validation complete for sale-ledger tombstone association and WPF local marker assertions. Flutter run #134: 23/23 tests passed on Ubuntu and Windows; analyzer step succeeded with 10 info-level lint suggestions. WPF run #492: Release build 0 warnings/0 errors and 106/106 tests passed.

## Final validation — recalled-sale sync protocol (2026-11-22)

- [x] WPF Release build: 0 warnings, 0 errors.
- [x] WPF tests: 106 passed, 0 failed, 0 skipped. Actions run #492: https://github.com/magscacoffice/general_store_pos/actions/runs/45010853799
- [x] Flutter tests: 23 passed on Ubuntu and 23 passed on Windows. Actions run #134: https://github.com/magscacoffice/general_store_pos/actions/runs/45010828018
- [x] Flutter analyzer workflow step succeeded. It reported 10 info-level lint suggestions (not analyzer errors); these include existing formatting/deprecation suggestions outside the sale-revision logic.
- [x] Schema-v2 Drive envelope and SQLite schema-v18 remain unchanged; no new columns or build artifacts.
- [ ] Physical Android/Windows device tests and real Google Drive account round-trip remain pending. Do not mark Drive sync production-accepted until those tests and the business-case matrix are completed.

## Mandatory app versioning rule — Android and Windows (2026-11-22)

- [ ] **Every new Android or Windows app release/version must include an updated version number.** Do not prepare or publish a new app version while its version metadata still identifies the previous release.
- [ ] Before each Android release, update and verify the Flutter app version/build metadata (the `version:` value in `pubspec.yaml`, including its build number where applicable).
- [ ] Before each Windows release, update and verify the WPF application/package version metadata consistently (assembly, file and installer/package version fields that are used by the actual release workflow).
- [ ] Keep Android and Windows version numbers documented together in `PROJECT_UPDATE.md` for every coordinated release, clearly identifying each platform's version and build/release number. If only one platform is released, update and document that platform without falsely changing the other platform's release version.
- [ ] Follow the repository's existing versioning scheme; inspect the current configuration before choosing the next number. Increment versions for actual app releases, not for every source commit or documentation-only change.
- [ ] Verify the version shown in app/package metadata matches the version recorded in `PROJECT_UPDATE.md` and the release artifact/manifest before marking a release complete.


## Coordinated test release preparation (2026-11-22)

- [x] Android test release version bumped to **1.0.1+2** in `pubspec.yaml`.
- [x] Windows WPF test release metadata set to **1.0.1** (assembly/file version **1.0.1.0**, informational version **1.0.1-test**).
- [x] Windows CI workflow packages a self-contained unsigned x64 test ZIP after successful Release build and tests; artifact retention is 30 days.
- [ ] Android CI test-release workflow must build and upload an unsigned APK; signing/release-key setup remains separate.
- [ ] Dispatch the manual unsigned Windows installer validation workflow only for this explicitly authorized test release; production signing is not included.
- [ ] Verify both platform workflows on `main` after merge. This is an unsigned acceptance release only; it is not production approval.
- [ ] Physical Android/Windows and Google Drive acceptance remains pending.


### Test release workflow follow-up (2026-11-22)

- [x] Windows main-branch CI now compiles and uploads both the unsigned self-contained x64 ZIP and unsigned Inno Setup installer for version 1.0.1.0 after Release build/tests pass.
- [x] Android main-branch CI builds and uploads the unsigned APK for version 1.0.1+2 after Flutter tests pass.
- [ ] Verify the two GitHub Actions runs and download/inspect the resulting artifacts before calling the test release delivered.
- [ ] Old branch deletion remains pending; the available GitHub repository connection in this session does not expose a branch/ref deletion operation. Do not claim old branches were deleted.
- [ ] Production signing and physical device/Google Drive acceptance remain pending.
