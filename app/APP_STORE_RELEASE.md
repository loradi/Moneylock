# Moneylock — App Store release kit

## Build to upload

- Bundle ID: `com.moneylock.moneylock`
- Version: `1.0.7`
- Build: `16`
- Primary category: Finance
- Secondary category: Productivity
- Age rating: answer the App Store Connect questionnaire from the actual app content; Moneylock has no user-generated social content, ads, gambling, or purchases.

## English metadata

**Name**

Moneylock

**Subtitle**

Your money, on lock

**Promotional text**

Build a spending plan, stay ahead of subscriptions, and ask Vector for practical help with your money.

**Description**

Moneylock helps you make confident day-to-day money decisions without handing your financial life to a cloud service.

Create a budget that fits your rhythm — weekly, biweekly, or monthly — and set clear spending caps for the categories that matter to you. Add purchases manually, with your voice, or by scanning a receipt. See where your money goes, review past activity, and keep recurring subscriptions from slipping through the cracks.

Meet Vector, your on-device financial assistant. Ask Vector to add, find, edit, or remove records; update plans, categories, subscriptions, and savings goals; or get a clear financial check-in. Vector focuses on Moneylock and financial education, and asks for confirmation before changing saved information.

Moneylock is built for privacy: your records and Vector conversations stay on your device. Optional sync only sends data to the private Moneylock server that you configure yourself.

Features:

- Budgets for weekly, biweekly, and monthly plans
- Expense history, category caps, and savings goals
- Subscription tracking and renewal reminders
- Receipt scanning and voice entry
- Local, on-device Vector assistance
- CSV backup and restore
- Optional private-server sync

Moneylock provides educational information, not financial, tax, legal, insurance, credit, or investment advice.

**Keywords**

budget,expense tracker,money,savings,subscriptions,spending,personal finance,finance planner

## Spanish localization (optional at launch)

**Subtitle**

Tu dinero, bajo control

**Promotional text**

Planea tus gastos, controla tus suscripciones y recibe ayuda práctica de Vector.

## Screenshots to capture

Capture five portrait screenshots on a 6.9-inch iPhone simulator or physical device. Use only real app UI and realistic, non-sensitive sample amounts.

1. Dashboard: spending versus plan and category progress.
2. Budget: weekly, biweekly, and monthly plan options with category caps.
3. Vector: a short financial check-in or a confirmed record action.
4. Subscriptions: renewal projection and reminder value.
5. History or receipt scan: quick, private expense capture.

App Store Connect accepts one to ten screenshots. Supply the highest required iPhone size; do not include alpha channels. See Apple’s current screenshot specifications before capture.

## App Review notes

No account or login is required.

The app works without connecting to a bank. Financial records are created by the user and are stored locally. Optional sync is disabled until the user enters their own private Moneylock server URL and API key in Settings.

Vector is an on-device assistant. It can manage local Moneylock data after the user confirms a change. It provides financial education and Moneylock help only; it does not offer personalized investment, legal, tax, insurance, or credit advice.

The Control Center control “Add with Vector” is available on iOS 18 or later. It opens Moneylock with Vector ready to capture a purchase.

Camera, microphone, and speech-recognition permissions are requested only after the user selects receipt scanning or voice entry.

## App Store Connect fields that need owner input

These values must be real public URLs and contact details. Do not submit placeholders.

- Support URL: `https://moneylock-legal.vercel.app/support`
- Privacy policy URL: `https://moneylock-legal.vercel.app/privacy`
- Marketing URL: `https://moneylock-legal.vercel.app/`
- App Review contact name, email, and phone number
- Copyright holder and year
- Availability territories and price
- Export-compliance answer: `No` for Moneylock’s current use of standard Apple/HTTPS encryption only, subject to your legal confirmation.

## App Privacy decision

The app has no analytics, advertising, account system, tracking, or developer-operated data collection in the current codebase. Transactions, plans, subscriptions, categories, savings goals, and Vector chats remain on the device by default. The user may voluntarily configure a private sync server; that service’s privacy practices must be disclosed by its operator.

Before publishing the App Privacy label, confirm who operates the optional Moneylock server. If it is operated by Moneylock or the developer can access its data, disclose **Financial Information** as collected for app functionality and ensure the privacy policy covers it. If it is solely a user-operated private server and the developer cannot access the data, retain documentation supporting the “not collected by developer” answer.
