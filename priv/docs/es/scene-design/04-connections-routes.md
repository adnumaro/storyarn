%{
title: "Conexiones y rutas",
category_label: "Diseño de Escenas",
order: 4,
description: "Conecta pines con caminos, etiquetas, dirección, estilos de línea y edición de waypoints."
}

---

Las conexiones son líneas visuales entre pines. Úsalas para rutas, caminos, enlaces de viaje, relaciones, dependencias de misión o cualquier asociación que convenga ver en la escena.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Mapa con varios pines conectados mediante líneas sólidas, discontinuas y rutas con waypoints
</div>

## Crear conexiones

Usa la herramienta de conector y elige un pin de origen y uno de destino. Las conexiones se anclan a pines, así que los extremos permanecen estables cuando los pines se mueven.

## Dirección

| Dirección | Significado |
| --------- | ----------- |
| **Bidireccional** | Viaje o relación en ambos sentidos. |
| **Una dirección** | Movimiento, dependencia o relación con una sola dirección. |

## Estilo

Las conexiones pueden definir color, ancho, estilo y visibilidad de etiqueta.

- Líneas sólidas para rutas normales.
- Discontinuas para rutas condicionales, ocultas o indirectas.
- Punteadas para relaciones o enlaces no físicos.

## Waypoints

Los waypoints permiten curvar una conexión alrededor de elementos del mapa. Úsalos cuando una ruta deba seguir una carretera, pasillo, costa o camino de diseño en vez de ser una línea recta.

## Qué no hacen

Las conexiones explican rutas y relaciones en el mapa. Si una ruta debe bloquearse, ocultarse o cambiar de estado durante la exploración, configura esa lógica en los pines o zonas relacionados mediante condiciones y acciones.
