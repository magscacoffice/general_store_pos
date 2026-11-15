# Khan Baba POS — Native WPF Client

Isolated Windows migration using WPF only (no WinUI 3). Flutter Android and legacy Flutter Windows sources remain intact.

Phase 1 adds entity models for all 17 current SQLite v18 tables, EF Core SQLite mappings, the Windows data-folder and staged-restore-pointer resolver, and a read-only schema verifier. No EF migrations, EnsureCreated, schema upgrades or automatic empty database creation are used. The bootstrap window is a placeholder; cashier and operational workflows are not yet implemented.

Build on Windows with .NET 10 SDK: `dotnet restore desktop-wpf/KhanBabaPos.Wpf.csproj`, then `dotnet build desktop-wpf/KhanBabaPos.Wpf.csproj -c Release`. Use a verified database copy for development.
