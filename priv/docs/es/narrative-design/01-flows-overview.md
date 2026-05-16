%{
title: "Vista general de Flujos",
category_label: "Diseño Narrativo",
order: 1,
description: "Árboles de diálogo visuales y lógica narrativa ramificada."
}

---

Los Flujos (Flows) son el corazón de Storyarn -- **grafos de nodos visuales** donde construyes diálogos ramificados, lógica de juego y narrativas interactivas. Cada flujo es un lienzo de nodos conectados que define cómo se desarrolla una conversación o secuencia, desde un intercambio lineal simple hasta un árbol de misiones extenso con decenas de ramas.

<img src="/images/docs/veilbreak-flow-editor.png" alt="Lienzo del editor de flujos de Veilbreak con nodos conectados y minimapa" loading="lazy">

---

## El editor

El editor de flujos es un lienzo a pantalla completa. Creas nodos (Nodes) desde la barra de herramientas flotante, los conectas arrastrando entre pines de salida y entrada, y editas el contenido en el panel lateral que aparece al seleccionar un nodo.

- **Desplazar** arrastrando el fondo
- **Zoom** con la rueda del raton
- **Seleccionar** un nodo haciendo clic; doble clic para abrir su editor principal (editor de guion para dialogos, panel constructor para condiciones e instrucciones)
- **Seleccion multiple** con clic-arrastre o Shift+clic
- **Duplicar** nodos seleccionados con el menu contextual o atajo de teclado
- **Deshacer/Rehacer** para operaciones de nodos

Los nodos se conectan mediante **pines** -- pequenos circulos en los bordes de cada nodo. Arrastra desde un pin de salida a un pin de entrada para crear una conexion. Las conexiones definen el orden en que los nodos se ejecutan durante la reproduccion y la depuracion.

---

## Tipos de nodos

Storyarn tiene **10 tipos de nodos**, cada uno con un rol distinto en el grafo del flujo:

| Nodo            | Icono          | Proposito                                                                                                                                                                                                                                        |
| --------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Entrada**     | Play           | Donde comienza el flujo. Se crea automaticamente con el flujo, no se puede eliminar. Muestra que otros flujos lo referencian mediante nodos de subflujo.                                                                                         |
| **Salida**      | Arrow right    | Donde termina el flujo. Soporta tres modos: **Terminal** (termina completamente), **Continuar a flujo** (encadena con otro flujo) y **Retornar al llamador** (retorna desde un subflujo). Tiene etiquetas de resultado y codificacion por color. |
| **Dialogo**     | Message square | Dialogo de personaje con respuestas opcionales del jugador. El tipo de nodo mas comun -- consulta la [guia dedicada](/docs/narrative-design/dialogue-nodes).                                                                                     |
| **Condicion**   | Git branch     | Ramifica el flujo segun valores de variables. Constructor visual con logica AND/OR -- no requiere codigo. Soporta modo booleano (salidas Verdadero/Falso) y modo switch (multiples salidas personalizadas).                                      |
| **Instruccion** | Zap            | Modifica valores de variables cuando el flujo pasa a traves del nodo. Soporta Establecer, Sumar, Restar, Alternar, Limpiar y operaciones especificas para booleanos.                                                                             |
| **Hub**         | Log in         | Un punto de convergencia con nombre donde multiples caminos se unen. Tiene una etiqueta, un ID y un color.                                                                                                                                       |
| **Salto**       | Log out        | Salta a un nodo Hub dentro del mismo flujo. Selecciona un hub destino desde el desplegable de la barra de herramientas; un boton de mira lo localiza en el lienzo.                                                                               |
| **Subflujo**    | Box            | Incrusta otro flujo dentro de este. Los pines de salida dinamicos se generan a partir de los nodos de Salida del flujo referenciado, permitiendo ramificar segun como termina el subflujo. Las referencias circulares se detectan y previenen.   |
| **Secuencia**   | Panels top     | Agrupa nodos relacionados dentro de un contenedor visual. Permite organizar beats largos, configurar capas visuales y asociar pistas de audio a una secuencia narrativa.                                                                          |
| **Anotacion**   | Sticky note    | Nota visual pura para documentar intencion, tareas o contexto de diseno en el lienzo. No afecta a la ejecucion del flujo ni a los exports de dialogo.                                                                                            |

---

## Una estructura tipica

```
Sequence ("Tavern encounter")
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

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Un flujo con nodos hub/salto mostrando como multiples ramas de dialogo convergen en un solo camino
</div>

---

## Subflujos y ejecucion anidada

Los nodos de subflujo te permiten incrustar un flujo dentro de otro. Cuando la ejecucion llega a un nodo de subflujo, entra al nodo de Entrada del flujo referenciado y lo recorre. Cuando alcanza un nodo de Salida con modo **Retornar al llamador**, la ejecucion vuelve al flujo padre y continua desde el pin de salida correspondiente.

Cada nodo de Salida en el flujo referenciado crea un pin de salida separado en el nodo de subflujo, de modo que el flujo padre puede ramificarse segun la salida que tomo el subflujo. El depurador y el Story Player soportan navegacion completa entre flujos con pila de llamadas, asi que los subflujos anidados funcionan exactamente como esperarias.

---

## {accent}Story Player{/accent}

Haz clic en **Play** en la barra de herramientas para experimentar tu flujo como lo haria un jugador. El {accent}Story Player{/accent} es una vista cinematica a pantalla completa que avanza automaticamente a traves de nodos no interactivos (entrada, hubs, condiciones, instrucciones, saltos y subflujos) y se detiene solo en nodos de dialogo donde lees lineas o tomas decisiones.

- Los fondos de escena de escenas vinculadas se atenuan detras del dialogo
- Navega hacia atras en el historial con el boton de retroceso
- **Controles de teclado**: 1-9 para seleccionar respuestas, Espacio/Enter para continuar, Escape para salir
- **Reiniciar** el flujo en cualquier momento para reproducirlo desde el principio
- Los subflujos se siguen automaticamente -- el reproductor gestiona la pila de llamadas completa

Activa el {accent}Modo de analisis{/accent} para ver respuestas ocultas que no cumplieron sus condiciones, mostradas como opciones en gris con texto tachado. Esto te ayuda a verificar que las respuestas condicionales funcionan como se espera sin editar el flujo.

Esto no es una vista previa. Es la experiencia real de reproduccion, con evaluacion de variables y cambios de estado reales.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El Story Player mostrando un dialogo con opciones de respuesta y un fondo de escena
</div>

---

## {accent}Modo de depuracion{/accent}

La mayoria de herramientas narrativas te obligan a probar jugando el juego completo. Storyarn tiene un {accent}depurador{/accent} integrado -- avanza paso a paso por tu flujo, inspecciona cada variable en tiempo real, establece puntos de interrupcion y ve exactamente que camino se tomo y por que.

- **Paso** avanza un nodo a la vez
- **Paso atras** retrocede al estado anterior
- **Ejecutar** avanza automaticamente a velocidad configurable (200ms-3000ms por paso), deteniendose en puntos de interrupcion y decisiones del jugador
- **Reiniciar** reinicia desde el nodo de inicio
- **Iniciar desde cualquier nodo** -- elige cualquier nodo del flujo como punto de partida
- **Puntos de interrupcion** -- haz clic en el punto junto a cualquier nodo en la pestana Ruta para establecer un punto de interrupcion; la reproduccion automatica se detiene ahi
- **4 pestanas de informacion**: Consola (registro con marcas de tiempo y detalles de evaluacion de reglas), Variables (valores en vivo con filtrado, edicion en linea y seguimiento de cambios), Historial (cada cambio de variable con atribucion de origen) y Ruta (traza visual de ejecucion con controles de puntos de interrupcion)
- **Editar variables durante la sesion** -- haz clic en cualquier valor de variable en la pestana Variables para cambiarlo, luego continua la ejecucion para probar caminos alternativos

Cambia un valor de variable, reinicia y vuelve a ejecutar para probar caminos alternativos. Sin necesidad de motor de juego, sin ciclo de exportacion -- verifica tu logica justo donde la escribes.

Para una guia detallada, consulta la [guia del Modo de depuracion](/docs/narrative-design/debug-mode).
