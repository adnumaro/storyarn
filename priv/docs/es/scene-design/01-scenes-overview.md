%{
title: "Vista general de Escenas",
category_label: "Diseño de Escenas",
order: 1,
description: "Mapea tu mundo con lienzos espaciales, zonas, pines, conexiones, capas y exploración."
}

---

Las Escenas son lienzos espaciales para mapear el mundo de un proyecto. Úsalas para mapas, layouts de nivel, jerarquías de ubicaciones, exploración interactiva y espacios narrativos que necesitan algo más que un flujo lineal.

<img src="/images/docs/scenes-editor-current.png" alt="Lienzo completo del editor de escenas con mapa de fondo, zonas, pines, herramientas y barra inferior" loading="lazy">

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
