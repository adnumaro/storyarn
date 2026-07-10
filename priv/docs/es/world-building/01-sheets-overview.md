%{
title: "Visión general de las Fichas",
category_label: "Construcción de Mundos",
order: 1,
description: "Comprende cómo las fichas organizan los datos de tu juego en una base de datos viva."
}

---

Las Fichas (Sheets) son {accent}contenedores de datos estructurados{/accent} para los datos del mundo de tu proyecto. Perfiles de personajes, catálogos de objetos, detalles de ubicaciones, registros de facciones — cualquier cosa que necesites definir y rastrear a lo largo de tu narrativa.

Cada ficha contiene un conjunto de **bloques (blocks)** (campos tipados como texto, número, selección o booleano) que definen su estructura. Los bloques con valor que no estén marcados como constantes se convierten en **variables** que los flujos pueden leer y modificar en tiempo de ejecución. Los bloques de referencia y galería no participan en el sistema de variables.

<img src="/images/docs/sheets-character-current.png" alt="Ficha de Kael con bloques heredados, campos de texto enriquecido, galería, tablas y propiedades propias" loading="lazy">

---

## Atajos (Shortcuts)

Cada ficha tiene un {accent}atajo (shortcut){/accent} — un identificador con notación de puntos que los flujos, condiciones e instrucciones usan para referenciarla.

Los atajos se generan automáticamente a partir del nombre de la ficha, pero pueden editarse manualmente. El formato es alfanumérico en minúsculas con puntos y guiones (p.ej., `mc.jaime`). Usa prefijos para organizar por dominio:

- `mc.jaime` -- personaje principal
- `item.healing-potion` -- un objeto
- `loc.tavern` -- una ubicación
- `faction.guild` -- una facción

Los atajos deben ser únicos dentro de un proyecto. Si una ficha ya tiene variables referenciadas en flujos, renombrarla no cambiará el atajo para evitar romper referencias.

---

## Referencias de variables

Los bloques que admiten variables usan el patrón:

```
{atajo_de_hoja}.{nombre_de_variable}
```

El nombre de variable se genera automáticamente a partir de la etiqueta del bloque usando notación con guiones bajos. Por ejemplo, un bloque etiquetado "Health Points" en la ficha `mc.jaime` se convierte en:

```
mc.jaime.health_points
```

Estas referencias son las que los flujos usan en condiciones ("¿Es `mc.jaime.health_points` mayor que 50?") e instrucciones ("Establecer `mc.jaime.health_points` a 100").

---

## Organización con carpetas

Las fichas admiten una {accent}estructura de árbol{/accent}. Arrastra y suelta para reordenar, anida fichas dentro de otras para organizarlas.

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

Cualquier ficha puede tener tanto hijos como sus propios bloques. Las fichas padre también pueden definir propiedades heredadas que se propagan a sus hijos (ver [Herencia de propiedades](#herencia-de-propiedades) más abajo).

<img src="/images/docs/sheets-character-current.png" alt="El árbol de fichas en la barra lateral mostrando fichas anidadas con controles de arrastre y jerarquía tipo carpetas." loading="lazy">

---

## Herencia de propiedades

Los bloques tienen un ajuste de {accent}alcance (scope){/accent} que controla si permanecen locales o se propagan a las fichas hijas:

- **Propio (Self)** (predeterminado) -- el bloque existe solo en esta hoja.
- **Hijos (Children)** -- la definición del bloque se propaga a todas las fichas descendientes. Cada hija obtiene su propia instancia con valores locales pero el mismo tipo, etiqueta y configuración.

Esto te permite crear fichas padre tipo plantilla. Una ficha "Base de Personaje" con bloques de alcance hijos (salud, nivel, facción) les da automáticamente esos mismos campos a todas las fichas hijas, cada una con sus propios valores independientes.

Las instancias hijas se mantienen sincronizadas con la definición del padre: si cambias la etiqueta, el tipo o las opciones en el bloque padre, todas las instancias no desvinculadas se actualizan. Puedes **desvincular (detach)** una instancia para hacerla completamente independiente, o **volver a vincularla (re-attach)** para sincronizarla de nuevo.

Las fichas también pueden **ocultar** bloques heredados específicos, evitando que se propaguen más abajo a sus propios hijos.

<img src="/images/docs/sheets-character-current.png" alt="Una ficha padre con el alcance &quot;Hijos&quot; en un bloque de Health, y una ficha hija mostrando el bloque de Health heredado con su propio valor local." loading="lazy">

---

## Personalización de fichas

Cada ficha admite metadatos adicionales:

- **Color** -- un color hexadecimal para identificación visual en la barra lateral y las referencias.
- **Avatar** -- una imagen subida que se muestra como el icono de la ficha.
- **Banner** -- una imagen de cabecera que se muestra en la parte superior de la ficha.
- **Descripción** -- texto enriquecido para notas y anotaciones (no se expone como variable).

---

## Versionado

Storyarn registra el historial de cada ficha mediante {accent}capturas de versión (version snapshots){/accent}.

- **Auto-versionado** -- se crea automáticamente una captura cuando editas una ficha, con un intervalo mínimo de 5 minutos entre capturas para evitar ruido.
- **Capturas manuales** -- puedes crear una versión con nombre, con título y descripción, en cualquier momento para marcar un hito significativo.
- **Restaurar** -- vuelve a cualquier versión anterior. Esto restaura el nombre de la ficha, el atajo, el avatar, el banner y todos los tipos, configuraciones y valores de los bloques.

Cada versión registra quién hizo el cambio y genera un resumen de lo que cambió (bloques añadidos, eliminados o modificados).

<img src="/images/docs/project-snapshots.png" alt="El panel de capturas del proyecto para crear y restaurar copias de seguridad de un momento concreto." loading="lazy">
