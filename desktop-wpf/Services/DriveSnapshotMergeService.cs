using System.Globalization;
using System.Text.Json;
using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;

namespace KhanBabaPos.Wpf.Services;

/// <summary>
/// Transactional Windows-master import for the Android schema-v2 Drive snapshot.
/// Local integer IDs are rebuilt from stable sync IDs/barcodes; append-only
/// transactions are idempotent; mutable stock/accounts require explicit review.
/// </summary>
public sealed class DriveSnapshotMergeService
{
    public static bool IsSnapshotFullyAccepted(int pendingConflicts, int deferredRecords) =>
        pendingConflicts == 0 && deferredRecords == 0;

    public static bool IsMissingStableId(string? syncId) =>
        string.IsNullOrWhiteSpace(syncId);

    public static bool IsMissingRequiredPartyReference(string? remotePartySyncId, long? localPartyId) =>
        !string.IsNullOrWhiteSpace(remotePartySyncId) && localPartyId is null;

    private static readonly string[] ProductFields =
        ["name", "price", "purchasePrice", "wholesalePrice", "damaged_quantity", "quantity", "is_active", "stock_unit"];
    private static readonly string[] PartyFields = ["name", "phone", "type", "customer_type", "balance"];
    private static readonly string[] SaleFields = ["total_amount", "discount", "final_amount", "payment_type",
        "customer_type", "received_amount", "balance_due", "date", "salesman_uid", "salesman_name",
        "customer_sync_id"];

    public async Task<DriveMergeResult> MergeAsync(
        ValidatedDriveSnapshot snapshot,
        string sourceDeviceId,
        string databasePath,
        bool applyMasterState = false,
        bool detectConflicts = true,
        CancellationToken cancellationToken = default,
        bool autoResolveConflictsKeepWindows = false)
    {
        AccessService.RequireCurrentAdmin();
        ArgumentNullException.ThrowIfNull(snapshot);
        if (string.IsNullOrWhiteSpace(sourceDeviceId)) throw new ArgumentException("Source device ID is required.", nameof(sourceDeviceId));
        await PosDatabaseSchemaVerifier.VerifyAsync(databasePath, cancellationToken);
        await DatabaseSafetyService.EnsureVerifiedBackupAsync(databasePath, cancellationToken);

        await using var db = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = databasePath, Mode = SqliteOpenMode.ReadWrite, Pooling = false
        }.ToString());
        await db.OpenAsync(cancellationToken);
        using var tx = db.BeginTransaction();

        try
        {
            await using (var supersede = db.CreateCommand())
            {
                supersede.Transaction = tx;
                supersede.CommandText = "UPDATE drive_sync_conflicts SET status='superseded' WHERE source_device_id=$device AND snapshot_hash<>$hash AND status='pending';";
                supersede.Parameters.AddWithValue("$device", sourceDeviceId);
                supersede.Parameters.AddWithValue("$hash", snapshot.SnapshotHash);
                await supersede.ExecuteNonQueryAsync(cancellationToken);
            }

            var collections = new Dictionary<string, List<Dictionary<string, object?>>>(StringComparer.Ordinal);
            foreach (var name in new[] { "products", "parties", "sales", "sale_items", "purchases", "khata_transactions", "expenses", "reminders", "sale_returns", "sale_return_items", "tombstones" })
                collections[name] = ReadCollection(snapshot.Data, name);

            var partyIds = new Dictionary<string, long>(StringComparer.Ordinal);
            var created = 0;
            var updated = 0;
            var conflicts = 0;
            var skipped = 0;
            var deferredRecords = 0;

            async Task AddConflictAsync(string type, string key, Dictionary<string, object?> local, Dictionary<string, object?> remote)
            {
                await using (var existing = db.CreateCommand())
                {
                    existing.Transaction = tx;
                    existing.CommandText = "SELECT status FROM drive_sync_conflicts WHERE source_device_id=$device AND snapshot_hash=$hash AND entity_type=$type AND entity_key=$key LIMIT 1;";
                    Add(existing, ("$device", sourceDeviceId), ("$hash", snapshot.SnapshotHash), ("$type", type), ("$key", key));
                    var status = Convert.ToString(await existing.ExecuteScalarAsync(cancellationToken), CultureInfo.InvariantCulture);
                    if (status == "resolved") return;
                }
                await using (var prior = db.CreateCommand())
                {
                    prior.Transaction = tx;
                    prior.CommandText = "SELECT remote_payload FROM drive_sync_conflicts WHERE source_device_id=$device AND entity_type=$type AND entity_key=$key AND status='resolved' AND resolution='keep_local' ORDER BY id DESC LIMIT 1;";
                    Add(prior, ("$device", sourceDeviceId), ("$type", type), ("$key", key));
                    var priorJson = Convert.ToString(await prior.ExecuteScalarAsync(cancellationToken), CultureInfo.InvariantCulture);
                    if (priorJson == JsonSerializer.Serialize(remote)) return;
                }
                await using var insert = db.CreateCommand();
                insert.Transaction = tx;
                insert.CommandText = """
                    INSERT OR REPLACE INTO drive_sync_conflicts
                    (source_device_id,snapshot_hash,entity_type,entity_key,local_payload,remote_payload,status,resolution,resolved_at,created_at)
                    VALUES($device,$hash,$type,$key,$local,$remote,$status,$resolution,$resolved,$created);
                    """;
                Add(insert, ("$device", sourceDeviceId), ("$hash", snapshot.SnapshotHash),
                    ("$type", type), ("$key", key), ("$local", JsonSerializer.Serialize(local)),
                    ("$remote", JsonSerializer.Serialize(remote)),
                    ("$status", autoResolveConflictsKeepWindows ? "resolved" : "pending"),
                    ("$resolution", autoResolveConflictsKeepWindows ? "keep_local" : DBNull.Value),
                    ("$resolved", autoResolveConflictsKeepWindows ? DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture) : DBNull.Value),
                    ("$created", DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture)));
                await insert.ExecuteNonQueryAsync(cancellationToken);
                conflicts++;
            }

            async Task<long?> PartyIdForAsync(string? remoteSyncId)
            {
                if (string.IsNullOrWhiteSpace(remoteSyncId)) return null;
                if (partyIds.TryGetValue(remoteSyncId, out var known)) return known;
                var direct = await FindIdAsync(db, tx, "parties", "sync_id", remoteSyncId, cancellationToken);
                if (direct is not null) return direct;
                await using var alias = db.CreateCommand();
                alias.Transaction = tx;
                alias.CommandText = "SELECT local_sync_id FROM drive_sync_aliases WHERE source_device_id=$device AND remote_sync_id=$remote LIMIT 1;";
                Add(alias, ("$device", sourceDeviceId), ("$remote", remoteSyncId));
                var localSyncId = Convert.ToString(await alias.ExecuteScalarAsync(cancellationToken), CultureInfo.InvariantCulture);
                return string.IsNullOrWhiteSpace(localSyncId) ? null :
                    await FindIdAsync(db, tx, "parties", "sync_id", localSyncId, cancellationToken);
            }

            async Task<string?> CanonicalPartySyncIdAsync(string? remoteSyncId)
            {
                var id = await PartyIdForAsync(remoteSyncId);
                return id is null ? null : await ScalarStringAsync(db, tx, "SELECT sync_id FROM parties WHERE id=$id LIMIT 1;", cancellationToken, ("$id", id.Value));
            }

            // Products: barcode is the stable key. A device cannot silently
            // overwrite the Windows master's current stock or pricing.
            foreach (var remote in collections["products"])
            {
                var barcode = Text(remote, "barcode").Trim();
                if (barcode.Length == 0) { skipped++; deferredRecords++; continue; }
                var local = await ReadOneAsync(db, tx, "products", "barcode", barcode, cancellationToken);
                var deleted = await ExistsAsync(db, tx, "drive_sync_tombstones", "entity_type='product' AND entity_key=$key", cancellationToken, ("$key", barcode));
                if (deleted && !applyMasterState)
                {
                    var ignored = await ExistsAsync(db, tx, "drive_sync_ignored_tombstones", "source_device_id=$device AND entity_type='product_readd' AND entity_key=$key", cancellationToken, ("$device", sourceDeviceId), ("$key", barcode));
                    if (!ignored && detectConflicts)
                    {
                        var readd = ProductValues(remote, barcode);
                        readd["_has_related_records"] =
                            await ExistsAsync(db, tx, "sale_items", "barcode=$key", cancellationToken, ("$key", barcode)) ||
                            await ExistsAsync(db, tx, "purchases", "barcode=$key", cancellationToken, ("$key", barcode));
                        await AddConflictAsync("product_readd", barcode,
                            new Dictionary<string, object?> { ["_deleted"] = true, ["barcode"] = barcode }, readd);
                    }
                    skipped++;
                    continue;
                }

                await DeleteAsync(db, tx, "drive_sync_tombstones", "entity_type='product' AND entity_key=$key", cancellationToken, ("$key", barcode));
                await DeleteAsync(db, tx, "drive_sync_ignored_tombstones", "entity_type='product' AND entity_key=$key", cancellationToken, ("$key", barcode));
                var values = ProductValues(remote, barcode);
                if (local is null)
                {
                    await InsertRowAsync(db, tx, "products", values, cancellationToken);
                    created++;
                }
                else if (applyMasterState)
                {
                    await UpdateRowAsync(db, tx, "products", values, "barcode=$key", cancellationToken, ("$key", barcode));
                    updated++;
                }
                else if (Different(local, values, ProductFields) && detectConflicts)
                {
                    local.Remove("id");
                    await AddConflictAsync("product", barcode, local, values);
                }
            }

            // Parties use stable sync IDs plus source-specific aliases. A unique
            // name+phone+type match repairs older duplicate identity records.
            foreach (var remote in collections["parties"])
            {
                var syncId = Text(remote, "sync_id").Trim();
                if (syncId.Length == 0) { skipped++; deferredRecords++; continue; }
                var aliasLocal = await ScalarStringAsync(db, tx,
                    "SELECT local_sync_id FROM drive_sync_aliases WHERE source_device_id=$device AND remote_sync_id=$remote LIMIT 1;",
                    cancellationToken, ("$device", sourceDeviceId), ("$remote", syncId));
                var tombstoned = await ExistsAsync(db, tx, "drive_sync_tombstones",
                    "entity_type='party' AND entity_key IN ($sync,$alias)", cancellationToken,
                    ("$sync", syncId), ("$alias", aliasLocal ?? syncId));
                if (tombstoned && !applyMasterState)
                {
                    var ignored = await ExistsAsync(db, tx, "drive_sync_ignored_tombstones",
                        "source_device_id=$device AND entity_type='party_readd' AND entity_key=$key",
                        cancellationToken, ("$device", sourceDeviceId), ("$key", syncId));
                    if (!ignored && detectConflicts)
                    {
                        var payload = new Dictionary<string, object?>(remote, StringComparer.Ordinal);
                        payload.Remove("id");
                        payload["_has_related_records"] =
                            await ExistsAsync(db, tx, "sales", "customer_sync_id=$key", cancellationToken, ("$key", syncId)) ||
                            await ExistsAsync(db, tx, "khata_transactions", "party_sync_id=$key", cancellationToken, ("$key", syncId)) ||
                            await ExistsAsync(db, tx, "purchases", "supplier_sync_id=$key", cancellationToken, ("$key", syncId)) ||
                            await ExistsAsync(db, tx, "sale_returns", "party_sync_id=$key", cancellationToken, ("$key", syncId));
                        await AddConflictAsync("party_readd", syncId,
                            new Dictionary<string, object?> { ["_deleted"] = true, ["sync_id"] = syncId }, payload);
                    }
                    skipped++;
                    continue;
                }

                var local = await ReadOneAsync(db, tx, "parties", "sync_id", syncId, cancellationToken);
                if (local is null && aliasLocal is not null)
                    local = await ReadOneAsync(db, tx, "parties", "sync_id", aliasLocal, cancellationToken);
                if (local is null)
                {
                    var name = Text(remote, "name").Trim().ToLowerInvariant();
                    var phone = Digits(Text(remote, "phone"));
                    if (phone.Length > 0)
                    {
                        var candidates = await ReadManyAsync(db, tx, "SELECT * FROM parties WHERE lower(trim(name))=$name AND type=$type;", cancellationToken,
                            ("$name", name), ("$type", Text(remote, "type")));
                        var exact = candidates.Where(x => Digits(Text(x, "phone")) == phone).ToList();
                        if (exact.Count == 1) local = exact[0];
                    }
                }

                var partyValues = new Dictionary<string, object?>(StringComparer.Ordinal)
                {
                    ["name"] = Text(remote, "name"),
                    ["phone"] = Value(remote, "phone"),
                    ["type"] = Text(remote, "type"),
                    ["customer_type"] = Value(remote, "customer_type") ?? "Khata",
                    ["balance"] = Number(remote, "balance"),
                    ["sync_id"] = syncId
                };
                if (local is null)
                {
                    var id = await InsertRowAsync(db, tx, "parties", partyValues, cancellationToken);
                    partyIds[syncId] = id;
                    created++;
                }
                else
                {
                    var localId = Convert.ToInt64(local["id"], CultureInfo.InvariantCulture);
                    var localSyncId = Text(local, "sync_id");
                    if (string.IsNullOrWhiteSpace(localSyncId)) localSyncId = syncId;
                    partyIds[syncId] = localId;
                    await DeleteAsync(db, tx, "drive_sync_tombstones",
                        "entity_type='party' AND entity_key IN ($remote,$local)", cancellationToken,
                        ("$remote", syncId), ("$local", localSyncId));
                    await DeleteAsync(db, tx, "drive_sync_ignored_tombstones",
                        "source_device_id=$device AND entity_type='party' AND entity_key=$key", cancellationToken,
                        ("$device", sourceDeviceId), ("$key", syncId));
                    if (!string.Equals(localSyncId, syncId, StringComparison.Ordinal))
                    {
                        await ExecuteAsync(db, tx,
                            "INSERT OR REPLACE INTO drive_sync_aliases(source_device_id,remote_sync_id,local_sync_id) VALUES($device,$remote,$local);",
                            cancellationToken, ("$device", sourceDeviceId), ("$remote", syncId), ("$local", localSyncId));
                    }
                    var compare = new Dictionary<string, object?>(partyValues, StringComparer.Ordinal);
                    compare.Remove("sync_id");
                    if (applyMasterState)
                    {
                        compare["sync_id"] = localSyncId;
                        await UpdateRowAsync(db, tx, "parties", compare, "id=$id", cancellationToken, ("$id", localId));
                        updated++;
                    }
                    else if (Different(local, compare, PartyFields) && detectConflicts)
                    {
                        local.Remove("id");
                        compare.Remove("sync_id");
                        await AddConflictAsync("party", localSyncId, local, compare);
                    }
                }
            }

            // Sales are append-only until a sale_revision marker explicitly
            // announces a recalled-bill edit. Revisions are monotonic per stable
            // sale ID; equal/older revisions never replace Windows-master state.
            var remoteSaleRevisions = new Dictionary<string, long>(StringComparer.Ordinal);
            var remoteSaleLedgerParents = new Dictionary<string, string>(StringComparer.Ordinal);
            var appliedSaleRevisions = new HashSet<string>(StringComparer.Ordinal);
            var allowedSaleItemImports = new HashSet<string>(StringComparer.Ordinal);
            foreach (var marker in collections["tombstones"])
            {
                var type = Text(marker, "entity_type");
                var key = Text(marker, "entity_key");
                var split = key.LastIndexOf('|');
                if (split <= 0) continue;
                var saleKey = key[..split];
                var recordKey = key[(split + 1)..];
                if (type == "sale_revision")
                {
                    if (!long.TryParse(recordKey, NumberStyles.None, CultureInfo.InvariantCulture, out var revision) || revision <= 0) continue;
                    remoteSaleRevisions[saleKey] = Math.Max(remoteSaleRevisions.GetValueOrDefault(saleKey), revision);
                }
                else if (type == "sale_ledger" && recordKey.Length > 0)
                    remoteSaleLedgerParents[recordKey] = saleKey;
            }

            foreach (var remote in collections["sales"])
            {
                var syncId = Text(remote, "sync_id");
                if (syncId.Length == 0) { skipped++; deferredRecords++; continue; }
                var existingSaleId = await FindIdAsync(db, tx, "sales", "sync_id", syncId, cancellationToken);
                var remoteParty = NullableText(remote, "customer_sync_id");
                var partyId = await PartyIdForAsync(remoteParty);
                if (remoteParty is not null && partyId is null) { skipped++; deferredRecords++; continue; }
                var canonicalParty = await CanonicalPartySyncIdAsync(remoteParty);
                var values = Copy(remote);
                values.Remove("id"); values.Remove("customer_id");
                values["sync_id"] = syncId;
                values["customer_sync_id"] = canonicalParty;
                values["customer_id"] = partyId;

                if (existingSaleId is null)
                {
                    await InsertRowAsync(db, tx, "sales", values, cancellationToken); created++;
                    allowedSaleItemImports.Add(syncId);
                    continue;
                }

                var remoteRevision = remoteSaleRevisions.GetValueOrDefault(syncId);
                var localRevision = await GetSaleRevisionAsync(db, tx, syncId, cancellationToken);
                if (remoteRevision < localRevision) continue;

                var localSale = await ReadOneAsync(db, tx, "sales", "id", existingSaleId.Value, cancellationToken);
                if (localSale is null) { skipped++; deferredRecords++; continue; }
                if (remoteRevision == 0 && localRevision == 0)
                {
                    allowedSaleItemImports.Add(syncId); // legacy append-only sale without revision markers
                    continue;
                }
                if (remoteRevision <= 0) continue;
                if (remoteRevision == localRevision)
                {
                    var comparableLocal = new Dictionary<string, object?>(localSale, StringComparer.Ordinal);
                    comparableLocal.Remove("id");
                    if (Different(comparableLocal, values, SaleFields))
                        await AddConflictAsync("sale_revision", syncId, comparableLocal, values);
                    else
                        allowedSaleItemImports.Add(syncId); // permits retry of a deferred item in this accepted revision
                    continue;
                }
                var localCustomerId = localSale.TryGetValue("customer_id", out var localCustomerValue) &&
                    localCustomerValue is not null ? Convert.ToInt64(localCustomerValue, CultureInfo.InvariantCulture) : (long?)null;
                if (localCustomerId != partyId)
                {
                    await AddConflictAsync("sale_revision", syncId, localSale, values);
                    skipped++;
                    continue;
                }

                var hasReturns = await ExistsAsync(db, tx, "sale_returns", "sale_id=$sale",
                    cancellationToken, ("$sale", existingSaleId.Value));
                if (hasReturns)
                {
                    await AddConflictAsync("sale_revision", syncId, localSale, values);
                    skipped++;
                    continue;
                }

                var remoteItems = collections["sale_items"]
                    .Where(x => Text(x, "sale_sync_id") == syncId).ToList();
                if (remoteItems.Count == 0) { skipped++; deferredRecords++; continue; }

                var preparedRemoteItems = new List<(Dictionary<string, object?> Row, long ProductId, long Quantity)>();
                var stockDeltas = new Dictionary<long, long>();
                var invalidOldItems = false;
                await using (var oldItems = db.CreateCommand())
                {
                    oldItems.Transaction = tx;
                    oldItems.CommandText = "SELECT product_id,quantity FROM sale_items WHERE sale_id=$sale;";
                    oldItems.Parameters.AddWithValue("$sale", existingSaleId.Value);
                    await using var reader = await oldItems.ExecuteReaderAsync(cancellationToken);
                    while (await reader.ReadAsync(cancellationToken))
                    {
                        if (reader.IsDBNull(0)) { invalidOldItems = true; break; }
                        var productId = reader.GetInt64(0);
                        stockDeltas[productId] = stockDeltas.GetValueOrDefault(productId) + reader.GetInt64(1);
                    }
                }
                if (invalidOldItems) { skipped++; deferredRecords++; continue; }

                var missingProduct = false;
                foreach (var item in remoteItems)
                {
                    var barcode = Text(item, "barcode");
                    var productId = await FindIdAsync(db, tx, "products", "barcode", barcode, cancellationToken);
                    if (productId is null) { missingProduct = true; break; }
                    var quantity = Number(item, "quantity");
                    if (quantity <= 0 || quantity != Math.Truncate(quantity)) { missingProduct = true; break; }
                    stockDeltas[productId.Value] = stockDeltas.GetValueOrDefault(productId.Value) - (long)quantity;
                    preparedRemoteItems.Add((item, productId.Value, (long)quantity));
                }
                if (missingProduct) { skipped++; deferredRecords++; continue; }

                // Validate every stock delta before writing any of them so a
                // failed line cannot leave a partially adjusted inventory.
                foreach (var (productId, delta) in stockDeltas)
                {
                    await using var checkStock = db.CreateCommand();
                    checkStock.Transaction = tx;
                    checkStock.CommandText = "SELECT quantity FROM products WHERE id=$id LIMIT 1;";
                    checkStock.Parameters.AddWithValue("$id", productId);
                    var quantity = await checkStock.ExecuteScalarAsync(cancellationToken);
                    if (quantity is null || quantity is DBNull ||
                        Convert.ToInt64(quantity, CultureInfo.InvariantCulture) + delta < 0)
                    {
                        missingProduct = true;
                        break;
                    }
                }
                if (missingProduct) { skipped++; deferredRecords++; continue; }
                foreach (var (productId, delta) in stockDeltas)
                    await ExecuteAsync(db, tx, "UPDATE products SET quantity=quantity+$delta WHERE id=$id;",
                        cancellationToken, ("$delta", delta), ("$id", productId));

                if (localCustomerId is not null)
                {
                    var oldDue = Number(localSale, "balance_due");
                    var newDue = Number(values, "balance_due");
                    await ExecuteAsync(db, tx,
                        "UPDATE parties SET balance=COALESCE(balance,0)-$oldDue+$newDue WHERE id=$id;",
                        cancellationToken, ("$oldDue", oldDue), ("$newDue", newDue), ("$id", localCustomerId.Value));
                }

                await UpdateRowAsync(db, tx, "sales", values, "id=$id", cancellationToken,
                    ("$id", existingSaleId.Value));
                await DeleteAsync(db, tx, "sale_items", "sale_id=$sale", cancellationToken,
                    ("$sale", existingSaleId.Value));
                await RecordTombstoneAsync(db, tx, "sale_revision", $"{syncId}|{remoteRevision}",
                    sourceDeviceId, cancellationToken);
                appliedSaleRevisions.Add(syncId);
                allowedSaleItemImports.Add(syncId);
                updated++;
            }

            foreach (var remote in collections["sale_items"])
            {
                var syncId = Text(remote, "sync_id");
                if (syncId.Length == 0) { skipped++; deferredRecords++; continue; }
                var parentSaleSyncId = Text(remote, "sale_sync_id");
                if (!allowedSaleItemImports.Contains(parentSaleSyncId)) continue;
                if (await FindIdAsync(db, tx, "sale_items", "sync_id", syncId, cancellationToken) is not null) continue;
                var saleId = await FindIdAsync(db, tx, "sales", "sync_id", parentSaleSyncId, cancellationToken);
                if (saleId is null) { skipped++; deferredRecords++; continue; }
                var productId = await FindIdAsync(db, tx, "products", "barcode", Text(remote, "barcode"), cancellationToken);
                if (productId is null) { skipped++; deferredRecords++; continue; }
                var values = Copy(remote);
                values.Remove("id"); values.Remove("sale_id"); values.Remove("product_id");
                values["sync_id"] = syncId; values["sale_id"] = saleId; values["product_id"] = productId;
                await InsertRowAsync(db, tx, "sale_items", values, cancellationToken); created++;
            }

            foreach (var remote in collections["purchases"])
            {
                var syncId = Text(remote, "sync_id");
                if (syncId.Length == 0) { skipped++; deferredRecords++; continue; }
                if (await FindIdAsync(db, tx, "purchases", "sync_id", syncId, cancellationToken) is not null) continue;
                var productId = await FindIdAsync(db, tx, "products", "barcode", Text(remote, "barcode"), cancellationToken);
                if (productId is null) { skipped++; deferredRecords++; continue; }
                var remoteSupplier = NullableText(remote, "supplier_sync_id");
                var supplierId = await PartyIdForAsync(remoteSupplier);
                if (IsMissingRequiredPartyReference(remoteSupplier, supplierId))
                {
                    skipped++; deferredRecords++;
                    continue;
                }
                var values = Copy(remote);
                values.Remove("id"); values.Remove("product_id"); values.Remove("supplier_id");
                values["sync_id"] = syncId; values["product_id"] = productId; values["supplier_id"] = supplierId;
                values["supplier_sync_id"] = await CanonicalPartySyncIdAsync(remoteSupplier);
                await InsertRowAsync(db, tx, "purchases", values, cancellationToken); created++;
            }

            foreach (var remote in collections["khata_transactions"])
            {
                var syncId = Text(remote, "sync_id");
                if (syncId.Length == 0) { skipped++; deferredRecords++; continue; }
                var wasDeletedBySaleRevision = await ExistsAsync(db, tx, "drive_sync_tombstones",
                    "entity_type='khata_transaction' AND instr(entity_key,'|')>0 AND substr(entity_key,instr(entity_key,'|')+1)=$key",
                    cancellationToken, ("$key", syncId));
                if (wasDeletedBySaleRevision) continue;
                var parentSaleSyncId = remoteSaleLedgerParents.GetValueOrDefault(syncId);
                if (parentSaleSyncId is not null && !allowedSaleItemImports.Contains(parentSaleSyncId))
                    continue; // never import ledger rows for a stale or rejected sale revision
                if (await FindIdAsync(db, tx, "khata_transactions", "sync_id", syncId, cancellationToken) is not null) continue;
                var remoteParty = Text(remote, "party_sync_id");
                var partyId = await PartyIdForAsync(remoteParty);
                if (partyId is null) { skipped++; deferredRecords++; continue; }
                var values = Copy(remote);
                values.Remove("id"); values.Remove("party_id"); values.Remove("sale_sync_id");
                values["sync_id"] = syncId; values["party_id"] = partyId;
                values["party_sync_id"] = await CanonicalPartySyncIdAsync(remoteParty);
                await InsertRowAsync(db, tx, "khata_transactions", values, cancellationToken); created++;
            }

            foreach (var table in new[] { "expenses", "reminders" })
                foreach (var remote in collections[table])
                {
                    var syncId = Text(remote, "sync_id");
                    if (IsMissingStableId(syncId)) { skipped++; deferredRecords++; continue; }
                    if (await FindIdAsync(db, tx, table, "sync_id", syncId, cancellationToken) is not null) continue;
                    var values = Copy(remote); values.Remove("id"); values["sync_id"] = syncId;
                    await InsertRowAsync(db, tx, table, values, cancellationToken); created++;
                }

            foreach (var remote in collections["sale_returns"])
            {
                var syncId = Text(remote, "sync_id");
                if (syncId.Length == 0) { skipped++; deferredRecords++; continue; }
                if (await FindIdAsync(db, tx, "sale_returns", "sync_id", syncId, cancellationToken) is not null) continue;
                var saleId = await FindIdAsync(db, tx, "sales", "sync_id", Text(remote, "sale_sync_id"), cancellationToken);
                if (saleId is null) { skipped++; deferredRecords++; continue; }
                var remoteParty = NullableText(remote, "party_sync_id");
                var customerId = await PartyIdForAsync(remoteParty);
                if (IsMissingRequiredPartyReference(remoteParty, customerId))
                {
                    skipped++; deferredRecords++;
                    continue;
                }
                var values = Copy(remote);
                values.Remove("id"); values.Remove("sale_id"); values.Remove("customer_id");
                values["sync_id"] = syncId; values["sale_id"] = saleId; values["customer_id"] = customerId;
                values["party_sync_id"] = await CanonicalPartySyncIdAsync(remoteParty);
                await InsertRowAsync(db, tx, "sale_returns", values, cancellationToken); created++;
            }

            foreach (var remote in collections["sale_return_items"])
            {
                var syncId = Text(remote, "sync_id");
                if (syncId.Length == 0) { skipped++; deferredRecords++; continue; }
                if (await FindIdAsync(db, tx, "sale_return_items", "sync_id", syncId, cancellationToken) is not null) continue;
                var returnId = await FindIdAsync(db, tx, "sale_returns", "sync_id", Text(remote, "return_sync_id"), cancellationToken);
                var saleItemId = await FindIdAsync(db, tx, "sale_items", "sync_id", Text(remote, "sale_item_sync_id"), cancellationToken);
                if (returnId is null || saleItemId is null) { skipped++; deferredRecords++; continue; }
                var productId = await FindIdAsync(db, tx, "products", "barcode", Text(remote, "barcode"), cancellationToken);
                var values = Copy(remote);
                values.Remove("id"); values.Remove("return_id"); values.Remove("sale_item_id"); values.Remove("product_id");
                values["sync_id"] = syncId; values["return_id"] = returnId; values["sale_item_id"] = saleItemId; values["product_id"] = productId;
                await InsertRowAsync(db, tx, "sale_return_items", values, cancellationToken); created++;
            }

            // Deletion markers are never silently applied to an Android-origin
            // record on the Windows master. History/balance checks protect data.
            foreach (var tombstone in collections["tombstones"])
            {
                var type = Text(tombstone, "entity_type");
                var key = Text(tombstone, "entity_key");
                if (key.Length == 0) continue;
                if (type == "sale_revision")
                {
                    // A revision is retained as the per-sale high-water mark.
                    var split = key.LastIndexOf('|');
                    if (split > 0 && long.TryParse(key[(split + 1)..], NumberStyles.None,
                        CultureInfo.InvariantCulture, out var revision) && revision > 0)
                    {
                        var saleKey = key[..split];
                        if (revision <= await GetSaleRevisionAsync(db, tx, saleKey, cancellationToken))
                            continue;
                        // If its sale was not in this snapshot, keep the snapshot pending.
                        if (!collections["sales"].Any(x => Text(x, "sync_id") == saleKey))
                        {
                            deferredRecords++;
                            continue;
                        }
                        await RecordTombstoneAsync(db, tx, type, key, sourceDeviceId, cancellationToken);
                    }
                    continue;
                }
                if (type == "sale_ledger")
                {
                    var split = key.LastIndexOf('|');
                    if (split > 0 && key[(split + 1)..].Length > 0)
                        await RecordTombstoneAsync(db, tx, type, key, sourceDeviceId, cancellationToken);
                    continue;
                }
                if (type is "sale_item" or "khata_transaction")
                {
                    var split = key.LastIndexOf('|');
                    if (split <= 0) { deferredRecords++; continue; }
                    var saleKey = key[..split];
                    var recordKey = key[(split + 1)..];
                    if (!appliedSaleRevisions.Contains(saleKey)) continue;
                    if (type == "sale_item")
                    {
                        var referencedByReturn = await ExistsAsync(db, tx, "sale_return_items",
                            "sale_item_id=(SELECT id FROM sale_items WHERE sync_id=$key LIMIT 1)",
                            cancellationToken, ("$key", recordKey));
                        if (referencedByReturn)
                        {
                            var localItem = await ReadOneAsync(db, tx, "sale_items", "sync_id", recordKey, cancellationToken);
                            if (localItem is not null)
                                await AddConflictAsync("sale_item_delete", recordKey, localItem,
                                    new Dictionary<string, object?> { ["_deleted"] = true, ["sync_id"] = recordKey });
                            continue;
                        }
                    }
                    var table = type == "sale_item" ? "sale_items" : "khata_transactions";
                    await DeleteAsync(db, tx, table, "sync_id=$key", cancellationToken, ("$key", recordKey));
                    await RecordTombstoneAsync(db, tx, type, key, sourceDeviceId, cancellationToken);
                    continue;
                }
                if (type is not ("product" or "party")) continue;
                if (type == "product" && collections["products"].Any(x => Text(x, "barcode") == key)) continue;
                if (type == "party" && collections["parties"].Any(x => Text(x, "sync_id") == key)) continue;
                if (await ExistsAsync(db, tx, "drive_sync_ignored_tombstones",
                    "source_device_id=$device AND entity_type=$type AND entity_key=$key",
                    cancellationToken, ("$device", sourceDeviceId), ("$type", type), ("$key", key))) continue;

                if (type == "product")
                {
                    var product = await ReadOneAsync(db, tx, "products", "barcode", key, cancellationToken);
                    if (product is null) { await RecordTombstoneAsync(db, tx, "product", key, sourceDeviceId, cancellationToken); continue; }
                    var stock = Number(product, "quantity");
                    var damaged = Number(product, "damaged_quantity");
                    var hasHistory = await ExistsAsync(db, tx, "sale_items", "barcode=$key", cancellationToken, ("$key", key)) ||
                                     await ExistsAsync(db, tx, "purchases", "barcode=$key", cancellationToken, ("$key", key));
                    if (sourceDeviceId == "windows-master" && applyMasterState && stock == 0 && damaged == 0 && !hasHistory)
                    {
                        await DeleteAsync(db, tx, "products", "barcode=$key", cancellationToken, ("$key", key));
                        await RecordTombstoneAsync(db, tx, "product", key, sourceDeviceId, cancellationToken);
                        updated++;
                    }
                    else if (detectConflicts)
                    {
                        var local = new Dictionary<string, object?>(product, StringComparer.Ordinal); local.Remove("id");
                        await AddConflictAsync("product_delete", key, local,
                            new Dictionary<string, object?> { ["_deleted"] = true, ["barcode"] = key, ["deleted_at"] = Value(tombstone, "deleted_at") });
                    }
                }
                else
                {
                    var partyId = await PartyIdForAsync(key);
                    if (partyId is null) { await RecordTombstoneAsync(db, tx, "party", key, sourceDeviceId, cancellationToken); continue; }
                    var party = await ReadOneAsync(db, tx, "parties", "id", partyId.Value, cancellationToken);
                    if (party is null) { await RecordTombstoneAsync(db, tx, "party", key, sourceDeviceId, cancellationToken); continue; }
                    var refs = await CountPartyReferencesAsync(db, tx, partyId.Value, cancellationToken);
                    var balance = Number(party, "balance");
                    var localSync = Text(party, "sync_id");
                    if (sourceDeviceId == "windows-master" && applyMasterState && refs == 0 && Math.Abs(balance) < 0.000001)
                    {
                        await DeleteAsync(db, tx, "parties", "id=$id", cancellationToken, ("$id", partyId.Value));
                        await RecordTombstoneAsync(db, tx, "party", localSync, sourceDeviceId, cancellationToken);
                        if (key != localSync) await RecordTombstoneAsync(db, tx, "party", key, sourceDeviceId, cancellationToken);
                        updated++;
                    }
                    else if (detectConflicts)
                    {
                        var local = new Dictionary<string, object?>(party, StringComparer.Ordinal); local.Remove("id");
                        await AddConflictAsync("party_delete", localSync,
                            local, new Dictionary<string, object?> { ["_deleted"] = true, ["sync_id"] = key, ["deleted_at"] = Value(tombstone, "deleted_at") });
                    }
                }
            }

            await tx.CommitAsync(cancellationToken);
            var pending = await CountPendingConflictsAsync(db, sourceDeviceId, snapshot.SnapshotHash, cancellationToken);
            return new DriveMergeResult(created, updated, conflicts, skipped, pending,
                IsSnapshotFullyAccepted(pending, deferredRecords));
        }
        catch
        {
            await tx.RollbackAsync(cancellationToken);
            throw;
        }
    }

    public async Task ResolveConflictAsync(long conflictId, bool useRemote, string databasePath,
        CancellationToken cancellationToken = default)
    {
        AccessService.RequireCurrentAdmin();
        await PosDatabaseSchemaVerifier.VerifyAsync(databasePath, cancellationToken);
        await DatabaseSafetyService.EnsureVerifiedBackupAsync(databasePath, cancellationToken);
        await using var db = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = databasePath, Mode = SqliteOpenMode.ReadWrite, Pooling = false }.ToString());
        await db.OpenAsync(cancellationToken);
        using var tx = db.BeginTransaction();
        try
        {
            var conflict = await ReadOneAsync(db, tx, "drive_sync_conflicts", "id", conflictId, cancellationToken);
            if (conflict is null || Text(conflict, "status") != "pending") { await tx.CommitAsync(cancellationToken); return; }
            var type = Text(conflict, "entity_type");
            var key = Text(conflict, "entity_key");
            var source = Text(conflict, "source_device_id");
            var remoteJson = Text(conflict, "remote_payload");
            var payload = JsonSerializer.Deserialize<Dictionary<string, object?>>(remoteJson)
                ?? throw new FormatException("Conflict remote payload is invalid.");
            payload = NormalizeJsonValues(payload);

            if (type is "product_readd" or "party_readd")
            {
                var product = type == "product_readd";
                var baseType = product ? "product_readd" : "party_readd";
                var remoteKey = product ? Text(payload, "barcode", key) : Text(payload, "sync_id", key);
                if (!useRemote && Bool(payload, "_has_related_records"))
                    throw new InvalidOperationException("Doosre device par linked transactions mojood hain. History bachane ke liye record restore karna zaroori hai.");
                if (useRemote)
                {
                    if (product)
                    {
                        await InsertRowAsync(db, tx, "products", ProductValues(payload, remoteKey), cancellationToken, replace: true);
                        await DeleteAsync(db, tx, "drive_sync_tombstones", "entity_type='product' AND entity_key=$key", cancellationToken, ("$key", remoteKey));
                    }
                    else
                    {
                        payload.Remove("_has_related_records"); payload.Remove("id"); payload["sync_id"] = remoteKey;
                        payload["balance"] = Number(payload, "balance");
                        await InsertRowAsync(db, tx, "parties", payload, cancellationToken, replace: true);
                        await DeleteAsync(db, tx, "drive_sync_tombstones", "entity_type='party' AND entity_key=$key", cancellationToken, ("$key", remoteKey));
                        await DeleteAsync(db, tx, "drive_sync_tombstones",
                            "entity_type='party' AND entity_key IN (SELECT local_sync_id FROM drive_sync_aliases WHERE source_device_id=$device AND remote_sync_id=$remote)",
                            cancellationToken, ("$device", source), ("$remote", remoteKey));
                    }
                    await DeleteAsync(db, tx, "drive_sync_ignored_tombstones",
                        "source_device_id=$device AND entity_type=$type AND entity_key=$key",
                        cancellationToken, ("$device", source), ("$type", baseType), ("$key", remoteKey));
                }
                else
                    await InsertIgnoredAsync(db, tx, source, baseType, remoteKey, cancellationToken);
            }
            else if (type is "product_delete" or "party_delete")
            {
                var product = type == "product_delete";
                var baseType = product ? "product" : "party";
                var remoteKey = product ? Text(payload, "barcode", key) : Text(payload, "sync_id", key);
                if (useRemote)
                {
                    if (product)
                    {
                        var row = await ReadOneAsync(db, tx, "products", "barcode", remoteKey, cancellationToken);
                        if (row is not null)
                        {
                            var stock = Number(row, "quantity"); var damaged = Number(row, "damaged_quantity");
                            var history = await ExistsAsync(db, tx, "sale_items", "barcode=$key", cancellationToken, ("$key", remoteKey)) ||
                                          await ExistsAsync(db, tx, "purchases", "barcode=$key", cancellationToken, ("$key", remoteKey));
                            if (stock != 0 || damaged != 0 || history)
                                throw new InvalidOperationException("Is product par stock ya transaction history mojood hai. Windows master record preserve karein.");
                            await DeleteAsync(db, tx, "products", "barcode=$key", cancellationToken, ("$key", remoteKey));
                        }
                        await RecordTombstoneAsync(db, tx, "product", remoteKey, source, cancellationToken);
                    }
                    else
                    {
                        var party = await ReadOneAsync(db, tx, "parties", "sync_id", key, cancellationToken);
                        if (party is not null)
                        {
                            var id = Convert.ToInt64(party["id"], CultureInfo.InvariantCulture);
                            if (await CountPartyReferencesAsync(db, tx, id, cancellationToken) > 0 || Math.Abs(Number(party, "balance")) > 0.000001)
                                throw new InvalidOperationException("Is party ki transaction history ya outstanding balance mojood hai. Windows master record preserve karein.");
                            await DeleteAsync(db, tx, "parties", "id=$id", cancellationToken, ("$id", id));
                        }
                        await RecordTombstoneAsync(db, tx, "party", key, source, cancellationToken);
                        if (remoteKey != key) await RecordTombstoneAsync(db, tx, "party", remoteKey, source, cancellationToken);
                    }
                }
                else await InsertIgnoredAsync(db, tx, source, baseType, remoteKey, cancellationToken);
            }
            else if (useRemote && type == "product")
            {
                var values = ProductValues(payload, key);
                values.Remove("barcode");
                await UpdateRowAsync(db, tx, "products", values, "barcode=$key", cancellationToken, ("$key", key));
            }
            else if (useRemote && type == "party")
            {
                foreach (var field in PartyFields) { }
                var values = new Dictionary<string, object?>(StringComparer.Ordinal);
                foreach (var field in PartyFields) if (payload.TryGetValue(field, out var value)) values[field] = value;
                await UpdateRowAsync(db, tx, "parties", values, "sync_id=$key", cancellationToken, ("$key", key));
            }

            await ExecuteAsync(db, tx,
                "UPDATE drive_sync_conflicts SET status='resolved',resolution=$resolution,resolved_at=$at WHERE id=$id;",
                cancellationToken, ("$resolution", useRemote ? "use_remote" : "keep_local"),
                ("$at", DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture)), ("$id", conflictId));
            await tx.CommitAsync(cancellationToken);
        }
        catch
        {
            await tx.RollbackAsync(cancellationToken);
            throw;
        }
    }

    public async Task<IReadOnlyList<DriveConflictRow>> GetPendingConflictsAsync(string databasePath,
        CancellationToken cancellationToken = default)
    {
        AccessService.RequireCurrentAdmin();
        await PosDatabaseSchemaVerifier.VerifyAsync(databasePath, cancellationToken);
        await using var db = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = databasePath, Mode = SqliteOpenMode.ReadOnly, Pooling = false }.ToString());
        await db.OpenAsync(cancellationToken);
        await using var cmd = db.CreateCommand();
        cmd.CommandText = "SELECT id,source_device_id,snapshot_hash,entity_type,entity_key,local_payload,remote_payload,created_at FROM drive_sync_conflicts WHERE status='pending' ORDER BY created_at;";
        await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
        var rows = new List<DriveConflictRow>();
        while (await reader.ReadAsync(cancellationToken))
            rows.Add(new(reader.GetInt64(0), reader.GetString(1), reader.GetString(2), reader.GetString(3),
                reader.GetString(4), reader.GetString(5), reader.GetString(6), reader.GetString(7)));
        return rows;
    }

    private static List<Dictionary<string, object?>> ReadCollection(IReadOnlyDictionary<string, object?> data, string name)
    {
        if (!data.TryGetValue(name, out var raw) || raw is not IEnumerable<object?> items)
            throw new FormatException("Snapshot collection missing: " + name);
        return items.Select(item => item as Dictionary<string, object?> ?? throw new FormatException("Invalid row in " + name)).ToList();
    }

    private static Dictionary<string, object?> ProductValues(IReadOnlyDictionary<string, object?> row, string barcode) =>
        new(StringComparer.Ordinal)
        {
            ["name"] = Text(row, "name"), ["barcode"] = barcode,
            ["price"] = Number(row, "price"), ["purchasePrice"] = Number(row, "purchasePrice"),
            ["wholesalePrice"] = Number(row, "wholesalePrice"), ["damaged_quantity"] = (long)Number(row, "damaged_quantity"),
            ["quantity"] = (long)Number(row, "quantity"), ["is_active"] = (long)(row.ContainsKey("is_active") ? Number(row, "is_active") : 1),
            ["stock_unit"] = Value(row, "stock_unit")
        };

    private static Dictionary<string, object?> Copy(IReadOnlyDictionary<string, object?> row) =>
        new(row, StringComparer.Ordinal);

    private static Dictionary<string, object?> NormalizeJsonValues(Dictionary<string, object?> row)
    {
        foreach (var key in row.Keys.ToArray())
            if (row[key] is JsonElement element) row[key] = FromJson(element);
        return row;
    }

    private static object? FromJson(JsonElement e) => e.ValueKind switch
    {
        JsonValueKind.Object => e.EnumerateObject().ToDictionary(x => x.Name, x => FromJson(x.Value), StringComparer.Ordinal),
        JsonValueKind.Array => e.EnumerateArray().Select(FromJson).ToList(),
        JsonValueKind.String => e.GetString(),
        JsonValueKind.Number when e.TryGetInt64(out var i) => i,
        JsonValueKind.Number => e.GetDouble(),
        JsonValueKind.True => true, JsonValueKind.False => false, JsonValueKind.Null => null,
        _ => null
    };

    private static object? Value(IReadOnlyDictionary<string, object?> row, string key) => row.TryGetValue(key, out var value) ? value : null;
    private static string Text(IReadOnlyDictionary<string, object?> row, string key, string fallback = "") => Convert.ToString(Value(row, key), CultureInfo.InvariantCulture) ?? fallback;
    private static string? NullableText(IReadOnlyDictionary<string, object?> row, string key) => Value(row, key) is null ? null : Text(row, key);
    private static double Number(IReadOnlyDictionary<string, object?> row, string key) => double.TryParse(Text(row, key, "0"), NumberStyles.Any, CultureInfo.InvariantCulture, out var n) && double.IsFinite(n) ? n : 0;
    private static bool Bool(IReadOnlyDictionary<string, object?> row, string key) => Value(row, key) is bool b && b;
    private static string Digits(string value) => new(value.Where(char.IsDigit).ToArray());

    private static bool Different(IReadOnlyDictionary<string, object?> local, IReadOnlyDictionary<string, object?> remote, IEnumerable<string> fields) =>
        fields.Any(field => !Equivalent(Value(local, field), Value(remote, field)));

    private static bool Equivalent(object? left, object? right)
    {
        if (left is null || right is null) return left is null && right is null;
        if (double.TryParse(Convert.ToString(left, CultureInfo.InvariantCulture), NumberStyles.Any, CultureInfo.InvariantCulture, out var a) &&
            double.TryParse(Convert.ToString(right, CultureInfo.InvariantCulture), NumberStyles.Any, CultureInfo.InvariantCulture, out var b))
            return Math.Abs(a - b) < 0.000001;
        return string.Equals(Convert.ToString(left, CultureInfo.InvariantCulture), Convert.ToString(right, CultureInfo.InvariantCulture), StringComparison.Ordinal);
    }

    private static void Add(SqliteCommand cmd, params (string Name, object? Value)[] values)
    {
        foreach (var (name, value) in values) cmd.Parameters.AddWithValue(name, value ?? DBNull.Value);
    }

    private static async Task<long> InsertRowAsync(SqliteConnection db, SqliteTransaction tx, string table,
        Dictionary<string, object?> values, CancellationToken ct, bool replace = false)
    {
        var columns = await GetColumnsAsync(db, tx, table, ct);
        var selected = values.Where(x => columns.Contains(x.Key) && x.Key != "id").ToArray();
        if (selected.Length == 0) throw new InvalidOperationException("No compatible columns to insert into " + table);
        await using var cmd = db.CreateCommand(); cmd.Transaction = tx;
        cmd.CommandText = $"INSERT {(replace ? "OR REPLACE " : "")}INTO \"{table}\" ({string.Join(",", selected.Select(x => "\"" + x.Key + "\""))}) VALUES ({string.Join(",", selected.Select((x, i) => "$p" + i))}); SELECT last_insert_rowid();";
        for (var i = 0; i < selected.Length; i++) cmd.Parameters.AddWithValue("$p" + i, selected[i].Value ?? DBNull.Value);
        return Convert.ToInt64(await cmd.ExecuteScalarAsync(ct), CultureInfo.InvariantCulture);
    }

    private static async Task UpdateRowAsync(SqliteConnection db, SqliteTransaction tx, string table,
        Dictionary<string, object?> values, string where, CancellationToken ct, params (string Name, object? Value)[] whereArgs)
    {
        var columns = await GetColumnsAsync(db, tx, table, ct);
        var selected = values.Where(x => columns.Contains(x.Key) && x.Key != "id").ToArray();
        if (selected.Length == 0) return;
        await using var cmd = db.CreateCommand(); cmd.Transaction = tx;
        cmd.CommandText = $"UPDATE \"{table}\" SET {string.Join(",", selected.Select((x, i) => "\"" + x.Key + "\"=$p" + i))} WHERE {where};";
        for (var i = 0; i < selected.Length; i++) cmd.Parameters.AddWithValue("$p" + i, selected[i].Value ?? DBNull.Value);
        Add(cmd, whereArgs);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static async Task<HashSet<string>> GetColumnsAsync(SqliteConnection db, SqliteTransaction tx, string table, CancellationToken ct)
    {
        await using var cmd = db.CreateCommand(); cmd.Transaction = tx; cmd.CommandText = $"PRAGMA table_info(\"{table}\");";
        await using var reader = await cmd.ExecuteReaderAsync(ct); var result = new HashSet<string>(StringComparer.Ordinal);
        while (await reader.ReadAsync(ct)) result.Add(reader.GetString(1));
        return result;
    }

    private static async Task<Dictionary<string, object?>?> ReadOneAsync(SqliteConnection db, SqliteTransaction tx,
        string table, string column, object value, CancellationToken ct)
    {
        var rows = await ReadManyAsync(db, tx, $"SELECT * FROM \"{table}\" WHERE \"{column}\"=$key LIMIT 1;", ct, ("$key", value));
        return rows.Count == 0 ? null : rows[0];
    }

    private static async Task<List<Dictionary<string, object?>>> ReadManyAsync(SqliteConnection db, SqliteTransaction tx,
        string sql, CancellationToken ct, params (string Name, object? Value)[] args)
    {
        await using var cmd = db.CreateCommand(); cmd.Transaction = tx; cmd.CommandText = sql; Add(cmd, args);
        await using var reader = await cmd.ExecuteReaderAsync(ct); var rows = new List<Dictionary<string, object?>>();
        while (await reader.ReadAsync(ct))
        {
            var row = new Dictionary<string, object?>(StringComparer.Ordinal);
            for (var i = 0; i < reader.FieldCount; i++) row[reader.GetName(i)] = await reader.IsDBNullAsync(i, ct) ? null : reader.GetValue(i);
            rows.Add(row);
        }
        return rows;
    }

    private static async Task<long?> FindIdAsync(SqliteConnection db, SqliteTransaction tx, string table, string column, object value, CancellationToken ct)
    {
        await using var cmd = db.CreateCommand(); cmd.Transaction = tx;
        cmd.CommandText = $"SELECT id FROM \"{table}\" WHERE \"{column}\"=$key LIMIT 1;"; cmd.Parameters.AddWithValue("$key", value);
        var result = await cmd.ExecuteScalarAsync(ct);
        return result is null or DBNull ? null : Convert.ToInt64(result, CultureInfo.InvariantCulture);
    }

    private static async Task<string?> ScalarStringAsync(SqliteConnection db, SqliteTransaction tx, string sql, CancellationToken ct, params (string Name, object? Value)[] args)
    {
        await using var cmd = db.CreateCommand(); cmd.Transaction = tx; cmd.CommandText = sql; Add(cmd, args);
        var value = await cmd.ExecuteScalarAsync(ct); return value is null or DBNull ? null : Convert.ToString(value, CultureInfo.InvariantCulture);
    }

    private static async Task<bool> ExistsAsync(SqliteConnection db, SqliteTransaction tx, string table, string where, CancellationToken ct, params (string Name, object? Value)[] args)
    {
        await using var cmd = db.CreateCommand(); cmd.Transaction = tx; cmd.CommandText = $"SELECT EXISTS(SELECT 1 FROM \"{table}\" WHERE {where} LIMIT 1);"; Add(cmd, args);
        return Convert.ToInt64(await cmd.ExecuteScalarAsync(ct), CultureInfo.InvariantCulture) != 0;
    }

    private static async Task DeleteAsync(SqliteConnection db, SqliteTransaction tx, string table, string where, CancellationToken ct, params (string Name, object? Value)[] args)
    {
        await using var cmd = db.CreateCommand(); cmd.Transaction = tx; cmd.CommandText = $"DELETE FROM \"{table}\" WHERE {where};"; Add(cmd, args); await cmd.ExecuteNonQueryAsync(ct);
    }

    private static async Task ExecuteAsync(SqliteConnection db, SqliteTransaction tx, string sql, CancellationToken ct, params (string Name, object? Value)[] args)
    {
        await using var cmd = db.CreateCommand(); cmd.Transaction = tx; cmd.CommandText = sql; Add(cmd, args); await cmd.ExecuteNonQueryAsync(ct);
    }

    private static async Task<long> GetSaleRevisionAsync(
        SqliteConnection db, SqliteTransaction tx, string saleSyncId, CancellationToken ct)
    {
        var prefix = saleSyncId + "|";
        await using var command = db.CreateCommand();
        command.Transaction = tx;
        command.CommandText = "SELECT entity_key FROM drive_sync_tombstones WHERE entity_type='sale_revision' AND substr(entity_key,1,length($prefix))=$prefix;";
        command.Parameters.AddWithValue("$prefix", prefix);
        var current = 0L;
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            var key = reader.GetString(0);
            if (long.TryParse(key[prefix.Length..], NumberStyles.None, CultureInfo.InvariantCulture, out var revision))
                current = Math.Max(current, revision);
        }
        return current;
    }

    private static async Task RecordTombstoneAsync(SqliteConnection db, SqliteTransaction tx, string type, string key, string source, CancellationToken ct)
    {
        await ExecuteAsync(db, tx, "INSERT OR REPLACE INTO drive_sync_tombstones(entity_type,entity_key,deleted_at,source_device_id) VALUES($type,$key,$at,$source);",
            ct, ("$type", type), ("$key", key), ("$at", DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture)), ("$source", source));
        await DeleteAsync(db, tx, "drive_sync_ignored_tombstones", "entity_type=$type AND entity_key=$key", ct, ("$type", type), ("$key", key));
    }

    private static Task InsertIgnoredAsync(SqliteConnection db, SqliteTransaction tx, string source, string type, string key, CancellationToken ct) =>
        ExecuteAsync(db, tx, "INSERT OR REPLACE INTO drive_sync_ignored_tombstones(source_device_id,entity_type,entity_key) VALUES($source,$type,$key);",
            ct, ("$source", source), ("$type", type), ("$key", key));

    private static async Task<long> CountPartyReferencesAsync(SqliteConnection db, SqliteTransaction tx, long id, CancellationToken ct)
    {
        await using var cmd = db.CreateCommand(); cmd.Transaction = tx;
        cmd.CommandText = """
            SELECT (SELECT COUNT(*) FROM sales WHERE customer_id=$id) +
                   (SELECT COUNT(*) FROM khata_transactions WHERE party_id=$id) +
                   (SELECT COUNT(*) FROM purchases WHERE supplier_id=$id) +
                   (SELECT COUNT(*) FROM sale_returns WHERE customer_id=$id);
            """;
        cmd.Parameters.AddWithValue("$id", id);
        return Convert.ToInt64(await cmd.ExecuteScalarAsync(ct), CultureInfo.InvariantCulture);
    }

    private static async Task<int> CountPendingConflictsAsync(SqliteConnection db, string source, string hash, CancellationToken ct)
    {
        await using var cmd = db.CreateCommand();
        cmd.CommandText = "SELECT COUNT(*) FROM drive_sync_conflicts WHERE source_device_id=$device AND snapshot_hash=$hash AND status='pending';";
        Add(cmd, ("$device", source), ("$hash", hash));
        return Convert.ToInt32(await cmd.ExecuteScalarAsync(ct), CultureInfo.InvariantCulture);
    }
}

public sealed record DriveMergeResult(int CreatedRecords, int UpdatedRecords, int NewConflicts,
    int SkippedRecords, int PendingConflicts, bool SnapshotFullyAccepted);
public sealed record DriveConflictRow(long Id, string SourceDeviceId, string SnapshotHash,
    string EntityType, string EntityKey, string LocalPayload, string RemotePayload, string CreatedAt);
