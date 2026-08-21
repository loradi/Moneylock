# LearnPath — Spec de Diseño

**Fecha:** 2026-08-17
**Estado:** Aprobado por el usuario
**Stack:** SwiftUI + SwiftData + Core ML (iOS 18+), Xcode 26+
**Motor de IA:** Gemma 4 E2B (Core ML, ~5.4 GB) — Qwen3.5-2B / Gemma 4 E4B intercambiables a futuro

---

## 1. Concepto

App de aprendizaje estilo Duolingo donde el **usuario elige el tema**. La IA local genera un *path* de aprendizaje con niveles de dificultad creciente. Cada nivel contiene lecciones con 4 tipos de ejercicios interactivos:

1. **Quiz** — opción múltiple
2. **Autocompletar** — fill-the-blank
3. **Ordenar pasos** — reorder (arrastrar a la secuencia correcta)
4. **Emparejar conceptos** — matching (dos columnas)

El progreso se persiste con SwiftData: niveles desbloqueados, lecciones completadas, XP.

## 2. Flujo del usuario

```
1. Escribir tema          →  "Física cuántica", "Historia de Roma", "Swift"
2. IA genera el PATH      →  árbol de niveles (fácil → difícil), cada uno con lecciones
3. Nivel N                →  lecciones con 4 tipos de ejercicios
4. Responder              →  validación instantánea + feedback (explicación de la IA)
5. Completar nivel        →  desbloquea el siguiente (progreso guardado en SwiftData)
```

## 3. Arquitectura (4 capas)

```
┌──────────────────────────────────────────────────┐
│ UI (SwiftUI)                                     │
│ TopicInputView → PathView → LessonView →         │
│ FeedbackView · ProgressViewModel (SwiftData)     │
├──────────────────────────────────────────────────┤
│ Orquestador (Swift)                              │
│ PathGenerator · LessonGenerator ·                │
│ ExerciseValidator · JSONParser                   │
├──────────────────────────────────────────────────┤
│ Motor de inferencia (Swift/Core ML)              │
│ LLMEngine (conforma ModelProvider) · Sampler ·   │
│ Tokenizer (KV-cache stateful, streaming)         │
├──────────────────────────────────────────────────┤
│ Modelo (descargado a Documents/Models)              │
│ Gemma 4 E2B-CoreML (mlboydaisuke) — 4 chunks       │
│ INT8 + embed q8 + tokenizer (hf_model/ incluido)   │
└──────────────────────────────────────────────────┘
```

## 4. Decisiones clave

### 4.1 La IA genera el contenido CON la respuesta embebida

En vez de evaluar semánticamente las respuestas (lento y frágil con modelos pequeños), la IA genera cada ejercicio como JSON con la solución incluida; `ExerciseValidator` compara contra ella.

```json
{ "type": "quiz",
  "prompt": "¿Qué es un quark?",
  "options": ["Partícula elemental", "Un tipo de estrella", "Un átomo", "Una fuerza"],
  "correctIndex": 0,
  "explanation": "..." }

{ "type": "fillBlank",
  "prompt": "El átomo está formado por protones, neutrones y ______",
  "correct": ["electrones"],
  "explanation": "..." }

{ "type": "reorder",
  "prompt": "Ordena los pasos del método científico",
  "steps": ["Observar", "Formular hipótesis", "Experimentar", "Concluir"],
  "correctOrder": [0, 1, 2, 3] }

{ "type": "matching",
  "prompt": "Empareja cada concepto",
  "left": ["ADN", "ARN", "Proteína"],
  "right": ["Ácido desoxirribonucleico", "Ácido ribonucleico", "Cadena de aminoácidos"],
  "correctPairs": [0, 1, 2] }
```

### 4.2 Generación en 2 fases

- **Path skeleton**: `tema → {niveles: [{título, descripción, dificultad}]}` — generado al crear el path.
- **Ejercicios on-demand**: al abrir una lección se generan 4-6 ejercicios. Respuestas cortas = menos errores de JSON.

### 4.3 Modelo intercambiable

`ModelProvider` es un protocolo: `generate(prompt:) -> AsyncThrowingStream<String, Error>`. `LLMEngine` (Gemma 4 E2B) lo conforma hoy; `QwenProvider`/`Gemma4E4BProvider` lo conformarán a futuro sin tocar el resto de la app.

### 4.4 Modelo elegido

| Modelo | Tamaño | Velocidad | Licencia | Nota |
|---|---|---|---|---|
| **Gemma 4 E2B** (elegido) | 5.4 GB | ~20 tok/s | Gemma TOS | 4 chunks INT8 + embed q8, tokenizer incluido |
| Gemma 4 E4B (futuro) | 5.5 GB | ~15.7 tok/s | Gemma TOS | Requiere iPhone 12+ GB RAM |

Repo: `mlboydaisuke/gemma-4-E2B-coreml` (rama `n1024`). Layout estándar compatible con `CoreMLLLM.load(repo:)` — el tokenizer viene incluido en `hf_model/`.

## 5. Componentes

| Componente | Responsabilidad | Depende de |
|---|---|---|
| `Tokenizer` | encode/decode texto ↔ tokens | `tokenizer.json` en bundle |
| `Sampler` | elige siguiente token (temperature, top-k/top-p) | — |
| `LLMEngine` | loop autoregresivo con KV-cache stateful, streaming, stop tokens | Core ML `MLModel` |
| `ModelLoader` | carga/libera los `.mlmodelc`, gestión de memoria | Core ML |
| `PathGenerator` | tema → JSON de path skeleton; reintentos si falla parseo | ModelProvider |
| `LessonGenerator` | nivel → JSON de ejercicios (con respuesta embebida) | ModelProvider |
| `JSONParser` | extrae JSON de la respuesta (primer `{` … último `}`), decodifica, reintenta | — |
| `ExerciseValidator` | quiz/reorder/matching = comparación exacta; fillBlank = normalización (minúsculas, sin acentos, espacios dobles) | — |
| `ProgressViewModel` | niveles desbloqueados, lecciones completadas, XP | SwiftData |
| Vistas | `TopicInputView`, `PathView`, `LessonView`, `FeedbackView` + 4 vistas de ejercicio | ProgressViewModel |

## 6. Manejo de errores

- **JSON inválido** (lo más común): hasta 2 reintentos con prompt corregido; fallback a formato plano.
- **Contexto excedido**: truncar historial con ventana deslizante.
- **Modelo no cargado / memoria insuficiente**: pantalla de error clara; liberar modelo (`nil`) al pasar a background.
- **Respuesta vacía / solo stop token**: reintento con prompt simplificado.
- **Térmica**: `maxTokens` 400–800 por llamada, indicador de progreso, cancelación al salir de pantalla.

## 7. Persistencia (SwiftData)

- `PathRecord`: tema, niveles, fecha de creación.
- `LevelRecord`: título, dificultad, desbloqueado, completado.
- `LessonRecord`: ejercicios completados.
- `XP`: total acumulado.

## 8. Testing

- Unit tests: `ExerciseValidator` (4 tipos + casos límite de normalización: acentos, mayúsculas, respuestas múltiples), `JSONParser` (JSON embebido en texto, inválido, reintentos), `Tokenizer` (round-trip encode/decode).
- Smoke test del modelo en simulador (requiere Mac Apple Silicon).
- Prueba end-to-end en iPhone real: velocidad de generación, memoria, temperatura.

## 9. Fases de implementación

1. **Fase 1** — Proyecto base + modelo integrado + botón "Probar IA" (streaming en consola)
2. **Fase 2** — Capa de dominio (structs Codable: Path/Level/Lesson/Exercise/Answer) + protocolo `ModelProvider`
3. **Fase 3** — `PathGenerator` + `LessonGenerator` + `JSONParser` (JSON válido en consola)
4. **Fase 4** — `ExerciseValidator` + unit tests
5. **Fase 5** — SwiftData (`PathRecord`, `LevelRecord`, `LessonRecord`, `XP`) + `ProgressViewModel`
6. **Fase 6** — UI completa (TopicInput → Path → Lesson → Feedback)
7. **Fase 7** — Robustez (errores, térmica, memoria, contexto)
8. **Fase 8** — Testing final (unit + smoke + dispositivo)
9. **Fase 9** — Swap a Gemma 4B (futuro, ya diseñado vía `ModelProvider`)

## 10. Fuera de alcance (YAGNI)

- Rachas, tienda, sonidos, multijugador.
- Descarga on-demand del modelo (MVP embebe 2.8 GB en bundle; se evalúa después).
- RAG / subir apuntes.
- Modo chat libre (solo feedback por ejercicio).