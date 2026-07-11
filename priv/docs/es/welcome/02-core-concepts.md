%{
title: "Conceptos clave",
category_label: "Bienvenida",
order: 2,
description: "Un glosario de los conceptos principales de Storyarn que aparecen en la documentación."
}

---

Storyarn conecta datos de mundo, narrativa ramificada, escenas espaciales, localización y flujos de exportación. Este glosario te da el vocabulario compartido que se usa en toda la documentación.

## Estructura del proyecto

| Concepto      | Significado                                                                                                                               | Dónde leer más                                                       |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| **Workspace** | El contenedor principal de tu equipo. Contiene proyectos y controla la membresía del espacio de trabajo.                                  | [Crear un espacio de trabajo](/docs/quick-start/create-workspace)    |
| **Project**   | Un espacio narrativo independiente con sus propias fichas, flujos, escenas, datos de localización, recursos y miembros de proyecto.       | [Dashboard del proyecto](/docs/project-management/project-dashboard) |
| **Asset**     | Un archivo multimedia subido, como una imagen o audio. Los assets pueden usarse en fichas, flujos, escenas, localización y exportaciones. | [Recursos](/docs/project-management/assets)                          |

## Datos del mundo

| Concepto     | Significado                                                                                                                                                   | Dónde leer más                                                   |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| **Sheet**    | Un registro de datos estructurados para un personaje, objeto, ubicación, facción, misión o cualquier entidad del mundo que necesites seguir.                  | [Resumen de fichas](/docs/world-building/sheets-overview)        |
| **Block**    | Un campo tipado dentro de una ficha. Los bloques pueden guardar texto, texto enriquecido, números, booleanos, selecciones, fechas, tablas, referencias y más. | [Bloques y variables](/docs/world-building/blocks-and-variables) |
| **Variable** | Un valor legible en runtime generado desde un bloque compatible y no constante. Los bloques de referencia y galería no son variables.                         | [Tu primera ficha](/docs/quick-start/first-sheet)                |

Las variables usan este patrón:

```text
{atajo_de_ficha}.{nombre_de_variable}
```

Por ejemplo, un bloque Health en la ficha `mc.jaime` se convierte en `mc.jaime.health`.

## Lógica narrativa

| Concepto | Significado                                                                                                                                         | Dónde leer más                                             |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| **Flow** | Un grafo visual que define diálogo, lógica ramificada, condiciones, instrucciones, subflujos y rutas de ejecución.                                  | [Resumen de flujos](/docs/narrative-design/flows-overview) |
| **Node** | Un paso individual dentro de un flujo. Tipos comunes de nodo incluyen Dialogue, Condition, Instruction, Sequence, Subflow, Hub, Jump, Entry y Exit. | [Tu primer flujo](/docs/quick-start/first-flow)            |
| **Pin**  | Un punto de conexión en un nodo. Los pines de salida se conectan a pines de entrada para definir el orden de ejecución y las ramas.                 | [Resumen de flujos](/docs/narrative-design/flows-overview) |

## Diseño espacial

| Concepto  | Significado                                                                                                                                     | Dónde leer más                                           |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| **Scene** | Un mapa espacial donde el contenido narrativo puede explorarse mediante zonas, pines, escenas hijas y overlays de flujo.                        | [Resumen de escenas](/docs/scene-design/scenes-overview) |
| **Zone**  | Una región dibujada dentro de una escena. Las zonas pueden evaluar condiciones, ejecutar instrucciones, enlazar a flujos o abrir escenas hijas. | [Zonas y áreas interactivas](/docs/scene-design/zones)   |

## Localización

| Concepto            | Significado                                                                                                                                                     | Dónde leer más                                                      |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| **Localization ID** | Un identificador estable que el sistema de localización usa para seguir texto extraído entre cambios de fuente, traducción, revisión e importación/exportación. | [Resumen de localización](/docs/localization/localization-overview) |

## Cómo se conectan

Las fichas definen el estado del mundo. Los bloques de las fichas se convierten en variables. Los flujos leen esas variables mediante nodos de condición y las modifican mediante nodos de instrucción. Las escenas colocan los flujos en un contexto espacial. Localización extrae el texto visible para el jugador. Exportar mueve el resultado a formatos específicos de engine.
