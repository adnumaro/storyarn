%{
title: "Vista general de Escenas",
category_label: "Diseño de Escenas",
order: 1,
description: "Mapea tu mundo con lienzos espaciales, zonas, pines, conexiones, capas y exploración."
}

---

Las Escenas son lienzos espaciales para mapear el mundo de un proyecto. Úsalas para mapas, layouts de nivel, jerarquías de ubicaciones, exploración interactiva y espacios narrativos que necesitan algo más que un flujo lineal.

<div class="docs-alert docs-alert-warning">
  <svg class="docs-alert-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21.73 18-8-14a2 2 0 0 0-3.46 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg>
  <p><strong>Documentación en construcción.</strong> Escenas tiene varios sistemas conectados. Esta sección los divide en páginas enfocadas para que cada concepto sea más fácil de seguir.</p>
</div>

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Lienzo completo del editor de escenas con mapa de fondo, zonas, pines, rutas, panel de capas y barra inferior
</div>

## Piezas principales

| Pieza           | Qué hace                                                                                                            | Sigue leyendo                                                                            |
| --------------- | ------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| **Zonas**       | Áreas poligonales en el lienzo para habitaciones, regiones, zonas interactivas, escenas hijas y acceso condicional. | [Zonas y áreas interactivas](/docs/scene-design/zones)                                   |
| **Pines**       | Marcadores puntuales para ubicaciones, personajes, eventos, objetos o referencias personalizadas.                   | [Pines](/docs/scene-design/pins)                                                         |
| **Conexiones**  | Líneas entre pines para caminos, rutas, enlaces de viaje o relaciones.                                              | [Conexiones y rutas](/docs/scene-design/connections-routes)                              |
| **Capas**       | Grupos de visibilidad para organizar elementos y revisar overlays de niebla sobre la escena.                        | [Capas y visibilidad](/docs/scene-design/layers-visibility)                              |
| **Exploración** | Modo a pantalla completa que evalúa acciones, condiciones y flujos abiertos sobre la escena.                        | [Acciones, condiciones y exploración](/docs/scene-design/actions-conditions-exploration) |

## Cuándo usar escenas

- **Mapas de mundo** -- continentes, regiones, ciudades o mazmorras.
- **Diseño de niveles** -- habitaciones con conexiones navegables.
- **Jerarquías de ubicación** -- bajar desde un mapa a regiones, edificios o salas.
- **Exploración interactiva** -- permitir clics en elementos, evaluar condiciones, cambiar variables y lanzar flujos.

## Modelo del editor

Las Escenas usan coordenadas porcentuales, así que los elementos permanecen alineados cuando cambia el tamaño del lienzo. El editor tiene una barra inferior para herramientas, un panel lateral para propiedades avanzadas y una estructura de árbol para organizar escenas.

Cada escena puede tener imagen de fondo, shortcut, escala para medición, escenas hijas, capas y exportación PNG/SVG.
