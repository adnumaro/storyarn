%{
title: "Visión general de las Hojas",
category_label: "Construcción de Mundos",
order: 1,
description: "Comprende cómo las hojas organizan los datos de tu juego en una base de datos viva."
}

---

Las Hojas (Sheets) son {accent}contenedores de datos estructurados{/accent} para los datos del mundo de tu proyecto. Perfiles de personajes, catálogos de objetos, detalles de ubicaciones, registros de facciones — cualquier cosa que necesites definir y rastrear a lo largo de tu narrativa.

Cada hoja contiene un conjunto de **bloques (blocks)** (campos tipados como texto, número, selección, booleano) que definen su estructura. Los bloques que no estén marcados como constantes se convierten automáticamente en **variables** que los flujos pueden leer y modificar en tiempo de ejecución.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Una hoja de personaje mostrando bloques como Name (texto), Health (número), Class (selección) y una imagen de banner.
</div>

---

## Atajos (Shortcuts)

Cada hoja tiene un {accent}atajo (shortcut){/accent} — un identificador con notación de puntos que los flujos, condiciones e instrucciones usan para referenciarla.

Los atajos se generan automáticamente a partir del nombre de la hoja, pero pueden editarse manualmente. El formato es alfanumérico en minúsculas con puntos y guiones (p.ej., `mc.jaime`). Usa prefijos para organizar por dominio:

- `mc.jaime` -- personaje principal
- `item.healing-potion` -- un objeto
- `loc.tavern` -- una ubicación
- `faction.guild` -- una facción

Los atajos deben ser únicos dentro de un proyecto. Si una hoja ya tiene variables referenciadas en flujos, renombrarla no cambiará el atajo para evitar romper referencias.

---

## Referencias de variables

Los bloques de una hoja se convierten en variables con el patrón:

```
{atajo_de_hoja}.{nombre_de_variable}
```

El nombre de variable se genera automáticamente a partir de la etiqueta del bloque usando notación con guiones bajos. Por ejemplo, un bloque etiquetado "Health Points" en la hoja `mc.jaime` se convierte en:

```
mc.jaime.health_points
```

Estas referencias son las que los flujos usan en condiciones ("¿Es `mc.jaime.health_points` mayor que 50?") e instrucciones ("Establecer `mc.jaime.health_points` a 100").

---

## Organización con carpetas

Las hojas admiten una {accent}estructura de árbol{/accent}. Arrastra y suelta para reordenar, anida hojas dentro de otras para organizarlas.

```
Main Characters/
  mc.jaime
  mc.elena
  mc.kai
Items/
  Weapons/
    item.iron-sword
    item.fire-staff
  Potions/
    item.healing-potion
```

Cualquier hoja puede tener tanto hijos como sus propios bloques. Las hojas padre también pueden definir propiedades heredadas que se propagan a sus hijos (ver [Herencia de propiedades](#herencia-de-propiedades) más abajo).

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El árbol de hojas en la barra lateral mostrando hojas anidadas con controles de arrastre y jerarquía tipo carpetas.
</div>

---

## Herencia de propiedades

Los bloques tienen un ajuste de {accent}alcance (scope){/accent} que controla si permanecen locales o se propagan a las hojas hijas:

- **Propio (Self)** (predeterminado) -- el bloque existe solo en esta hoja.
- **Hijos (Children)** -- la definición del bloque se propaga a todas las hojas descendientes. Cada hija obtiene su propia instancia con valores locales pero el mismo tipo, etiqueta y configuración.

Esto te permite crear hojas padre tipo plantilla. Una hoja "Base de Personaje" con bloques de alcance hijos (salud, nivel, facción) les da automáticamente esos mismos campos a todas las hojas hijas, cada una con sus propios valores independientes.

Las instancias hijas se mantienen sincronizadas con la definición del padre: si cambias la etiqueta, el tipo o las opciones en el bloque padre, todas las instancias no desvinculadas se actualizan. Puedes **desvincular (detach)** una instancia para hacerla completamente independiente, o **volver a vincularla (re-attach)** para sincronizarla de nuevo.

Las hojas también pueden **ocultar** bloques heredados específicos, evitando que se propaguen más abajo a sus propios hijos.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Una hoja padre con el alcance "Hijos" en un bloque de Health, y una hoja hija mostrando el bloque de Health heredado con su propio valor local.
</div>

---

## Personalización de hojas

Cada hoja admite metadatos adicionales:

- **Color** -- un color hexadecimal para identificación visual en la barra lateral y las referencias.
- **Avatar** -- una imagen subida que se muestra como el icono de la hoja.
- **Banner** -- una imagen de cabecera que se muestra en la parte superior de la hoja.
- **Descripción** -- texto enriquecido para notas y anotaciones (no se expone como variable).

---

## Versionado

Storyarn registra el historial de cada hoja mediante {accent}capturas de versión (version snapshots){/accent}.

- **Auto-versionado** -- se crea automáticamente una captura cuando editas una hoja, con un intervalo mínimo de 5 minutos entre capturas para evitar ruido.
- **Capturas manuales** -- puedes crear una versión con nombre, con título y descripción, en cualquier momento para marcar un hito significativo.
- **Restaurar** -- vuelve a cualquier versión anterior. Esto restaura el nombre de la hoja, el atajo, el avatar, el banner y todos los tipos, configuraciones y valores de los bloques.

Cada versión registra quién hizo el cambio y genera un resumen de lo que cambió (bloques añadidos, eliminados o modificados).

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El panel de historial de versiones mostrando una lista de capturas con marcas de tiempo, resúmenes de cambios y un botón de restaurar.
</div>
