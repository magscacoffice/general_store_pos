# Khan Baba POS — Native WPF Client

This is the native Windows desktop client migration. Windows UI and Windows hardware work belong exclusively in this WPF project; Android remains Flutter. The retired Flutter Windows runner/build workflow must not be restored.

## Integrated implementation

- Dashboard-hosted cashier workspace with scanner-ready focus, exact barcode lookup (including the wholesale-price column), product suggestions, keyboard navigation, repeat-scan quantity increment, editable cart quantities, pending-bill switching and autosave.
- Separate Walk-in, Khata and Wholesale customer types; Wholesale accounts support Cash/Credit/Partial payments, saved wholesale-rate defaults and editable per-item rates with purchase-cost validation.
- Transactional sale posting, inventory CRUD/search (including wholesale price), purchase entry, stock movements and protected product deletion.
- Customer/supplier list, customer Khata ledger and receipt posting, sales history and invoice details.
- Sale returns/refunds, sales reports, expenses, reminders and profit/loss views.
- Windows printer queue discovery and preferred-printer settings, 80mm ESC/POS receipt builder, raw spooler output, test print, invoice/receipt preview and PDF save/open.
- Existing SQLite v18 entity/schema foundation, read-only schema verifier, Windows data path/restore-pointer resolver and schema compatibility tests are retained from current main.
- Manual Backup & Restore uses verified SQLite backups, SHA-256 sidecars, schema-v18 validation and a staged restore file activated through an atomic `.active_database` pointer; the previous live database is never overwritten.
- Windows business data remains local-first. Firebase/Firestore business-data sync is not added.

## Google Drive sync migration status

The native WPF project now contains the PKCE loopback OAuth flow, DPAPI-protected Windows token storage, Google Drive v3 file transport and a schema-v2 SQLite snapshot exporter. The exporter’s disposable schema-v18 integration test passes in the current 14-test WPF suite. This is foundation work only: Windows-master reconciliation, conflict/alias/tombstone processing, processed-snapshot manifests, periodic/offline sync, WPF controls and owner acceptance remain pending. Do not treat Drive sync as operational or connect a production store until those items are implemented and verified.

## Build and test

On Windows with the .NET 10 SDK:

```powershell
dotnet restore desktop-wpf/KhanBabaPos.Wpf.csproj
dotnet build desktop-wpf/KhanBabaPos.Wpf.csproj --configuration Release
dotnet test desktop-wpf.Tests/KhanBabaPos.Wpf.Tests.csproj --configuration Release
```

Use only a verified disposable copy of a real schema-v18 database for integration testing. Never test against the live store database. Do not use EF migrations, `EnsureCreated`, or automatic empty database creation.

## Still required before production cutover

The integrated .NET 10 Release build and current SQLite v18 schema tests pass in GitHub Actions (latest WPF validation run #254). WPF Khata supports full-ledger copy/print-to-PDF and a separate date-range item statement including returns; it uses the Unicode-capable Windows print dialog. The disposable-database backup/restore regression test passed in WPF Actions run #169. WPF Wholesale sale-posting integration tests also pass for partial/cash receipts, same-account ledger balances, stock deduction, percentage discounts and account-type mismatch rollback (Actions #181). Backup restore failure-path testing also confirms a bad SHA-256 sidecar cannot change the active pointer or current database (Actions #186). WPF purchase, sale-return and Khata receipt integration tests pass for stock/cost changes, damaged/saleable returns, account adjustments and overpayment rejection (Actions #198). Sales-report and profit/loss calculations also pass against disposable schema-v18 data with discounts, returns, purchases and expenses (Actions #205). Android Flutter Wholesale parity, broader disposable-database transaction tests, Windows runtime/visual acceptance, Google Drive sync/authentication/role parity, and physical SpeedX SP60D / Black Copper BC-86AC hardware acceptance remain pending. A successful CI build does not complete those checks. No release/package should be produced until the project tracker is complete and owner acceptance is recorded.
