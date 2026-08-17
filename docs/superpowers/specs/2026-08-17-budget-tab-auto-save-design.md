# Budget tab: auto-save + swipe-to-delete

Sub-project 1 of 5 in the larger onboarding/notifications/subscriptions/mentor
initiative. See conversation context: the full initiative is decomposed into
(1) this spec, (2) notification scheduling, (3) subscriptions tracking,
(4) mentor data access + scope expansion, (5) onboarding redesign — built in
that order so onboarding can showcase real, working features.

## Constraint

All UI copy is in English. No Spanish (or any other language) strings in
user-facing text, ever — this applies to every sub-project in the initiative,
not just this one.

## Problem

`lib/features/budget/budget_screen.dart`'s category rows require two manual
icon-button taps: a checkmark to save the cap amount, and a remove-circle to
delete the category (behind a confirm dialog). Additionally, the keyboard
does not dismiss when tapping outside a text field — the only way out today
is tapping the currency dropdown, which is a discovered bug blocking the
auto-save flow (a stuck keyboard prevents seeing the row below it).

## Scope

`lib/features/budget/budget_screen.dart` only — `_BudgetRow`,
`_BudgetScreenState`, and the `Scaffold`/`body` wiring around them. No DB
schema changes, no other files.

## Design

### 1. Global keyboard dismiss

Wrap the `Scaffold.body` in `GestureDetector(onTap: () =>
FocusScope.of(context).unfocus())` so any tap outside an input closes the
keyboard. The budget-cap `TextField` and the custom-cycle-days `TextField`
get `textInputAction: TextInputAction.done`, so the keyboard's own "Done"
button also dismisses it.

### 2. Auto-save (debounce + on-blur)

- Remove the checkmark `IconButton`.
- `_BudgetRow` starts a 600ms debounce `Timer` on every text change to the
  cap field; when it fires, it calls `onSave(category, text)`.
- A `FocusNode` on the cap field also calls `onSave` immediately on focus
  loss (tap-away or keyboard "Done"), canceling any pending debounce timer
  so there's no double-save race.
- On success: no `SnackBar`. A small checkmark fades in next to the field
  for ~200ms as non-intrusive confirmation.
- On failure (invalid amount, DB error): the existing error `SnackBar`
  still shows.

### 3. Swipe-to-delete

- Remove the remove-circle `IconButton`.
- Each `_BudgetRow` wraps in `Dismissible(key: ValueKey(category),
  direction: DismissDirection.endToStart, background: <red trash-icon
  background>)`.
- `confirmDismiss` reuses the existing removal `AlertDialog` copy/logic
  (currently in `_removeCategory`). Cancel → `Dismissible` snaps back
  (return `false`). Confirm → row is removed and `categoriesDao.remove`
  is called (return `true`).
- Default and custom categories behave identically, same as today.

## Testing

One widget test: typing into the cap field and letting the debounce fire
calls `budgetsDao.upsert` without tapping any button. One widget test:
swiping a row and confirming the dialog calls `categoriesDao.remove`.
