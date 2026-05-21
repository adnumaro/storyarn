%{
title: "Tu primera hoja",
category_label: "Inicio Rápido",
order: 2,
description: "Crea una ficha de personaje y comprende cómo funcionan las variables."
}

---

Las Fichas (Sheets) son la columna vertebral de datos de tu proyecto. Cada campo que añadas a una ficha puede convertirse en una {accent}variable{/accent} que tus flujos leen y modifican en tiempo de ejecución.

## Crea la ficha

Abre tu proyecto y selecciona **Fichas** en la barra lateral. Haz clic en el botón **Nueva Ficha** en la parte superior del árbol de fichas.

Se crea una nueva hoja con un nombre predeterminado. Haz clic en el título para renombrarlo — por ejemplo, "Jaime". El {accent}atajo (shortcut){/accent} (que se muestra debajo del nombre) se genera automáticamente a partir del nombre de la ficha. Puedes editarlo manualmente — para un personaje, algo como `mc.jaime` funciona bien porque crea un espacio de nombres legible para todas las variables de esta hoja.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Una nueva hoja con el título "Jaime" y el atajo "mc.jaime" visible debajo del nombre
</div>

## Añade bloques

Haz clic en el botón **+** en la parte inferior de la ficha para abrir el menú de bloques. Los bloques están organizados en dos categorías:

**Bloques Básicos** -- Texto, Texto Enriquecido, Número, Selección, Selección Múltiple, Fecha, Booleano, Referencia

**Datos Estructurados** -- Tabla, Galería

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El menú de tipos de bloque mostrando las categorías Bloques Básicos y Datos Estructurados
</div>

Prueba a añadir estos bloques a tu hoja de personaje:

1. Elige **Número** y etiquétalo como "Health". Establece el valor predeterminado en `100`. Esto crea la variable `mc.jaime.health`.

2. Elige **Selección** y etiquétalo como "Class". Añade opciones como Warrior, Mage y Rogue usando el popover de configuración del bloque. Esto crea `mc.jaime.class`.

3. Elige **Booleano** y etiquétalo como "Is Alive". Actívalo. Esto crea `mc.jaime.is_alive`.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  La hoja con los bloques Health (número), Class (selección) e Is Alive (booleano) rellenados
</div>

## Constantes vs. variables

Por defecto, cada bloque se convierte en una variable — excepto los bloques de {accent}Referencia{/accent} y {accent}Galería{/accent}, que nunca exponen variables.

Si quieres que un bloque contenga datos de solo visualización que los flujos no puedan leer, márcalo como **constante** en el popover de configuración del bloque. Las constantes son útiles para etiquetas, descripciones o texto de lore que no necesita participar en la lógica del juego.

## Cómo funcionan las variables

Cada bloque no constante se convierte en una variable con el formato `{atajo_de_hoja}.{nombre_de_variable}`:

| Bloque   | Variable            | Tipo    |
| -------- | ------------------- | ------- |
| Health   | `mc.jaime.health`   | number  |
| Class    | `mc.jaime.class`    | select  |
| Is Alive | `mc.jaime.is_alive` | boolean |

El {accent}nombre de variable{/accent} se genera automáticamente a partir de la etiqueta del bloque (en minúsculas, los espacios se convierten en guiones bajos). Puedes personalizarlo en la configuración avanzada del bloque.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El popover de configuración del bloque mostrando el campo de nombre de variable y el interruptor "es constante"
</div>

En la siguiente guía, usarás `mc.jaime.health` para crear diálogos ramificados en un flujo.
