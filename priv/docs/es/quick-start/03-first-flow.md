%{
title: "Tu primer flujo",
category_label: "Inicio Rápido",
order: 3,
description: "Construye un diálogo ramificado que reacciona a las estadísticas del personaje."
}

---

Los Flujos (Flows) son donde tu narrativa cobra vida. En esta guía construirás un diálogo corto que se ramifica según la ficha de personaje de la guía anterior.

## Crea el flujo

Selecciona **Flujos** en la barra lateral y haz clic en **Nuevo Flujo**. Renómbralo a "Tavern Encounter".

El lienzo se abre con un nodo de {accent}Entrada (Entry){/accent} ya colocado — aquí es donde comienza la ejecución.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Un nuevo lienzo de flujo con el nodo de Entrada y el desplegable "Añadir Nodo" visible en la barra de herramientas superior derecha
</div>

## Añade un nodo de diálogo

Haz clic en el botón **Añadir Nodo** en la barra de herramientas superior derecha y selecciona **Diálogo**. Un nuevo nodo aparece en el lienzo.

Conecta la salida del nodo de Entrada a la entrada del nodo de Diálogo arrastrando de un puerto al otro.

Selecciona el nodo de Diálogo y escribe la línea del NPC directamente en el nodo (haz doble clic o pulsa `E` para empezar la edición en línea):

> _"You look like you've been through a lot, traveler."_

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El nodo de Entrada conectado a un nodo de Diálogo con la línea del NPC visible en el cuerpo del nodo
</div>

## Añade una condición

Añade un nodo de **Condición** desde la barra de herramientas y conéctalo después del nodo de Diálogo.

Selecciona el nodo de Condición y haz clic en el icono de ajustes en su barra flotante (o pulsa `E`) para abrir el panel del {accent}Constructor de Condiciones (Condition Builder){/accent}:

1. Selecciona la variable `mc.jaime.health`
2. Establece el operador a **Mayor que**
3. Introduce el valor `50`

El nodo de Condición ahora tiene dos salidas: **Verdadero (True)** y **Falso (False)**.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El panel del Constructor de Condiciones abierto a la derecha, con la variable mc.jaime.health seleccionada, operador "Mayor que" y valor 50
</div>

## Ramifica la conversación

Añade dos nodos de Diálogo más y conéctalos a las salidas de la Condición:

- Salida **Verdadero (True)** -- _"Ah, you seem in good shape! What can I get you?"_
- Salida **Falso (False)** -- _"You're barely standing! Sit down, I'll bring a healing potion."_

Añade un nodo de {accent}Salida (Exit){/accent} después de cada diálogo para terminar el flujo.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El flujo completo: Entrada > Diálogo > Condición > dos Diálogos ramificados > dos nodos de Salida
</div>

## Prueba con el depurador

Haz clic en el botón **Depurar** en la barra de herramientas superior derecha (o pulsa `Ctrl+Shift+D`) para abrir el panel de depuración en la parte inferior del lienzo.

El panel de depuración tiene tres pestañas:

- **Consola** -- muestra la salida de ejecución a medida que ocurre
- **Variables** -- muestra todas las variables del proyecto y sus valores actuales
- **Historial** -- un registro paso a paso de los nodos visitados

Haz clic en **Paso** (o pulsa `F10`) para avanzar nodo por nodo. El panel de variables muestra `mc.jaime.health = 100`. Como 100 > 50, el flujo toma el camino Verdadero.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El panel de depuración abierto en la parte inferior mostrando la pestaña de Consola con la salida de ejecución, y el camino Verdadero resaltado en el lienzo
</div>

Prueba a cambiar el valor de Health a `30` en la ficha de personaje y ejecutar el depurador de nuevo — el flujo tomará el camino Falso en su lugar.

## Tipos de nodos disponibles

El editor de flujos admite estos tipos de nodos, todos disponibles desde el desplegable **Añadir Nodo**:

| Nodo            | Propósito                                                                          |
| --------------- | ---------------------------------------------------------------------------------- |
| **Entrada (Entry)**      | Punto de inicio del flujo                                                |
| **Salida (Exit)**        | Termina el flujo (terminal, continuar a otro flujo, o volver al llamador)|
| **Diálogo (Dialogue)**   | Discurso de personaje con respuestas opcionales, locutor, audio y acotaciones |
| **Condición (Condition)**| Ramifica según condiciones de variables (modo booleano o switch)         |
| **Instrucción (Instruction)** | Modifica valores de variables (asignaciones)                        |
| **Hub**         | Punto de convergencia con nombre al que los nodos de Salto pueden apuntar          |
| **Salto (Jump)**| Salta la ejecución a un nodo Hub                                                   |
| **Encabezado de escena (Slug Line)** | Encabezado de escena estilo guion (INT/EXT, ubicación, momento del día) |
| **Subflujo (Subflow)**   | Incrusta otro flujo como una subrutina reutilizable                     |
