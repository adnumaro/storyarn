%{
title: "Acciones, condiciones y exploración",
category_label: "Diseño de Escenas",
order: 6,
description: "Haz interactivos los elementos con condiciones, instrucciones, acciones de display, overlays de flujo y modo exploración."
}

---

Las Escenas pueden ser más que mapas estáticos. Zonas y pines pueden evaluar condiciones, ejecutar instrucciones, mostrar valores de variables, navegar a escenas y lanzar flujos durante la exploración.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Modo exploración mostrando un mapa interactivo con una zona resaltada y un overlay de diálogo de flujo
</div>

## Acciones

| Acción | Comportamiento |
| ------ | -------------- |
| **None** | El elemento no tiene acción runtime. |
| **Instruction** | Ejecuta asignaciones de variables con el [Editor de Instrucciones](/docs/narrative-design/instruction-editor) compartido. |
| **Display** | Muestra el valor actual de una variable. |
| **Flow target** | Abre un flujo como overlay sobre la escena. |
| **Scene target** | Navega a otra escena, a menudo una escena hija. |

## Condiciones

Añade una condición a una zona o pin cuando su disponibilidad depende del estado de juego. Las condiciones de escena usan el [Editor de Condiciones](/docs/narrative-design/condition-editor) compartido.

Cuando la condición es falsa, el elemento puede:

- **Ocultarse** -- desaparece de la vista de exploración.
- **Deshabilitarse** -- sigue visible, pero no se puede interactuar.

Úsalo para puertas bloqueadas, NPCs ocultos, áreas restringidas, rutas revelables o eventos condicionales.

## Modo exploración

El modo exploración es una simulación a pantalla completa de la escena. Evalúa acciones y condiciones en tiempo real.

Durante la exploración puedes:

1. Hacer clic en zonas y pines.
2. Lanzar flujos sin abandonar la escena.
3. Navegar a escenas hijas.
4. Ejecutar instrucciones que actualizan variables.
5. Mostrar valores de variables.
6. Ver elementos ocultarse o deshabilitarse según condiciones.

## Overlays de flujo

Cuando un elemento apunta a un flujo, la escena se atenúa y el flujo aparece como overlay. Al completar el diálogo o la rama, vuelves al mapa con los cambios de variables aplicados.

Este es el puente principal entre diseño espacial y lógica narrativa.

## Probar interacciones

Usa el modo exploración para validar la lógica antes de exportar o compartir el mapa. Comprueba que las condiciones se evalúan como esperas, que las instrucciones actualizan las variables correctas y que los overlays vuelven al estado correcto.
