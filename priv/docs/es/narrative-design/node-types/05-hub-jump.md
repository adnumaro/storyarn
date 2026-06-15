%{
title: "Nodos Hub y Jump",
category_label: "Diseño Narrativo",
section_label: "Tipos de nodos",
section_order: 1,
order: 5,
description: "Une ramas y salta a puntos con nombre sin duplicar diálogo."
}

---

Los nodos Hub y Jump trabajan juntos. Un Hub es un destino con nombre dentro del flujo. Un Jump envía la ejecución a ese destino.

Úsalos cuando varias ramas necesitan converger en la misma continuación sin dibujar conexiones largas o duplicar nodos.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Lienzo de flujo con varias ramas usando nodos Jump para converger en un Hub
</div>

## Nodos Hub

Un Hub marca un punto con nombre en el flujo. Dale una etiqueta clara y un ID estable, como `after_intro`, `quest_acceptance` o `combat_setup`.

La barra del Hub muestra referencias desde nodos Jump, para que puedas ver qué partes del flujo apuntan a él.

## Nodos Jump

Un Jump selecciona un Hub destino. Cuando la ejecución llega al Jump, el flujo continúa desde ese Hub.

Usa la acción de localizar en la barra cuando necesites mover la vista del lienzo hasta el Hub destino.

## Buenos usos

- Varias respuestas de diálogo vuelven al mismo seguimiento.
- Una condición tiene varias ramas de fallo que regresan a un punto común.
- Un flujo largo tiene checkpoints con nombre.
- Quieres evitar duplicar diálogo o instrucciones idénticas.

## No abusar

Hub y Jump limpian grafos grandes, pero demasiados saltos pueden hacer que la ejecución sea más difícil de seguir. Prefiere conexiones directas mientras el grafo sea pequeño. Añade hubs cuando las líneas se vuelvan ruidosas o empiece a aparecer contenido duplicado.
