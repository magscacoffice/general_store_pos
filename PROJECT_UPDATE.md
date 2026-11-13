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
