# Khan Baba POS — Native WPF Client

This is the native Windows desktop client migration. Windows UI and Windows hardware work belong exclusively in this WPF project; Android remains Flutter. The retired Flutter Windows runner/build workflow must not be restored.

## Integrated implementation

- Dashboard-hosted cashier workspace with scanner-ready focus, exact barcode lookup (including the wholesale-price column), product suggestions, keyboard navigation, repeat-scan quantity increment, editable cart quantities, pending-bill switching and autosave.
- Printer & Invoice can be opened from the main navigation to select/save the preferred Windows printer, refresh queues and run a test print. Receipt output is fixed to the 80mm layout; user-facing margin/header/total tuning controls are intentionally removed.
- Walk-in and Khata customer types; Khata payment method remains separate and supports Cash/Credit/Partial. Legacy Wholesale customer rows are preserved and treated as Khata.
- Transactional sale posting, inventory CRUD/search (including wholesale price), purchase entry, stock movements and protected product deletion.
- Customer/supplier list, customer Khata ledger and receipt posting, sales history and invoice details.
- Sale returns/refunds, sales reports, expenses, reminders and profit/loss views.
- Windows printer queue discovery and preferred-printer persistence, fixed 80mm ESC/POS receipt builder, raw spooler output, test print, read-only draft preview and PDF save/open. New Sale provides separate Save Only (F10) and Save & Print (F9/Ctrl+P); Save & Print posts first and sends the final saved receipt directly to the available preferred queue.
- Existing SQLite v18 entity/schema foundation, read-only schema verifier, Windows data path/restore-pointer resolver and schema compatibility tests are retained from current main.
- Manual Backup & Restore uses verified SQLite backups, SHA-256 sidecars, schema-v18 validation and a staged restore file activated through an atomic `.active_database` pointer; the previous live database is never overwritten.
- Windows business data remains local-first. Firebase/Firestore business-data sync is not added.

## Google Drive sync migration status

The native WPF project contains the PKCE loopback OAuth flow, DPAPI-protected Windows token storage, Google Drive v3 transport, schema-v2 snapshot export/envelope validation, Windows-master manifest, transactional SQLite v18 reconciliation, stable party aliases, tombstones, processed-snapshot tracking, snapshot-scoped verified pre-merge backups, sync status UI and two-minute offline retry source. **Owner-approved Drive sync and device-snapshot imports are enabled in the current source.** WPF now uses the owner-created Windows Desktop OAuth Client ID (`707319476515-vtdi3s5vn0tudh3ihnppco14kkrgtk78.apps.googleusercontent.com`), PKCE, and a token cache scoped to that client. Installed-app requests do not send a client secret; a stale `GOOGLE_WINDOWS_CLIENT_SECRET` is not required. Conflicting Windows stock, price and Khata values are automatically resolved in favour of Windows Master; Android-created records and non-conflicting changes continue through the merge path. Before every remote import, the local pre-merge backup must pass SHA-256, schema and SQLite integrity verification. Disconnect removes only this Windows user's local DPAPI credentials; it does not revoke the shared Google Cloud project's grant or break Android authorization. Automated protocol and OAuth request-construction tests are included, but real Google consent/refresh, end-to-end Android/Windows multi-device round-trip, update/delete identity parity and target-PC acceptance remain pending. Use only disposable database copies until those gates pass.

## Build and test

On Windows with the .NET 10 SDK:

```powershell
dotnet restore desktop-wpf/KhanBabaPos.Wpf.csproj
dotnet build desktop-wpf/KhanBabaPos.Wpf.csproj --configuration Release
dotnet test desktop-wpf.Tests/KhanBabaPos.Wpf.Tests.csproj --configuration Release
```

Use only a verified disposable copy of a real schema-v18 database for integration testing. Never test against the live store database. Do not use EF migrations, `EnsureCreated`, or automatic empty database creation.

## Still required before production cutover

The integrated .NET 10 Release build and current SQLite v18 schema tests pass in GitHub Actions (latest WPF validation run #254). WPF Khata supports full-ledger copy/print-to-PDF and a separate date-range item statement including returns; it uses the Unicode-capable Windows print dialog. The disposable-database backup/restore regression test passed in WPF Actions run #169. WPF Khata sale-posting integration tests cover partial/cash receipts, same-account ledger balances, stock deduction, percentage discounts and unsupported customer-type rejection. Backup restore failure-path testing also confirms a bad SHA-256 sidecar cannot change the active pointer or current database (Actions #186). WPF purchase, sale-return and Khata receipt integration tests pass for stock/cost changes, damaged/saleable returns, account adjustments and overpayment rejection (Actions #198). Sales-report and profit/loss calculations also pass against disposable schema-v18 data with discounts, returns, purchases and expenses (Actions #205). Android Flutter Wholesale parity, broader disposable-database transaction tests, Windows runtime/visual acceptance, Google Drive sync/authentication/role parity, and physical SpeedX SP60D / Black Copper BC-86AC hardware acceptance remain pending. A successful CI build does not complete those checks. No release/package should be produced until the project tracker is complete and owner acceptance is recorded.
