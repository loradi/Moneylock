# Moneylock Redesign — Design Spec

Fecha: 2026-08-15
Estado: Aprobado

## Objetivo

Reestilizar la UI de Moneylock (actualmente Cupertino nativo azul) a un sistema de diseño custom basado en la referencia visual "Kinetic Intel" (Material 3 custom): paleta **Red & White**, tipografía **Inter + Geist**, superficies blancas con bordes sutiles, label-caps uppercase, mono-data para números, chips pill, glass-blur en header/nav, burbujas de chat dark, y FAB flotante para el mentor.

## Principios

- **Offline-first**: sin imágenes remotas, sin fetch de fuentes en runtime. Fuentes empaquetadas como assets.
- **Idioma de la UI: inglés** (labels, eyebrows, nav, todo el copy visible) — fiel a la referencia.
- **Sin cambio de funcionalidad**: solo look & feel y reorganización de navegación. El backend LLM, sync, speech y lógica de negocios no se tocan.
  - **Única excepción**: el mic del input del chat (sección 4) dicta la pregunta a texto reutilizando el `SpeechToTextService` existente — es un affordance nuevo del rediseño, sin lógica nueva.
- **Fiel a la referencia** en tokens, layout y micro-detalles (glow, blur, shine).

## 1. Design tokens

### Colores (light — Red & White)

| Token | Valor |
|---|---|
| primary | `#BA1A1A` |
| primary-bright (glow/hover) | `#FF3B30` |
| on-primary | `#FFFFFF` |
| primary-container | `#FFDAD6` |
| on-primary-container | `#410002` |
| primary-fixed-dim | `#FFB4AB` |
| background | `#F9F9FA` |
| surface | `#FFFFFF` |
| surface-container | `#F4F4F5` |
| surface-container-high | `#E8E8E9` |
| surface-container-highest | `#E2E2E3` |
| surface-container-low | `#F3F3F4` |
| surface-variant | `#E2E2E3` |
| on-surface | `#131313` |
| on-surface-variant | `#444933` |
| outline | `#747A60` |
| outline-variant | `#C4C9AC` |
| border-subtle | `#E4E4E7` |
| error | `#BA1A1A` |
| error-container | `#FFDAD6` |
| on-error-container | `#93000A` |
| on-secondary | `#FFFFFF` |
| secondary-container | `#E5E2E1` |
| tertiary | `#4F616E` |
| tertiary-container | `#DCEFFF` |
| shadow-base | `rgba(0,0,0,0.04)` |

### Colores dark (solo chat modal)

| Token | Valor |
|---|---|
| background / surface | `#131313` |
| surface-container | `#201F1F` |
| surface-container-low | `#1C1B1B` |
| surface-container-high | `#2A2A2A` |
| surface-container-highest | `#353534` |
| surface-bright | `#3A3939` |
| surface-variant | `#353534` |
| on-surface | `#E5E2E1` |
| on-surface-variant | `#C4C9AC` |
| primary | `#FFB4AB` (acentos rojo pálido en dark) |
| primary-fixed-dim | `#FFB4AB` |
| error | `#FFB4AB` |
| outline | `#8E9379` |
| outline-variant | `#444933` |

### Tipografía

Fuentes: **Inter** (400/500/600/700) y **Geist** (400/500/600). Empaquetadas como assets en `app/assets/fonts/`, registradas en `pubspec.yaml`. Sin dependencia de red.

| Rol | Font | Size/Line | Weight | Notas |
|---|---|---|---|---|
| display | Inter | 48/52 | 700 | tracking -4% (balance total) |
| headline-lg | Inter | 32/38 | 600 | -2% |
| headline-lg-mobile | Inter | 24/28 | 600 | -1% (títulos de pantalla) |
| headline-md | Inter | 20/28 | 600 | títulos de card / filas |
| body-md | Inter | 16/24 | 400 | cuerpo |
| body-lg | Inter | 18/28 | 400 | montos grandes mono-override |
| mono-data | Geist | 14/20 | 500 | números, categorías, horas, metadata |
| label-caps | Geist | 12/12 | 600 | +0.1em uppercase: eyebrows, nav, chips, botones |

### Radios / Spacing / Efectos

| Token | Valor |
|---|---|
| radius-xl | 8px |
| radius-full | 12px (pills) |
| radius-md | 4px |
| unit | 4px |
| stack-sm | 8px |
| stack-md | 16px |
| stack-lg | 32px |
| gutter | 12px |
| margin / container-padding | 20px |
| card border | 1px `border-subtle` / `outline 10%` |
| card shadow | 0 1px 8px shadow-base |
| header/nav | `surface/80` + backdrop-blur-xl |
| glow primary | box-shadow `0 0 10px rgba(186,26,26,0.2)` |
| glow orb (cards) | radial `primary/5` blur-2xl esquina sup-der |
| alert bar | 4px izquierda `error` |

## 2. Navegación y shell

- **Bottom nav glass** (`surface/80` + blur + borde superior `outline/10`), height 64px, safe-area: **3 tabs** — Dashboard (icono `dashboard`), Insights (`monitoring`), History (`history`). Tab activa `primary` (#BA1A1A), inactivas `on-surface-variant`.
- **FAB del mentor** (56px, `primary` #BA1A1A, glow rojo, icono `smart_toy` — agente): **abajo-derecha, `bottom: 96px`** (por encima del nav), visible en las 3 tabs. Tap → abre **Chat modal full-screen dark** (ruta `/chat`, slide-up, SafeArea).
- **Header por pantalla** (height 64px, glass): eyebrow label-caps o título + **avatar redondo 32px** a la derecha → abre **Settings** (/settings, también full-screen push).
- GoRouter: StatefulShellRoute se mantiene, se reemplazan branches → `/`, `/insights`, `/history`; `/chat` y `/settings` rutas fuera del shell (overlay/modal). Estado de cada tab preservado.

## 3. Dashboard

1. **Hero centrado**: eyebrow `TOTAL LIQUIDITY` label-caps → display 48px con total → pill (`surface`, ring `outline-variant/30`, shadow-sm) con punto `primary` pulso + mono-data `+X% vs last month` (dato real: monto gastado del mes actual vs mes anterior; si no hay datos → pill vacío "No activity yet").
2. **Monthly Burn card** (`surface`, borde, gradient `primary/5`→transparent de fondo): label `MONTHLY BURN` + `$gastado / $límite` headline-md + % mono `primary`; **barra de progreso** height 2px con glow (CustomPaint: track `surface-container-highest`, fill `primary` con shadow roja, animación 1s ease-out).
   - Si no hay presupuesto configurado: la card muestra solo el gasto del mes (sin /límite).
3. **Alert card** (si el último veredicto del mentor es alert/warning): `surface` borde `error/30`, **barra izquierda 4px error**, icono warning en `error-container` rounded-lg 40px, título `error`, mensaje LLM, botón uppercase `ANALYZE DEVIATION` (borde inferior `error/30`) → abre `/chat` con pre-contexto del veredicto.
4. **Recent Ledger** (top 5): header `RECENT LEDGER` (headline-md) + `VIEW ALL` (mono primary) → `/history`. Filas: icono 40px rounded-lg (category) con ring, merchant body-md, metadata mono `Dining • Today, hh:mm`, monto `-$X` mono.
5. **Empty state**: si cero transacciones → hero sin monto + card "Sin datos" con CTA `+` primera captura (abre el add sheet).
6. Voice capture: botón mic se mantiene en el add sheet (sheet del botón `+` del header). El FAB inferior ahora es del chat.

## 4. Chat — modal dark siempre

- Fondo `#131313`; header: avatar 64px `surface-container-high` con **icono de agente Material (`smart_toy`) rojo** (offline), nombre **Vector**, subtitle label-caps `FINANCIAL INTELLIGENCE CORE`, botón cerrar (X) + Volver.
- Mensajes: burbuja mentor `surface-container-high` (borde `outline/10`, radius 16 con esquina sup-izq 4px, **shine superior** gradiente `primary/5`→transparent); cantidades mono-data `primary-fixed-dim` bold; pregunta del usuario alineada derecha `primary` (#FF3B30) texto `on-primary`.
- **Chips de acción** en la burbuja del mentor cuando el veredicto incluye severidad: `STOP BUYING` (outline) y `ADJUST BUDGET` (rojo) → insertan un mensaje de usuario (p.ej. "quiero parar estos gastos") al hilo.
- **Input bar glass** (bottom, border-t, blur): botón `+` (abre add sheet rápido), textarea auto-grow `surface-container`, **mic circular 48px `primary` glow** — dicta la pregunta a texto (speech ya implementado); mientras el LLM genera, hint `VECTOR IS TYPING...` mono 10px.
- Timestamps: mono 10px uppercase `VECTOR • 09:41 AM`.

## 5. History

- Header sticky (`background/90` blur): título `TRANSACTIONS` + botón `FILTER` pill + **chips horizontales scrollables** (`overflow-x-auto`, snap-x): `ALL` (activo: `primary/10` text+border primary/20) + chips por categoría existente con icono (DINING, GROCERIES, TRANSPORT, etc.) + chip `VOICE INPUT` (icono mic) filtrando `source == voice`.
- Lista agrupada por **día** con header sticky label-caps `TODAY, AGO 14` / `YESTERDAY, ...`; filas: avatar circular 48px `secondary-container/50` con icono de categoría (FILL 1), merchant headline-md, sub-línea mono `Category • [phone_iphone|mic|more_horiz] • hh:mm`, monto `-$X` mono a la derecha.
- **Income** (amount < 0, futuro): texto/icono `primary`, monto `+$X` `primary` (hoy la app solo trackea gastos — la UI lo soporta).
- Fila de voz: badge mic circular pequeño `primary` sobre la esquina del avatar.
- Empty state por filtro: "Sin transacciones en esta categoría".

## 6. Insights

- Header + grid (stack vertical) de tarjetas: cada insight del mentor LLM = card `surface-container/90` borde + glow orb sup-der (primary/5 blur) con:
  - Row: icono Material 18px `primary` + tema label-caps `primary` (p.ej. `CATEGORY: DINNING` — 6 variantes temáticas) + mono 12px time-ago (real: hace Xh).
  - Título headline-md + texto body-md con valores destacados (mono primary).
  - **Sparkline** (CustomPaint, 64px height): serie = gasto diario últimos 30 días; línea `primary` 1.5px + gradiente relleno `primary 20%→0`; si <2 puntos → ocultar y mostrar texto corto.
- Disclaimer legal pequeño al pie (body-md 11px, muted): idéntico espíritu al de referencia (educativo, no consejo financiero).
- Empty state: sin insights generados → tarjeta con copy + CTA al chat.

## 7. Settings + Add flow

- **Settings** reestilado con misma paleta: cards `surface` con rows (icono 40 rounded-lg + título + subtítulo + chevron + switch/material): modelo LLM (estado descarga: botón descargar con progreso), sync URL, notificaciones, clear data. Sin cambio funcional.
- **Add sheet** (bajar del botón `+` del header): modal con toggle **Manual / Voice** — manual = campos de texto reestilizados (`surface-container`, radius 8, focus ring primary); voice = el botón mic con estado grabando (pulse rojo `error` + glow). Flujo `AddTransactionFlow` intacto.

## 8. Testing

- Tests existentes de lógica (32) se mantienen verdes: los rediseños tocan solo widgets de presentación; `add_flow_test`, `budget_summary_test`, etc. no cambian.
- Ajustar `widget_test.dart` si referencia widgets Cupertino que desaparecen (nav/iconos).
- Nuevos assets de fuentes se registran (`flutter test` sigue corriendo offline).
- Verificación: `flutter analyze` + `flutter test` + build sim + smoke screenshot.