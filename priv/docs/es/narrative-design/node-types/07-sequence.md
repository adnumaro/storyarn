%{
title: "Nodos Sequence existentes",
category_label: "Diseño Narrativo",
section_label: "Tipos de Nodos",
section_order: 1,
order: 7,
description: "Compatibilidad con contenedores Sequence existentes y el editor visual actual."
}

---

Las composiciones nuevas pertenecen a los nodos de diálogo y se editan en el [editor de Sequence](/docs/narrative-design/sequence-editor). No necesitas un nodo Sequence para añadir fondos, personajes, objetos, overlays o audio.

Los contenedores Sequence pueden seguir apareciendo en proyectos existentes. Storyarn conserva sus contenidos y composiciones por compatibilidad. Un diálogo puede continuar explícitamente la composición de otro diálogo o de un contenedor Sequence existente; mover un nodo dentro de un contenedor no crea herencia visual.

Para trabajo nuevo, abre el editor visual con **Play**, selecciona un diálogo y elige **Continúa desde** cuando deba compartir una composición existente. Usa nodos **Condition** y diálogos separados cuando una rama necesite otra composición o tono de voz.
