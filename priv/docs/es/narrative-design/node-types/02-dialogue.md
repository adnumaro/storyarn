%{
title: "Nodos de Diálogo",
category_label: "Diseño Narrativo",
section_label: "Tipos de nodos",
section_order: 1,
order: 2,
description: "Diálogo de personajes, respuestas del jugador y configuración de diálogos."
}

---

Los nodos de Dialogo (Dialogue) son el tipo de nodo mas comun. Representan **lo que dice un personaje** y opcionalmente **lo que el jugador puede responder**. Cada nodo de dialogo puede ser tan simple como una unica linea de texto o tan completo como un beat narrativo configurado con hablante, acotaciones, audio y respuestas ramificadas.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Un nodo de dialogo seleccionado en el editor de flujos con el panel lateral abierto mostrando todos los campos
</div>

---

## Escribir dialogos

Selecciona un nodo de dialogo para abrir el panel lateral. Encontraras los siguientes campos:

- **Hablante** -- vinculo a una ficha de personaje de tu proyecto. El nombre y avatar del personaje aparecen en el nodo del lienzo, y el contexto del hablante se usa para la extraccion de localizacion y los informes.
- **Texto** -- la linea de dialogo en si. Es un campo de texto enriquecido con formato (negrita, cursiva, subrayado, tachado, enlaces). Soporta variables de mencion de personaje para texto dinamico.
- **Acotaciones** -- notas opcionales de actuacion o puesta en escena que acompanan la linea (p. ej., "suspira profundamente", "se gira hacia la ventana"). Dan contexto adicional a traductores y revisores.
- **Texto de menu** -- una version mas corta de la linea para menus de eleccion, usada cuando el texto completo del dialogo es demasiado largo para mostrarse como opcion del jugador.

---

## Editor enfocado de dialogo

Haz doble clic en un nodo de dialogo (o haz clic en el boton de configuracion en la barra de herramientas) para abrir el {accent}**editor enfocado de dialogo**{/accent} -- un modo de escritura a pantalla completa que muestra todos los campos de dialogo en un diseno enfocado. Es la forma mas rapida de escribir y editar contenido de dialogo sin la distraccion del lienzo.

---

## Audio y campos tecnicos

- **Audio** -- adjunta un recurso de audio para doblaje. Cuando se vincula un archivo de audio, un icono indicador de audio aparece en el nodo del lienzo.
- **ID tecnico** -- un identificador unico para la integracion con el motor. Haz clic en el boton de generar en la barra de herramientas para auto-generar uno basado en el shortcut del flujo, el nombre del hablante y la posicion del nodo (p. ej., `tavern_quest_bartender_3`). Tambien puedes escribir un ID personalizado.
- **ID de localizacion** -- se genera automaticamente al crear el nodo. Lo usa el sistema de localizacion para rastrear y extraer texto traducible.

---

## Imagen personalizada

Si la ficha de personaje del hablante tiene una galeria con imagenes, aparece un selector de imagenes en la barra de herramientas. Puedes seleccionar una imagen para reemplazar el retrato predeterminado del hablante para esta linea de dialogo especifica -- util para mostrar diferentes expresiones o poses.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El selector de imagen personalizada en la barra de herramientas del dialogo mostrando imagenes de la galeria del personaje
</div>

---

## Respuestas del jugador

Un nodo de dialogo puede tener multiples **respuestas** -- las elecciones que hace el jugador. Cada respuesta tiene su propio texto y su propio pin de salida en el nodo, para que puedas conectar diferentes respuestas a diferentes caminos en el flujo.

Haz clic en **Agregar respuesta** para crear una nueva respuesta. El orden en que las defines es el orden en que aparecen en el Story Player.

Cuando un nodo de dialogo no tiene respuestas, funciona como una simple linea de dialogo con un unico pin de salida. La primera vez que agregas una respuesta, la conexion de salida existente se migra automaticamente al nuevo pin de respuesta.

---

## Condiciones de respuesta

Cada respuesta puede tener una **condicion** que debe ser verdadera para que aparezca como opcion valida. Las condiciones usan el [Editor de Condiciones](/docs/narrative-design/condition-editor) compartido, con Builder view y Code view.

> _Ejemplo: "[Fuerza > 15] Derribar la puerta"_
> Si la fuerza del jugador es 15 o menos, esta opcion no aparece (en modo Reproductor) o aparece en gris con texto tachado (en {accent}Modo de analisis{/accent}).

Un indicador de condicion aparece en la respuesta en el lienzo, para que puedas ver de un vistazo que respuestas tienen condiciones adjuntas.

---

## Instrucciones de respuesta

Cada respuesta tambien puede llevar **instrucciones** que modifican variables cuando se elige esa respuesta. Usan el [Editor de Instrucciones](/docs/narrative-design/instruction-editor) compartido, con todas las operaciones de asignación: Establecer, Sumar, Restar, Alternar, Establecer verdadero/falso y Limpiar.

> _Ejemplo: El jugador elige "Aceptar la mision" -> establece `quest.tavern.accepted` a verdadero_

Esto mantiene la logica simple cerca del dialogo sin necesitar un nodo de instruccion separado despues de cada rama de respuesta. Para casos complejos con multiples cambios de variables o logica compartida, usa un nodo de instruccion dedicado en su lugar.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Un nodo de dialogo con multiples respuestas, una mostrando un indicador de condicion y otra con una instruccion
</div>

---

## Asignacion de hablante

Vincular un nodo de dialogo a una ficha de personaje proporciona varios beneficios:

- El **nombre y avatar** del personaje aparecen en el nodo del lienzo, facilitando identificar quien habla de un vistazo
- La **extraccion de localizacion** incluye el contexto del hablante, para que los traductores sepan que personaje esta hablando
- Las **exportaciones e informes** pueden atribuir las lineas a los personajes correctos
- La **generacion de ID tecnico** incluye el nombre del hablante para identificadores significativos
- Puedes **rastrear que personajes aparecen** en que flujos a lo largo de tu proyecto

Para asignar un hablante, selecciona una ficha desde el desplegable de hablante en el panel lateral o la barra de herramientas. Cualquier ficha de tu proyecto puede usarse como hablante -- fichas de personaje, fichas de NPC o cualquier entidad que quieras asociar con dialogos.

---

## Reproduccion rapida

Haz clic en el boton **Play** en la barra de herramientas del nodo de dialogo para iniciar el {accent}Story Player{/accent} desde ese nodo especifico. Esto te permite previsualizar rapidamente como se desarrolla un intercambio de dialogo sin tener que navegar desde el nodo de Entrada.
