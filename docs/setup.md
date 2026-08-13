# Setup de entorno (Flutter + Xcode)

Comandos usados para dejar el entorno listo para desarrollar la app iOS de Moneylock.

## Prerrequisitos

- macOS (Apple Silicon / arm64)
- Homebrew (`/opt/homebrew`)
- Xcode 26.6 instalado (`/Applications/Xcode.app`)

## Instalar Flutter

```bash
brew install --cask flutter
```

Instala Flutter y enlaza los binarios `flutter` y `dart` en `/opt/homebrew/bin` (ya en el PATH en shells nuevas). Verificar:

```bash
which flutter dart
flutter --version
```

## Verificar toolchain iOS

```bash
flutter doctor
```

Si reporta `CocoaPods not installed`, instalarlo:

```bash
brew install cocoapods
```

## Licencias Xcode

El primer launch y la licencia de Xcode suelen quedar aceptados tras la instalación de Xcode (verificar con `xcodebuild -checkFirstLaunchStatus`). Si no:

```bash
sudo xcodebuild -runFirstLaunch
sudo xcodebuild -license accept
```

## Estado esperado de `flutter doctor`

```text
[✓] Flutter (Channel stable, 3.47.0)
[✓] Xcode - develop for iOS and macOS (Xcode 26.6)
```

Notas: las secciones de Android toolchain y Chrome pueden aparecer en rojo; no son necesarias para el MVP iOS de Moneylock.

## Herramientas instaladas

| Herramienta | Versión | Vía |
|---|---|---|
| Flutter | 3.47.0 (stable) | `brew install --cask flutter` |
| Dart | 3.13.0 | incluido con Flutter |
| CocoaPods | 1.17.0 | `brew install cocoapods` |
| Xcode | 26.6 (build 17F113) | preinstalado |
