using System.Globalization;
using Microsoft.Data.Sqlite;
using KhanBabaPos.Wpf.Data;

namespace KhanBabaPos.Wpf.Services;

/// <summary>
/// Posts a sale using the same schema-v18 transaction contract as Flutter.
/// This service never creates a database, changes schema, or calls Firebase.
/// </summary>
public sealed class SalePostingService
{
    private readonly AccessService _access;

    public SalePostingService(AccessService access) => _access = access ?? throw new ArgumentNullException(nameof(access));
    public Task<SalePostingResult> CompleteSaleAsync(
        SaleCheckoutRequest request,
        CancellationToken cancellationToken = default) =>
        CompleteSaleAsync(request, PosDatabasePath.Resolve(requireExisting: true), cancellationToken);

    public async Task<SalePostingResult> CompleteSaleAsync(
        SaleCheckoutRequest request,
        string databasePath,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        _access.RequireRole(AccessRole.Admin, AccessRole.Salesman);
        var activeSession = _access.CurrentSession
            ?? throw new UnauthorizedAccessException("Session expire ho gaya. Dobara login karein.");
        if ((request.CashierUid is not null && !string.Equals(request.CashierUid, activeSession.UserId, StringComparison.Ordinal)) ||
            !string.Equals(request.CashierName, activeSession.DisplayName, StringComparison.Ordinal))
            throw new UnauthorizedAccessException("Sale cashier identity active login se match nahi karti.");
        if (string.IsNullOrWhiteSpace(databasePath))
            throw new ArgumentException("Database path is required.", nameof(databasePath));
        if (request.Items.Count == 0) throw new InvalidOperationException("Cart is empty.");
        if (!double.IsFinite(request.DiscountValue) || request.DiscountValue < 0 ||
            (request.IsPercentageDiscount && request.DiscountValue > 100))
            throw new InvalidOperationException("Discount must be between 0 and 100 percent.");
        if (!request.IsPercentageDiscount && request.DiscountValue > request.Items.Sum(x => x.SalePrice * x.Quantity))
            throw new InvalidOperationException("Fixed discount cannot exceed the bill subtotal.");

        await PosDatabaseSchemaVerifier.VerifyAsync(databasePath, cancellationToken);
        await DatabaseSafetyService.EnsureVerifiedBackupAsync(databasePath, cancellationToken);
        var connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = databasePath,
            Mode = SqliteOpenMode.ReadWrite,
            Pooling = false
        }.ToString();

        await using var connection = new SqliteConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = connection.BeginTransaction();

        try
        {
            var prepared = new List<PreparedSaleLine>(request.Items.Count);
            foreach (var item in request.Items)
            {
                if (string.IsNullOrWhiteSpace(item.Barcode) || item.Quantity <= 0 ||
                    !double.IsFinite(item.SalePrice) || item.SalePrice < 0)
                    throw new InvalidOperationException("Invalid product barcode, quantity or sale price.");

                await using var lookup = connection.CreateCommand();
                lookup.Transaction = transaction;
                lookup.CommandText = """
                    SELECT id, name, barcode, COALESCE(price, 0),
                           COALESCE(purchasePrice, 0), COALESCE(quantity, 0),
                           COALESCE(stock_unit, 'pcs'), COALESCE(is_active, 1)
                    FROM products WHERE barcode = $barcode LIMIT 1;
                    """;
                lookup.Parameters.AddWithValue("$barcode", item.Barcode.Trim());
                await using var reader = await lookup.ExecuteReaderAsync(cancellationToken);
                if (!await reader.ReadAsync(cancellationToken))
                    throw new InvalidOperationException($"Product not found: {item.Barcode}");
                var productId = reader.GetInt32(0);
                var productName = reader.GetString(1);
                var barcode = reader.GetString(2);
                var purchasePrice = reader.GetDouble(4);
                var stock = reader.GetInt32(5);
                var stockUnit = reader.IsDBNull(6) ? "pcs" : reader.GetString(6);
                var active = reader.GetInt32(7);
                await reader.DisposeAsync();

                if (active != 1) throw new InvalidOperationException($"{productName} is inactive.");
                if (stock < item.Quantity)
                    throw new InvalidOperationException($"Insufficient stock for {productName}. Available: {stock}, required: {item.Quantity}.");
                if (!double.IsFinite(purchasePrice) || item.SalePrice < purchasePrice)
                    throw new InvalidOperationException($"Sale price for {productName} must not be below purchase cost (Rs. {purchasePrice.ToString("N2", CultureInfo.InvariantCulture)}).");

                prepared.Add(new PreparedSaleLine(productId, productName, barcode, item.Quantity,
                    item.SalePrice, purchasePrice, stockUnit));
            }

            // Match Flutter's current subtotal and fixed/percentage discount rules.
            var subtotal = prepared.Sum(x => x.SalePrice * x.Quantity);
            var discount = request.IsPercentageDiscount
                ? subtotal * request.DiscountValue / 100d
                : request.DiscountValue;
            var finalAmount = Math.Max(0d, subtotal - discount);
            var customerId = request.CustomerId;
            var customerType = request.CustomerType;
            if (customerType is not ("Walk-in" or "Khata" or "Wholesale"))
                throw new InvalidOperationException("Customer type must be Walk-in, Khata or Wholesale.");
            if ((customerType == "Walk-in") != (customerId is null))
                throw new InvalidOperationException("Walk-in sale must not have a customer account; Khata/Wholesale sales require a selected customer.");
            var paymentMode = customerType == "Walk-in" ? "Cash" : request.PaymentMode;
            double receivedAmount;
            string paymentType;
            switch (paymentMode)
            {
                case "Cash":
                    receivedAmount = finalAmount;
                    paymentType = "Cash";
                    break;
                case "Credit":
                    receivedAmount = 0;
                    paymentType = "Khata";
                    break;
                case "Partial":
                    receivedAmount = request.PartialReceivedAmount ?? -1;
                    if (!double.IsFinite(receivedAmount) || receivedAmount <= 0 || receivedAmount >= finalAmount)
                        throw new InvalidOperationException("Partial payment bill total se kam aur zero se zyada honi chahiye.");
                    paymentType = "Partial";
                    break;
                default:
                    throw new InvalidOperationException("Unsupported payment mode. Use Cash, Credit or Partial.");
            }

            string? customerSyncId = null;
            if (customerId is not null)
            {
                await using var customer = connection.CreateCommand();
                customer.Transaction = transaction;
                customer.CommandText = "SELECT sync_id, COALESCE(customer_type, 'Khata') FROM parties WHERE id = $id AND type = 'customer' LIMIT 1;";
                customer.Parameters.AddWithValue("$id", customerId.Value);
                await using var reader = await customer.ExecuteReaderAsync(cancellationToken);
                if (!await reader.ReadAsync(cancellationToken))
                    throw new InvalidOperationException("Selected customer account was not found.");
                customerSyncId = reader.IsDBNull(0) ? null : reader.GetString(0);
                var storedCustomerType = reader.IsDBNull(1) ? "Khata" : reader.GetString(1);
                if (!string.Equals(storedCustomerType, customerType, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException($"Selected account is {storedCustomerType}, not {customerType}. Refresh customer list and select the matching account.");
            }

            var saleDate = (request.SaleDate ?? DateTime.Now).ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture);
            var saleSyncId = NewSyncId();
            await using (var sale = connection.CreateCommand())
            {
                sale.Transaction = transaction;
                sale.CommandText = """
                    INSERT INTO sales
                    (total_amount, discount, final_amount, payment_type, customer_id,
                     salesman_uid, salesman_name, customer_type, received_amount,
                     balance_due, sync_id, customer_sync_id, date)
                    VALUES ($total, $discount, $final, $payment, $customer,
                            $uid, $cashier, $customerType, $received,
                            $balance, $sync, $customerSync, $date);
                    SELECT last_insert_rowid();
                    """;
                sale.Parameters.AddWithValue("$total", subtotal);
                sale.Parameters.AddWithValue("$discount", discount);
                sale.Parameters.AddWithValue("$final", finalAmount);
                sale.Parameters.AddWithValue("$payment", paymentType);
                sale.Parameters.AddWithValue("$customer", (object?)customerId ?? DBNull.Value);
                sale.Parameters.AddWithValue("$uid", activeSession.UserId);
                sale.Parameters.AddWithValue("$cashier", string.IsNullOrWhiteSpace(request.CashierName) ? "Local Windows User" : request.CashierName);
                sale.Parameters.AddWithValue("$customerType", customerType);
                sale.Parameters.AddWithValue("$received", receivedAmount);
                sale.Parameters.AddWithValue("$balance", customerId is null ? 0d : finalAmount - receivedAmount);
                sale.Parameters.AddWithValue("$sync", saleSyncId);
                sale.Parameters.AddWithValue("$customerSync", (object?)customerSyncId ?? DBNull.Value);
                sale.Parameters.AddWithValue("$date", saleDate);
                var id = Convert.ToInt32(await sale.ExecuteScalarAsync(cancellationToken), CultureInfo.InvariantCulture);

                foreach (var line in prepared)
                {
                    await using var stockUpdate = connection.CreateCommand();
                    stockUpdate.Transaction = transaction;
                    stockUpdate.CommandText = "UPDATE products SET quantity = quantity - $quantity WHERE id = $id AND quantity >= $quantity;";
                    stockUpdate.Parameters.AddWithValue("$quantity", line.Quantity);
                    stockUpdate.Parameters.AddWithValue("$id", line.ProductId);
                    if (await stockUpdate.ExecuteNonQueryAsync(cancellationToken) != 1)
                        throw new InvalidOperationException($"Stock update failed for {line.Name}. Please retry.");

                    await using var saleItem = connection.CreateCommand();
                    saleItem.Transaction = transaction;
                    saleItem.CommandText = """
                        INSERT INTO sale_items
                        (sale_id, product_id, barcode, product_name, quantity, sale_price,
                         purchase_price, line_total, cost_total, sync_id, sale_sync_id, stock_unit)
                        VALUES ($saleId, $productId, $barcode, $name, $quantity, $salePrice,
                                $purchasePrice, $lineTotal, $costTotal, $syncId, $saleSyncId, $unit);
                        """;
                    saleItem.Parameters.AddWithValue("$saleId", id);
                    saleItem.Parameters.AddWithValue("$productId", line.ProductId);
                    saleItem.Parameters.AddWithValue("$barcode", line.Barcode);
                    saleItem.Parameters.AddWithValue("$name", line.Name);
                    saleItem.Parameters.AddWithValue("$quantity", line.Quantity);
                    saleItem.Parameters.AddWithValue("$salePrice", line.SalePrice);
                    saleItem.Parameters.AddWithValue("$purchasePrice", line.PurchasePrice);
                    saleItem.Parameters.AddWithValue("$lineTotal", line.SalePrice * line.Quantity);
                    saleItem.Parameters.AddWithValue("$costTotal", line.PurchasePrice * line.Quantity);
                    saleItem.Parameters.AddWithValue("$syncId", NewSyncId());
                    saleItem.Parameters.AddWithValue("$saleSyncId", saleSyncId);
                    saleItem.Parameters.AddWithValue("$unit", line.StockUnit);
                    await saleItem.ExecuteNonQueryAsync(cancellationToken);
                }

                if (customerId is not null)
                {
                    await InsertKhataEntryAsync(connection, transaction, customerId.Value, customerSyncId,
                        "credit", finalAmount, $"Sale #{id}", saleDate, cancellationToken);
                    if (receivedAmount > 0)
                        await InsertKhataEntryAsync(connection, transaction, customerId.Value, customerSyncId,
                            "receipt", receivedAmount, $"Cash received at sale #{id}", saleDate, cancellationToken);

                    await using var balance = connection.CreateCommand();
                    balance.Transaction = transaction;
                    balance.CommandText = "UPDATE parties SET balance = COALESCE(balance, 0) + $due WHERE id = $id;";
                    balance.Parameters.AddWithValue("$due", finalAmount - receivedAmount);
                    balance.Parameters.AddWithValue("$id", customerId.Value);
                    await balance.ExecuteNonQueryAsync(cancellationToken);
                }

                transaction.Commit();
                return new SalePostingResult(id, subtotal, discount, finalAmount, receivedAmount,
                    customerId is null ? 0 : finalAmount - receivedAmount, paymentType, saleDate);
            }
        }
        catch
        {
            transaction.Rollback();
            throw;
        }
    }


    public Task<SalePostingResult> UpdateSaleFromRecallAsync(
        int saleId, SaleCheckoutRequest request, CancellationToken cancellationToken = default) =>
        UpdateSaleFromRecallAsync(saleId, request, PosDatabasePath.Resolve(requireExisting: true), cancellationToken);

    public async Task<SalePostingResult> UpdateSaleFromRecallAsync(
        int saleId, SaleCheckoutRequest request, string databasePath,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        if (string.IsNullOrWhiteSpace(databasePath))
            throw new ArgumentException("Database path is required.", nameof(databasePath));
        _access.RequireRole(AccessRole.Admin, AccessRole.Salesman);
        var session = _access.CurrentSession ?? throw new UnauthorizedAccessException("Session expire ho gaya. Dobara login karein.");
        if (!string.Equals(request.CashierUid, session.UserId, StringComparison.Ordinal) ||
            !string.Equals(request.CashierName, session.DisplayName, StringComparison.Ordinal))
            throw new UnauthorizedAccessException("Sale cashier identity active login se match nahi karti.");
        if (request.Items.Count == 0) throw new InvalidOperationException("Cart is empty.");
        var path = databasePath;
        await PosDatabaseSchemaVerifier.VerifyAsync(path, cancellationToken);
        await DatabaseSafetyService.EnsureVerifiedBackupAsync(path, cancellationToken);
        await using var connection = new SqliteConnection(new SqliteConnectionStringBuilder
        { DataSource = path, Mode = SqliteOpenMode.ReadWrite, Pooling = false }.ToString());
        await connection.OpenAsync(cancellationToken);
        await using var transaction = connection.BeginTransaction();
        try
        {
            await using var oldCommand = connection.CreateCommand();
            oldCommand.Transaction = transaction;
            oldCommand.CommandText = "SELECT customer_id, COALESCE(customer_type,'Walk-in'), COALESCE(payment_type,'Cash'), COALESCE(total_amount,0), COALESCE(discount,0), COALESCE(final_amount,0), COALESCE(received_amount,0), COALESCE(balance_due,0), date, sync_id, customer_sync_id FROM sales WHERE id=$id LIMIT 1;";
            oldCommand.Parameters.AddWithValue("$id", saleId);
            await using var oldReader = await oldCommand.ExecuteReaderAsync(cancellationToken);
            if (!await oldReader.ReadAsync(cancellationToken)) throw new InvalidOperationException("Original bill nahi mila.");
            var oldCustomerId = oldReader.IsDBNull(0) ? (int?)null : oldReader.GetInt32(0);
            var oldCustomerType = oldReader.GetString(1);
            var oldDate = oldReader.GetString(8);
            var oldSaleSync = oldReader.IsDBNull(9) ? null : oldReader.GetString(9);
            var oldCustomerSync = oldReader.IsDBNull(10) ? null : oldReader.GetString(10);
            var oldTotal = oldReader.GetDouble(3);
            var oldDiscount = oldReader.GetDouble(4);
            var oldFinal = oldReader.GetDouble(5) > 0 || oldTotal <= 0 ? oldReader.GetDouble(5) : Math.Max(0, oldTotal-oldDiscount);
            var oldReceived = oldReader.GetDouble(6);
            var oldDue = oldReader.GetDouble(7) > 0 ? oldReader.GetDouble(7) :
                oldReader.GetString(2) is "Khata" or "Partial" ? Math.Max(0, oldFinal-oldReceived) : 0;
            await oldReader.DisposeAsync();
            if (oldSaleSync is null || oldSaleSync.Length == 0) throw new InvalidOperationException("Original bill sync identity missing hai.");
            if (oldCustomerId != request.CustomerId || oldCustomerType != request.CustomerType)
                throw new InvalidOperationException("Existing bill ka customer/type change nahi ho sakta. Save as New Bill karein.");

            await using (var returns = connection.CreateCommand())
            {
                returns.Transaction = transaction;
                returns.CommandText = "SELECT COUNT(*) FROM sale_returns WHERE sale_id=$id;";
                returns.Parameters.AddWithValue("$id", saleId);
                if (Convert.ToInt32(await returns.ExecuteScalarAsync(cancellationToken), CultureInfo.InvariantCulture) > 0)
                    throw new InvalidOperationException("Is bill par return record mojood hai. Sirf Save as New Bill karein.");
            }
            if (oldCustomerId is not null)
            {
                await using (var account = connection.CreateCommand())
                {
                    account.Transaction = transaction;
                    account.CommandText = "SELECT sync_id, COALESCE(customer_type,'Khata') FROM parties WHERE id=$party AND type='customer' LIMIT 1;";
                    account.Parameters.AddWithValue("$party", oldCustomerId.Value);
                    await using var accountReader = await account.ExecuteReaderAsync(cancellationToken);
                    if (!await accountReader.ReadAsync(cancellationToken))
                        throw new InvalidOperationException("Original customer account verify nahi ho saka.");
                    oldCustomerSync = accountReader.IsDBNull(0) ? null : accountReader.GetString(0);
                    var actualType = accountReader.GetString(1);
                    if (!string.Equals(actualType, oldCustomerType, StringComparison.OrdinalIgnoreCase))
                        throw new InvalidOperationException("Original customer type change ho chuka hai; overwrite safe nahi.");
                }
                var ownReceiptNote = $"Cash received at sale #{saleId}";
                await using var ownReceipt = connection.CreateCommand();
                ownReceipt.Transaction = transaction;
                ownReceipt.CommandText = "SELECT id FROM khata_transactions WHERE party_id=$party AND note=$note ORDER BY id DESC LIMIT 1;";
                ownReceipt.Parameters.AddWithValue("$party", oldCustomerId.Value);
                ownReceipt.Parameters.AddWithValue("$note", ownReceiptNote);
                var ownReceiptValue = await ownReceipt.ExecuteScalarAsync(cancellationToken);
                object originalReceiptId = ownReceiptValue is null or DBNull ? DBNull.Value : Convert.ToInt64(ownReceiptValue, CultureInfo.InvariantCulture);

                // Sale timestamps have second-level precision. Use the original
                // checkout receipt row ID to detect a later receipt in the same
                // second. Without an original receipt, same-second receipts are
                // conservatively treated as later because ordering is unknown.
                await using var receipts = connection.CreateCommand();
                receipts.Transaction = transaction;
                receipts.CommandText = """
                    SELECT COUNT(*) FROM khata_transactions
                    WHERE party_id=$party AND type='receipt' AND note != $ownReceipt
                      AND (date > $saleDate OR (date = $saleDate AND ($ownReceiptId IS NULL OR id > $ownReceiptId)));
                    """;
                receipts.Parameters.AddWithValue("$party", oldCustomerId.Value);
                receipts.Parameters.AddWithValue("$ownReceipt", ownReceiptNote);
                receipts.Parameters.AddWithValue("$saleDate", oldDate);
                receipts.Parameters.AddWithValue("$ownReceiptId", originalReceiptId);
                if (Convert.ToInt32(await receipts.ExecuteScalarAsync(cancellationToken), CultureInfo.InvariantCulture) > 0)
                    throw new InvalidOperationException("Khata receipt/payment history mojood hai. Sirf Save as New Bill karein.");
            }

            var oldItems = new List<(int ProductId, int Quantity)>();
            await using (var items = connection.CreateCommand())
            {
                items.Transaction = transaction;
                items.CommandText = "SELECT product_id, quantity FROM sale_items WHERE sale_id=$id;";
                items.Parameters.AddWithValue("$id", saleId);
                await using var reader = await items.ExecuteReaderAsync(cancellationToken);
                while (await reader.ReadAsync(cancellationToken))
                {
                    if (reader.IsDBNull(0)) throw new InvalidOperationException("Purane bill ka product link missing hai.");
                    oldItems.Add((reader.GetInt32(0), reader.GetInt32(1)));
                }
            }
            foreach (var old in oldItems)
            {
                await using var restore = connection.CreateCommand();
                restore.Transaction = transaction;
                restore.CommandText = "UPDATE products SET quantity=quantity+$qty WHERE id=$id;";
                restore.Parameters.AddWithValue("$qty", old.Quantity);
                restore.Parameters.AddWithValue("$id", old.ProductId);
                if (await restore.ExecuteNonQueryAsync(cancellationToken) != 1)
                    throw new InvalidOperationException("Original stock restore nahi ho saka.");
            }

            var prepared = new List<PreparedSaleLine>();
            foreach (var input in request.Items)
            {
                if (string.IsNullOrWhiteSpace(input.Barcode) || input.Quantity <= 0 ||
                    !double.IsFinite(input.SalePrice) || input.SalePrice < 0)
                    throw new InvalidOperationException("Invalid barcode, quantity ya sale rate.");
                await using var lookup = connection.CreateCommand();
                lookup.Transaction = transaction;
                lookup.CommandText = "SELECT id,name,barcode,COALESCE(purchasePrice,0),COALESCE(quantity,0),COALESCE(stock_unit,'pcs'),COALESCE(is_active,1) FROM products WHERE barcode=$barcode LIMIT 1;";
                lookup.Parameters.AddWithValue("$barcode", input.Barcode.Trim());
                await using var reader = await lookup.ExecuteReaderAsync(cancellationToken);
                if (!await reader.ReadAsync(cancellationToken)) throw new InvalidOperationException("Product nahi mila: " + input.Barcode);
                var line = new PreparedSaleLine(reader.GetInt32(0), reader.GetString(1), reader.GetString(2),
                    input.Quantity, input.SalePrice, reader.GetDouble(3), reader.GetString(5));
                var stock = reader.GetInt32(4);
                var active = reader.GetInt32(6);
                await reader.DisposeAsync();
                if (active != 1) throw new InvalidOperationException(line.Name + " inactive hai.");
                if (stock < line.Quantity) throw new InvalidOperationException("Stock kam hai: " + line.Name);
                if (line.SalePrice < line.PurchasePrice) throw new InvalidOperationException("Sale rate purchase cost se kam hai: " + line.Name);
                prepared.Add(line);
            }
            var subtotal = prepared.Sum(x => x.SalePrice * x.Quantity);
            if (!double.IsFinite(request.DiscountValue) || request.DiscountValue < 0 ||
                (request.IsPercentageDiscount && request.DiscountValue > 100) ||
                (!request.IsPercentageDiscount && request.DiscountValue > subtotal))
                throw new InvalidOperationException("Discount valid nahi.");
            var discount = request.IsPercentageDiscount ? subtotal * request.DiscountValue / 100d : request.DiscountValue;
            var finalAmount = Math.Max(0, subtotal-discount);
            double received;
            string paymentType;
            switch (request.CustomerType == "Walk-in" ? "Cash" : request.PaymentMode)
            {
                case "Cash": received = finalAmount; paymentType = "Cash"; break;
                case "Credit": received = 0; paymentType = "Khata"; break;
                case "Partial":
                    received = request.PartialReceivedAmount ?? -1;
                    if (!double.IsFinite(received) || received <= 0 || received >= finalAmount)
                        throw new InvalidOperationException("Partial payment amount valid nahi.");
                    paymentType = "Partial"; break;
                default: throw new InvalidOperationException("Payment mode unsupported.");
            }
            var due = oldCustomerId is null ? 0 : finalAmount-received;
            foreach (var line in prepared)
            {
                await using var stock = connection.CreateCommand();
                stock.Transaction = transaction;
                stock.CommandText = "UPDATE products SET quantity=quantity-$qty WHERE id=$id AND quantity >= $qty;";
                stock.Parameters.AddWithValue("$qty", line.Quantity);
                stock.Parameters.AddWithValue("$id", line.ProductId);
                if (await stock.ExecuteNonQueryAsync(cancellationToken) != 1)
                    throw new InvalidOperationException("Stock update fail hua: " + line.Name);
            }
            await using (var update = connection.CreateCommand())
            {
                update.Transaction = transaction;
                update.CommandText = "UPDATE sales SET total_amount=$total, discount=$discount, final_amount=$final, payment_type=$payment, received_amount=$received, balance_due=$due WHERE id=$id AND sync_id=$sync;";
                update.Parameters.AddWithValue("$total", subtotal);
                update.Parameters.AddWithValue("$discount", discount);
                update.Parameters.AddWithValue("$final", finalAmount);
                update.Parameters.AddWithValue("$payment", paymentType);
                update.Parameters.AddWithValue("$received", received);
                update.Parameters.AddWithValue("$due", due);
                update.Parameters.AddWithValue("$id", saleId);
                update.Parameters.AddWithValue("$sync", oldSaleSync);
                if (await update.ExecuteNonQueryAsync(cancellationToken) != 1) throw new InvalidOperationException("Original bill update nahi hua.");
            }
            await using (var delete = connection.CreateCommand())
            {
                delete.Transaction = transaction;
                delete.CommandText = "DELETE FROM sale_items WHERE sale_id=$id;";
                delete.Parameters.AddWithValue("$id", saleId);
                await delete.ExecuteNonQueryAsync(cancellationToken);
            }
            foreach (var line in prepared)
            {
                await using var insert = connection.CreateCommand();
                insert.Transaction = transaction;
                insert.CommandText = "INSERT INTO sale_items (sale_id,product_id,barcode,product_name,quantity,sale_price,purchase_price,line_total,cost_total,sync_id,sale_sync_id,stock_unit) VALUES ($sale,$product,$barcode,$name,$qty,$price,$cost,$line,$total,$sync,$saleSync,$unit);";
                insert.Parameters.AddWithValue("$sale", saleId);
                insert.Parameters.AddWithValue("$product", line.ProductId);
                insert.Parameters.AddWithValue("$barcode", line.Barcode);
                insert.Parameters.AddWithValue("$name", line.Name);
                insert.Parameters.AddWithValue("$qty", line.Quantity);
                insert.Parameters.AddWithValue("$price", line.SalePrice);
                insert.Parameters.AddWithValue("$cost", line.PurchasePrice);
                insert.Parameters.AddWithValue("$line", line.SalePrice*line.Quantity);
                insert.Parameters.AddWithValue("$total", line.PurchasePrice*line.Quantity);
                insert.Parameters.AddWithValue("$sync", NewSyncId());
                insert.Parameters.AddWithValue("$saleSync", oldSaleSync);
                insert.Parameters.AddWithValue("$unit", line.StockUnit);
                await insert.ExecuteNonQueryAsync(cancellationToken);
            }
            if (oldCustomerId is not null)
            {
                await using (var deleteLedger = connection.CreateCommand())
                {
                    deleteLedger.Transaction = transaction;
                    deleteLedger.CommandText = "DELETE FROM khata_transactions WHERE party_id=$party AND (note=$sale OR note=$receipt);";
                    deleteLedger.Parameters.AddWithValue("$party", oldCustomerId.Value);
                    deleteLedger.Parameters.AddWithValue("$sale", $"Sale #{saleId}");
                    deleteLedger.Parameters.AddWithValue("$receipt", $"Cash received at sale #{saleId}");
                    await deleteLedger.ExecuteNonQueryAsync(cancellationToken);
                }
                await InsertKhataEntryAsync(connection, transaction, oldCustomerId.Value, oldCustomerSync, "credit", finalAmount, $"Sale #{saleId}", oldDate, cancellationToken);
                if (received > 0) await InsertKhataEntryAsync(connection, transaction, oldCustomerId.Value, oldCustomerSync, "receipt", received, $"Cash received at sale #{saleId}", oldDate, cancellationToken);
                await using var balance = connection.CreateCommand();
                balance.Transaction = transaction;
                balance.CommandText = "UPDATE parties SET balance=COALESCE(balance,0)-$oldDue+$newDue WHERE id=$id;";
                balance.Parameters.AddWithValue("$oldDue", oldDue);
                balance.Parameters.AddWithValue("$newDue", due);
                balance.Parameters.AddWithValue("$id", oldCustomerId.Value);
                await balance.ExecuteNonQueryAsync(cancellationToken);
            }
            transaction.Commit();
            return new SalePostingResult(saleId, subtotal, discount, finalAmount, received, due, paymentType, oldDate);
        }
        catch { transaction.Rollback(); throw; }
    }

    private static async Task InsertKhataEntryAsync(
        SqliteConnection connection, SqliteTransaction transaction, int partyId,
        string? partySyncId, string type, double amount, string note, string date,
        CancellationToken cancellationToken)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            INSERT INTO khata_transactions (party_id, type, amount, note, date, sync_id, party_sync_id)
            VALUES ($party, $type, $amount, $note, $date, $sync, $partySync);
            """;
        command.Parameters.AddWithValue("$party", partyId);
        command.Parameters.AddWithValue("$type", type);
        command.Parameters.AddWithValue("$amount", amount);
        command.Parameters.AddWithValue("$note", note);
        command.Parameters.AddWithValue("$date", date);
        command.Parameters.AddWithValue("$sync", NewSyncId());
        command.Parameters.AddWithValue("$partySync", (object?)partySyncId ?? DBNull.Value);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static string NewSyncId() => $"{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}_{Guid.NewGuid():N}";

    private sealed record PreparedSaleLine(
        int ProductId, string Name, string Barcode, int Quantity,
        double SalePrice, double PurchasePrice, string StockUnit);
}

public sealed record SaleLineInput(string Barcode, int Quantity, double SalePrice);
public sealed record SaleCheckoutRequest(
    IReadOnlyList<SaleLineInput> Items,
    int? CustomerId,
    string PaymentMode,
    double? PartialReceivedAmount,
    double DiscountValue,
    bool IsPercentageDiscount,
    string CustomerType = "Walk-in",
    string CashierName = "Local Windows User",
    string? CashierUid = null,
    DateTime? SaleDate = null);
public sealed record SalePostingResult(
    int SaleId, double Subtotal, double Discount, double FinalAmount,
    double ReceivedAmount, double BalanceDue, string PaymentType, string SaleDate);
