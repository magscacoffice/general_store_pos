# Khan Baba POS — Native WPF Client

This is the isolated native Windows client migration. Windows UI and Windows release work belong exclusively in this WPF project; Flutter remains the Android client. The retired Flutter Windows runner/build workflow must not be restored.

## Current implementation status

- Entity models and explicit column mappings cover all 17 SQLite v18 tables.
- EF Core SQLite mappings include the known unique indexes and legacy defaults.
- The data-folder resolver preserves the existing `%LOCALAPPDATA%\\KhanBabaPOS\\Data` location and validates the staged `.active_database` pointer.
- The schema verifier opens the existing database read-only and checks schema version, table/column presence, primary keys, required NOT NULL/default constraints, required unique constraints, SQLite quick-check and foreign-key integrity. It never migrates or writes to the database.
- No EF migrations, `EnsureCreated`, schema upgrades, or automatic empty database creation are used.
- The WPF window is still a bootstrap placeholder. Cashier and operational workflows, transaction services, parity tests, and Windows acceptance are not complete.

## Safe development

Build on Windows with the .NET 10 SDK:

```powershell
dotnet restore desktop-wpf/KhanBabaPos.Wpf.csproj
dotnet build desktop-wpf/KhanBabaPos.Wpf.csproj -c Release
```

Use a verified copy of a real schema-v18 database for development. Never test against the live store database. Do not mark a feature complete until it builds, passes automated tests, and is verified against the Flutter behaviour and schema.
