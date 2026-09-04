# Moneylock — App Store submission kit

Prepared for **version 1.0.9 (build 18)**. Copy the localized English values below into App Store Connect. They describe the shipped product only.

## App information

| Field | Value |
| --- | --- |
| App name | Moneylock |
| Bundle ID | `com.moneylock.moneylock` |
| SKU | `moneylock-ios-001` |
| Primary category | Finance |
| Secondary category | Productivity |
| Support URL | `https://moneylock-legal.vercel.app/support` |
| Marketing URL | `https://moneylock-legal.vercel.app/` |
| Privacy Policy URL | `https://moneylock-legal.vercel.app/privacy` |

Enter a real copyright holder in the format `2026 Legal Entity Name`. The entity, review contact, territories, availability date, price, and App Store tax/banking agreements belong to the account owner and cannot be supplied from source code.

## English (U.S.) product page

**Subtitle — 30 characters maximum**

Private money planning

**Promotional text — 170 characters maximum**

Plan your spending, track subscriptions, and ask Vector—your fast, private on-device money assistant—for practical help.

**Description — 4,000 characters maximum**

Moneylock gives you a calm, private place to plan your money. Your plans, purchases, goals, and Vector conversations stay on your device—not in an advertising or analytics cloud.

Build a budget that fits your rhythm: weekly, biweekly, or monthly. Set spending caps for the categories that matter, add income, and see exactly what is safe to spend in the current plan period.

Capture purchases your way. Add them manually, use your voice, or scan a receipt. Review history, correct an entry, track subscriptions, and protect a savings goal.

Meet Vector, your on-device financial assistant. Vector can add, find, edit, and remove local records; update plans, categories, subscriptions, and savings goals; and provide a concise financial check-in. It focuses on Moneylock and financial education, asks for confirmation before saving changes, and works offline once its local model is installed.

MONEYLOCK FEATURES

• Weekly, biweekly, and monthly budgets
• Category caps and current-period budget health
• Expense history, editing, and deletion
• Savings goals and subscription reminders
• Receipt scanning and voice entry
• Vector: fast local AI for your Moneylock data
• CSV backup and restore
• Optional private-server sync, controlled by you

Moneylock provides educational information only, not investment, legal, tax, insurance, credit, or other professional financial advice.

**Keywords — 100 bytes maximum**

budget,expenses,savings,spending,subscriptions,personal finance,offline,receipt,goals

## Spanish (Canada) localization

**Subtitle**

Planifica tu dinero en privado

**Promotional text**

Controla tus gastos y usa Vector, tu asistente financiero local y privado, para organizar tu dinero.

## Screenshots and icon

The ready-to-upload image assets are in [`store-assets/`](store-assets/). They are PNG files without alpha, rendered at the current 6.9-inch iPhone portrait size of **1290 × 2796 px**. Upload one to ten screenshots; these four are ordered for the product page:

1. `01-dashboard.png` — current spending and category health
2. `02-vector-welcome.png` — Vector's local privacy promise
3. `03-vector-action.png` — asking Vector to manage a record
4. `04-vector-confirm.png` — transparent confirmation before saved changes

`AppIcon-1024.png` is the 1024 × 1024 marketing icon embedded in the IPA. Do not upload an image with transparency. The dashboard screenshot source is genuine UI; the illustrative sample amounts contain no personal information.

## App Review notes

Paste this in **Notes** for the reviewer:

> No account or login is required. Moneylock works without bank connectivity. Financial records are entered by the user and stored locally. Optional sync is disabled unless the user explicitly enters their own server URL and API key in Settings.
>
> Vector is an on-device assistant. It manages local Moneylock data only after the user confirms a proposed saved change. It provides Moneylock help and financial education only; it does not provide personalized investment, legal, tax, insurance, or credit advice.
>
> The iOS 18+ Control Center control, “Add with Vector,” opens Moneylock with Vector ready to capture a purchase. Camera, microphone, and speech-recognition permission prompts appear only when the user chooses receipt scanning or voice entry.

## App privacy and compliance

The release has no analytics SDK, advertising SDK, tracking, or mandatory account. Local transactions, plans, categories, subscriptions, goals, settings, and Vector chats stay on the device. Select **“No, we do not collect data from this app”** only if the optional sync server is truly user-operated and neither Moneylock nor its developer can access its data. Otherwise, disclose the information sent to that server as Financial Information used for App Functionality, then update the published privacy policy to name the server operator, retention policy, and deletion process.

Complete Apple’s age-rating questionnaire from the actual app content. The app contains no user-generated social content, ads, gambling, purchases, or unrestricted web access. Confirm export compliance with the account holder; standard Apple/HTTPS encryption alone generally does not require additional documentation, but this is a legal declaration by the publisher.

## Owner-required preflight

- Add a genuine support email address, mailing address or phone number to the public Support page before submission. Apple requires the Support URL to lead to real contact information.
- Enter the App Review contact name, email, and phone number in App Store Connect.
- Enter the legal copyright holder, availability territories, and price.
- Confirm the optional-sync operator and make the App Privacy answer match that decision.
- Open every public URL on the final domain and make sure no placeholder text remains.
