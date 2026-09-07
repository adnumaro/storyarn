%{
title: "Vista general de Flujos",
category_label: "Diseño Narrativo",
order: 1,
description: "Árboles de diálogo visuales y lógica narrativa ramificada."
}

---

Los Flujos (Flows) son el corazón de Storyarn -- **grafos de nodos visuales** donde construyes diálogos ramificados, lógica de juego y narrativas interactivas. Cada flujo es un lienzo de nodos conectados que define cómo se desarrolla una conversación o secuencia, desde un intercambio lineal simple hasta un árbol de misiones extenso con decenas de ramas.

<img src="/images/docs/flows-editor-current.png" alt="Lienzo del editor de flujos con nodos de diálogo, condición, instrucción, hub, subflow y salida conectados" loading="lazy">

---

## El editor

El editor de flujos es un lienzo a pantalla completa. Creas nodos (Nodes) desde la barra de herramientas flotante, los conectas arrastrando entre pines de salida y entrada, y editas el contenido en el panel lateral que aparece al seleccionar un nodo.

- **Desplazar** arrastrando el fondo
- **Zoom** con la rueda del raton
- **Seleccionar** un nodo haciendo clic; doble clic para abrir su editor principal (editor enfocado para dialogos, panel constructor para condiciones e instrucciones)
- **Seleccion multiple** con clic-arrastre o Shift+clic
- **Duplicar** nodos seleccionados con el menu contextual o atajo de teclado
- **Deshacer/Rehacer** para operaciones de nodos

Los nodos se conectan mediante **pines** -- pequenos circulos en los bordes de cada nodo. Arrastra desde un pin de salida a un pin de entrada para crear una conexion. Las conexiones definen el orden en que los nodos se ejecutan durante la reproduccion y la depuracion.

---

## Tipos de nodos

La paleta ofrece **9 tipos de nodos**. Los proyectos antiguos pueden conservar contenedores Sequence; las composiciones nuevas se crean en el [editor de Sequence](/docs/narrative-design/sequence-editor).

| Nodo            | Icono          | Proposito                                                                                                                                                                                                                 |
| --------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Entrada**     | Play           | Donde comienza el flujo. Se crea automaticamente con el flujo y no se puede eliminar. Consulta [Nodos de Entrada y Salida](/docs/narrative-design/node-types/entry-exit).                                                 |
| **Salida**      | Arrow right    | Donde termina el flujo. Soporta modos terminal, continuar a flujo y volver al llamador. Consulta [Nodos de Entrada y Salida](/docs/narrative-design/node-types/entry-exit).                                               |
| **Dialogo**     | Message square | Dialogo de personaje con respuestas opcionales del jugador. El tipo de nodo mas comun -- consulta la [guia dedicada](/docs/narrative-design/node-types/dialogue).                                                         |
| **Condicion**   | Git branch     | Ramifica el flujo segun valores de variables. Consulta [Nodos de Condición](/docs/narrative-design/node-types/condition) y el [Editor de Condiciones](/docs/narrative-design/condition-editor).                           |
| **Instruccion** | Zap            | Modifica valores de variables cuando el flujo pasa por el nodo. Consulta [Nodos de Instrucción](/docs/narrative-design/node-types/instruction) y el [Editor de Instrucciones](/docs/narrative-design/instruction-editor). |
| **Hub**         | Log in         | Punto de convergencia con nombre donde multiples caminos se unen. Consulta [Nodos Hub y Jump](/docs/narrative-design/node-types/hub-jump).                                                                                |
| **Salto**       | Log out        | Salta a un nodo Hub dentro del mismo flujo. Consulta [Nodos Hub y Jump](/docs/narrative-design/node-types/hub-jump).                                                                                                      |
| **Subflujo**    | Box            | Incrusta otro flujo dentro de este. Consulta [Nodos Subflow](/docs/narrative-design/node-types/subflow).                                                                                                                  |
| **Anotacion**   | Sticky note    | Nota visual pura para intención, tareas o contexto en el lienzo. Consulta [Nodos de anotación](/docs/narrative-design/node-types/annotation).                                                                             |

---

## Una estructura tipica

```
Entry
  -> Dialogue (NPC greeting)
    -> Condition (has quest item?)
      -> True: Dialogue (quest complete)
           -> Instruction (give reward, mark quest done)
             -> Exit (Terminal, outcome: "quest_complete")
      -> False: Dialogue (come back later)
           -> Exit (Terminal, outcome: "quest_pending")
```

Los flujos pueden ser tan simples como una conversacion lineal o tan complejos como un arbol de misiones completo. Usa nodos **Hub** y **Salto** para fusionar caminos convergentes sin duplicar dialogos. Usa nodos **Subflujo** para componer narrativas mas grandes a partir de fragmentos de flujo reutilizables.

<img src="/images/docs/flows-editor-current.png" alt="Un flujo con nodos hub y salto mostrando cómo múltiples ramas de diálogo convergen en un solo camino" loading="lazy">

---

## Subflujos y ejecucion anidada

Los nodos de subflujo te permiten incrustar un flujo dentro de otro. Cuando la ejecucion llega a un nodo de subflujo, entra al nodo de Entrada del flujo referenciado y lo recorre. Cuando alcanza un nodo de Salida con modo **Retornar al llamador**, la ejecucion vuelve al flujo padre y continua desde el pin de salida correspondiente.

Cada nodo de Salida en el flujo referenciado crea un pin de salida separado en el nodo de subflujo, de modo que el flujo padre puede ramificarse segun la salida que tomo el subflujo. El depurador y la reproducción integrada soportan navegacion completa entre flujos con pila de llamadas, asi que los subflujos anidados funcionan exactamente como esperarias.

---

## {accent}Editor de Sequence y reproducción{/accent}

Flows se abre con el lienzo de nodos completo. Pulsa **Play** en la barra de herramientas para abrir el editor visual de Sequence encima; arrastra el separador para ajustar ambas vistas. Selecciona un diálogo para editar sus imágenes, capas y audio. Pulsa **Stop** en la barra para volver al lienzo de nodos completo.

Usa **Reproducir escena** dentro del editor para probar la narrativa sin salir de él. La reproducción evalúa condiciones e instrucciones, sigue subflujos y se detiene en diálogos o decisiones del jugador. Puedes retroceder, reiniciar, cambiar el idioma de prueba o ampliar el espacio a pantalla completa sin navegar a otra página.

Las variables de la prueba pertenecen a la sesión de reproducción; probar una rama no escribe esos valores en las fichas. Usa Debug para inspeccionar el estado de ejecución y las respuestas no disponibles.

Consulta la [guía del editor de Sequence](/docs/narrative-design/sequence-editor) para editar la composición, el audio, los comentarios y la reproducción.

---

## {accent}Modo de depuracion{/accent}

La mayoria de herramientas narrativas te obligan a probar jugando el juego completo. Storyarn tiene un {accent}depurador{/accent} integrado -- avanza paso a paso por tu flujo, inspecciona cada variable en tiempo real, establece puntos de interrupcion y ve exactamente que camino se tomo y por que.

- **Paso** avanza un nodo a la vez
- **Paso atras** retrocede al estado anterior
- **Ejecutar** avanza automaticamente a velocidad configurable (200ms-3000ms por paso), deteniendose en puntos de interrupcion y decisiones del jugador
- **Reiniciar** reinicia desde el nodo de inicio
- **Iniciar desde cualquier nodo** -- elige cualquier nodo del flujo como punto de partida
- **Puntos de interrupcion** -- haz clic en el punto junto a cualquier nodo en la pestana Ruta para establecer un punto de interrupcion; la reproduccion automatica se detiene ahi
- **5 pestañas de información**: Consola (registro con marcas de tiempo y detalles de evaluacion de reglas), Variables (valores en vivo con filtrado, edicion en linea y seguimiento de cambios), Historial (cada cambio de variable con atribucion de origen) Ruta (traza visual de ejecución con controles de puntos de interrupción) y Composición (capas visuales, audio y sus orígenes)
- **Editar variables durante la sesion** -- haz clic en cualquier valor de variable en la pestana Variables para cambiarlo, luego continua la ejecucion para probar caminos alternativos

Cambia un valor de variable, reinicia y vuelve a ejecutar para probar caminos alternativos. Sin necesidad de motor de juego, sin ciclo de exportacion -- verifica tu logica justo donde la escribes.

Para una guia detallada, consulta la [guia del Modo de depuracion](/docs/narrative-design/debug-mode).
