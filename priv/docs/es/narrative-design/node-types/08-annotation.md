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

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Lienzo de flujo con notas de anotación junto a una sección de diálogo ramificado
</div>

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
