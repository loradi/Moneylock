# Moneylock — Design Doc (MVP)

**Fecha:** 2026-08-13
**Estado:** Aprobado por el usuario
**Mercado objetivo:** EE.UU. y Canadá (USD/CAD)

---

## 1. Contexto y objetivos

Moneylock es una app móvil de finanzas personales con un mentor financiero agéntico.
El MVP se centra en: captura de transacciones (manual, voz y Apple Shortcut),
categorización automática, un mentor estricto que vigila el presupuesto, e
insights educativos de hábitos de gasto.

**Restricciones del usuario:**
- **Todo gratis / opensource**: nada que requiera pago para desarrollo o uso.
- **Inferencia LLM 100% on-device** (privacidad, sin API keys, sin red).
- **iOS únicamente** para el MVP.
- La app funciona **offline-first**; el backend solo sincroniza.

## 2. Arquitectura general

```
┌────────────────────── iPhone (Flutter, offline-first) ─────────────────────┐
│                                                                           │
│  Captura:                                                                 │
│  ├─ Apple Shortcut ──► moneylock://add?amount=45.50&merchant=Starbucks     │
│  ├─ Voz ──► whisper.cpp on-device (modelo base.en ~145MB)                  │
│  └─ Manual (formulario en la app)                                         │
│                                                                           │
│  Motor LLM local (llama.cpp vía llama_cpp_dart):                          │
│  ├─ CategorizerAgent: Qwen 2.5 3B Q4 (~1.9GB, descarga en primer uso)     │
│  │   + fallback determinista (regex/reglas)                               │
│  └─ StrictMentorAgent: mismo modelo; contexto = presupuesto acumulado     │
│      (SQLite) + historial de 7 días                                       │
│                                                                           │
│  Datos: Drift/SQLite · Notificaciones: UNUserNotificationCenter (locales) │
│  Estado: Riverpod · UI: Dashboard / Chat / Insights / Settings            │
└───────────────────────────────────────────────────────────────────────────┘
          │ sync opcional cuando hay red
          ▼
┌── Backend minimal: FastAPI + PostgreSQL (Docker) + API keys ──┐
│  POST /users · POST/GET /sync/transactions · GET /health      │
└───────────────────────────────────────────────────────────────┘
```

## 3. Stack de tecnologías

| Capa | Tecnología | Licencia/Costo |
|---|---|---|
| App móvil | Flutter (iOS) | BSD, gratis |
| Estado | Riverpod | MIT |
| Navegación | go_router | MIT |
| BD local | Drift (SQLite) | MIT |
| Inferencia | llama.cpp vía `llama_cpp_dart` | MIT |
| Modelo LLM | Qwen 2.5 3B Instruct GGUF Q4_K_M | Apache 2.0 |
| STT | whisper.cpp vía `flutter_whisper` | MIT |
| Notificaciones | UNUserNotificationCenter | gratis (sin APNs) |
| Sync backend | FastAPI + SQLAlchemy async + PostgreSQL (Docker) | MIT / PostgreSQL |
| Migraciones backend | Alembic | MIT |

**Decidido (no implementar en v1):** OpenAI (GPT-4o/mini/Whisper API), LangGraph/LangChain,
pgvector, Plaid, FCM, Perplexity/FMP, RSS de noticias, Android.

## 4. Estructura de la app

```
lib/
├── main.dart
├── core/
│   ├── config.dart          → constantes (URL scheme, límites, versión del modelo)
│   ├── theme.dart           → tema iOS nativo (Cupertino)
│   ├── router.dart          → go_router: tabs Dashboard/Chat/Insights/Settings
│   └── notifications.dart   → UNUserNotificationCenter wrapper
├── data/
│   ├── db.dart              → Drift database + migraciones
│   ├── transactions_dao.dart
│   ├── budgets_dao.dart
│   ├── messages_dao.dart
│   └── memories_dao.dart
├── llm/
│   ├── llama_service.dart   → wrapper llama_cpp_dart (carga, descarga, stream)
│   ├── prompts.dart         → system prompts Categorizer y Mentor
│   ├── categorizer_agent.dart → salida JSON estricta + validación
│   ├── mentor_agent.dart
│   └── fallback_parser.dart → regex/reglas deterministas (sin modelo)
├── voice/
│   └── whisper_service.dart → flutter_whisper wrapper
├── features/
│   ├── dashboard/           → gasto diario/mensual + barra de presupuesto
│   ├── add/                 → entrada manual + botón de voz
│   ├── chat/                → chat con el mentor (con persistencia)
│   ├── insights/            → análisis educativo de hábitos de gasto
│   └── settings/            → tono del mentor, sincronización, modelo
└── sync/
    └── api_client.dart      → sync offline-first con cola de reintentos
```

## 5. Modelo de datos (Drift/SQLite local)

- **`transactions`** — id, amount (REAL), currency (TEXT, default "USD"), merchant,
  category, source (enum: shortcut|voice|manual), raw_text, timestamp,
  dedup_hash (TEXT UNIQUE) — `sha256(raw_text normalizado + timestamp)`; si el
  hash ya existe, la transacción se ignora
- **`budgets`** — category (TEXT), monthly_limit (REAL), period (TEXT "YYYY-MM"),
  UNIQUE(category, period)
- **`mentor_messages`** — id, role (TEXT: user|mentor), content, created_at
- **`agent_memories`** — fact (TEXT), kind (TEXT: overspend|weekend_pattern|...),
  confidence (REAL), created_at. **Relacional, sin vectores.**
- **`settings`** — mentor_tone (TEXT: strict_ramsey|neutral_analyst|friendly_coach,
  default strict_ramsey), model_version

## 6. Capa LLM on-device

### 6.1 Modelo y carga
- Qwen 2.5 3B Instruct, cuantización Q4_K_M (~1.9GB).
- Se descarga en el primer uso con indicador de progreso; no va en el bundle.
- `llama_service.dart` expone API async (cargar, generar, cancelar) sobre `llama_cpp_dart`.
- Contexto corto: prompts ≤ 1-2K tokens para latencia aceptable en iPhone.

### 6.2 CategorizerAgent
- Entrada: `raw_text` + source.
- Salida JSON estricto validado:
  ```json
  {"amount": 45.50, "currency": "USD", "merchant": "Starbucks",
   "category": "Coffee & Dining", "confidence": 0.95}
  ```
- Prompt few-shot con ejemplos de notificaciones y texto de voz.
- Si el JSON no valida o el modelo no responde: **`fallback_parser`** (regex de montos
  `$45.50`, `45.50 USD`; diccionario de merchants → categorías). Una transacción
  nunca se pierde por fallo del modelo.
- Categorías del catálogo inicial: Coffee & Dining, Groceries, Transport,
  Entertainment, Shopping & E-commerce, Bills & Utilities, Health, Tech, Travel, Other.

### 6.3 StrictMentorAgent
- System prompt base (estilo Dave Ramsey, del spec original):
  > "Eres un Mentor Financiero estricto, pragmático y sin rodeos. Tu objetivo es hacer
  > que el usuario cumpla sus metas financieras. Si el usuario gasta en cosas
  > innecesarias o se acerca al límite de su presupuesto, debes llamarle la atención
  > directamente, señalarle el impacto en sus metas futuras y exigir un ajuste.
  > Sé firme, conciso y motivador desde la disciplina."
- Contexto inyectado en el prompt: presupuesto del período actual (por categoría),
  gasto acumulado, últimas 5 transacciones, tono configurado.
- Salida: mensaje corto (≤ ~120 palabras) + severidad (info|warning|alert).

### 6.4 Reglas de presupuesto y notificaciones
1. Entrada capturada → CategorizerAgent (o fallback) → guardar en SQLite (dedup).
2. MentorAgent evalúa gasto acumulado del período vs límites.
3. Gasto ≥ 80% del límite → notificación local info + mensaje en chat.
4. Gasto ≥ 100% → notificación local alert + mensaje severo en chat.
5. El mensaje del mentor se persiste en `mentor_messages` (aparece en el chat).

### 6.5 Tonos del mentor
- `strict_ramsey` (default), `neutral_analyst`, `friendly_coach` — cambian solo el
  system prompt; la lógica de reglas es idéntica.

## 7. Captura de transacciones

### 7.1 Apple Shortcut (URL scheme)
- Scheme registrado: `moneylock://add?amount=45.50&merchant=Starbucks`
  (+ `category` y `date` opcionales).
- El Shortcut iOS usa "Open URL" (datos del comprobante Apple Pay o entrada manual
  con "Ask for Input"). El spec incluirá las instrucciones de configuración del
  Shortcut en un documento (docs/apple-shortcut.md).

### 7.2 Voz
- Grabación con botón flotante → `flutter_whisper` (whisper.cpp, modelo base.en
  ~145MB, descarga en primer uso) → transcripción → CategorizerAgent.

### 7.3 Manual
- Formulario: merchant, amount, categoría (sugerida por el modelo), fecha.

## 8. Insights de mercado (local, educativo)

- `MarketInsightAgent` analiza el patrón de gasto del usuario del último mes
  (agregaciones SQLite) y genera cápsulas educativas que relacionan hábitos de
  consumo con sectores de mercado (sin noticias externas en v1).
- **Disclaimer obligatorio** en cada cápsula: información educativa, no constituye
  asesoramiento de inversión financiero regulado.
- Cache: se regenera 1x por día o al cambiar de mes.

## 9. Backend de sync (mínimo, opcional)

- FastAPI + SQLAlchemy async + Alembic.
- **Motor v1: SQLite** (sin Docker instalado; mismo código SQLAlchemy — cambiar a
  PostgreSQL = solo cambiar la URL de conexión). Postgres queda como swap-in.
- Endpoints: `POST /users`, `POST /sync/transactions` (batch upsert con dedup_hash),
  `GET /sync/transactions?since=<ts>`, `GET /health`.
- Auth: API key por usuario (header `X-API-Key`).
- La app sincroniza en segundo plano cuando hay red; los fallos no bloquean nada.
- Se construye al final: es el componente menos crítico del MVP.

## 10. Testing

- **Unit (Dart):** `fallback_parser` con casos reales ("Starbucks $12.50",
  "Apple.com 9.99 USD", "PENDING UBER *TRIP"), validación JSON del Categorizer
  (con LLM mock), reglas de presupuesto (80%/100%), dedup.
- **Widget:** dashboard renderiza la barra de presupuesto; chat persiste mensajes.
- **Manual en simulador:** prueba del modelo real (descarga + categorización + mentor).
- **Backend (pytest):** endpoints de sync, upsert con dedup, auth por API key.

## 11. Orden de construcción

1. Skeleton Flutter iOS + Drift schema + settings
2. Capa LLM: `llama_service` + descarga de modelo + CategorizerAgent + fallback_parser
3. MentorAgent + reglas de presupuesto + notificaciones locales
4. Captura: URL scheme (Shortcut), voz (whisper.cpp), formulario manual
5. UI: Dashboard, Chat, Insights, Settings
6. Backend sync (FastAPI + PostgreSQL + Docker + Alembic)
7. Tests + polish

## 12. Fuera de alcance (v1)

- Plaid, banca conectada, FCM/APNs, Android, RSS/noticias externas, pgvector/RAG,
  LangGraph/LangChain, OpenAI APIs, multiusuario público, Apple Developer account.

## 13. Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Modelo 3B da respuestas pobres | Prompts cortos y estrictos; fallback regex garantiza parsing |
| Descarga de 1.9GB en primer uso | Indicador de progreso, retomable, verificación de hash |
| Latencia en iPhone viejos | Contextos ≤ 1-2K tokens; modelo Q4_K_M; cancelación |
| Notificaciones duplicadas | dedup_hash único por transacción |
| Tamaño de la app | Modelos descargados fuera del bundle (App Store < 4GB) |
