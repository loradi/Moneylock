# Añadir transacciones con un atajo de Apple Shortcuts

Moneylock expone el URL scheme `moneylock://add` que captura una transacción
desde cualquier atajo de Apple Shortcuts (o desde `x-callback-url`).

## URL scheme

```
moneylock://add?amount=45.50&merchant=Starbucks
```

Params:

| Parámetro | Requerido | Descripción |
|-----------|-----------|-------------|
| `amount`  | sí        | Monto numérico. Sin él la URL lanza `FormatException` y no se captura nada. |
| `merchant`| no        | Nombre del comercio. Opcional: si falta, el categorizador lo deduce del texto de la transacción. |
| `category`| no        | Aceptado por la URL pero **ignorado en v1**: `parseShortcutUrl` no lo lee; la categoría la infiere el categorizador. |
| `date`    | no        | Aceptado por la URL pero **ignorado en v1**: `parseShortcutUrl` no lo lee; la transacción se registra con la fecha actual. |

`category` y `date` se reservan en el URL scheme para una versión futura;

## Pasos en la app Shortcuts

1. Abre la app **Shortcuts** y crea un atajo nuevo llamado "Add Transaction".
2. Añade la acción **Ask for Input** (Prompt: "Amount?", tipo Number) y otra
   **Ask for Input** (Prompt: "Merchant?", tipo Text).
3. Añade una acción **Text** que construya:
   `moneylock://add?amount=Amount&merchant=Merchant` (usa las variables de
   magia de los pasos 1-2).
4. Añade la acción **Open URLs** con el resultado del paso 3. Confirmar que
   la URL empieza por `moneylock://add`.
5. Guarda el atajo. Ahora se puede ejecutar desde el widget de Shortcuts,
   el botón del Apple Watch, "Hey Siri" o desde el botón de compartir con
   "Run Shortcut".

## Notas

- Se puede invocar también desde fuera de Shortcuts con
  `shortcuts://run-shortcut?name=Add%20Transaction` (configúralo en
  "Settings > Allow running from other apps" si lo necesitas).
- Opcional: capturar el recibo de Apple Pay manualmente con una acción
  **Show Notification** en el propio atajo; la app por su parte registra
  la categoría y la fecha si se pasan como parámetros extra.
- Ejemplo del atajo exportado (definición `shortcut` de un plist):

```xml
<key>WFWorkflowActions</key>
<array>
    <dict>
        <key>WFWorkflowActionIdentifier</key>
        <string>is.workflow.actions.gettext</string>
        <key>WFWorkflowActionParameters</key>
        <dict>
            <key>WFTextActionText</key>
            <string>moneylock://add?amount=Amount&merchant=Merchant</string>
        </dict>
    </dict>
    <dict>
        <key>WFWorkflowActionIdentifier</key>
        <string>is.workflow.actions.openurl</string>
    </dict>
</array>
```

El flujo completo es: captura → categoriza (LLM on-device) → dedup → guarda
en SQLite → mentor evalúa el presupuesto → notificación local con el
veredicto.