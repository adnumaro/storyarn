%{
title: "Editor de Condiciones",
category_label: "Diseño Narrativo",
order: 2,
description: "Usa Builder view y Code view para definir condiciones reutilizables en flujos, respuestas, zonas y pines."
}

---

El Editor de Condiciones define comprobaciones que leen variables y devuelven verdadero o falso. Storyarn usa el mismo editor en varios sitios:

| Dónde | Qué controla la condición |
| ----- | ------------------------- |
| **Nodos de Condición** | Qué rama del flujo se ejecuta a continuación. |
| **Respuestas de diálogo** | Si una respuesta del jugador está disponible. |
| **Zonas de escena** | Si un área es visible o interactiva durante la exploración. |
| **Pines de escena** | Si un marcador, personaje o punto interactivo es visible o interactivo durante la exploración. |

Las condiciones solo leen variables. No cambian estado. Usa el [Editor de Instrucciones](/docs/narrative-design/instruction-editor) cuando necesites escribir valores.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Editor de Condiciones mostrando las pestañas Builder y Code con una condición de variable seleccionada
</div>

## Modos de edición

Cada condición tiene dos modos de edición:

| Modo | Mejor para | Qué editas |
| ---- | ---------- | ---------- |
| **Builder view** | La mayoría de usuarios, lógica legible, revisión colaborativa | Bloques en forma de frase con variables, operadores, valores y grupos lógicos. |
| **Code view** | Technical designers, edición rápida, expresiones compactas | Una expresión de texto como `mc.jaime.health > 50 && quest.door.unlocked == true`. |

Los dos modos describen la misma condición. Al cambiar a Code view, Storyarn serializa el estado actual del builder como texto. Al editar Code view, el texto se parsea de vuelta al formato estructurado que usa Storyarn.

## Builder view

Builder view crea condiciones con bloques y reglas.

| Nivel | Propósito |
| ----- | --------- |
| **Regla** | Una comparación variable/operador/valor, como `mc.jaime.health > 50`. |
| **Bloque** | Un conjunto de reglas combinado con **Todas (AND)** o **Alguna (OR)**. |
| **Grupo** | Un conjunto anidado de bloques seleccionados con su propia lógica **Todas** o **Alguna**. Los grupos funcionan como paréntesis. |

Una condición simple se lee como una frase:

```text
mc.jaime · health es mayor que 50
```

Usa **Group selected** cuando un subconjunto de bloques deba evaluarse junto:

```text
(mc.jaime.has_key && door.lock_level < 3) || mc.jaime.is_admin
```

En builder, agrupa las comprobaciones de llave y nivel de cerradura con **Todas**, y después combina ese grupo con la comprobación de admin usando **Alguna**.

## Operadores por tipo de variable

| Tipo de variable | Operadores comunes |
| ---------------- | ------------------ |
| **Número** | igual, no igual, mayor que, menor que, no está establecido |
| **Texto / enriquecido** | igual, contiene, empieza con, termina con, está vacío |
| **Booleano** | es verdadero, es falso, no está establecido |
| **Selección** | igual, no igual, no está establecido |
| **Selección múltiple** | contiene, no contiene, está vacío |
| **Fecha** | igual, antes de, después de, no está establecido |

Los operadores disponibles dependen del tipo de variable seleccionado, así que el builder evita comparaciones inválidas cuando puede.

## Code view

Code view es el editor de expresiones. Es útil cuando ya conoces las rutas de variables o cuando una expresión es más rápida de escribir que de montar visualmente.

```text
mc.jaime.health > 50 && (quest.door.unlocked == true || mc.jaime.has_key == true)
```

Code view ofrece autocompletado, linting y formato. Usa el formato después de editar una expresión larga para que los paréntesis y grupos lógicos sigan siendo legibles.

Si una expresión no se puede parsear a datos de condición soportados, corrige la expresión antes de confiar en ella en player, depuración o exploración.

## Nodos de condición y modo switch

El editor es compartido, pero algunas funciones dependen del sitio donde se usa la condición.

Los nodos de Condición pueden usar modo de salida **Booleano** o **Switch**. En modo switch, cada bloque de condición se convierte en una rama de salida y gana el primer bloque que coincida. Las respuestas de diálogo, zonas y pines no usan salidas switch; usan la condición como puerta de acceso.
