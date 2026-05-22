%{
title: "Nodos de Condición",
category_label: "Diseño Narrativo",
section_label: "Tipos de nodos",
section_order: 1,
order: 3,
description: "Ramifica un flujo evaluando variables con salidas booleanas o switch."
}

---

Los nodos de Condición leen variables y eligen qué camino debe seguir el flujo. Úsalos cuando la lógica de ramificación pertenece a la estructura del flujo, no solo a una respuesta concreta de diálogo.

Para los modos compartidos Builder y Code, consulta el [Editor de Condiciones](/docs/narrative-design/condition-editor).

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Nodo de Condición seleccionado con el Editor de Condiciones abierto y ramas Verdadero/Falso conectadas
</div>

## Modos de salida

| Modo | Úsalo cuando |
| ---- | ------------ |
| **Booleano** | Necesitas una rama simple Verdadero/Falso. |
| **Switch** | Necesitas varias salidas etiquetadas y quieres que gane la primera condición coincidente. |

El modo booleano da al nodo dos salidas: **Verdadero** y **Falso**. El flujo continúa por Verdadero cuando la condición pasa, y por Falso cuando no pasa.

El modo switch convierte cada bloque de condición en una rama de salida. Storyarn evalúa los bloques en orden y sigue el primero que pasa. Úsalo para clase, facción, reputación, fase de misión, nivel de relación o cualquier decisión con más de dos resultados.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Nodo de Condición en modo switch con varias ramas de salida etiquetadas
</div>

## Condición inline o nodo

Las respuestas de diálogo pueden tener condiciones inline. Usa una condición inline cuando solo controla si esa respuesta aparece.

Usa un nodo de Condición cuando:

- La rama forma parte de la estructura visible del flujo.
- Varias rutas comparten la misma decisión.
- Necesitas salidas switch.
- Quieres que la lógica sea fácil de depurar desde el lienzo.

## Depurar nodos de Condición

El Modo Depuración muestra qué rama toma un nodo de Condición y registra detalles por regla: qué variable se comprobó, el valor esperado, el valor real y si la regla pasó.

Cuando una rama no se comporta como esperas, avanza por el nodo en Modo Depuración y compara los detalles de la condición con el panel de variables actual.
