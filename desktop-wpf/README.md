# Khan Baba POS — Native WPF Client

Isolated Windows migration using WPF only (no WinUI 3). Android Flutter remains unchanged and is the supported mobile client.

## Current implementation

- Existing SQLite v18 schema mapping and read-only schema verifier.
- Windows user-data path and staged restore-pointer resolver.
- Native WPF cashier shell with a dashboard-hosted New Sale workspace.
- Scanner/search input is focused on startup and after product addition.
- Product lookup uses parameterized, read-only SQLite queries.
- Exact barcode scans add a product; repeat scans increment the same cart line.
- Product name suggestions support keyboard selection and Enter.
- Inventory, bill contents and subtotal are read-only/in-memory in this phase; checkout, discounts, payments, stock deduction, pending-bill persistence, Khata posting, printer, sync and other operational modules are deliberately not wired yet.

## Build

On Windows with .NET 10 SDK:

```powershell
dotnet restore desktop-wpf/KhanBabaPos.Wpf.csproj
dotnet build desktop-wpf/KhanBabaPos.Wpf.csproj -c Release
```

Use a verified copy of the real database for development. This phase does not create or migrate a database and does not write business data.
