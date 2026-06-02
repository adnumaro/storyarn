%{
title: "Capas y visibilidad",
category_label: "Diseño de Escenas",
order: 5,
description: "Organiza elementos de escena en capas y controla visibilidad y overlays de niebla."
}

---

Las capas agrupan elementos para organizar escenas densas. Úsalas para separar geografía, información de encuentros, posiciones de personajes, notas de diseño, rutas, spoilers o áreas de exploración.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Panel de capas mostrando varias capas con toggles de visibilidad y acceso al diseño de fog
</div>

## Asignación de capas

Zonas, pines y anotaciones pertenecen a una capa. Asigna elementos al crearlos o muévelos después desde el panel del elemento.

Las conexiones se leen en contexto con los puntos que conectan. Si una escena tiene muchas rutas, usa nombres de capas claros para organizar los pines, zonas y anotaciones que ayudan a entenderlas.

## Toggles de visibilidad

Activa o desactiva capas para concentrarte en una parte del diseño. Este toggle ayuda a editar la escena; no sustituye las reglas, condiciones o ajustes de exploración que determinan qué ve el jugador.

- Geografía
- Rutas de misión
- Posiciones de NPCs
- Interacciones ocultas
- Notas de diseño
- Anotaciones de revisión

## Overlay de niebla

Una capa puede marcarse como revelada sobre fog. El color y la opacidad del overlay se configuran una vez desde los ajustes de la escena, y se aplican a toda la escena cuando al menos una capa tiene esta opción activa.

Cuando el fog está activo, la escena se cubre con el overlay y el contenido de las capas reveladas se vuelve a dibujar por encima. Esto funciona con pines, zonas y anotaciones de esas capas. Las conexiones se muestran por encima cuando conectan con pines de una capa revelada.

Este ajuste no guarda progreso de exploración del jugador ni revela áreas automáticamente. Para controlar cuándo aparece un elemento en exploration mode, usa las condiciones del elemento correspondiente.

## Editar con seguridad

Un flujo práctico para escenas grandes:

1. Crea fondo y zonas principales.
2. Bloquea la geografía estable.
3. Añade pines y rutas en capas separadas.
4. Añade elementos condicionales o de exploración al final.
