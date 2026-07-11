%{
title: "Nodos Subflow",
category_label: "Diseño Narrativo",
section_label: "Tipos de nodos",
section_order: 1,
order: 6,
description: "Reutiliza un flujo dentro de otro y ramifica desde sus resultados de salida."
}

---

Los nodos Subflow permiten que un flujo llame a otro. Son la herramienta principal para componer sistemas narrativos grandes a partir de piezas pequeñas y reutilizables.

<img src="/images/docs/flows-editor-current.png" alt="Flujo padre con un nodo Subflow cuyos pines de salida vienen de los nodos de Salida del flujo referenciado" loading="lazy">

## Cómo se ejecutan

Cuando la ejecución llega a un Subflow:

1. Storyarn entra en el flujo referenciado por su nodo de Entrada.
2. Ese flujo se ejecuta normalmente.
3. Si llega a una Salida configurada para volver al llamador, la ejecución vuelve al flujo padre.
4. El flujo padre continúa desde el pin que coincide con el resultado de salida.

El Story Player y el depurador soportan ejecución anidada con pila de llamadas.

## Pines de salida

Los pines de salida se generan desde las salidas de retorno del flujo referenciado. Así el flujo padre ve explícitamente los resultados a los que puede reaccionar.

```text
agreed
refused
not_enough_gold
relationship_too_low
```

## Referencias circulares

Storyarn evita referencias circulares. Un flujo no puede llamarse a sí mismo directa o indirectamente mediante una cadena de subflujos.

## Cuándo crear un subflow

Usa subflows para conversaciones reutilizables, comprobaciones compartidas, beats repetidos de misión, tutoriales o cualquier fragmento narrativo que necesite estructura interna pero deba poder llamarse desde más de un lugar.
