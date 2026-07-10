%{
title: "Nodos de anotación",
category_label: "Diseño Narrativo",
section_label: "Tipos de nodos",
section_order: 1,
order: 8,
description: "Añade notas visuales a un flujo sin cambiar la ejecución."
}

---

Los nodos de anotación son notas en el lienzo. Ayudan a explicar intención, marcar preguntas abiertas, dejar TODOs o añadir contexto cerca de otros nodos.

<img src="/images/docs/flows-editor-current.png" alt="Lienzo de flujo con notas de anotación junto a una sección de diálogo ramificado" loading="lazy">

## Comportamiento de ejecución

Las anotaciones no se ejecutan. No afectan a la reproducción, depuración, variables, extracción de localización ni exportaciones.

## Buenos usos

- Marcar intención de diseño: "Esta rama es para jugadores con poca confianza."
- Dejar notas de implementación para compañeros.
- Identificar secciones que necesitan escritura, revisión de localización o QA.
- Explicar por qué existe una condición.
- Añadir TODOs temporales mientras organizas un grafo grande.

## Mantenerlas útiles

Usa anotaciones para aclarar el grafo, no para duplicar lo que ya se ve en los nodos. Si una anotación se convierte en documentación permanente de un sistema reutilizable, considera mover esa explicación a documentación de proyecto o mejorar los nombres de los nodos cercanos.
