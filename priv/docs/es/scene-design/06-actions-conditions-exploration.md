%{
title: "Acciones, condiciones y exploración",
category_label: "Diseño de Escenas",
order: 6,
description: "Haz interactivos los elementos con condiciones, acciones, indicadores, colecciones, flujos sobre la escena y modo exploración."
}

---

Las Escenas pueden ser más que mapas estáticos. Las zonas concentran las acciones de área: ejecutar instrucciones, mostrar valores, navegar a escenas o lanzar flujos. Los pines representan puntos concretos y pueden lanzar un flujo, moverse como personajes jugables o patrullas, y evaluar reglas de visibilidad durante la exploración.

<img src="/images/docs/scenes-exploration-current.png" alt="Modo exploración mostrando un mapa interactivo con pines y controles del jugador" loading="lazy">

## Tipos de interacción

| Tipo                       | Comportamiento                                                                                       |
| -------------------------- | ---------------------------------------------------------------------------------------------------- |
| **Acción**                 | Ejecuta instrucciones, navega a escena o flujo, o combina ambas cosas.                               |
| **Área transitable**       | Marca por dónde puede moverse el jugador en modo exploración.                                        |
| **Mostrar**                | Muestra una variable en el mapa, como valor o como nombre + valor.                                   |
| **Colección**              | Abre una ventana con elementos recogibles, cada uno con condiciones e instrucciones opcionales.      |
| **Pin con flujo**          | Lanza un flujo asociado al pin sobre la escena.                                                      |
| **Pin jugable o patrulla** | Permite controlar un personaje en áreas transitables o mover un pin no jugable siguiendo conexiones. |

Las zonas de Acción son el tipo principal para comportamiento interactivo. Úsalas cuando una parte del mapa deba abrir una escena, lanzar un flujo o modificar variables.

## Condiciones

Añade una condición a una zona o pin cuando su disponibilidad depende del estado de juego. Las condiciones de escena usan el [Editor de Condiciones](/docs/narrative-design/condition-editor) compartido.

Cuando la condición es falsa, el elemento puede:

- **Ocultarse** -- desaparece de la vista de exploración.
- **Deshabilitarse** -- sigue visible, pero queda bloqueado.

Úsalo para puertas bloqueadas, NPCs ocultos, áreas restringidas, rutas revelables o eventos condicionales.

## Modo exploración

El modo exploración es una simulación a pantalla completa de la escena. Evalúa acciones y condiciones en tiempo real.

Durante la exploración puedes:

1. Hacer clic en zonas interactivas y pines con flujo.
2. Lanzar flujos sin abandonar la escena.
3. Navegar a escenas hijas desde zonas de Acción.
4. Ejecutar instrucciones desde zonas de Acción o Colección.
5. Mostrar valores de variables con zonas Mostrar.
6. Abrir colecciones de elementos.
7. Mover personajes jugables dentro de áreas transitables.
8. Ver elementos ocultarse o deshabilitarse según condiciones.

## Flujos sobre la escena

Cuando un elemento abre un flujo, la escena se atenúa y el flujo aparece encima. Al completar el diálogo o la rama, vuelves al mapa con los cambios de variables aplicados.

Este es el puente principal entre diseño espacial y lógica narrativa.

## Probar interacciones

Usa el modo exploración para revisar la lógica antes de compartir el mapa. Comprueba que las condiciones se evalúan como esperas, que las instrucciones actualizan las variables correctas, que las zonas transitables limitan el movimiento, que las patrullas siguen su ruta y que los flujos vuelven al estado correcto.
