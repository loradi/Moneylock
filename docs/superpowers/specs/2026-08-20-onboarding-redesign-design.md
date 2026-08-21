# Onboarding redesign

Sub-project 5 of 5 in the larger onboarding/notifications/subscriptions/
mentor initiative (see [2026-08-17-budget-tab-auto-save-design.md](2026-08-17-budget-tab-auto-save-design.md)
for the full decomposition). Built last, on purpose, so onboarding can
showcase real, working features rather than description of features that
don't exist yet.

## Constraint

All UI copy is in English — standing rule, unchanged.

## Problem

`lib/features/onboarding/onboarding_screen.dart`'s 4-step flow (welcome →
"have you used a planner before?" → "what best describes your shopping
habits?" → a 3-item setup checklist) predates every feature built in this
initiative. The two survey questions write `onboarding_used_planner`/
`onboarding_shopping_habits` to the `Settings` key-value table via
`SettingsDao.completeOnboarding()`, but nothing in the app ever reads
those two keys back — dead data collected for no purpose. The setup
checklist mentions "Ask your Moneylock mentor" as one line with no
explanation of what that means, and has no entry for Subscriptions at all.

## Design

### 1. Remove the two unused survey questions

Delete `_ChoiceStep` usage for `usedPlanner`/`shoppingHabits` entirely.
`SettingsDao.completeOnboarding()` becomes a no-argument method that only
writes `onboarding_completed = 'true'` — no schema migration needed, the
`Settings` table is already a generic key-value store, removing two keys
nobody wrote a reader for is a pure code deletion, not a data migration.

### 2. New step: "Meet Vector"

Replaces the two removed survey steps, keeping the total step count close
to before (3 steps instead of 4: Welcome → Meet Vector → Setup checklist).
Describes, in the same visual style as the existing `_WelcomeStep`, what
the mentor can actually do today — grounded in real, shipped capabilities,
not aspirational copy:

- Find and answer questions about past transactions and subscriptions
  ("how much did I spend on groceries?", "what's my biggest expense?").
- Add, edit, or delete a transaction or subscription — always with a
  real Confirm button, never from a typed "yes".
- Change a budget limit on request.
- Give advice grounded in your actual spending data, never generic filler.

Presented as 2-3 short example prompts (e.g. "add Netflix for $15,
recurring the 20th", "what am I spending the most on?"), not a real
interactive chat — the on-device model's first-load latency makes a live
demo mid-onboarding a UX risk not worth taking for this step; description
plus real example phrasing is enough to set expectations correctly.

### 3. Setup checklist: add Subscriptions, keep everything else's shape

The existing `_SetupStep` pattern (a tappable `Card`/`Checkbox` row that
navigates to a real screen on tap) stays exactly as it is structurally.
Goes from 3 items to 4:

1. "Set your currency and budget" → navigates to Budget (unchanged,
   already wired).
2. "Add your first subscription" (new) → navigates to `/subscriptions`.
3. "Add your first expense" → stays exactly as it is today, no
   navigation action (`null`) — the original design already left this
   inert since there's no single "add" screen to jump to (it's a modal
   sheet reachable from the Dashboard's "+" button); not expanding this
   task's scope to wire that up.
4. "Ask your Moneylock mentor" → navigates to `/chat` (new — currently
   has no action either).

### 4. Navigation wiring

`OnboardingGate`/`OnboardingScreen` currently only receive an
`onOpenBudget` callback from `AppShell` (`lib/core/router.dart`), wired to
`navigationShell.goBranch(1)`. Add two more callbacks threading the same
way: `onOpenSubscriptions` (→ `context.push('/subscriptions')`, mirroring
how the existing mentor FAB already does `context.push('/chat')`) and
`onOpenChat` (→ `context.push('/chat')`).

## Testing

- `SettingsDao.completeOnboarding()`: DAO test confirming it writes only
  `onboarding_completed = 'true'`, and that `onboarding_used_planner`/
  `onboarding_shopping_habits` are never written (a two-line assertion
  against a fresh in-memory DB, no migration to test since nothing in the
  schema changes).
- `OnboardingScreen`: a widget test exercising step navigation (Welcome →
  Meet Vector → Setup checklist → Back) **without ever tapping "Start
  using Moneylock"** on the final step — `_next()` only touches
  `ref.read(appDatabaseProvider)` on that final tap, so a test that never
  reaches it needs no `appDatabaseProvider` override at all, sidestepping
  the `driftDatabase()`-under-`pumpAndSettle()` hang already documented
  elsewhere in this codebase's test history. This is the same reasoning
  that makes DAO-level testing preferred over full-interaction widget
  tests for DB-backed screens throughout this codebase.
