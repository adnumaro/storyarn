%{
title: "Tablas",
category_label: "Construcción de Mundos",
order: 3,
description: "Cuadrículas estilo hoja de cálculo dentro de las hojas para inventarios, matrices de estadísticas y listas estructuradas."
}

---

Las tablas son un tipo de bloque que incrusta una {accent}cuadrícula tipo hoja de cálculo{/accent} dentro de una hoja. Cada tabla tiene columnas tipadas, filas con nombre y referencias a variables a nivel de celda. Úsalas para inventarios, tablas de estadísticas, matrices de relaciones, árboles de habilidades o catálogos de tiendas.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Un bloque de tabla mostrando una cuadrícula de inventario con columnas para Objeto (texto), Cantidad (número), Equipado (booleano) y una columna de fórmula calculando el peso.
</div>

---

## Estructura

Una tabla se compone de:

- **Columnas** -- campos tipados que definen la estructura de la tabla. Cada columna tiene un nombre, un tipo y un slug (autogenerado a partir del nombre).
- **Filas** -- registros con nombre. Cada fila tiene un nombre y un slug. Los nombres de las filas deben ser descriptivos: "Poción Curativa", "Espada de Hierro", "Fuerza".
- **Celdas** -- la intersección de una fila y una columna. Los valores de las celdas se almacenan como un mapa JSON indexado por el slug de la columna.

---

## Tipos de columnas

Las columnas de tabla admiten {accent}8 tipos{/accent}:

| Tipo             | Descripción                                         |
| ---------------- | --------------------------------------------------- |
| **Número**       | Valores numéricos (tipo de columna por defecto)     |
| **Texto**        | Texto plano (no hay texto enriquecido en las tablas)|
| **Booleano**     | Interruptor de verdadero/falso                      |
| **Selección**    | Opción única a partir de opciones definidas         |
| **Sel. Múltiple**| Varias opciones a partir de opciones definidas      |
| **Fecha**        | Valor de fecha                                      |
| **Referencia**   | Enlace a una hoja o flujo (no es una variable)      |
| **Fórmula**      | Valor calculado a partir de una expresión matemática con vinculaciones |

Estos reflejan los tipos de bloques normales, excepto que las tablas utilizan texto plano en lugar de texto enriquecido y añaden el tipo de columna de fórmula.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El selector de tipo de columna mostrando los 8 tipos disponibles.
</div>

---

## Variables a nivel de celda

Cada celda que no sea constante ni referencia se convierte en una variable usando una {accent}notación de puntos extendida{/accent}:

```
{atajo_hoja}.{variable_tabla}.{slug_fila}.{slug_columna}
```

Por ejemplo, en la hoja `mc.jaime` con un bloque de tabla etiquetado como "Inventario" (variable `inventory`), una fila llamada "Healing Potion" y una columna llamada "Quantity":

```
mc.jaime.inventory.healing_potion.quantity
```

Esto significa que los flujos pueden leer y modificar celdas individuales. Una condición puede comprobar "¿Es `mc.jaime.inventory.healing_potion.quantity` > 0?" y una instrucción puede establecerle un nuevo valor.

Los slugs se autogeneran a partir de los nombres usando notación de guion bajo, al igual que los nombres de variables de bloques.

---

## Columnas de fórmula

Las columnas de fórmula te permiten definir {accent}valores calculados{/accent} usando expresiones matemáticas. Cada celda en una columna de fórmula almacena su propia expresión y vinculaciones de variables.

### Sintaxis

Las fórmulas admiten funciones y operaciones matemáticas estándar:

| Categoría        | Sintaxis                                                                         |
| --------------- | -------------------------------------------------------------------------------- |
| **Operadores**  | `+`, `-`, `*`, `/`, `^` (potencia)                                               |
| **Menos unario**| `-a`                                                                             |
| **Paréntesis**  | `(a + b) * c`                                                                    |
| **Literales**   | `42`, `3.14`                                                                     |
| **Funciones**   | `sqrt(x)`, `abs(x)`, `floor(x)`, `ceil(x)`, `round(x)`, `min(a, b)`, `max(a, b)` |

Las expresiones utilizan símbolos de una sola letra o con nombre (`a`, `b`, `valor_con`) que están vinculados a fuentes de datos reales.

### Tipos de vinculación (Bindings)

Cada símbolo en una fórmula está vinculado a una fuente de datos. Hay dos tipos de vinculación:

- **Misma fila (Same-row)** -- hace referencia a otra columna en la misma fila. Por ejemplo, vincular `a` a la columna "Base" significa que `a` se resuelve como el valor Base de esa fila.
- **Variable de otras hojas** -- hace referencia a cualquier variable del proyecto por su ruta completa. Por ejemplo, vincular `b` a `mc.jaime.level` introduce el nivel del personaje en la fórmula.

### Ejemplo

Una columna de fórmula "Modificador" en una tabla de estadísticas con la expresión `floor((a - 10) / 2)`, donde `a` está vinculado a la columna "Valor" de la misma fila:

| Estadística  | Valor | Modificador |
| ------------ | ----- | -------- |
| Fuerza       | 16    | 3        |
| Destreza     | 12    | 1        |
| Constitución | 8     | -1       |

El modificador se recalcula siempre que los valores vinculados cambian.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Una configuración de columna de fórmula que muestra el editor de expresiones con enlaces de símbolos: "a" vinculado a la columna "Valor" de la misma fila y la previsualización renderizada en LaTeX de la fórmula.
</div>

---

## Configuración de columna

Las columnas tienen las mismas opciones de configuración que sus tipos de bloque equivalentes:

- Las columnas de **Selección / Selección Múltiple** obtienen una lista de opciones.
- **Las columnas se pueden marcar como constantes** -- sus celdas no se expondrán como variables.
- **Las columnas se pueden marcar como obligatorias** -- se advertirá sobre las celdas vacías.

---

## Herencia

Cuando un bloque de tabla tiene su alcance ajustado en "hijos", se copia toda la estructura de la tabla (columnas y filas) {accent}a las hojas secundarias{/accent}. Cada hijo u hoja anidada obtiene su propia tabla con las mismas columnas y filas pero con valores de celdas independientes.

Las vinculaciones a las fórmulas (bindings) que apuntan o hacen referencia a la misma hoja raíz se volverán a mapear y escribirse de manera autónoma para indicar hacia las variables intrínsecas de la hoja hija.  Por ejemplo, si la principal (`main`) formula algo con referencia `main.combat.attack`, su hija llamada o sub-hoja (`seven`) ajustará internamente dicha fórmula hacia sus propios datos rescribiendo su referencia a: `seven.combat.attack` (suponiendo que haya heredado también la sección general de `combat`).

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El bloque de tabla heredado por en una hoja matriz junto con su contraparte inferior replicada a partir de los datos parentales pero disponiendo de libertad total en sus valores intrarrenales de celdas.
</div>
