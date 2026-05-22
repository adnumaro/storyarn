%{
title: "Zonas y áreas interactivas",
category_label: "Diseño de Escenas",
order: 2,
description: "Dibuja áreas en una escena, dales estilo, enlázalas y úsalas para navegación a escenas hijas."
}

---

Las zonas son regiones poligonales dibujadas en una escena. Pueden representar habitaciones, distritos, terreno, encuentros, puertas, áreas ocultas o cualquier parte del mapa que deba comportarse como un área interactiva.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Lienzo de escena con varias zonas: una habitación rectangular, una región libre y una zona resaltada para drill-down
</div>

## Dibujar zonas

| Herramienta | Uso típico |
| ----------- | ---------- |
| **Rectángulo** | Habitaciones, edificios, paneles de mapa |
| **Triángulo** | Marcadores direccionales, puntos de interés |
| **Círculo** | Áreas de influencia, campamentos, radios aproximados |
| **Libre** | Habitaciones irregulares, regiones, caminos, límites de terreno |

Los vértices se guardan como porcentajes relativos al tamaño de la escena. Así las zonas siguen alineadas si cambia la imagen de fondo o el viewport.

## Editar vértices

Haz doble clic en una zona para editar sus vértices. Arrastra los handles para ajustar la forma y confirma el cambio.

## Estilo y visibilidad

Las zonas pueden definir color de relleno, borde, ancho, estilo de línea, opacidad, tooltip, capa y bloqueo. Bloquea zonas que no quieras mover accidentalmente mientras editas pines o conexiones.

## Targets y drill-down

Una zona puede enlazar a otra escena. También puedes crear una escena hija desde una zona: Storyarn recorta el fondo del padre alrededor de la zona, escala la imagen cuando hace falta y crea una escena hija con coordenadas normalizadas.

```text
Mapa del mundo -> Región -> Ciudad -> Edificio -> Sala
```

## Acciones y condiciones

Las zonas pueden ejecutar instrucciones, mostrar variables, ocultarse o deshabilitarse según condiciones. Consulta [Acciones, condiciones y exploración](/docs/scene-design/actions-conditions-exploration).
