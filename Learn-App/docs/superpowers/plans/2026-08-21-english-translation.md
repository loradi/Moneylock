# English Translation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Translate all Spanish content in the LearnPath app — AI prompts, user-facing text, error messages, code comments, and test fixtures — to English.

**Architecture:** File-by-file translation grouped by layer (AI prompts → validation/locale fix → models/app → views → test fixtures), each group ending in a grep-verified zero-Spanish-remaining check plus the relevant test run. Unlike algorithmic tasks, translation steps don't pre-specify literal replacement text (that would mean writing the whole translation twice) — each step instead names the exact file, the concrete mechanical transformation ("translate every string literal and comment to natural English, preserving exact behavior/meaning, applying light polish to awkward phrasing"), and an unambiguous, automatable verification (grep pattern, test command).

**Tech Stack:** Swift, XCTest, `grep`, `xcodebuild`.

## Global Constraints

- Every string's *meaning and behavior* must be preserved — this is translation + light polish, not a rewrite. No new features, no UX changes.
- `Locale(identifier: "es")` in `ExerciseValidator.swift` must become `Locale(identifier: "en_US")` once lesson content generates in English (see Task 2).
- After each task, `grep -c "[áéíóúñ¿¡]" <files>` across that task's files must return 0.
- `CFBundleDisplayName` stays "LearnPath" — out of scope (user confirmed).

---

### Task 1: Translate the AI layer

**Files:**
- Modify: `LearnPath/AI/PathGenerator.swift`
- Modify: `LearnPath/AI/LessonGenerator.swift`
- Modify: `LearnPath/AI/JSONParser.swift`
- Modify: `LearnPath/AI/LLMEngine.swift`

**Interfaces:**
- Consumes: nothing new
- Produces: no signature changes — `GenerationError`/`JSONParsingError` enums, `PathGenerator.generatePath(topic:)`, `LessonGenerator.generateLesson(...)` keep identical signatures; only their internal prompt strings, error message strings, and comments change language.

- [ ] **Step 1: Translate all four files**

For each file, translate every Spanish string literal (prompts, `LocalizedError.errorDescription` cases) and every Spanish comment/doc-comment to natural English. This is the prompt text the on-device LLM receives, so keep the same structure (rules, exact JSON schema example, instruction to respond with JSON only) — only the language changes. Apply light polish to any awkward phrasing found along the way.

- [ ] **Step 2: Verify no Spanish remains**

Run: `grep -c "[áéíóúñ¿¡]" LearnPath/AI/PathGenerator.swift LearnPath/AI/LessonGenerator.swift LearnPath/AI/JSONParser.swift LearnPath/AI/LLMEngine.swift`
Expected: `0` for every file (or `grep` reports "no matches" per file).

- [ ] **Step 3: Run JSONParserTests (exercises PathGenerator's PathSkeleton/Exercise decoding path)**

Run: `cd Learn-App && xcodebuild -project LearnPath.xcodeproj -scheme LearnPath -destination "platform=iOS Simulator,name=iPhone 17" test -only-testing:LearnPathTests/JSONParserTests`
Expected: all tests pass (existing fixtures still English-agnostic at this point — Task 5 translates the fixtures themselves).

- [ ] **Step 4: Commit**

```bash
git add Learn-App/LearnPath/AI/PathGenerator.swift Learn-App/LearnPath/AI/LessonGenerator.swift Learn-App/LearnPath/AI/JSONParser.swift Learn-App/LearnPath/AI/LLMEngine.swift
git commit -m "feat: translate AI prompts and error messages to English"
```

---

### Task 2: Translate validation layer + fix locale

**Files:**
- Modify: `LearnPath/Validation/ExerciseValidator.swift`
- Modify: `LearnPathTests/ExerciseValidatorTests.swift`

**Interfaces:**
- Consumes: nothing new
- Produces: `ExerciseValidator.normalize(_:)` and `.validate(_:answer:)` keep identical signatures; only the hardcoded `Locale` value and comments change.

- [ ] **Step 1: Fix the locale and translate comments**

In `LearnPath/Validation/ExerciseValidator.swift`, change line 9's `Locale(identifier: "es")` to `Locale(identifier: "en_US")`. Translate the doc comment on `normalize(_:)` to English (e.g. "Normalizes text for tolerant comparison: lowercase, no accents, no punctuation, no double spaces.").

- [ ] **Step 2: Translate test fixtures in ExerciseValidatorTests.swift**

Replace every Spanish exercise prompt/option/answer with an equivalent English one, preserving what each test actually checks:
- `testNormalizeRemovesAccentsAndCase`: `"EléCTRONES"` → an example that still has mixed case and an accent, e.g. `"ElÉCTRONS"` → expected `"electrons"` (keep at least one accented character so the diacritic-folding path stays exercised)
- `testNormalizeRemovesPunctuationAndDoubleSpaces`: keep the punctuation/double-space shape, translate words (e.g. `"  protons,   neutrons. "` → `"protons neutrons"`)
- `testNormalizeNumbersAreKept`: `"Fórmula H2O"` → `"Fórmula H2O"` stays (keep the accent for coverage) → expected `"formula h2o"`
- `testFillBlankToleratesAccentsAndCase`: replace `"París"`/`"PARIS"` with an English-context word that still has a diacritic, to keep exercising accent-folding: `"café"` → answer `"CAFE"`, prompt e.g. `"A coffee shop is also called a ______"`
- All quiz/reorder/matching prompts, options, and explanations: translate to equivalent English content (e.g. `"¿Qué es un quark?"` → `"What is a quark?"`, `"Ordena el método científico"` / `["Observar", "Hipótesis", "Experimentar", "Concluir"]` → `"Order the steps of the scientific method"` / `["Observe", "Hypothesize", "Experiment", "Conclude"]`)
- MARK comments (`// MARK: - Normalización`, etc.) → English section names

- [ ] **Step 3: Run the tests**

Run: `cd Learn-App && xcodebuild -project LearnPath.xcodeproj -scheme LearnPath -destination "platform=iOS Simulator,name=iPhone 17" test -only-testing:LearnPathTests/ExerciseValidatorTests`
Expected: all tests pass, including the rewritten `testFillBlankToleratesAccentsAndCase` (confirms the `en_US` locale still folds `café`→`cafe` correctly).

- [ ] **Step 4: Verify remaining Spanish is only the intentional diacritic-coverage characters**

Run: `grep -n "[áéíóúñ¿¡]" LearnPath/Validation/ExerciseValidator.swift LearnPathTests/ExerciseValidatorTests.swift`
Expected: only the deliberate accented English-context words from Step 2 (café, Fórmula, ElÉCTRONS) — no leftover Spanish sentences/comments.

- [ ] **Step 5: Commit**

```bash
git add Learn-App/LearnPath/Validation/ExerciseValidator.swift Learn-App/LearnPathTests/ExerciseValidatorTests.swift
git commit -m "fix: switch answer-matching locale to en_US, translate validation layer"
```

---

### Task 3: Translate models, persistence, and app layer

**Files:**
- Modify: `LearnPath/App/AppModel.swift`
- Modify: `LearnPath/App/ContentView.swift`
- Modify: `LearnPath/Persistence/ProgressViewModel.swift`
- Modify: `LearnPath/Persistence/SwiftDataModels.swift`

**Interfaces:**
- Consumes: nothing new
- Produces: no signature changes — only string literals (status text, e.g. `.generatingLesson: return "Preparando la lección…"`) and comments change language.

- [ ] **Step 1: Translate all four files**

Translate every Spanish string literal (UI status strings, default values) and comment to natural English, applying light polish where phrasing is awkward.

- [ ] **Step 2: Verify no Spanish remains**

Run: `grep -c "[áéíóúñ¿¡]" LearnPath/App/AppModel.swift LearnPath/App/ContentView.swift LearnPath/Persistence/ProgressViewModel.swift LearnPath/Persistence/SwiftDataModels.swift`
Expected: `0` for every file.

- [ ] **Step 3: Build the app target to confirm no compile errors**

Run: `cd Learn-App && xcodebuild -project LearnPath.xcodeproj -scheme LearnPath -destination "platform=iOS Simulator,name=iPhone 17" build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Learn-App/LearnPath/App/AppModel.swift Learn-App/LearnPath/App/ContentView.swift Learn-App/LearnPath/Persistence/ProgressViewModel.swift Learn-App/LearnPath/Persistence/SwiftDataModels.swift
git commit -m "feat: translate app and persistence layer to English"
```

---

### Task 4: Translate views

**Files:**
- Modify: `LearnPath/Views/ExerciseViews.swift`
- Modify: `LearnPath/Views/FeedbackView.swift`
- Modify: `LearnPath/Views/LessonView.swift`
- Modify: `LearnPath/Views/LevelDetailView.swift`
- Modify: `LearnPath/Views/TopicInputView.swift`

**Interfaces:**
- Consumes: nothing new
- Produces: no signature changes — only `Text`, button labels, placeholder strings, and comments change language.

- [ ] **Step 1: Translate all five files**

Translate every Spanish string literal and comment to natural English (e.g. `"¿Qué quieres aprender?"` → `"What do you want to learn?"`, `"Escribe cualquier tema y la IA creará tu plan de aprendizaje paso a paso."` → `"Type any topic and the AI will build your step-by-step learning plan."`, placeholder `"Ej: Física cuántica, Historia de Roma, Swift…"` → `"E.g. Quantum physics, Roman history, Swift…"`). Apply light polish where phrasing is awkward.

- [ ] **Step 2: Verify no Spanish remains**

Run: `grep -c "[áéíóúñ¿¡]" LearnPath/Views/ExerciseViews.swift LearnPath/Views/FeedbackView.swift LearnPath/Views/LessonView.swift LearnPath/Views/LevelDetailView.swift LearnPath/Views/TopicInputView.swift`
Expected: `0` for every file.

- [ ] **Step 3: Build the app target to confirm no compile errors**

Run: `cd Learn-App && xcodebuild -project LearnPath.xcodeproj -scheme LearnPath -destination "platform=iOS Simulator,name=iPhone 17" build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Learn-App/LearnPath/Views/
git commit -m "feat: translate views to English"
```

---

### Task 5: Translate JSONParserTests fixtures

**Files:**
- Modify: `LearnPathTests/JSONParserTests.swift`

**Interfaces:**
- Consumes: nothing new
- Produces: no signature changes — only the Spanish sample JSON strings inside each test body change (e.g. `"topic": "Física"` → `"topic": "Physics"`, `"¿Qué es X?"` → `"What is X?"`, `"porque sí"` → `"because it is"`).

- [ ] **Step 1: Translate all Spanish fixture content**

Replace every Spanish word/phrase in the test fixtures with an equivalent English one, keeping the JSON structure and test assertions identical (only the content language changes, not the shape being tested — brace-balancing, nested braces, escaped quotes, etc.).

- [ ] **Step 2: Verify no Spanish remains**

Run: `grep -c "[áéíóúñ¿¡]" LearnPathTests/JSONParserTests.swift`
Expected: `0`

- [ ] **Step 3: Run the tests**

Run: `cd Learn-App && xcodebuild -project LearnPath.xcodeproj -scheme LearnPath -destination "platform=iOS Simulator,name=iPhone 17" test -only-testing:LearnPathTests/JSONParserTests`
Expected: all 11 tests pass.

- [ ] **Step 4: Commit**

```bash
git add Learn-App/LearnPathTests/JSONParserTests.swift
git commit -m "test: translate JSONParserTests fixtures to English"
```

---

### Task 6: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Confirm zero unintended Spanish remains anywhere in the app**

Run: `cd Learn-App && grep -rn "[áéíóúñ¿¡]" LearnPath LearnPathTests --include="*.swift"`
Expected: no output, or only the deliberate accented English-context words from Task 2 Step 2 (café, Fórmula, ElÉCTRONS).

- [ ] **Step 2: Run the full test suite**

Run: `cd Learn-App && xcodebuild -project LearnPath.xcodeproj -scheme LearnPath -destination "platform=iOS Simulator,name=iPhone 17" test`
Expected: all tests pass, 0 failures.

- [ ] **Step 3: Archive-build to confirm a clean release build**

Run:
```bash
cd Learn-App
xcodegen generate
rm -rf /tmp/lerni-final-archive /tmp/lerni-final-dd
xcodebuild -project LearnPath.xcodeproj -scheme LearnPath -configuration Release \
  -destination "generic/platform=iOS" -derivedDataPath /tmp/lerni-final-dd \
  -archivePath /tmp/lerni-final-archive/LearnPath.xcarchive archive CODE_SIGNING_ALLOWED=NO
```
Expected: `** ARCHIVE SUCCEEDED **`

- [ ] **Step 4: Clean up scratch artifacts**

```bash
rm -rf /tmp/lerni-final-archive /tmp/lerni-final-dd
```
