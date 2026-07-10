%{
title: "Nodos de Instrucción",
category_label: "Diseño Narrativo",
section_label: "Tipos de nodos",
section_order: 1,
order: 4,
description: "Modifica variables mientras el flujo se ejecuta usando asignaciones visibles en el lienzo."
}

---

Los nodos de Instrucción escriben en variables cuando el flujo llega a ellos. Son la forma en que un flujo cambia el estado del juego: dar objetos, marcar flags de misión, actualizar relaciones, limpiar notas temporales o copiar una variable en otra.

Para los modos compartidos Builder y Code, las operaciones y la sintaxis de asignaciones, consulta el [Editor de Instrucciones](/docs/narrative-design/instruction-editor).

<img src="/images/docs/flows-instruction-builder.png" alt="Nodo de Instrucción en el lienzo conectado al grafo narrativo" loading="lazy">

## Cuándo usar un nodo de Instrucción

Usa un nodo de Instrucción dedicado cuando:

- El cambio de estado sea importante para la estructura del flujo.
- Varios valores cambien juntos.
- La actualización deba ocurrir sin depender de una respuesta concreta del jugador.
- Quieras que el cambio sea fácil de inspeccionar durante la depuración del flujo.

Usa instrucciones inline en respuestas para efectos simples ligados a una opción concreta del jugador.

## Comportamiento en el flujo

Los nodos de Instrucción son automáticos. El Story Player y el Modo Depuración no se detienen en ellos como elecciones del jugador; ejecutan las asignaciones y continúan por la siguiente conexión.

Mantén los nodos de instrucción cerca del beat narrativo al que afectan. Si una actualización de variable desbloquea una rama posterior, colocar la instrucción antes de esa rama hace que el flujo sea más fácil de leer y depurar.

## Depurar instrucciones

El depurador registra los cambios de variables causados por nodos de Instrucción. Al probar un flujo, avanza por el nodo e inspecciona el panel de variables para confirmar que la asignación produjo el valor esperado.
