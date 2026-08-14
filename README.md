# Moneylock

Moneylock is a personal finance app for iOS with an on-device financial mentor. It
captures transactions manually, by voice, or from Apple Shortcuts, categorizes them
automatically, watches your budget with a strict (and configurable) mentor, and
offers educational insights about your spending habits — all 100% free and
open-source.

**Key principles**

- **On-device LLM** — a 3B parameter model (Qwen 2.5) runs locally on your iPhone via
  llama.cpp. No API keys, no cloud inference, no data leaves the device.
- **Offline-first** — the app works fully offline; a sync client and backend are
  included and tested, but UI wiring for sync is a planned follow-up, not a
  dependency.
- **Privacy** — voice is transcribed with Apple's on-device Speech framework.
- **Free forever** — every model and package is open-source (see [Licenses](#licenses)).

Target market: US and Canada (USD/CAD).

---

## Architecture

```
┌────────────────────── iPhone (Flutter, offline-first) ─────────────────────┐
│                                                                           │
│  Capture:                                                                 │
│  ├─ Apple Shortcut ──► moneylock://add?amount=45.50&merchant=Starbucks     │
│  ├─ Voice ──► Apple Speech on-device (speech_to_text)                      │
│  └─ Manual (in-app form)                                                  │
│                                                                           │
│  On-device LLM (llama.cpp via llama_cpp_dart):                            │
│  ├─ CategorizerAgent: Qwen 2.5 3B Q4_K_M (~1.9GB, downloaded on first     │
│  │   use) + deterministic regex fallback                                  │
│  └─ StrictMentorAgent: same model; context = accumulated budget (SQLite)  │
│      + 7-day history                                                      │
│                                                                           │
│  Data: Drift/SQLite · Notifications: local (UNUserNotificationCenter)     │
│  State: Riverpod · UI: Dashboard / Chat / Insights / Settings             │
└───────────────────────────────────────────────────────────────────────────┘
          │ planned sync: client + backend tested, UI wiring TBD
          ▼
┌── Minimal sync backend: FastAPI + SQLite (PostgreSQL-ready) ──┐
│  POST /users · POST/GET /sync/transactions · GET /health      │
└───────────────────────────────────────────────────────────────┘
```

| Layer | Technology | License |
|---|---|---|
| Mobile app | Flutter (iOS only, MVP) | BSD-3-Clause |
| State | Riverpod | MIT |
| Navigation | go_router | MIT |
| Local DB | Drift (SQLite) | MIT |
| Inference | llama.cpp via `llama_cpp_dart` | MIT |
| LLM model | Qwen 2.5 3B Instruct GGUF Q4_K_M | Apache 2.0 |
| Speech-to-text | Apple Speech (`speech_to_text`) | MIT |
| Notifications | Local (flutter_local_notifications) | MIT |
| Sync backend | FastAPI + SQLAlchemy + Alembic | MIT |
| Deep links | `app_links` (`moneylock://`) | MIT |

Budget rules: when spending reaches ≥ 80% of a category's monthly limit the mentor
sends a local notification (`info`); at ≥ 100% it escalates to `alert`. Dedup hashes
(`sha256` of normalized raw text) prevent duplicate transactions from Shortcuts or
sync.

---

## Requirements

- macOS with **Xcode** installed
- **Flutter >= 3.47**

```bash
brew install --cask flutter
```

> **IMPORTANT — Swift Package Manager is required.** `llama_cpp_dart` 0.9.x is
> resolved through SwiftPM; **CocoaPods is not supported** for this dependency.
> Before building the app, run exactly once:
>
> ```bash
> flutter config --enable-swift-package-manager
> ```

Verify the toolchain with `flutter doctor` (Android/Chrome sections are not needed
for this project). Flutter itself installs a recent stable SDK; check with `flutter --version`.

---

## Running the app

```bash
cd app
flutter run            # pick an iOS simulator when prompted
```

On **first use** the Qwen 2.5 model (~1.9 GB) is downloaded from
**Settings → "Download model"** with a progress indicator. Make sure you have at
least **~3 GB of free disk space**. The model is stored outside the app bundle and
downloaded once; afterwards everything works offline. Categorization falls back to a
deterministic regex parser while (or if) the model is unavailable, so transactions
are never lost.

`flutter run` supports hot reload while you develop: `r` reloads, `R` restarts.

---

## Running the backend (optional sync)

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Endpoints:

| Method | Path | Description |
|---|---|---|
| `POST` | `/users` | Create a user, returns an `X-API-Key` |
| `POST` | `/sync/transactions` | Batch upsert of transactions (dedup by hash) |
| `GET` | `/sync/transactions?since=<ts>` | Pull transactions since a timestamp |
| `GET` | `/health` | Health check |

The backend runs on SQLite by default; the SQLAlchemy layer also works with
PostgreSQL (just change the connection URL). A ready-to-use sync client
(FastAPI backend + Dart client) is included and tested; UI wiring (Settings →
Sync now) is a planned follow-up. The app is fully offline-first without it.

---

## Apple Shortcut

Moneylock exposes a URL scheme (`moneylock://`) so you can log purchases from iOS
Shortcuts (e.g. from an Apple Pay receipt or "Ask for Input" prompts).

Full setup instructions: [`docs/apple-shortcut.md`](docs/apple-shortcut.md)

---

## Testing

```bash
cd app && flutter test      # unit + widget tests (31)
cd backend && pytest -q     # backend API tests
```

Also run `flutter analyze` before committing.

---

## Licenses

All models and packages are free and open-source:

- **Qwen 2.5** — Apache 2.0 (model weights)
- **llama.cpp** (via `llama_cpp_dart`) — MIT
- **speech_to_text** (Apple Speech wrapper) — MIT
- **Drift** (SQLite) — MIT
- **Flutter / FastAPI / Riverpod / go_router** — BSD / MIT

No paid APIs, no subscriptions, no telemetry.