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

- [ ] **[VALIDATION] Windows Google Drive login aur token refresh test karein.** Windows OAuth code mein `GOOGLE_WINDOWS_CLIENT_SECRET` support add karke commit kiya gaya tha (commit `1c9fe93`). GitHub Actions Windows Build #48 ka rerun pehle queued report hua tha; final result aur app ke andar successful login/refresh abhi verify karna baqi hai.
- [ ] **[INVESTIGATION] Windows black-screen issue dobara reproduce aur root cause identify karein.** Build #17 pehle kaam kar rahi thi, Build #20 par black screen report hui thi, aur Build #14 baad mein dashboard tak open hui. Current status ko fresh build par verify karein; purane test ko current result na samjhein.
- [ ] **[VALIDATION] Android Build #150 ki FCM notification workflow failure resolve/verify karein.** APK compile aur release hui thi, lekin final notification step par `iamcredentials.googleapis.com` disabled hone ka error report hua tha. APK build success aur notification workflow success ko alag track karein.
- [ ] **[SAMPLE ONLY — user approval required]** New Sale screen par product search field ko sale start hote hi keyboard focus dena. Ye sirf update likhne ka demo hai; is line ko actual task tab samjha jaye jab user isay confirm kare.

## New notes from user (2026-11-13)

- [ ] **Windows New Sale — combine barcode scan and product search into one field.** Currently the New Sale screen shows a barcode-scan cell and a separate search cell beside it. User wants a single unified input cell that supports both barcode scanning and product search; do not show two separate adjacent fields. Preserve the existing scan/search behaviour while combining the UI.
- [ ] **Windows app — redesign as a professional native desktop POS interface.** The current Windows version still looks like the Android/mobile UI. User wants a proper Windows desktop software experience, with a professional desktop layout and interaction patterns rather than simply reusing the Android screen design. Review the Windows-specific UI and implement a coherent desktop-oriented interface.

## Additional Windows and sync notes from user (2026-11-13)

- [ ] **Google Drive sync — automate periodic syncing.** User currently experiences sync as manual and wants it to happen automatically at a practical interval, ideally every 1–5 minutes (or the safest/reliable interval supported by the app). Review upload/download direction, pending changes, conflict handling, retries, and status/error feedback so automatic sync does not silently overwrite newer data. Keep Windows local/offline behaviour and existing platform rules intact; do not claim sync is reliable until tested on real devices.
- [ ] **Windows startup/status message — inspect the initial "Offline" message.** When the Windows app opens, an "Offline" (or similar) status/message appears initially. Inspect the actual screen and code path to determine why it appears, whether it is accurate/transient, and whether the wording/timing/behaviour should be corrected. Do not hide a genuine offline state.
- [ ] **Windows lists — provide visible desktop scrollbars.** Customer/party lists (including Khata parties), supplier lists, and product lists currently lack the expected side scrollbar/desktop scrolling affordance and appear to retain Android-style scrolling. Review all relevant list screens and implement conventional Windows scrolling with a visible scrollbar and mouse-wheel/trackpad support where appropriate.
- [ ] **Full Windows UI audit — make every screen/window desktop-native.** Review every Windows screen, dialog, list, and workflow, not just New Sale. Replace Android/mobile-style layouts and interaction patterns where unsuitable with a consistent, professional Windows desktop POS experience. Preserve feature parity and existing business rules.
- [ ] **Windows New Sale system-tray workflow — clarify and implement the intended behaviour.** User does NOT want a separate New Sale window to open automatically at startup. They want a New Sale entry/icon available in the Windows system tray (notification area near Wi-Fi, volume, and clock). When a barcode scanner reads an item, the tray workflow should be able to bring up/show the New Sale interface and add the scanned item automatically. Review Windows tray integration, app running/minimized state, scanner input/focus, and safe popup behaviour. Confirm the exact desired activation behaviour before implementing if technical details remain ambiguous; do not make the app steal focus unexpectedly.
- [ ] **Windows New Sale — one combined scan/search input.** Keep barcode scanning and product search in one unified field, not two separate adjacent fields.

## Cross-platform inventory duplicate-check note from user (2026-11-13)

- [ ] **[Android + Windows] Detect an already-inventory barcode immediately during product entry.** When adding a product, if the scanned barcode already belongs to a product in inventory, the app should detect and notify the user immediately at scan time (before the user spends time entering the rest of the product details). Current reported behaviour: the duplicate barcode is accepted during entry and only reported when the user presses Save, wasting time and entered work. Review and fix the barcode lookup/duplicate validation flow on both Android and Windows. Keep legitimate editing/updating of an existing product possible; distinguish an intentional edit from accidentally adding a duplicate new product. Add appropriate feedback and verify both platforms.

## Sales history / invoice detail note from user (2026-11-13)

- [ ] **Sales History — open a selected invoice and show its complete contents.** When the user opens Sales History and taps/clicks an invoice, that invoice should open in a detail view. Show all items/products included in that sale and the relevant invoice details (such as quantities, rates, amounts, totals, date/time, bill number, customer/payment information where available). Review Android and Windows behaviour for consistency unless the existing platform design requires different layouts. The invoice detail must reflect the saved sale record and must not accidentally create or modify a sale.

## Reports / custom date-wise business summary note from user (2026-11-13)

- [ ] **Reports — add a user-selectable date or date-range report instead of only fixed Daily / Weekly / Monthly choices.** The user should be able to choose any specific date (and ideally a custom from–to date range) and see what happened during that period. Include, at minimum:
  - Total sales for the selected date/period.
  - Total purchases for the selected date/period.
  - Total expenses for the selected date/period.
  - A clear date-wise daily breakdown when a range contains multiple days, so sales, purchases, and expenses can be reviewed for each individual day, not only as one combined total.
  - Relevant totals and a net summary where the underlying data supports it; clearly distinguish sales, purchases, and expenses rather than mixing them.
  Review Android and Windows report screens and keep figures consistent with saved transactions and the selected date boundaries.


## Khata customer ledger and shareable statements note from user (2026-11-13)

- [ ] **Khata customer account — provide a complete overall ledger that can be shared.** When the user opens/taps a Khata customer and views that customer's record, provide the full account ledger/history (all relevant transactions, purchases/charges, payments/receipts, dates, and running/outstanding balance where the saved data supports it) in a clear statement that can be shared with the customer.
- [ ] **Khata customer account — allow a selective date-range statement of items purchased.** Provide an option to choose a specific date or custom from–to dates and generate a shareable statement showing what items/products that customer took during the selected period, with transaction dates and available quantities/rates/amounts and totals. The full overall ledger and the selective date-wise item statement should be separate, clearly labelled sharing options. Ensure the statement is based on the customer's saved records, respects date boundaries, and does not alter the account. Review Android and Windows for consistent functionality.

## Supplier invoice photo scanning / OCR to purchase-stock entry note from user (2026-11-13)

- [ ] **Supplier purchase invoice — add camera/photo scanning with OCR-assisted purchase entry, subject to feasibility review.** When a supplier delivers goods and provides an invoice, allow the user to take a photo with the Android mobile camera (and optionally import an existing image/PDF where supported). The app should attempt to read both computer-generated/printed invoices and handwritten bills and extract available details such as supplier, invoice/bill number and date, product/item descriptions, quantities, units/pack sizes, purchase rates, line totals, discounts/taxes, and grand total.
- [ ] **Use a review-and-confirm step before changing stock or accounts.** Show extracted values in an editable purchase-invoice review screen. Let the user correct OCR mistakes and map invoice item names to existing inventory products; provide a clear path to add a genuinely new product and resolve unit/pack-size conversions. Only after the user confirms should the app save the purchase, update stock, and update supplier/purchase balances according to existing purchase workflows. Never post uncertain OCR results directly to inventory.
- [ ] **Handle printed and handwritten bills realistically.** Printed/computer-generated invoices are expected to be more reliably readable; handwritten invoices should be attempted but may require more manual correction. Show uncertain/unreadable fields clearly and allow manual entry without blocking the purchase.
- [ ] **Prevent duplicate invoice posting and preserve the source document.** Review a practical duplicate check using supplier + invoice number/date and/or invoice image/document fingerprint so the same bill is not accidentally entered twice. Where practical, retain the captured invoice image/PDF with the saved purchase record for later reference.
- [ ] **Feasibility and platform review before implementation.** Assess OCR/AI accuracy, offline versus internet requirements, privacy/cost, supported image/PDF formats, and Android/Windows capability. Do not assume handwritten OCR is fully automatic or promise zero manual work. Keep the Windows local/offline rule intact unless the user explicitly approves a cloud dependency; clarify any required online service before adopting it. Prefer a workflow that can fall back to manual review/entry.

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
