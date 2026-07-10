%{
title: "Zonas y áreas interactivas",
category_label: "Diseño de Escenas",
order: 2,
description: "Dibuja áreas en una escena y conviértelas en navegación, interacciones, indicadores, colecciones o zonas transitables."
}

---

Las zonas son regiones poligonales dibujadas sobre una escena. En el editor sirven para delimitar partes del mapa; en modo exploración pueden comportarse como botones de mapa, áreas transitables, indicadores de variables o colecciones de elementos.

<img src="/images/docs/scenes-editor-current.png" alt="Lienzo de escena con zonas de Acción, Mostrar, Colección y Área transitable visibles en el editor" loading="lazy">

## Dibujar zonas

| Herramienta    | Uso típico                                                   |
| -------------- | ------------------------------------------------------------ |
| **Rectángulo** | Habitaciones, edificios, paneles de interfaz dentro del mapa |
| **Triángulo**  | Marcadores direccionales, puntos de interés, cuñas de mapa   |
| **Círculo**    | Áreas de influencia, campamentos, radios aproximados         |
| **Libre**      | Habitaciones irregulares, caminos, límites de terreno        |

Los vértices se guardan como porcentajes relativos al tamaño de la escena. Así las zonas siguen alineadas si cambia la imagen de fondo o el tamaño de la vista.

Haz doble clic en una zona para editar sus vértices. Arrastra los puntos de edición para ajustar la forma y confirma el cambio cuando quieras que la zona siga mejor el arte del mapa.

## Tipos de zona

El selector de tipo define qué hace la zona en modo exploración:

| Tipo                 | Uso                                                                                                                                                                                                              |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Acción**           | Crea una interacción: puede ejecutar instrucciones, abrir una escena, lanzar un flujo o combinar varias de estas acciones. Úsala para puertas, puntos interactivos, botones de mapa y cambios de estado simples. |
| **Área transitable** | Marca por dónde puede moverse el jugador en modo exploración.                                                                                                                                                    |
| **Mostrar**          | Muestra el valor actual de una variable en el mapa. Puede mostrar solo el valor o nombre + valor.                                                                                                                |
| **Colección**        | Abre una ventana con elementos recogibles. Cada elemento puede tener condición propia e instrucciones al recogerlo.                                                                                              |

Usa **Área transitable** para definir por dónde puede moverse el jugador. Usa **Acción** para los puntos del mapa que deben responder al clic con navegación, instrucciones o flujos.

## Panel de propiedades

Las propiedades de zona están organizadas en pestañas:

| Pestaña                             | Qué configura                                                          |
| ----------------------------------- | ---------------------------------------------------------------------- |
| **Visual**                          | Texto, icono, variable mostrada, tamaño, fuente, peso y estilo.        |
| **Reglas**                          | Condición de disponibilidad y efecto cuando la condición no se cumple. |
| **Acción / Movimiento / Colección** | Opciones específicas del tipo de zona seleccionada.                    |
| **Ajustes**                         | Atajo, estado oculto en exploración y texto de ayuda.                  |

## Visual

Las zonas de Acción, Colección y Área transitable pueden mostrar:

- **Texto** -- muestra el nombre de la zona.
- **Icono** -- muestra un icono subido por el usuario.
- **Texto e icono** -- muestra ambos.
- **Nada** -- oculta la etiqueta en modo exploración, pero el editor sigue mostrando el nombre para que puedas localizar la zona.

Los iconos pueden ser **SVG, PNG o GIF** y pesar como máximo **256 KB**.

En zonas Mostrar, selecciona la variable que quieres enseñar y elige si se renderiza solo el **valor** o **nombre + valor**. El tamaño y la fuente afectan al valor mostrado en modo exploración.

## Reglas

Cada zona puede tener una condición construida con el [Editor de Condiciones](/docs/narrative-design/condition-editor). Si la condición no se cumple, elige un efecto:

- **Ocultar** -- la zona desaparece de la vista de exploración.
- **Deshabilitar** -- la zona sigue visible, pero queda bloqueada.

Úsalo para puertas bloqueadas, rutas revelables, indicadores contextuales, colecciones que aparecen más tarde o puntos interactivos que dependen del estado del juego.

## Acción

Una zona de Acción puede:

- Navegar a una **escena**.
- Lanzar un **flujo** sobre la escena.
- Ejecutar instrucciones con el [Editor de Instrucciones](/docs/narrative-design/instruction-editor).
- Combinar navegación e instrucciones.

Para que una Acción tenga efecto en modo exploración, configúrale al menos una navegación, una instrucción o ambas.

## Área transitable

Las zonas Área transitable definen dónde se puede mover el personaje líder en modo exploración. El movimiento usa el polígono de la zona: si haces clic fuera de cualquier área transitable visible, el movimiento se bloquea.

Las áreas transitables se resaltan en verde cuando activas la visualización de zonas en modo exploración.

## Mostrar

Las zonas Mostrar enseñan una variable en el mapa. Sirven para interfaz integrada en el mundo, contadores, estadísticas visibles o etiquetas dependientes del estado.

Cuando una variable numérica no tiene parte decimal útil, Storyarn la muestra como entero para evitar ruido visual.

## Colección

Las zonas Colección abren una ventana de colección. Cada elemento puede apuntar a una ficha, tener una etiqueta, evaluar una condición propia y ejecutar instrucciones al recogerlo. También puedes permitir **Recoger todo** y definir el mensaje cuando no hay elementos visibles.

<img src="/images/docs/scenes-zone-properties.png" alt="Panel de propiedades de una zona con ajustes visuales y pestañas de reglas, acciones y configuración" loading="lazy">
