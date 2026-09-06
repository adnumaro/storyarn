%{
title: "Editor de Sequence",
category_label: "Diseño Narrativo",
order: 6,
description: "Compón imágenes, sonido y diálogo, y prueba la escena en el mismo espacio."
}

---

Abre un flujo y pulsa **Play** en su barra de herramientas. El editor visual aparece encima del editor de nodos. Selecciona un diálogo para trabajar en su composición. **Stop** en la barra devuelve todo el espacio al editor de nodos.

Arrastra la separación para cambiar el tamaño de las dos vistas. Puedes redimensionar la Biblioteca y el inspector desde sus bordes, u ocultarlos para ampliar el escenario. Pantalla completa amplía el mismo editor, sin abrir otra página.

## Construye la composición

En **Fichas** encontrarás retratos y galerías de personajes; en **Assets**, las imágenes del proyecto. Elige si vas a añadir un personaje, escenario, objeto u overlay. Arrastra la imagen al escenario o selecciónala en la biblioteca. Las imágenes nuevas aparecen por encima de las capas existentes.

También puedes subir imágenes aquí. Soltarlas sobre el escenario las guarda en Assets y las añade al diálogo actual; soltarlas en la biblioteca solo las guarda. Cuando se ofrece optimización, Storyarn explica que conserva el original y crea una imagen más ligera para la web. La biblioteca muestra la de menor peso en lugar de duplicar ambas versiones.

Mueve las imágenes directamente, cambia su tamaño con los controles o introduce valores precisos en el inspector. El recuadro indica qué se verá durante la reproducción: las partes de la imagen que quedan fuera se ocultan, pero los controles de selección siguen disponibles. Usa la lista de capas para seleccionar una imagen tapada, cambiar el orden, ocultarla o bloquear su posición mientras editas.

**Continúa desde** elige la composición que se hereda. Los cambios afectan a este diálogo y a los que heredan de él. Restablecer una propiedad heredada recupera el valor de origen. Eliminar una capa heredada la oculta aquí sin borrarla del origen.

## Audio y voz

La pestaña **Audio** del inspector permite gestionar música, ambiente y efectos de sonido. Selecciona o sube una grabación, escúchala, ajusta su volumen o elimínala de esta intervención. La música y el ambiente se repiten; los efectos suenan una vez.

La voz procede de la grabación adjunta al diálogo. La pestaña de audio permite escucharla; su archivo se gestiona en el inspector del diálogo. El sonido de fondo y la voz se mantienen separados.

## Prueba la escena

La reproducción dentro del editor empieza desde el diálogo seleccionado. Puedes continuar, elegir una respuesta, retroceder o reiniciar en la misma vista. La música continúa entre diálogos cuando no cambia su origen; continuar corta de inmediato la voz anterior. Si el navegador bloquea el sonido, pulsa **Activar audio**.

Elige un idioma de contenido para comprobar diálogo, respuestas y voz localizados. Los indicadores avisan de traducciones o grabaciones ausentes o desactualizadas. Si falta una traducción se muestra el texto de origen; si falta la voz del idioma elegido, queda en silencio.

**Debug** utiliza el evaluador de Flows. Su pestaña Composición explica qué diálogo aporta cada capa o pista, incluidos los cambios y eliminaciones. Usa Variables y las otras pestañas para comprobar las condiciones narrativas.

## Revisa con tu equipo

Abre **Comentarios** en el editor para hablar sobre el diálogo seleccionado. Son los mismos hilos disponibles en su nodo de Flow. Las respuestas, menciones y resolución se mantienen juntas, también en pantalla completa. Los comentarios se refieren a la intervención completa.

## Ramificaciones y recuperación

Usa un **Condition** y diálogos distintos cuando una decisión requiera imágenes, indicaciones o voces diferentes. Un diálogo tiene un solo origen explícito de composición, también donde confluyen varias ramas. La composición no depende del recorrido realizado hasta llegar a él.

Deshacer y rehacer incluyen cambios visuales y de audio. Las versiones de Flow y los snapshots de proyecto conservan la composición y sus referencias a Assets. Otros formatos de exportación pueden advertir de que no representan estas composiciones; utiliza snapshots nativos para recuperar el proyecto completo.

Este editor crea escenas estáticas. No incluye una línea de tiempo de animación ni vídeo.
