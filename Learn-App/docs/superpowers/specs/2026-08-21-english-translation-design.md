# Translate LearnPath app to English

## Problem

The LearnPath app (source, AI prompts, UI copy, error messages, code
comments, and test fixtures) is written in Spanish. The user wants
the whole app in English.

## Scope

Full sweep — all Spanish content in every file, including test
fixtures. 15 files carry Spanish content (confirmed via
`grep -rl "[áéíóúñ¿¡]"`):

**AI layer** (highest user impact — controls the *language of
AI-generated content*, not just app chrome):
- `LearnPath/AI/PathGenerator.swift` — the prompt instructing the
  on-device LLM to generate the learning plan
- `LearnPath/AI/LessonGenerator.swift` — the prompt instructing the
  LLM to generate lesson exercises
- `LearnPath/AI/JSONParser.swift` — error messages + comments
- `LearnPath/AI/LLMEngine.swift` — comments

**User-facing text:**
- `LearnPath/App/AppModel.swift`, `LearnPath/App/ContentView.swift`
- `LearnPath/Persistence/ProgressViewModel.swift`,
  `LearnPath/Persistence/SwiftDataModels.swift`
- `LearnPath/Views/ExerciseViews.swift`, `FeedbackView.swift`,
  `LessonView.swift`, `LevelDetailView.swift`, `TopicInputView.swift`

**Validation (includes one functional fix):**
- `LearnPath/Validation/ExerciseValidator.swift` — comments, AND a
  hardcoded `Locale(identifier: "es")` (line 9) used for
  accent/case-insensitive answer-matching. Once lesson content
  generates in English, this must become `Locale(identifier: "en_US")`
  — otherwise fill-in-the-blank answer normalization uses the wrong
  locale's folding rules.

**Tests:**
- `LearnPathTests/JSONParserTests.swift` — Spanish sample JSON
  fixtures (e.g. `"topic": "Física"`)
- `LearnPathTests/ExerciseValidatorTests.swift` — Spanish exercise
  fixtures, including `testFillBlankToleratesAccentsAndCase` which
  specifically exercises accent folding (`"París"` → `"PARIS"`) and
  must be replaced with an equivalent English accent-folding case
  (e.g. `"café"` → `"CAFE"`) so the locale change stays covered.

## Approach

Translate + polish (not strict 1:1) — clean up awkward phrasing or
verbose copy while translating, without changing behavior or meaning.
Comments included in the sweep.

Work file-by-file in the four groups above. After each group:
1. `grep -c "[áéíóúñ¿¡]"` across the group's files → expect 0
2. Re-run affected tests (`JSONParserTests`, `ExerciseValidatorTests`
   after the Validation group)

Final step: full `LearnPathTests` suite run + one archive build (same
technique used for the icon/App Store fixes) to confirm nothing
broke.

## Out of scope

- App display name (`CFBundleDisplayName` stays "LearnPath" — user
  confirmed no change beyond the icon).
- Any new features or UX changes beyond copy quality.
