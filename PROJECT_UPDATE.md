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

<!-- Add new tasks below this line. Keep each task specific. -->

## New notes from user (2026-11-13)

- [ ] **Windows app — complete professional desktop UI audit.** Desktop dashboard/theme and some Windows-specific layouts exist, but the full screen-by-screen desktop redesign and interaction audit is not yet verified. Review all screens, dialogs, lists and workflows; retain this item until the complete Windows UI is consistent.

## Additional Windows and sync notes from user (2026-11-13)

- [x] **Google Drive periodic auto-sync — code implemented.** User currently experiences sync as manual and wants it to happen automatically at a practical interval, ideally every 1–5 minutes (or the safest/reliable interval supported by the app). Review upload/download direction, pending changes, conflict handling, retries, and status/error feedback so automatic sync does not silently overwrite newer data. Keep Windows local/offline behaviour and existing platform rules intact; do not claim sync is reliable until tested on real devices.
- [ ] **Windows startup/status message — inspect the initial "Offline" message.** When the Windows app opens, an "Offline" (or similar) status/message appears initially. Inspect the actual screen and code path to determine why it appears, whether it is accurate/transient, and whether the wording/timing/behaviour should be corrected. Do not hide a genuine offline state.
- [ ] **Windows lists — visible desktop scrollbars.** Audit customer/party, supplier and product lists and add conventional visible scrollbars plus mouse-wheel/trackpad support wherever missing.
- [ ] **Full Windows UI audit — make every screen/window desktop-native.** Review every Windows screen, dialog, list, and workflow, not just New Sale. Replace Android/mobile-style layouts and interaction patterns where unsuitable with a consistent, professional Windows desktop POS experience. Preserve feature parity and existing business rules.
- [ ] **Windows system-tray barcode activation — remaining work.** A system-tray icon/menu and manual “New Sale” action are already implemented. Still implement and verify the requested scanner-triggered activation/add-item workflow from the tray while the app is minimized/backgrounded. Do not steal focus unexpectedly or open a separate New Sale window automatically at startup.
- [ ] **Windows New Sale — one combined scan/search input.** The current code still has separate barcode and product-search controllers/fields. Combine them into one unified input while preserving scanner and search behaviour.

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
- [ ] **Handwritten invoice OCR — pending owner approval.** Current on-device ML Kit OCR handles printed Latin text and numeric fields. Handwriting recognition is not enabled; do not add an online handwriting OCR provider until the owner explicitly approves its cost and data-transfer implications. Keep manual correction/entry available.
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

- [ ] Yahan future improvement likhein.

## Completed Updates

<!-- Sirf woh kaam yahan likhein jo waqai complete/verify hua ho. -->

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
| 2026-11-13 | Added sample update, previously reported Windows bug, verified completed items, and validation follow-ups | This file update | Done |
| 2026-11-13 | Created project tracking file | `2c2409275da6a2518a1ca6b676605867e130a25d` | Done |
| 2026-11-14 | Consolidated Android/Windows build fixes; sync test workflow passed, Android and Windows workflows started | `215de3432d6884fbd4074c732c0c2c93c47ea915` | Build status to be confirmed |

## Scanner hardware and supplier-invoice capture clarification (2026-11-13)

- [x] **Barcode scanner model confirmed — Speed X SP9260.**** User has confirmed that the physical barcode scanner used with the POS is the **Speed X SP9260**. Use this exact model when reviewing scanner compatibility, configuration, focus/input handling, and Windows system-tray/New Sale behaviour. Do not confuse it with previously mentioned SpeedX model numbers.
- [x] **Supplier invoice capture device confirmed — Android/mobile camera.**** Supplier purchase/inventory invoices will be scanned or photographed using the **mobile phone camera**. The intended workflow is camera capture followed by OCR-assisted extraction and an editable review/confirmation step before posting purchase, stock, or supplier-account changes. This is separate from the Speed X SP9260 barcode scanner, which is for scanning product barcodes.

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
