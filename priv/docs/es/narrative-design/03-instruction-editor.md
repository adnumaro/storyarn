%{
title: "Editor de Instrucciones",
category_label: "Diseño Narrativo",
order: 3,
description: "Usa Builder view y Code view para escribir asignaciones de variables en flujos, respuestas, zonas y pines."
}

---

El Editor de Instrucciones define asignaciones que escriben en variables. Storyarn usa el mismo editor en cualquier punto donde la lógica runtime necesita cambiar estado:

| Dónde                     | Cuándo se ejecutan las instrucciones                          |
| ------------------------- | ------------------------------------------------------------- |
| **Nodos de Instrucción**  | Cuando el flujo llega al nodo.                                |
| **Respuestas de diálogo** | Cuando el jugador elige esa respuesta.                        |
| **Zonas de escena**       | Cuando la acción de la zona se activa durante la exploración. |
| **Pines de escena**       | Cuando la acción del pin se activa durante la exploración.    |

Las instrucciones pueden escribir valores literales o copiar valores desde otra variable. Usa el [Editor de Condiciones](/docs/narrative-design/condition-editor) cuando solo necesites comprobar estado.

<img src="/images/docs/flows-instruction-builder.png" alt="Lienzo del editor de flujos con un nodo de instrucción conectado al grafo narrativo" loading="lazy">

## Modos de edición

Cada conjunto de instrucciones tiene dos modos de edición:

| Modo             | Mejor para                                                                    | Qué editas                                             |
| ---------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------ |
| **Builder view** | La mayoría de usuarios, cambios de estado legibles, menos errores de sintaxis | Filas de asignación en forma de frase.                 |
| **Code view**    | Technical designers, edición rápida, cambios compactos en varias líneas       | Una asignación por línea, como `mc.jaime.gold += 100`. |

Al cambiar a Code view, Storyarn serializa las asignaciones actuales como texto. Al editar Code view, el texto se parsea de vuelta al formato estructurado que usa Storyarn.

## Builder view

Builder view se lee como lenguaje natural:

```text
Set mc.jaime · health to 75
Add 100 to mc.jaime · gold
Toggle quest.door · unlocked
```

Cada asignación tiene:

1. Una operación.
2. Una variable de destino.
3. Un valor, salvo que la operación no lo necesite.

Un mismo editor puede contener varias asignaciones. Se ejecutan en orden.

## Operaciones

| Operación                | Sintaxis en Code view         | Tipos de variable         |
| ------------------------ | ----------------------------- | ------------------------- |
| **Establecer**           | `mc.jaime.health = 75`        | Todos los tipos editables |
| **Sumar**                | `mc.jaime.gold += 100`        | Número                    |
| **Restar**               | `mc.jaime.health -= 25`       | Número                    |
| **Establecer verdadero** | `quest.door.unlocked = true`  | Booleano                  |
| **Establecer falso**     | `quest.door.unlocked = false` | Booleano                  |
| **Alternar**             | `toggle quest.door.unlocked`  | Booleano                  |
| **Limpiar**              | `clear mc.jaime.notes`        | Texto y texto enriquecido |

Las operaciones disponibles dependen del tipo de variable seleccionado. Por ejemplo, un número se puede establecer, sumar o restar, mientras que un booleano se puede establecer como verdadero, establecer como falso o alternar.

## Valores literales y referencias

La mayoría de asignaciones usan valores literales:

```text
mc.jaime.health = 75
```

También puedes cambiar el campo de valor a modo referencia de variable:

```text
mc.jaime.health = mc.jaime.max_health
```

Eso copia el valor actual de `max_health` en `health` cuando se ejecuta la instrucción.

## Code view

Code view usa una asignación por línea:

```text
quest.tavern.accepted = true
mc.jaime.gold += 100
mc.jaime.health = mc.jaime.max_health
clear mc.jaime.notes
```

Code view ofrece autocompletado, linting y formato. Si una línea no se puede parsear a una asignación soportada, corrígela antes de confiar en ella en player, depuración o exploración.

## Dónde colocar instrucciones

Usa un nodo de Instrucción dedicado cuando el cambio de estado sea importante para la estructura del flujo, cuando varios valores cambien juntos o cuando la actualización deba ocurrir sin depender de una respuesta concreta del jugador.

Usa instrucciones de respuesta, zona o pin cuando el cambio de estado pertenece a esa interacción concreta.
