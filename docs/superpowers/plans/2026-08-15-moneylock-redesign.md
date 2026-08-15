# Moneylock UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reestilizar la UI de Moneylock (hoy Cupertino azul) al sistema de diseño custom **Red & White** basado en la referencia "Kinetic Intel": Material 3 custom, tipografía Inter + Geist empaquetada offline, nav de 3 tabs + FAB del mentor, chat como modal dark siempre, pantalla History nueva, Insight cards con sparkline, Settings y Add sheet reestilados. Sin cambio de lógica de negocio/LLM/sync.

**Architecture:** App Flutter offline-first. La UI pasa de `CupertinoApp.router` a `MaterialApp.router` con `ThemeData` custom (tokens en `app/lib/theme/app_theme.dart`). go_router conserva `StatefulShellRoute.indexedStack` con **3 branches** (`/`, `/insights`, `/history`) + rutas overlay `/chat` y `/settings` (fuera del shell, root navigator). FAB del mentor y avatar del header disparan `context.push`. Los datos se consumen de los providers existentes (`transactionsStreamProvider`, `budgetSummaryProvider`, `insightsProvider`, `messagesStreamProvider`).

**Tech Stack:** Flutter, Riverpod, go_router (rootNavigatorKey), Material 3, CustomPaint (sparkline, barra glow), `speech_to_text` (mic del chat), fuentes Inter 4.1 + Geist 1.7.2 como assets. Sin nuevas dependencias de red/runtime.

**Spec:** `docs/superpowers/specs/2026-08-15-moneylock-redesign-design.md`

## Global Constraints

- **Offline-first**: fuentes como assets locales, sin imágenes remotas, sin fetch en runtime.
- **Idioma UI: inglés** (labels, eyebrows, copy visible). El copy de lógica (prompts LLM, mensajes del mentor) NO cambia.
- **Sin cambio de funcionalidad**: categorizador, mentor, sync, dedup, speech y providers intactos. **Única excepción funcional**: el mic del composer del chat dicta la pregunta a texto vía `SpeechToTextService` (affordance del rediseño).
- **Única adición de datos** (requerida por spec §3.3 y §4): columna `severity` en `mentor_messages` para la alert card y los action chips. Se hace con migración drift (schemaVersion 1→2), sin tocar lógica de negocio.
- **Contrato de test que NO debe romperse**: `chat_amount_test.dart` importa `hasMonetaryAmount` desde `package:moneylock/features/chat/chat_screen.dart` → el export debe permanecer en ese archivo.
- Tests de lógica existentes (32 Dart) se mantienen verdes; `add_flow_test` no cambia (solo se añade columna con default).
- Commits por tarea, mensajes en inglés (`feat:`, `test:`, `fix:`, `refactor:`).
- Cada tarea con código termina con `flutter analyze` limpio y `flutter test` en verde (desde `app/`).
- `flutter_test_config.dart` ya setea PathProviderPlatform fake → los widget tests con providers override no requieren DB real.

---

### Task 1: Assets de fuentes (Inter + Geist) y registro en pubspec

**Files:**
- Create: `app/assets/fonts/` (7 archivos .ttf)
- Modify: `app/pubspec.yaml`

**Interfaces:**
- Consumes: nada.
- Produces: fuentes `Inter` (400/500/600/700) y `Geist` (400/500/600) registradas para uso vía `fontFamily: 'Inter'` / `'Geist'`.

- [ ] **Step 1: Descargar y extraer los zips (URLs verificadas 2026-08-15)**
  ```bash
  mkdir -p /tmp/moneylock_fonts && cd /tmp/moneylock_fonts
  curl -sL -o inter.zip "https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip"
  curl -sL -o geist.zip "https://github.com/vercel/geist-font/releases/download/v1.7.2/geist-font-v1.7.2.zip"
  unzip -q inter.zip -d inter && unzip -q geist.zip -d geist
  ```
  Expected: `inter/extras/ttf/Inter-{Regular,Medium,SemiBold,Bold}.ttf` y `geist/geist-font/Geist/ttf/Geist-{Regular,Medium,SemiBold}.ttf` existen.

- [ ] **Step 2: Copiar fuentes al proyecto**
  ```bash
  mkdir -p /Users/diego/Documents/Moneylock/app/assets/fonts
  cp /tmp/moneylock_fonts/inter/extras/ttf/Inter-{Regular,Medium,SemiBold,Bold}.ttf /Users/diego/Documents/Moneylock/app/assets/fonts/
  cp /tmp/moneylock_fonts/geist/geist-font/Geist/ttf/Geist-{Regular,Medium,SemiBold}.ttf /Users/diego/Documents/Moneylock/app/assets/fonts/
  ls -la /Users/diego/Documents/Moneylock/app/assets/fonts/
  ```
  Expected: 7 archivos .ttf.

- [ ] **Step 3: Registrar fuentes en `app/pubspec.yaml`**
  ```yaml
  flutter:
    uses-material-design: true
    fonts:
      - family: Inter
        fonts:
          - asset: assets/fonts/Inter-Regular.ttf
          - asset: assets/fonts/Inter-Medium.ttf
            weight: 500
          - asset: assets/fonts/Inter-SemiBold.ttf
            weight: 600
          - asset: assets/fonts/Inter-Bold.ttf
            weight: 700
      - family: Geist
        fonts:
          - asset: assets/fonts/Geist-Regular.ttf
          - asset: assets/fonts/Geist-Medium.ttf
            weight: 500
          - asset: assets/fonts/Geist-SemiBold.ttf
            weight: 600
  ```

- [ ] **Step 4: Verificar**
  Run: `cd app && flutter analyze && flutter test test/chat_amount_test.dart`
  Expected: analyze limpio, test verde (el registro de fuentes no rompe nada; `flutter test` corre offline).

- [ ] **Step 5: Commit**
  ```bash
  git add app/assets/fonts app/pubspec.yaml
  git commit -m "feat: bundle Inter and Geist fonts as assets"
  ```

---

### Task 2: Design tokens y theme (app_theme.dart) + test

**Files:**
- Create: `app/lib/theme/app_theme.dart`
- Create: `app/test/app_theme_test.dart`

**Interfaces:**
- Consumes: nada (constantes puras + `ThemeData`).
- Produces:
  - `AppColors` (light + dark), `AppSpacing`, `AppRadii`, `AppShadows`.
  - `AppTextStyles` (display/headline-lg/headline-lg-mobile/headline-md/body-md/body-lg/mono-data/label-caps).
  - `buildAppTheme()` → `ThemeData` (Material 3, light, Red & White).

- [ ] **Step 1: Escribir el test que falla**
  `app/test/app_theme_test.dart`:
  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:moneylock/theme/app_theme.dart';

  void main() {
    test('tokens de color light matchean la spec', () {
      expect(AppColors.primary, const Color(0xFFBA1A1A));
      expect(AppColors.primaryBright, const Color(0xFFFF3B30));
      expect(AppColors.onSurface, const Color(0xFF131313));
      expect(AppColors.background, const Color(0xFFF9F9FA));
    });

    test('texto mono-data usa Geist y label-caps usan +0.1em uppercase', () {
      final label = AppTextStyles.labelCaps;
      expect(label.fontFamily, 'Geist');
      expect(label.fontWeight, FontWeight.w600);
      expect(label.letterSpacing, 0.1);
    });

    test('buildAppTheme produce Material3 light con primary rojo', () {
      final theme = buildAppTheme();
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.primary, AppColors.primary);
      expect(theme.fontFamily, 'Inter');
    });
  }
  ```

- [ ] **Step 2: Run test para confirmar que falla**
  Run: `cd app && flutter test test/app_theme_test.dart`
  Expected: FAIL — `app_theme.dart` no existe.

- [ ] **Step 3: Implementar `app/lib/theme/app_theme.dart`**
  ```dart
  import 'package:flutter/material.dart';

  abstract final class AppColors {
    static const primary = Color(0xFFBA1A1A);
    static const primaryBright = Color(0xFFFF3B30);
    static const onPrimary = Color(0xFFFFFFFF);
    static const primaryContainer = Color(0xFFFFDAD6);
    static const onPrimaryContainer = Color(0xFF410002);
    static const primaryFixedDim = Color(0xFFFFB4AB);

    static const background = Color(0xFFF9F9FA);
    static const surface = Color(0xFFFFFFFF);
    static const surfaceContainer = Color(0xFFF4F4F5);
    static const surfaceContainerLow = Color(0xFFF3F3F4);
    static const surfaceContainerHigh = Color(0xFFE8E8E9);
    static const surfaceContainerHighest = Color(0xFFE2E2E3);
    static const surfaceVariant = Color(0xFFE2E2E3);
    static const onSurface = Color(0xFF131313);
    static const onSurfaceVariant = Color(0xFF444933);
    static const outline = Color(0xFF747A60);
    static const outlineVariant = Color(0xFFC4C9AC);
    static const borderSubtle = Color(0xFFE4E4E7);
    static const error = Color(0xFFBA1A1A);
    static const errorContainer = Color(0xFFFFDAD6);
    static const onErrorContainer = Color(0xFF93000A);
    static const shadowBase = Color(0x0A000000);

    static const darkBackground = Color(0xFF131313);
    static const darkSurface = Color(0xFF131313);
    static const darkSurfaceContainer = Color(0xFF201F1F);
    static const darkSurfaceContainerLow = Color(0xFF1C1B1B);
    static const darkSurfaceContainerHigh = Color(0xFF2A2A2A);
    static const darkSurfaceContainerHighest = Color(0xFF353534);
    static const darkOnSurface = Color(0xFFE5E2E1);
    static const darkOnSurfaceVariant = Color(0xFFC4C9AC);
    static const darkPrimary = Color(0xFFFFB4AB);
    static const darkOutline = Color(0xFF8E9379);
    static const darkOutlineVariant = Color(0xFF444933);
  }

  abstract final class AppSpacing {
    static const unit = 4.0;
    static const sm = 8.0;
    static const md = 16.0;
    static const lg = 32.0;
    static const gutter = 12.0;
    static const margin = 20.0;
  }

  abstract final class AppRadii {
    static const md = 4.0;
    static const xl = 8.0;
    static const full = 12.0;
  }

  abstract final class AppShadows {
    static const card = <BoxShadow>[
      BoxShadow(color: AppColors.shadowBase, blurRadius: 8, offset: Offset(0, 1)),
    ];
    static const glow = <BoxShadow>[
      BoxShadow(color: Color(0x33BA1A1A), blurRadius: 10),
    ];
  }

  abstract final class AppTextStyles {
    static const display = TextStyle(
        fontFamily: 'Inter', fontSize: 48, height: 52 / 48, fontWeight: FontWeight.w700,
        letterSpacing: -0.04);
    static const headlineLg = TextStyle(
        fontFamily: 'Inter', fontSize: 32, height: 38 / 32, fontWeight: FontWeight.w600,
        letterSpacing: -0.02);
    static const headlineLgMobile = TextStyle(
        fontFamily: 'Inter', fontSize: 24, height: 28 / 24, fontWeight: FontWeight.w600,
        letterSpacing: -0.01);
    static const headlineMd = TextStyle(
        fontFamily: 'Inter', fontSize: 20, height: 28 / 20, fontWeight: FontWeight.w600);
    static const bodyMd = TextStyle(
        fontFamily: 'Inter', fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w400);
    static const bodyLg = TextStyle(
        fontFamily: 'Inter', fontSize: 18, height: 28 / 18, fontWeight: FontWeight.w400);
    static const monoData = TextStyle(
        fontFamily: 'Geist', fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500);
    static const labelCaps = TextStyle(
        fontFamily: 'Geist', fontSize: 12, height: 1, fontWeight: FontWeight.w600,
        letterSpacing: 0.1);
  }

  ThemeData buildAppTheme() {
    final scheme = const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      secondaryContainer: Color(0xFFE5E2E1),
      onSecondary: AppColors.onPrimary,
      tertiary: Color(0xFF4F616E),
      tertiaryContainer: Color(0xFFDCEFFF),
      error: AppColors.error,
      onError: AppColors.onPrimary,
      errorContainer: AppColors.errorContainer,
      onErrorContainer: AppColors.onErrorContainer,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      surfaceContainerHighest: AppColors.surfaceContainerHighest,
      surfaceContainerHigh: AppColors.surfaceContainerHigh,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineVariant,
      shadow: AppColors.shadowBase,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
    );
  }
  ```

- [ ] **Step 4: Verificar**
  Run: `cd app && flutter analyze && flutter test test/app_theme_test.dart`
  Expected: verde.

- [ ] **Step 5: Commit**
  ```bash
  git add app/lib/theme app/test/app_theme_test.dart
  git commit -m "feat: design tokens and Material 3 theme (Red & White)"
  ```

---

### Task 3: Mapeo de categoría → icono/color + utilidades de formato

**Files:**
- Create: `app/lib/theme/category_style.dart`
- Create: `app/test/category_style_test.dart`
- Modify: `app/lib/core/format.dart` (añadir `fmtTime`, `fmtTimeAgo`, `fmtDayGroup`)

**Interfaces:**
- Consumes: `categoryCatalog` (prompts.dart).
- Produces:
  - `IconData categoryIcon(String category)` (offline Material icons).
  - `Color categoryContainerColor(String category)`.
  - `String fmtTime(DateTime)`, `String fmtTimeAgo(DateTime)`, `String fmtDayGroup(DateTime)`.

- [ ] **Step 1: Tests primero**
  `app/test/category_style_test.dart`:
  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:moneylock/theme/category_style.dart';

  void main() {
    test('cada categoria del catalogo tiene icono y color', () {
      const catalog = [
        'Coffee & Dining', 'Groceries', 'Transport', 'Entertainment',
        'Shopping & E-commerce', 'Bills & Utilities', 'Health', 'Tech',
        'Travel', 'Other',
      ];
      for (final c in catalog) {
        expect(categoryIcon(c), isNotNull, reason: c);
        expect(categoryContainerColor(c), isNotNull, reason: c);
      }
    });

    test('desconocida cae en Other', () {
      expect(categoryIcon('Unknown'), categoryIcon('Other'));
    });
  }
  ```

- [ ] **Step 2: Implementar `app/lib/theme/category_style.dart`**
  ```dart
  import 'package:flutter/material.dart';

  IconData categoryIcon(String category) => switch (category) {
        'Coffee & Dining' => Icons.local_cafe_outlined,
        'Groceries' => Icons.storefront_outlined,
        'Transport' => Icons.directions_car_outlined,
        'Entertainment' => Icons.movie_outlined,
        'Shopping & E-commerce' => Icons.shopping_bag_outlined,
        'Bills & Utilities' => Icons.receipt_long_outlined,
        'Health' => Icons.health_and_safety_outlined,
        'Tech' => Icons.devices_outlined,
        'Travel' => Icons.flight_outlined,
        _ => Icons.category_outlined,
      };

  Color categoryContainerColor(String category) => switch (category) {
        'Groceries' => const Color(0xFFDCEFFF),
        'Transport' => const Color(0xFFFFDAD6),
        'Entertainment' => const Color(0xFFFFF2CC),
        'Shopping & E-commerce' => const Color(0xFFE5E2E1),
        'Bills & Utilities' => const Color(0xFFE3F2FD),
        'Health' => const Color(0xFFFCE4EC),
        'Tech' => const Color(0xFFEDE7F6),
        'Travel' => const Color(0xFFE0F7FA),
        _ => const Color(0xFFF4F4F5),
      };
  ```

- [ ] **Step 3: Añadir helpers de formato en `app/lib/core/format.dart`**
  ```dart
  import 'package:intl/intl.dart';

  String fmtCurrency(double value) =>
      NumberFormat.currency(locale: 'en_US', symbol: r'$').format(value);

  String fmtDate(DateTime d) => DateFormat('MMM d').format(d);

  String fmtTime(DateTime d) => DateFormat('hh:mm a').format(d);

  String fmtDayGroup(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'TODAY';
    if (diff == 1) return 'YESTERDAY';
    return '${DateFormat('EEE, MMM d').format(d).toUpperCase()}, ${diff}d AGO';
  }

  String fmtTimeAgo(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
  ```

- [ ] **Step 4: Verificar y commit**
  Run: `cd app && flutter analyze && flutter test test/category_style_test.dart test/chat_amount_test.dart`
  ```bash
  git add app/lib/theme/category_style.dart app/test/category_style_test.dart app/lib/core/format.dart
  git commit -m "feat: category icon/color mapping and time format helpers"
  ```

---

### Task 4: Persistir severidad del veredicto del mentor (schema v2)

**Files:**
- Modify: `app/lib/data/tables.dart` (columna `severity` en `MentorMessages`)
- Modify: `app/lib/data/db.dart` (schemaVersion → 2, migración)
- Modify: `app/lib/data/messages_dao.dart` (`add` con `severity` opcional)
- Modify: `app/lib/features/add/add_transaction_flow.dart` (guardar `verdict.severity.name`)
- Create: `app/test/severity_persistence_test.dart`

**Interfaces:**
- Consumes: `MentorVerdict.severity`.
- Produces: `MessagesDao.add(role, content, {String severity = 'info'})`; columna `mentor_messages.severity` (default `'info'`). Alert card y action chips consumen este campo.

- [ ] **Step 1: Test que falla**
  `app/test/severity_persistence_test.dart`:
  ```dart
  import 'package:drift_flutter/drift_flutter.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:moneylock/data/db.dart';

  void main() {
    test('mensaje del mentor persiste su severidad', () async {
      final db = AppDatabase.forTesting(
          driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));
      await db.messagesDao.add('mentor', 'You are over budget.', severity: 'alert');
      final msg = (await db.messagesDao.watchAll().first).single;
      expect(msg.severity, 'alert');
      await db.close();
    });
  }
  ```

- [ ] **Step 2: Run para confirmar que falla (columna no existe)**

- [ ] **Step 3: Modificar `app/lib/data/tables.dart`**
  En `MentorMessages`, añadir:
  ```dart
  TextColumn get severity => text().withDefault(const Constant('info'))();
  ```

- [ ] **Step 4: Modificar `app/lib/data/db.dart`** (migración 1→2)
  ```dart
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(mentorMessages, mentorMessages.severity);
          }
        },
      );
  ```

- [ ] **Step 5: Modificar `app/lib/data/messages_dao.dart`**
  ```dart
  Future<void> add(String role, String content, {String severity = 'info'}) =>
      db.into(db.mentorMessages).insert(MentorMessagesCompanion.insert(
          role: role, content: content, createdAt: DateTime.now(), severity: Value(severity)));
  ```

- [ ] **Step 6: Modificar `app/lib/features/add/add_transaction_flow.dart`**
  Reemplazar la línea de inserción del mensaje:
  ```dart
  await db.messagesDao.add('mentor', verdict.message, severity: verdict.severity.name);
  ```

- [ ] **Step 7: Regenerar código drift y verificar**
  Run: `cd app && dart run build_runner build --delete-conflicting-outputs`
  Run: `cd app && flutter analyze && flutter test`
  Expected: 33+ tests verdes (los tests de lógica existentes siguen pasando: `add_flow_test` no asume columnas ausentes).

- [ ] **Step 8: Commit**
  ```bash
  git add app/lib/data app/test/severity_persistence_test.dart
  git commit -m "feat: persist mentor verdict severity (schema v2 with migration)"
  ```

---

### Task 5: Kit de componentes reutilizables + Sparkline

**Files:**
- Create: `app/lib/widgets/kit.dart`
- Create: `app/lib/widgets/sparkline.dart`
- Create: `app/test/sparkline_test.dart`

**Interfaces:**
- Consumes: `AppColors`, `AppTextStyles`, `AppSpacing`, `AppRadii`, `AppShadows`, `categoryIcon`.
- Produces:
  - `AppGlassHeader({String? eyebrow, String? title, Widget? leading, VoidCallback? onAvatarTap})` — header 64px glass con avatar redondo 32px (icono persona) que abre Settings.
  - `AppCard({Widget child, Color? fill, List<BoxShadow>? shadow, bool glowOrb})` — superficie borde sutil.
  - `AppPill({String label, bool active, VoidCallback? onTap})` — chip pill label-caps.
  - `AppFabMentor({required VoidCallback onTap})` — FAB 56px primary glow `smart_toy`.
  - `AppEmptyState({String title, String body, IconData icon, String? actionLabel, VoidCallback? onAction})`.
  - `Sparkline({required List<double> series, double height = 64, Color? color})` — CustomPaint; `SparklinePainter`.
  - `double? normalizeSpark(List<double>)` → serie 0..1 o null si <2 puntos (puro, testeable).

- [ ] **Step 1: Test de la lógica pura del sparkline**
  `app/test/sparkline_test.dart`:
  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:moneylock/widgets/sparkline.dart';

  void main() {
    test('menos de 2 puntos devuelve null', () {
      expect(normalizeSpark([]), isNull);
      expect(normalizeSpark([3]), isNull);
    });

    test('normaliza a 0..1 manteniendo el maximo en 1', () {
      final n = normalizeSpark([0, 5, 10])!;
      expect(n[0], 0.0);
      expect(n[1], 0.5);
      expect(n[2], 1.0);
    });

    test('serie plana (max 0) no divide por cero', () {
      final n = normalizeSpark([0, 0, 0])!;
      expect(n.every((v) => v == 0.0), isTrue);
    });
  }
  ```

- [ ] **Step 2: Implementar `app/lib/widgets/sparkline.dart`**
  ```dart
  import 'package:flutter/material.dart';

  /// Normaliza una serie a valores 0..1 (máximo→1). Null si <2 puntos.
  List<double>? normalizeSpark(List<double> series) {
    if (series.length < 2) return null;
    final max = series.reduce((a, b) => a > b ? a : b);
    if (max <= 0) return List<double>.filled(series.length, 0);
    return series.map((v) => v / max).toList();
  }

  class Sparkline extends StatelessWidget {
    final List<double> series;
    final double height;
    final Color? color;
    const Sparkline({super.key, required this.series, this.height = 64, this.color});

    @override
    Widget build(BuildContext context) {
      final c = color ?? AppColors.primary;
      final n = normalizeSpark(series);
      if (n == null) {
        return SizedBox(height: height,
            child: Center(child: Text('Not enough data yet',
                style: AppTextStyles.monoData.copyWith(color: AppColors.onSurfaceVariant))));
      }
      return SizedBox(
        height: height,
        child: CustomPaint(painter: SparklinePainter(n, c), size: Size.infinite),
      );
    }
  }

  class SparklinePainter extends CustomPainter {
    final List<double> normalized;
    final Color color;
    SparklinePainter(this.normalized, this.color);

    @override
    void paint(Canvas canvas, Size size) {
      if (size.width <= 0 || size.height <= 0) return;
      final stroke = 1.5;
      final padV = 4.0;
      final points = <Offset>[];
      for (var i = 0; i < normalized.length; i++) {
        final x = size.width * i / (normalized.length - 1);
        final y = size.height - padV - (normalized[i] * (size.height - padV * 2));
        points.add(Offset(x, y));
      }
      final line = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        line.lineTo(p.dx, p.dy);
      }
      final fill = Path.from(line)
        ..lineTo(points.last.dx, size.height)
        ..lineTo(points.first.dx, size.height)
        ..close();
      canvas.drawPath(
          fill,
          Paint()
            ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0)])
            .createShader(Offset.zero & size));
      canvas.drawPath(
          line,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = color);
    }

    @override
    bool shouldRepaint(SparklinePainter old) =>
        old.normalized != normalized || old.color != color;
  }
  ```
  (Importa `app_theme.dart` para `AppColors`/`AppTextStyles`.)

- [ ] **Step 3: Implementar `app/lib/widgets/kit.dart`** (componentes UI puros, sin lógica de negocio)
  ```dart
  import 'package:flutter/material.dart';
  import '../theme/app_theme.dart';

  class AppGlassHeader extends StatelessWidget {
    final String? eyebrow;
    final String? title;
    final Widget? leading;
    final VoidCallback? onAvatarTap;
    const AppGlassHeader({super.key, this.eyebrow, this.title, this.leading, this.onAvatarTap});

    @override
    Widget build(BuildContext context) {
      return Container(
        height: 64,
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.margin),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.8),
          border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, SizedBox(width: AppSpacing.gutter)],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (eyebrow != null)
                    Text(eyebrow!, style: AppTextStyles.labelCaps.copyWith(color: AppColors.onSurfaceVariant)),
                  if (title != null) Text(title!, style: AppTextStyles.headlineLgMobile),
                ],
              ),
            ),
            if (onAvatarTap != null)
              GestureDetector(
                onTap: onAvatarTap,
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surfaceContainerHigh,
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Icon(Icons.person, size: 18, color: AppColors.onSurfaceVariant),
                ),
              ),
          ],
        ),
      );
    }
  }

  class AppCard extends StatelessWidget {
    final Widget child;
    final Color? fill;
    final bool glowOrb;
    const AppCard({super.key, required this.child, this.fill, this.glowOrb = false});

    @override
    Widget build(BuildContext context) {
      return Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: fill ?? AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.full),
          border: Border.all(color: AppColors.borderSubtle),
          boxShadow: AppShadows.card,
        ),
        child: Stack(children: [
          if (glowOrb)
            Positioned(
              top: -40, right: -40,
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.05),
                ),
              ),
            ),
          child,
        ]),
      );
    }
  }

  class AppPill extends StatelessWidget {
    final String label;
    final bool active;
    final VoidCallback? onTap;
    const AppPill({super.key, required this.label, this.active = false, this.onTap});

    @override
    Widget build(BuildContext context) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: active ? AppColors.primary.withValues(alpha: 0.10) : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.full),
            border: Border.all(
                color: active ? AppColors.primary.withValues(alpha: 0.20) : AppColors.borderSubtle),
          ),
          child: Text(label,
              style: AppTextStyles.labelCaps.copyWith(
                  color: active ? AppColors.primary : AppColors.onSurfaceVariant)),
        ),
      );
    }
  }

  class AppFabMentor extends StatelessWidget {
    final VoidCallback onTap;
    const AppFabMentor({super.key, required this.onTap});

    @override
    Widget build(BuildContext context) {
      return Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary,
          boxShadow: AppShadows.glow,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: const Icon(Icons.smart_toy, color: AppColors.onPrimary, size: 28),
          ),
        ),
      );
    }
  }

  class AppEmptyState extends StatelessWidget {
    final String title;
    final String body;
    final IconData icon;
    final String? actionLabel;
    final VoidCallback? onAction;
    const AppEmptyState({super.key, required this.title, required this.body,
        required this.icon, this.actionLabel, this.onAction});

    @override
    Widget build(BuildContext context) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Icon(icon, size: 40, color: AppColors.onSurfaceVariant),
            SizedBox(height: AppSpacing.md),
            Text(title, style: AppTextStyles.headlineMd, textAlign: TextAlign.center),
            SizedBox(height: AppSpacing.sm),
            Text(body,
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: AppSpacing.md),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ],
        ),
      );
    }
  }

  class AppSectionLabel extends StatelessWidget {
    final String label;
    const AppSectionLabel(this.label);
    @override
    Widget build(BuildContext context) => Text(label,
        style: AppTextStyles.labelCaps.copyWith(color: AppColors.onSurfaceVariant));
  }
  ```

- [ ] **Step 4: Verificar y commit**
  Run: `cd app && flutter analyze && flutter test test/sparkline_test.dart test/app_theme_test.dart`
  ```bash
  git add app/lib/widgets app/test/sparkline_test.dart
  git commit -m "feat: reusable component kit and sparkline widget"
  ```

---

### Task 6: Router, shell (3 tabs + FAB) y wiring del theme

**Files:**
- Modify: `app/lib/core/router.dart` (3 branches + overlay `/chat` `/settings` + AppShell con bottom nav glass + FAB)
- Modify: `app/lib/main.dart` (`MaterialApp.router` + `buildAppTheme`)
- Create: `app/lib/features/history/history_screen.dart` (stub verificado en Task 8)
- Modify: `app/test/widget_test.dart` (nav 3 tabs + FAB + avatar→settings)

**Interfaces:**
- Consumes: `DashboardScreen`, `InsightsScreen`, `HistoryScreen`, `ChatScreen`, `SettingsScreen`, `AppFabMentor`, `AppColors`.
- Produces: router con `rootNavigatorKey`; `/chat` y `/settings` como rutas fuera del shell (root navigator, push overlay).

- [ ] **Step 1: Reescribir `app/lib/core/router.dart`**
  ```dart
  import 'package:flutter/material.dart';
  import 'package:go_router/go_router.dart';

  import '../features/chat/chat_screen.dart';
  import '../features/dashboard/dashboard_screen.dart';
  import '../features/history/history_screen.dart';
  import '../features/insights/insights_screen.dart';
  import '../features/settings/settings_screen.dart';
  import '../theme/app_theme.dart';
  import '../widgets/kit.dart';

  final _rootNavigatorKey = GlobalKey<NavigatorState>();

  final appRouter = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/insights', builder: (_, _) => const InsightsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
          ]),
        ],
      ),
      GoRoute(
        path: '/chat',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const ChatScreen(),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, _) => const SettingsScreen(),
      ),
    ],
  );

  class AppShell extends StatelessWidget {
    final StatefulNavigationShell navigationShell;
    const AppShell({super.key, required this.navigationShell});

    void _go(int index) => navigationShell.goBranch(
        index, initialLocation: index == navigationShell.currentIndex);

    @override
    Widget build(BuildContext context) {
      return Stack(
        children: [
          Column(children: [
            Expanded(child: navigationShell),
            _BottomNav(current: navigationShell.currentIndex, onTap: _go),
          ]),
          Positioned(
            right: AppSpacing.md,
            bottom: 96,
            child: AppFabMentor(onTap: () => context.push('/chat')),
          ),
        ],
      );
    }
  }

  class _BottomNav extends StatelessWidget {
    final int current;
    final ValueChanged<int> onTap;
    const _BottomNav({required this.current, required this.onTap});

    @override
    Widget build(BuildContext context) {
      final items = const [
        (icon: Icons.dashboard_outlined, active: Icons.dashboard, label: 'Dashboard'),
        (icon: Icons.monitoring_outlined, active: Icons.monitoring, label: 'Insights'),
        (icon: Icons.history_outlined, active: Icons.history, label: 'History'),
      ];
      return Container(
        height: 64,
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.8),
          border: Border(top: BorderSide(color: AppColors.borderSubtle)),
        ),
        child: SafeArea(
          top: false,
          child: Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(i == current ? items[i].active : items[i].icon,
                          size: 22,
                          color: i == current ? AppColors.primary : AppColors.onSurfaceVariant),
                      SizedBox(height: 2),
                      Text(items[i].label,
                          style: AppTextStyles.labelCaps.copyWith(
                              fontSize: 10,
                              color: i == current ? AppColors.primary : AppColors.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
          ]),
        ),
      );
    }
  }
  ```

- [ ] **Step 2: Reescribir `app/lib/main.dart`**
  ```dart
  import 'dart:async';

  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';

  import 'core/notifications.dart';
  import 'core/router.dart';
  import 'providers.dart';
  import 'theme/app_theme.dart';

  Future<void> main() async {
    WidgetsFlutterBinding.ensureInitialized();
    await LocalNotifications().init();
    final container = ProviderContainer();
    unawaited(container.read(deepLinkHandlerProvider).startListening());
    runApp(UncontrolledProviderScope(
        container: container, child: const MoneylockApp()));
  }

  class MoneylockApp extends StatelessWidget {
    const MoneylockApp({super.key});

    @override
    Widget build(BuildContext context) {
      return MaterialApp.router(
        title: 'Moneylock',
        theme: buildAppTheme(),
        routerConfig: appRouter,
        debugShowCheckedModeBanner: false,
      );
    }
  }
  ```

- [ ] **Step 3: Crear stub de HistoryScreen (se completa en Task 8)**
  `app/lib/features/history/history_screen.dart`:
  ```dart
  import 'package:flutter/material.dart';

  class HistoryScreen extends StatelessWidget {
    const HistoryScreen({super.key});

    @override
    Widget build(BuildContext context) =>
        const Scaffold(body: Center(child: Text('History')));
  }
  ```

- [ ] **Step 4: Reescribir `app/test/widget_test.dart`**
  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_test/flutter_test.dart';

  import 'package:moneylock/features/insights/insights_agent.dart';
  import 'package:moneylock/main.dart';
  import 'package:moneylock/providers.dart';

  void main() {
    testWidgets('shell renders 3 tabs + mentor FAB; FAB abre chat, avatar abre settings',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          transactionsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          messagesStreamProvider.overrideWith((ref) => Stream.value(const [])),
          budgetSummaryProvider.overrideWith((ref) => Stream.value(
              BudgetSummary(totalSpent: 0, totalLimit: 0, byCategory: {}))),
          mentorToneProvider.overrideWith((ref) async => 'strict_ramsey'),
        ],
        child: const MoneylockApp(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsWidgets);
      expect(find.text('Insights'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.byIcon(Icons.smart_toy), findsOneWidget);
      expect(find.text('Chat'), findsNothing);

      await tester.tap(find.byIcon(Icons.smart_toy));
      await tester.pumpAndSettle();
      expect(find.text('Vector'), findsOneWidget);
      expect(find.text('FINANCIAL INTELLIGENCE CORE'), findsOneWidget);
      Navigator.of(tester.element(find.text('Vector'))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.person));
      await tester.pumpAndSettle();
      expect(find.text('Mentor tone'), findsOneWidget);
    });
  }
  ```

- [ ] **Step 5: Verificar**
  Run: `cd app && flutter analyze && flutter test test/widget_test.dart`
  Expected: verde (Chat y Settings abren como overlay; el resto de tests de lógica intactos).

- [ ] **Step 6: Commit**
  ```bash
  git add app/lib/core/router.dart app/lib/main.dart app/lib/features/history/history_screen.dart app/test/widget_test.dart
  git commit -m "feat: 3-tab shell with mentor FAB and overlay routes for chat and settings"
  ```

---

### Task 7: Dashboard reescrito (hero, burn card, alert card, recent ledger, add sheet)

**Files:**
- Rewrite: `app/lib/features/dashboard/dashboard_screen.dart`
- Rewrite: `app/lib/features/dashboard/budget_bar.dart` (barra glow 2px, CustomPaint)
- Modify: `app/lib/features/add/manual_form.dart` y `voice_button.dart` (restyle Material, manteniendo lógica)
- Create: `app/test/dashboard_widget_test.dart`

**Interfaces:**
- Consumes: `budgetSummaryProvider`, `transactionsStreamProvider`, `messagesStreamProvider`, `AppColors`, `AppTextStyles`, kit widgets, `categoryIcon`, `fmtCurrency/fmtTime/fmtDayGroup`, `ManualForm`, `VoiceButton`, `AddTransactionFlow` (vía ManualForm/VoiceButton).
- Produces: Dashboard con hero TOTAL LIQUIDITY, pill `+X% vs last month` (o "No activity yet"), Monthly Burn card, Alert card (último veredicto `severity in {alert,warning}`), Recent Ledger top 5 + VIEW ALL → `/history`, add sheet (botón `+` del header) con toggle Manual/Voice.

- [ ] **Step 1: Rewrite `app/lib/features/dashboard/budget_bar.dart`** (barra glow 2px)
  ```dart
  import 'package:flutter/material.dart';
  import '../../theme/app_theme.dart';

  class GlowProgressBar extends StatelessWidget {
    final double progress;
    const GlowProgressBar({super.key, required this.progress});

    @override
    Widget build(BuildContext context) {
      final p = progress.clamp(0.0, 1.0);
      return ClipRRect(
        borderRadius: BorderRadius.circular(1),
        child: SizedBox(
          height: 2,
          child: CustomPaint(
            painter: _GlowBarPainter(p),
            size: Size.infinite,
          ),
        ),
      );
    }
  }

  class _GlowBarPainter extends CustomPainter {
    final double progress;
    _GlowBarPainter(this.progress);

    @override
    void paint(Canvas canvas, Size size) {
      final track = Paint()..color = AppColors.surfaceContainerHighest;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(1)), track);
      if (progress <= 0) return;
      final fillW = size.width * progress;
      final fill = Paint()
        ..color = AppColors.primary
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, fillW, size.height),
              Radius.circular(1)), fill);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, fillW, size.height),
              Radius.circular(1)),
          Paint()..color = AppColors.primary);
    }

    @override
    bool shouldRepaint(_GlowBarPainter old) => old.progress != progress;
  }
  ```

- [ ] **Step 2: Reescribir `app/lib/features/dashboard/dashboard_screen.dart`**
  Estructura (copy en inglés, sin lógica nueva; el add sheet conserva ManualForm + VoiceButton con toggle):

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';

  import '../../core/format.dart';
  import '../../data/db.dart';
  import '../../providers.dart';
  import '../../theme/app_theme.dart';
  import '../../theme/category_style.dart';
  import '../../widgets/kit.dart';
  import '../add/manual_form.dart';
  import '../add/voice_button.dart';
  import '../insights/insights_agent.dart';
  import 'budget_bar.dart';

  class DashboardScreen extends ConsumerWidget {
    const DashboardScreen({super.key});

    @override
    Widget build(BuildContext context, WidgetRef ref) {
      final summary = ref.watch(budgetSummaryProvider).valueOrNull;
      final txs = ref.watch(transactionsStreamProvider).value ?? const [];
      final messages = ref.watch(messagesStreamProvider).value ?? const [];

      final lastVerdict = messages
          .lastWhere((m) => m.role == 'mentor' && m.severity != 'info',
              orElse: () => messages.isEmpty ? _emptyMsg() : messages.last)
          .severity;
      final showAlert = lastVerdict == 'alert' || lastVerdict == 'warning';

      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            AppGlassHeader(
              eyebrow: 'YOUR MONEY',
              title: 'Dashboard',
              leading: IconButton(
                onPressed: () => _showAddSheet(context),
                icon: const Icon(Icons.add, color: AppColors.onSurface),
              ),
              onAvatarTap: () => context.push('/settings'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
                children: [
                  _Hero(summary: summary),
                  const SizedBox(height: 24),
                  _MonthlyBurn(summary: summary),
                  if (showAlert) ...[
                    const SizedBox(height: 16),
                    _AlertCard(messages: messages),
                  ],
                  const SizedBox(height: 24),
                  Row(children: [
                    const Expanded(child: Text('Recent Ledger',
                        style: AppTextStyles.headlineMd)),
                    TextButton(
                      onPressed: () => context.push('/history'),
                      child: Text('VIEW ALL',
                          style: AppTextStyles.monoData
                              .copyWith(color: AppColors.primary)),
                    ),
                  ]),
                  if (txs.isEmpty)
                    const AppEmptyState(
                        title: 'No transactions yet',
                        body: 'Add your first purchase with the + button '
                            'or capture it by voice.',
                        icon: Icons.receipt_long_outlined)
                  else
                    for (final t in txs.take(5)) _LedgerRow(t: t),
                ],
              ),
            ),
          ]),
        ),
      );
    }
  }
  ```
  Widgets privados:
  - `_Hero`: centrado, eyebrow `TOTAL LIQUIDITY`, `fmtCurrency(summary?.totalSpent ?? 0)` con `AppTextStyles.display`, pill: si hay datos → `+X% vs last month` (dato real: `spentThisMonth - spentLastMonth`); si no → `No activity yet`. Para el % necesita gasto del mes previo: consultar `budgetSummaryProvider` (mes actual) y derivar del stream de txs (mismo mes año-previo). Implementar helper puro `double monthDelta(List<Transaction> txs)` en este archivo o en `insights_agent.dart` (ver Step 3).
  - `_MonthlyBurn`: card con label `MONTHLY BURN`, `$spent / $limit` (o solo `$spent` si no hay límite) headline-md, % mono primary y `GlowProgressBar(progress: spent/limit)`.
  - `_AlertCard`: card con borde `error/30`, barra izquierda 4px error, icono `Icons.warning_amber_rounded` en container error, título `Budget alert` error + mensaje del último veredicto (contenido LLM), botón `ANALYZE DEVIATION` (TextButton, border-bottom error/30) → `context.push('/chat')`.
  - `_LedgerRow`: icono 40px rounded (categoryIcon, container color), merchant headline-md (o category si vacío), mono `Category • hh:mm` (con `fmtDayGroup`), monto `-$X` mono.
  - `_AddSheet`: `showModalBottomSheet` con toggle `Manual / Voice` (SegmentedButton o custom pills) y el form/voz correspondiente. Mantiene `_status` y `onStatus`.

- [ ] **Step 3: Helper puro `monthDelta` + test** (para la pill `+X% vs last month`)
  En `app/lib/features/insights/insights_agent.dart` añadir:
  ```dart
  /// Diferencia porcentual entre gasto del mes actual y el mismo mes previo.
  /// Null si no hay datos suficientes en el mes previo.
  double? monthDeltaPercent(List<Transaction> txs) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final prevStart = DateTime(now.year, now.month - 1, 1);
    var cur = 0.0, prev = 0.0, prevCount = 0;
    for (final t in txs) {
      if (!t.timestamp.isBefore(start)) { cur += t.amount; }
      else if (!t.timestamp.isBefore(prevStart)) { prev += t.amount; prevCount++; }
    }
    if (prevCount == 0) return null;
    return prev == 0 ? null : ((cur - prev) / prev) * 100;
  }
  ```
  (Requiere import de `../../data/db.dart` para `Transaction` — ya lo importa? No: `insights_agent.dart` importa nada de data. Añadir `import '../../data/db.dart';`.) En `app/test/insights_test.dart` añadir casos para `monthDeltaPercent` (mismo mes, mes previo, sin datos → null).

- [ ] **Step 4: Restyle `manual_form.dart` y `voice_button.dart`** (solo visual, lógica intacta)
  - `manual_form.dart`: `CupertinoTextField` → `TextField` (Material) con `decoration: InputDecoration(filled: true, fillColor: AppColors.surfaceContainer, border: OutlineInputBorder(borderRadius: 8, borderSide: none), focusedBorder: ... primary)`. Mantener `_submit`, `_busy`, `_error`, `onStatus`, `Navigator.maybePop(true)`.
  - `voice_button.dart`: mantener `_speech`/estados; estilizar el botón circular 64px: `AppColors.primary` idle, `AppColors.error` + glow escuchando, icono `Icons.mic`. Label-caps en el texto de estado.

- [ ] **Step 5: Test widget del dashboard**
  `app/test/dashboard_widget_test.dart`:
  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:moneylock/features/dashboard/dashboard_screen.dart';
  import 'package:moneylock/features/insights/insights_agent.dart';
  import 'package:moneylock/providers.dart';

  void main() {
    testWidgets('dashboard muestra hero, burn y recent ledger', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          transactionsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          messagesStreamProvider.overrideWith((ref) => Stream.value(const [])),
          budgetSummaryProvider.overrideWith((ref) => Stream.value(
              BudgetSummary(totalSpent: 120.5, totalLimit: 300, byCategory: {}))),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('TOTAL LIQUIDITY'), findsOneWidget);
      expect(find.text(r'$120.50'), findsWidgets);
      expect(find.text('MONTHLY BURN'), findsOneWidget);
      expect(find.text('VIEW ALL'), findsOneWidget);
      expect(find.text('No transactions yet'), findsOneWidget);
    });
  }
  ```

- [ ] **Step 6: Verificar**
  Run: `cd app && flutter analyze && flutter test`
  Expected: todos los tests verdes.

- [ ] **Step 7: Commit**
  ```bash
  git add app/lib/features/dashboard app/lib/features/add app/lib/features/insights/insights_agent.dart app/test/dashboard_widget_test.dart app/test/insights_test.dart
  git commit -m "feat: redesigned dashboard with hero, monthly burn, alert card and add sheet"
  ```

---

### Task 8: History screen (agrupación por día, filtros, voz)

**Files:**
- Rewrite: `app/lib/features/history/history_screen.dart`
- Create: `app/test/history_widget_test.dart`

**Interfaces:**
- Consumes: `transactionsStreamProvider`, `AppColors/AppTextStyles`, kit widgets, `categoryIcon`, `fmtCurrency/fmtTime/fmtDayGroup`.
- Produces: header `TRANSACTIONS` sticky con chips `ALL` + categorías existentes + `VOICE INPUT` (filtra `source == voice`); lista agrupada por día (TODAY/YESTERDAY/…) con filas (avatar circular 48px category icon + badge mic si `source == voice`, merchant, mono `Category • source icon • hh:mm`, monto mono); income (`amount < 0`) con `+$X` primary; empty state por filtro.

- [ ] **Step 1: Reescribir `app/lib/features/history/history_screen.dart`**
  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';

  import '../../core/format.dart';
  import '../../data/db.dart';
  import '../../providers.dart';
  import '../../theme/app_theme.dart';
  import '../../theme/category_style.dart';
  import '../../widgets/kit.dart';

  class HistoryScreen extends ConsumerStatefulWidget {
    const HistoryScreen({super.key});

    @override
    ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
  }

  class _HistoryScreenState extends ConsumerState<HistoryScreen> {
    String? _filter;

    @override
    Widget build(BuildContext context) {
      final txs = ref.watch(transactionsStreamProvider).value ?? const [];
      final categories = <String>{
        for (final t in txs) t.category,
      }.toList()..sort();
      final filtered = _filter == null
          ? txs
          : _filter == 'voice'
              ? txs.where((t) => t.source == 'voice').toList()
              : txs.where((t) => t.category == _filter).toList();

      final groups = <String, List<Transaction>>{};
      for (final t in filtered) {
        groups.putIfAbsent(fmtDayGroup(t.timestamp), () => []).add(t);
      }
      final groupKeys = groups.keys.toList();

      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            const AppGlassHeader(
                eyebrow: 'YOUR MONEY', title: 'Transactions'),
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                children: [
                  AppPill(label: 'ALL', active: _filter == null,
                      onTap: () => setState(() => _filter = null)),
                  for (final c in categories)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: AppPill(label: c.toUpperCase(), active: _filter == c,
                          onTap: () => setState(() => _filter = c)),
                    ),
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: AppPill(label: 'VOICE INPUT', active: false),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? AppEmptyState(
                      title: 'No transactions',
                      body: _filter == 'voice'
                          ? 'No voice-captured purchases yet.'
                          : 'No transactions in this category yet.',
                      icon: Icons.receipt_long_outlined)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                      children: [
                        for (final key in groupKeys) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: AppSectionLabel(key),
                          ),
                          for (final t in groups[key]!)
                            _HistoryRow(t: t),
                        ],
                      ],
                    ),
            ),
          ]),
        ),
      );
    }
  }
  ```
  `_HistoryRow`: avatar circular 48px `secondary-container/50` (o `AppColors.surfaceContainerHigh`) con `categoryIcon`; si `t.source == 'voice'` badge mic circular `AppColors.primary` pequeño superpuesto; merchant headline-md; mono `Category • [icon] • hh:mm`; monto `-${fmtCurrency(t.amount)}` mono (income: `+${fmtCurrency(-t.amount)}` primary).

- [ ] **Step 2: Test widget de History**
  `app/test/history_widget_test.dart`:
  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:moneylock/data/db.dart';
  import 'package:moneylock/features/history/history_screen.dart';
  import 'package:moneylock/providers.dart';

  void main() {
    final txs = [
      Transaction(id: 1, amount: 18.4, currency: 'USD', merchant: 'Uber',
          category: 'Transport', source: 'manual', rawText: 'uber',
          timestamp: DateTime.now(), dedupHash: 'a'),
      Transaction(id: 2, amount: 5.75, currency: 'USD', merchant: 'OXXO',
          category: 'Groceries', source: 'voice', rawText: 'oxxo',
          timestamp: DateTime.now(), dedupHash: 'b'),
    ];

    testWidgets('history agrupa por dia y muestra chips', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [transactionsStreamProvider
            .overrideWith((ref) => Stream.value(txs))],
        child: const MaterialApp(home: HistoryScreen()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('ALL'), findsOneWidget);
      expect(find.text('VOICE INPUT'), findsOneWidget);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('Uber'), findsOneWidget);
      expect(find.text('OXXO'), findsOneWidget);
    });
  }
  ```

- [ ] **Step 3: Verificar**
  Run: `cd app && flutter analyze && flutter test`
  Expected: verde.

- [ ] **Step 4: Commit**
  ```bash
  git add app/lib/features/history/history_screen.dart app/test/history_widget_test.dart
  git commit -m "feat: history screen with day grouping, category and voice filters"
  ```

---

### Task 9: Chat — modal dark siempre (mantener export hasMonetaryAmount + mic)

**Files:**
- Rewrite: `app/lib/features/chat/chat_screen.dart`
- Modify: `app/lib/features/chat/` si hace falta split de widgets (mantener todo en el mismo archivo salvo que se justifique)
- Create: `app/test/chat_screen_widget_test.dart`

**Interfaces:**
- Consumes: `messagesStreamProvider`, `addFlowProvider`, `llmProviderProvider`, `appDatabaseProvider`, `speechServiceProvider`, `mentorPromptFor`, `hasMonetaryAmount` (definido aquí), `Severity`/`MentorVerdict`, kit/widgets, `AppColors` dark.
- Produces: pantalla dark full-screen (SafeArea) con header (avatar 64px `smart_toy` rojo + `Vector` + subtitle `FINANCIAL INTELLIGENCE CORE` + botón X que hace `Navigator.pop`), burbujas mentor (surface-container-high, shine superior `primary/5`, montos mono `primary-fixed-dim`), burbuja usuario derecha `primaryBright` (#FF3B30), chips de acción (`STOP BUYING` outline / `ADJUST BUDGET` rojo) en el último mensaje mentor con `severity in {alert,warning}`, composer glass con `+` (add sheet rápido), textarea auto-grow, mic circular 48px primary glow (dicta → rellena el textarea), hint `VECTOR IS TYPING...` mientras `_thinking`.

- [ ] **Step 1: Reescribir `app/lib/features/chat/chat_screen.dart`**
  Mantener **exportado** `hasMonetaryAmount` y el regex `_amountRe`. Mantener la lógica `_send`/`_handleTransaction`/`_handleChat` idéntica. Añadir:
  - `_ChatHeader`: Row con avatar 64 (`Icons.smart_toy` rojo en container `darkSurfaceContainerHigh`), columna `Vector` (headlineLgMobile, `darkOnSurface`) + `FINANCIAL INTELLIGENCE CORE` (labelCaps, `darkOnSurfaceVariant`), botón X (`Icons.close`) → `Navigator.of(context).pop()`.
  - `_Bubble`: dark; mentor a la izquierda (`darkSurfaceContainerHigh`, border `darkOutline/10`, radius 16 con sup-izq 4px, gradiente shine superior `darkPrimary/5→transparent` vía `Container` con `foregroundDecoration` o `ShaderMask`); user a la derecha `AppColors.primaryBright` texto `onPrimary`. Montos detectados con `_amountRe` dentro del texto mentor → envolver en `TextSpan` con `fontFamily: 'Geist'`, bold, `AppColors.darkPrimary`.
  - `_ActionChips`: visible cuando el **último** mensaje es mentor con `severity in {alert, warning}`; `STOP BUYING` (OutlinedButton outline) y `ADJUST BUDGET` (FilledButton primary) → `_send` inserta mensaje de usuario `'I want to stop these expenses'` / `'Help me adjust my budget'`.
  - `_Composer`: glass (blur vía `BackdropFilter`, border-top, `darkSurface` alpha), botón `+` (abre el add sheet con `showModalBottomSheet`), textarea auto-grow (`maxLines: null` con `minLines: 1` o `TextField(maxLines: 4, minLines: 1)` en `darkSurfaceContainer`), mic circular 48px (usa `speechServiceProvider`: `init` + `listen` → set `_controller.text`; estados idle/listening/error como en VoiceButton), botón enviar (arrow_up, primary).
  - Hint: si `_thinking`, mostrar `VECTOR IS TYPING...` (mono 10px, `darkOnSurfaceVariant`).
  - Fondo: `Scaffold(backgroundColor: AppColors.darkBackground)`. Todo texto del chat en colores dark.

- [ ] **Step 2: Test widget del chat (dark + chips + pop)**
  `app/test/chat_screen_widget_test.dart`:
  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:moneylock/data/db.dart';
  import 'package:moneylock/features/chat/chat_screen.dart';
  import 'package:moneylock/providers.dart';

  void main() {
    final msgs = [
      MentorMessage(id: 1, role: 'mentor', content: 'You are over budget on Transport.',
          createdAt: DateTime.now(), severity: 'alert'),
    ];

    testWidgets('chat dark muestra header, burbuja y action chips', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          messagesStreamProvider.overrideWith((ref) => Stream.value(msgs)),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Vector'), findsOneWidget);
      expect(find.text('FINANCIAL INTELLIGENCE CORE'), findsOneWidget);
      expect(find.text('STOP BUYING'), findsOneWidget);
      expect(find.text('ADJUST BUDGET'), findsOneWidget);
    });

    testWidgets('hasMonetaryAmount sigue exportado', (tester) {
      expect(hasMonetaryAmount('Starbucks 12.50'), isTrue);
      expect(hasMonetaryAmount('meet me at 5'), isFalse);
    });
  }
  ```
  Nota: `hasMonetaryAmount` test ya cubierto en `chat_amount_test.dart` — el test de aquí solo verifica el import del símbolo.

- [ ] **Step 3: Verificar**
  Run: `cd app && flutter analyze && flutter test`
  Expected: verde (incluye `chat_amount_test.dart` intacto).

- [ ] **Step 4: Commit**
  ```bash
  git add app/lib/features/chat/chat_screen.dart app/test/chat_screen_widget_test.dart
  git commit -m "feat: always-dark chat modal with action chips and voice-to-text composer"
  ```

---

### Task 10: Insights (cards + sparkline + disclaimer + empty state)

**Files:**
- Rewrite: `app/lib/features/insights/insights_screen.dart`
- Create: `app/lib/features/insights/daily_spend.dart` (serie diaria 30 días, puro)
- Create: `app/test/daily_spend_test.dart`
- Modify: `app/test/insights_test.dart` (ya cubre generateInsights; añadir casos si hace falta)

**Interfaces:**
- Consumes: `insightsProvider`, `transactionsStreamProvider`, `generateInsights`, `Sparkline`, kit/widgets, `fmtTimeAgo`.
- Produces: grid vertical de cards (icono 18px primary + tema label-caps + mono time-ago + título headline-md + body con valores mono primary + Sparkline del gasto diario 30 días); disclaimer `Educational information only, not financial advice.` al pie; empty state con CTA al chat.

- [ ] **Step 1: `app/lib/features/insights/daily_spend.dart`**
  ```dart
  import '../../data/db.dart';

  /// Gasto diario (suma de amounts) de los últimos [days] días, incluido hoy,
  /// con el día más reciente al final. Serie de hoy hacia atrás.
  List<double> dailySpendSeries(List<Transaction> txs, {int days = 30}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final result = List<double>.filled(days, 0);
    for (final t in txs) {
      final d = DateTime(t.timestamp.year, t.timestamp.month, t.timestamp.day);
      final idx = today.difference(d).inDays;
      if (idx >= 0 && idx < days) result[days - 1 - idx] += t.amount;
    }
    return result;
  }
  ```

- [ ] **Step 2: `app/test/daily_spend_test.dart`**
  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:moneylock/data/db.dart';
  import 'package:moneylock/features/insights/daily_spend.dart';

  void main() {
    test('asigna gastos a los dias correctos, hoy al final', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final txs = [
        Transaction(id: 1, amount: 10, currency: 'USD', merchant: 'a',
            category: 'Other', source: 'manual', rawText: 'a',
            timestamp: today, dedupHash: 'a'),
        Transaction(id: 2, amount: 5, currency: 'USD', merchant: 'b',
            category: 'Other', source: 'manual', rawText: 'b',
            timestamp: today.subtract(const Duration(days: 3)), dedupHash: 'b'),
      ];
      final s = dailySpendSeries(txs, days: 7);
      expect(s.length, 7);
      expect(s.last, 10);
      expect(s[7 - 1 - 3], 5);
      expect(s.where((v) => v == 0).length, 5);
    });
  }
  ```

- [ ] **Step 3: Reescribir `app/lib/features/insights/insights_screen.dart`**
  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';

  import '../../providers.dart';
  import '../../theme/app_theme.dart';
  import '../../widgets/kit.dart';
  import '../../widgets/sparkline.dart';
  import 'daily_spend.dart';
  import 'insights_agent.dart';

  class InsightsScreen extends ConsumerWidget {
    const InsightsScreen({super.key});

    @override
    Widget build(BuildContext context, WidgetRef ref) {
      final insights = ref.watch(insightsProvider);
      final txs = ref.watch(transactionsStreamProvider).value ?? const [];
      final series = dailySpendSeries(txs);
      final when = insights.when(
        data: (capsules) => capsules,
        loading: () => null,
        error: (_, __) => null,
      );

      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            const AppGlassHeader(
                eyebrow: 'YOUR MONEY', title: 'Insights'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                children: [
                  if (when == null)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (when.isEmpty)
                    AppEmptyState(
                        title: 'No insights yet',
                        body: 'Add transactions to unlock AI spending insights.',
                        icon: Icons.insights_outlined,
                        actionLabel: 'ASK YOUR MENTOR',
                        onAction: () => context.push('/chat'))
                  else ...[
                    for (final c in when) _InsightCard(capsule: c, series: series),
                    const SizedBox(height: 16),
                    Text(disclaimer,
                        style: AppTextStyles.bodyMd.copyWith(
                            fontSize: 11, color: AppColors.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
          ]),
        ),
      );
    }
  }
  ```
  `_InsightCard`: `AppCard(fill: AppColors.surfaceContainer.withValues(alpha: 0.9), glowOrb: true)` con Row (icono 18 primary + tema label-caps primary derivado del título `'X dominates' → 'CATEGORY: X'` o `'Budget health' → 'BUDGET HEALTH'` + mono 12 time-ago `'Generated ' + fmtTimeAgo(...)`, usando un timestamp estable — p.ej. `DateTime.now()` por construcción de render o el de la última transacción) + título headline-md + body con montos destacados (envolver cifras `$X`/`X%` en mono primary vía `Text.rich`) + `Sparkline(series: series)` (oculto si <2 puntos, maneja el null con copy corto).

- [ ] **Step 4: Verificar**
  Run: `cd app && flutter analyze && flutter test`
  Expected: verde.

- [ ] **Step 5: Commit**
  ```bash
  git add app/lib/features/insights app/test/daily_spend_test.dart
  git commit -m "feat: insight cards with 30-day sparkline and disclaimer"
  ```

---

### Task 11: Settings y Add sheet reestilados (misma lógica)

**Files:**
- Rewrite: `app/lib/features/settings/settings_screen.dart` (restyle a cards Material; lógica/DAOs intactos)
- Modify: `app/test/widget_test.dart` si hace falta (settings se abre por avatar — ya cubierto en Task 6)
- Create: `app/test/settings_widget_test.dart`

**Interfaces:**
- Consumes: `mentorToneProvider`, `appDatabaseProvider`, `llamaServiceProvider`, `speechServiceProvider`, `categoryCatalog`, `fmtCurrency`, kit/widgets.
- Produces: Settings con cards `AppCard` por sección: Mentor tone (SegmentedButton o pills), Budgets (filas con TextField Material), On-device model (estado descarga + progreso glow), Voice (test mic). Sin cambio funcional.

- [ ] **Step 1: Reescribir `app/lib/features/settings/settings_screen.dart`**
  Mantener `_ToneSelector` (pasar de `CupertinoSegmentedControl` a `SegmentedButton<String>` con label-caps), `_BudgetEditor` (filas `AppCard` con `TextField` Material + botón check), `_ModelCard` (icono, estado, botón descargar, barra progreso con `GlowProgressBar` + % mono), `_VoiceCard` (test mic). Títulos de sección con `AppSectionLabel`. Dialogs: `showCupertinoDialog` → `AlertDialog` de Material. Importar `budget_bar.dart` para `GlowProgressBar`. Todo el copy visible en inglés.

- [ ] **Step 2: Test widget de Settings**
  `app/test/settings_widget_test.dart`:
  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:moneylock/features/settings/settings_screen.dart';
  import 'package:moneylock/providers.dart';

  void main() {
    testWidgets('settings muestra secciones y tonos', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          mentorToneProvider.overrideWith((ref) async => 'strict_ramsey'),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Mentor tone'), findsOneWidget);
      expect(find.text('Strict'), findsOneWidget);
      expect(find.text('Budgets'), findsOneWidget);
      expect(find.text('On-device model'), findsOneWidget);
      expect(find.text('Voice'), findsOneWidget);
    });
  }
  ```

- [ ] **Step 3: Verificar**
  Run: `cd app && flutter analyze && flutter test`
  Expected: verde.

- [ ] **Step 4: Commit**
  ```bash
  git add app/lib/features/settings/settings_screen.dart app/test/settings_widget_test.dart
  git commit -m "feat: restyle settings with Material cards"
  ```

---

### Task 12: Verificación final integral

**Files:** ninguno (verificación)

- [ ] **Step 1: Suite completa**
  Run: `cd app && flutter analyze && flutter test`
  Expected: analyze limpio; 32 tests de lógica + nuevos tests de UI verdes.

- [ ] **Step 2: Backend intacto (no se tocó)**
  Run: `cd backend && pytest -q`
  Expected: 3 verdes (opcional si no se modificó backend).

- [ ] **Step 3: Build simulador**
  Run: `flutter build ios --simulator`
  Expected: build OK (bundle id `com.moneylock.moneylock`, SwiftPM activo).

- [ ] **Step 4: Smoke en simulador (si sigue booteado)**
  - `xcrun simctl launch booted com.moneylock.moneylock`
  - Screenshot de Dashboard y de `/chat` (deep link `moneylock://add` NO aplica aquí; abrir chat con tap en FAB o `simctl openurl` si hay route deep link — no hay; validar manualmente o via `flutter run`).
  Expected: 3 tabs + FAB visibles, chat dark, history con filtros.

- [ ] **Step 5: Commit final si hay ajustes**
  ```bash
  git add -A
  git commit -m "chore: redesign verification pass"
  ```
  (Solo si hubo cambios; no commitear en vacío.)

---

## Verificación final y criterios de aceptación

- `flutter analyze` limpio y `flutter test` en verde en `app/`.
- Nav = 3 tabs (Dashboard/Insights/History) + FAB mentor (`smart_toy`) + avatar→Settings; Chat y Settings como overlays full-screen.
- Chat siempre dark; `hasMonetaryAmount` sigue exportado desde `chat_screen.dart` (`chat_amount_test.dart` verde).
- Severidad persistida en `mentor_messages` (migración 1→2) usada por alert card y action chips.
- Fuentes Inter + Geist empaquetadas en `assets/fonts/`, sin fetch en runtime.
- Sin cambios en categorizador, mentor, sync, dedup, speech, providers de negocio ni backend.
- UI en inglés; copy de lógica/prompts intacto.