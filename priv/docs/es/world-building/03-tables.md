%{
title: "Tablas",
category_label: "Construcción de Mundos",
order: 3,
description: "Cuadrículas tipo hoja de cálculo dentro de las fichas para inventarios, matrices de estadísticas y listas estructuradas."
}

---

Las Tablas son un tipo de bloque que incrusta una {accent}cuadrícula tipo hoja de cálculo{/accent} dentro de una ficha. Cada tabla tiene columnas tipadas, filas con nombre y referencias a variables a nivel de celda. Úsalas para inventarios, tablas de estadísticas, matrices de relaciones, árboles de habilidades o catálogos de tiendas.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Un bloque de tabla mostrando una cuadrícula de inventario con columnas para Item (texto), Quantity (número), Equipped (booleano) y una columna de fórmula calculando el peso.
</div>

---

## Estructura

Una tabla se compone de:

- **Columnas** -- campos tipados que definen la estructura de la tabla. Cada columna tiene un nombre, un tipo y un slug (generado automáticamente a partir del nombre).
- **Filas** -- registros con nombre. Cada fila tiene un nombre y un slug. Los nombres de las filas deben ser descriptivos: "Healing Potion", "Iron Sword", "Strength".
- **Celdas** -- la intersección de una fila y una columna. Los valores de las celdas se almacenan como un mapa JSON indexado por el slug de la columna.

---

## Tipos de columnas

Las columnas de tabla admiten {accent}8 tipos{/accent}:

| Tipo                   | Descripción                                                            |
| ---------------------- | ---------------------------------------------------------------------- |
| **Número**             | Valores numéricos (tipo de columna predeterminado)                     |
| **Texto**              | Texto plano (sin texto enriquecido en tablas)                          |
| **Booleano**           | Interruptor verdadero/falso                                            |
| **Selección**          | Elección única de opciones definidas                                   |
| **Selección Múltiple** | Múltiples elecciones de opciones definidas                             |
| **Fecha**              | Valor de fecha                                                         |
| **Referencia**         | Enlace a una ficha o flujo (no es variable)                            |
| **Fórmula**            | Valor calculado a partir de una expresión matemática con vinculaciones |

Estos reflejan los tipos de bloques regulares, excepto que las tablas usan texto plano en lugar de texto enriquecido y añaden el tipo de columna de fórmula.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El selector de tipos de columna mostrando los 8 tipos disponibles.
</div>

---

## Variables a nivel de celda

Cada celda que no sea constante ni referencia se convierte en una variable usando {accent}notación de puntos extendida{/accent}:

```
{atajo_de_hoja}.{variable_de_tabla}.{slug_de_fila}.{slug_de_columna}
```

Por ejemplo, en la ficha `mc.jaime` con un bloque de tabla etiquetado "Inventory" (nombre de variable `inventory`), una fila llamada "Healing Potion" y una columna llamada "Quantity":

```
mc.jaime.inventory.healing_potion.quantity
```

Esto significa que los flujos pueden leer y modificar celdas individuales. Una condición puede comprobar "¿Es `mc.jaime.inventory.healing_potion.quantity` > 0?" y una instrucción puede establecerle un nuevo valor.

Los slugs se generan automáticamente a partir de los nombres usando notación con guiones bajos, igual que los nombres de variables de los bloques.

---

## Columnas de fórmula

Las columnas de fórmula te permiten definir {accent}valores calculados{/accent} usando expresiones matemáticas. Cada celda en una columna de fórmula almacena su propia expresión y vinculaciones de variables.

### Sintaxis

Las fórmulas admiten operaciones y funciones matemáticas estándar:

| Categoría        | Sintaxis                                                                         |
| ---------------- | -------------------------------------------------------------------------------- |
| **Operadores**   | `+`, `-`, `*`, `/`, `^` (potencia)                                               |
| **Menos unario** | `-a`                                                                             |
| **Paréntesis**   | `(a + b) * c`                                                                    |
| **Literales**    | `42`, `3.14`                                                                     |
| **Funciones**    | `sqrt(x)`, `abs(x)`, `floor(x)`, `ceil(x)`, `round(x)`, `min(a, b)`, `max(a, b)` |

Las expresiones usan símbolos de una sola letra o con nombre (`a`, `b`, `con_value`) que se vinculan a fuentes de datos reales.

### Tipos de vinculación

Cada símbolo en una fórmula se vincula a una fuente de datos. Hay dos tipos de vinculación:

- **Misma fila (Same-row)** -- referencia otra columna en la misma fila. Por ejemplo, vincular `a` a la columna "Base" significa que `a` se resuelve al valor de Base de esa fila.
- **Variable entre fichas (Cross-sheet variable)** -- referencia cualquier variable del proyecto por su ruta completa. Por ejemplo, vincular `b` a `mc.jaime.level` trae el nivel del personaje a la fórmula.

### Ejemplo

Una columna de fórmula "Modifier" en una tabla de estadísticas con la expresión `floor((a - 10) / 2)`, donde `a` está vinculado a la columna "Value" de la misma fila:

| Estadística  | Value | Modifier |
| ------------ | ----- | -------- |
| Strength     | 16    | 3        |
| Dexterity    | 12    | 1        |
| Constitution | 8     | -1       |

El modificador se recalcula cada vez que los valores vinculados cambian.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Configuración de una columna de fórmula mostrando el editor de expresiones con vinculaciones de símbolos: "a" vinculado a la columna "Value" de la misma fila, y la vista previa en LaTeX de la fórmula renderizada.
</div>

---

## Configuración de columnas

Las columnas tienen las mismas opciones de configuración que sus tipos de bloque equivalentes:

- Las columnas de **Selección / Selección Múltiple** obtienen una lista de opciones.
- **Las columnas pueden marcarse como constantes** -- sus celdas no se expondrán como variables.
- **Las columnas pueden marcarse como obligatorias** -- las celdas vacías se señalarán.

---

## Herencia

Cuando un bloque de tabla tiene el alcance configurado como "hijos", la estructura completa de la tabla (columnas y filas) se {accent}copia a las fichas hijas{/accent}. Cada hija obtiene su propia tabla con las mismas columnas y filas pero valores de celdas independientes.

Las vinculaciones de fórmulas que referencian la ficha padre se reescriben automáticamente para apuntar a la ficha hija. Por ejemplo, si una ficha padre `main` tiene una vinculación de fórmula a `main.combat.attack`, la ficha hija `seven` obtiene la vinculación reescrita a `seven.combat.attack` (asumiendo que el bloque `combat` también fue heredado).

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El bloque de tabla heredado de una ficha padre y la instancia de la misma tabla en una ficha hija, mostrando estructura idéntica pero valores de celdas diferentes.
</div>
