%{
title: "Tu primer flujo",
category_label: "Inicio Rápido",
order: 3,
description: "Construye un diálogo ramificado que reacciona a las estadísticas del personaje."
}

---

Los Flujos (Flows) son donde tu narrativa cobra vida. En esta guía construirás un diálogo corto que se ramifica según la ficha de personaje de la guía anterior, y después previsualizarás y exportarás el resultado.

## Crea el flujo

Selecciona **Flujos** en la barra lateral y haz clic en **Nuevo Flujo**. Renómbralo a "Tavern Encounter".

El lienzo se abre con un nodo de {accent}Entrada (Entry){/accent} ya colocado — aquí es donde comienza la ejecución.

<img src="/images/docs/flows-editor-current.png" alt="El lienzo del editor de flujos con un grafo de diálogo completo y la barra de nodos" loading="lazy">

## Añade un nodo de diálogo

Haz clic en el botón **Añadir Nodo** en la barra de herramientas superior derecha y selecciona **Diálogo**. Un nuevo nodo aparece en el lienzo.

Conecta la salida del nodo de Entrada a la entrada del nodo de Diálogo arrastrando de un puerto al otro.

Selecciona el nodo de Diálogo y escribe la línea del NPC directamente en el nodo (haz doble clic o pulsa `E` para empezar la edición en línea):

> _"You look like you've been through a lot, traveler."_

<img src="/images/docs/flows-editor-current.png" alt="El editor de flujos mostrando nodos de entrada, diálogo, condición y salida conectados" loading="lazy">

## Añade una condición

Añade un nodo de **Condición** desde la barra de herramientas y conéctalo después del nodo de Diálogo.

Selecciona el nodo de Condición y haz clic en el icono de ajustes en su barra flotante (o pulsa `E`) para abrir el panel del {accent}Constructor de Condiciones (Condition Builder){/accent}:

1. Selecciona la variable `mc.jaime.health`
2. Establece el operador a **Mayor que**
3. Introduce el valor `50`

El nodo de Condición ahora tiene dos salidas: **Verdadero (True)** y **Falso (False)**.

<img src="/images/docs/flows-condition-builder.png" alt="El editor de flujos mostrando un nodo de Condición con ramas Verdadero y Falso" loading="lazy">

## Ramifica la conversación

Añade dos nodos de Diálogo más y conéctalos a las salidas de la Condición:

- Salida **Verdadero (True)** -- _"Ah, you seem in good shape! What can I get you?"_
- Salida **Falso (False)** -- _"You're barely standing! Sit down, I'll bring a healing potion."_

Añade un nodo de {accent}Salida (Exit){/accent} después de cada diálogo para terminar el flujo.

<img src="/images/docs/flows-editor-current.png" alt="Un flujo ramificado completo con nodos de diálogo y lógica conectados" loading="lazy">

## Prueba con el depurador

Haz clic en el botón **Depurar** en la barra de herramientas superior derecha (o pulsa `Ctrl+Shift+D`) para abrir el panel de depuración en la parte inferior del lienzo.

El panel de depuración tiene tres pestañas:

- **Consola** -- muestra la salida de ejecución a medida que ocurre
- **Variables** -- muestra todas las variables del proyecto y sus valores actuales
- **Historial** -- un registro paso a paso de los nodos visitados

Haz clic en **Paso** (o pulsa `F10`) para avanzar nodo por nodo. El panel de variables muestra `mc.jaime.health = 100`. Como 100 > 50, el flujo toma el camino Verdadero.

<img src="/images/docs/flows-debug-current.png" alt="El panel de depuración abierto en la parte inferior mostrando la pestaña de Consola y la salida de ejecución" loading="lazy">

Prueba a cambiar el valor de Health a `30` en la ficha de personaje y ejecutar el depurador de nuevo — el flujo tomará el camino Falso en su lugar.

## Previsualiza con el Story Player

El Modo Depuración explica cómo se ejecuta el flujo. El {accent}Story Player{/accent} muestra cómo se siente para un jugador.

Haz clic en **Play** en la barra de herramientas del flujo para abrir el Story Player desde el nodo de Entrada. Avanza por el diálogo y confirma que:

- La primera línea del NPC aparece antes de que se evalúe la condición.
- Con `mc.jaime.health = 100`, el jugador llega a la respuesta saludable.
- Después de cambiar Health a `30`, el jugador llega a la respuesta de la poción curativa.

Usa Story Player cuando quieras revisar ritmo, texto de hablante y elecciones. Usa Modo Depuración cuando necesites inspeccionar variables, condiciones e historial de ejecución.

<img src="/images/docs/flows-player-current.png" alt="El Story Player mostrando la línea de diálogo de la taberna y la rama elegida por el valor actual de Health" loading="lazy">

## Exporta el proyecto

Cuando el flujo funcione, abre **Exportar** desde la barra lateral del proyecto. Para una primera exportación:

1. Elige **Yarn Spinner**, **Ink**, **Unity Dialogue System**, **Godot Dialogic**, **Unreal Engine** o **articy:draft** según el runtime o engine que quieras probar.
2. Mantén **Fichas** y **Flujos** seleccionados para que el diálogo exportado incluya los datos de variable usados por la condición.
3. Activa **Validar antes de exportar** para detectar nodos de entrada faltantes, nodos inalcanzables, referencias rotas y traducciones faltantes.
4. Haz clic en **Descargar**.

Para este tutorial, exporta un formato de engine que te interese. El objetivo es comprobar cómo el mismo flujo sale de Storyarn para integrarse en runtime.

## Checklist final

Has terminado el Inicio Rápido cuando puedas confirmar todo esto:

- Has creado un espacio de trabajo y un proyecto.
- Has creado la ficha `mc.jaime`.
- Has creado la variable `mc.jaime.health`.
- Has usado esa variable en un nodo de Condición.
- Has probado ambas ramas en Modo Depuración.
- Has previsualizado el flujo en Story Player.
- Has exportado el proyecto.

## Tipos de nodos disponibles

El editor de flujos admite estos tipos de nodos, todos disponibles desde el desplegable **Añadir Nodo**:

| Nodo                          | Propósito                                                                     |
| ----------------------------- | ----------------------------------------------------------------------------- |
| **Entrada (Entry)**           | Punto de inicio del flujo                                                     |
| **Salida (Exit)**             | Termina el flujo (terminal, continuar a otro flujo, o volver al llamador)     |
| **Diálogo (Dialogue)**        | Discurso de personaje con respuestas opcionales, locutor, audio y acotaciones |
| **Condición (Condition)**     | Ramifica según condiciones de variables (modo booleano o switch)              |
| **Instrucción (Instruction)** | Modifica valores de variables (asignaciones)                                  |
| **Hub**                       | Punto de convergencia con nombre al que los nodos de Salto pueden apuntar     |
| **Salto (Jump)**              | Salta la ejecución a un nodo Hub                                              |
| **Subflujo (Subflow)**        | Incrusta otro flujo como una subrutina reutilizable                           |
| **Secuencia (Sequence)**      | Agrupa nodos relacionados y permite configurar capas visuales y audio         |
| **Anotación (Annotation)**    | Nota visual para documentar el lienzo sin afectar a la ejecución              |
