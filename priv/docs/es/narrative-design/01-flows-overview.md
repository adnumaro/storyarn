%{
title: "Visión General de los Flujos",
category_label: "Diseño Narrativo",
order: 1,
description: "Árboles de diálogo visuales y lógica narrativa ramificada."
}

---

Los Flujos (Flows) son el corazón de Storyarn -- **grafos de nodos visuales** donde construyes diálogos ramificados, lógica de juego y narrativas interactivas. Cada flujo es un lienzo de nodos interconectados que definen cómo se desarrolla una conversación o secuencia, desde un simple intercambio lineal hasta un árbol de misiones ramificado con docenas de vías.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El lienzo del editor de flujos mostrando un árbol de diálogo ramificado con nodos conectados
</div>

---

## El editor

El editor de flujos es un lienzo a pantalla completa. Creas nodos desde la barra de herramientas flotante, los conectas arrastrando entre los pines de salida y entrada, y editas el contenido en el panel lateral que aparece al seleccionar un nodo.

- **Desplázate (Pan)** arrastrando el fondo
- **Haz zoom** con la rueda del ratón
- **Selecciona** un nodo haciendo clic en él; doble clic para abrir su editor principal (el editor de guiones para diálogos, o los paneles de constructores para condiciones e instrucciones)
- **Selección múltiple** arrastrando y soltando un área o presionando Shift+clic
- **Duplica** nodos seleccionados con el menú contextual o el atajo de teclado
- **Deshacer/Rehacer** para operaciones en los nodos

Los nodos se conectan mediante **pines** -- pequeños círculos en los bordes de cada nodo. Arrastra desde un pin de salida hasta un pin de entrada para crear una conexión. Las conexiones definen el orden en el que se ejecutan los nodos durante la reproducción y la depuración.

---

## Tipos de nodos

Storyarn cuenta con **9 tipos de nodos**, cada uno cumpliendo un papel distinto en el grafo del flujo:

| Nodo            | Icono          | Propósito                                                                                                                                                                                                         |
| --------------- | -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Entrada (Entry)** | Play           | Dónde comienza el flujo. Creado automáticamente con el flujo, no se puede eliminar. Muestra qué otros flujos hacen referencia a este mediante nodos de subflujo.                                               |
| **Salida (Exit)**| Flecha a la derecha| Dónde termina el flujo. Soporta tres modos: **Terminal** (termina por completo), **Continuar a flujo** (se enlaza a otro flujo) y **Retornar al llamador** (regresa de un subflujo). Posee etiquetas de resultado y código de color. |
| **Diálogo**     | Globo de mensaje| Discurso del personaje con opciones opcionales para el jugador. El nodo más común -- consulta la [guía dedicada](/es/narrative-design/dialogue-nodes).                                                                   |
| **Condición**   | Rama de git    | Ramifica el flujo basándose en los valores de las variables. Constructor visual con lógica AND/OR -- sin necesidad de programar. Soporta modo booleano (salidas Verdadero/Falso) y modo switch (múltiples salidas personalizadas). |
| **Instrucción** | Rayo             | Modifica los valores de las variables cuando el flujo pasa a través. Soporta operaciones de Establecer, Sumar, Restar, Alternar, Limpiar y lógicas estrictamente booleanas.                                      |
| **Centro (Hub)**| Iniciar sesión   | Un punto de convergencia con nombre donde confluyen varios caminos. Tiene una etiqueta, un ID y un color.                                                                                                        |
| **Salto (Jump)**| Cerrar sesión  | Salta a un nodo Centro (Hub) dentro del mismo flujo. Selecciona el nodo hub destino en el selector de la barra de herramientas; un botón de mirilla lo localizará visualmente en tu lienzo en un instante.        |
| **Línea de título**| Claqueta      | Encabezamiento de la escena o delimitador al estilo clásico de guía de guiones de cine (Slug lines). Apuntan a un escenario como marco con opciones para set (INT/EXT) y día/noche/etc.                           |
| **Subflujo**    | Caja           | Incrusta otro flujo dentro de este. Los pines de salida de este nodo se generarán dinámicamente según sean los Exits (Salidas) reales de ese sub-flujo que estemos incrustando, previniendo bucles infinitos (referencias cruzadas ciegas).|

---

## Una estructura típica

```
Entrada
  -> Línea de título ("INT. TABERNA - NOCHE")
    -> Diálogo (Saludo del NPC)
      -> Condición (¿tiene el objeto de misión?)
        -> Verdadero: Diálogo (misión completada)
             -> Instrucción (dar recompensa, marcar misión como hecha)
               -> Salida (Terminal, resultado: "mision_completada")
        -> Falso: Diálogo (vuelve más tarde)
             -> Salida (Terminal, resultado: "mision_pendiente")
```

Los flujos pueden ser tan simples como una conversación lineal o tan complejos como todo un árbol de misiones masivo. Usa los nodos de **Centro (Hub)** y **Salto (Jump)** para unificar y fusionar opciones o rutas que se repiten sin la necesidad de copiar a mano los cuadros de diálogos idénticos por cada ruta. Utiliza nodos de **Subflujo** para crear flujos fragmentados y fáciles de reciclar o reusar en distintos mapas.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Un flujo mostrando los saltos y hubs centralizando caminos diferentes
</div>

---

## Subflujos y ejecución anidada

Los nodos de subflujo permiten insertar y emparejar flujos enteros unos dentro de otros. Si el hilo de lectura toca tu nodo, Storyarn se transporta interiormente hacia las dinámicas que posee el Entry o inicio de aquél flujo anidado en el subflujo. Hasta que no tope con un nodo Exit dictaminado como "Return to caller", no podrá regresar de vuelta al exterior para poder trazar el escape usando las flechas de salida correspondientes.
Storyarn soporta la inspección completa de dichas escalas entre proyectos desde ambas reproducciones en tiempo vivo: depuraciones, y reproducciones teatrales mediante la Pila de Llamadas "Call Stack". 

---

## {accent}El Story Player{/accent}

Presiona el botón **Jugar (Play)** para proyectar visualmente la secuencia y el flujo como lo experimentaría interactuando un jugador. El {accent}Story Player{/accent} o su panel actitudinal emite una interfaz similar a pantalla completa asimilando cinemáticas puras para visualizar los diálogos visuales de forma rápida auto-escalando el paso entre bloques sistémicos como cálculos matemáticos subyacentes. Pararía enteramente ante cada Diálogo esperando lecturas o intervención del usuario si se muestran opciones:

- Elementos de trasfondo se iluminan tras los protagonistas.
- Navegación trasera de lectura por retroceso (Back) como función clásica.
- Opción al atajo numeral clásico con espacios. (1-9 opciones respuestas).
- Capacidad re-inicializadora (Reset).
- Los anidamientos via Subflujo continuarán su despliegue natural del jugador en su interior. 

Habilítale ocasionalmente el **Analysis mode (Modo Analítico)**. Permite que respuestas ocultadas en la actualidad se dibujen en vista del programador narrativo, transparentadas para confirmar que su bloque sub-escrito actúa e impide las entradas de lectura tal como él requirió, desahogando y ahorrando su propio esfuerzo o pericia en testing continuados por errores. No requiere exportaciones externas al ser 100% puro funcionamiento interno, realimentando y afectando variables del proyecto según se vayan operando decisiones, y demostrando variables.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Aspecto que evoca inmersiones de cinemáticas directas
</div>

---

## {accent}Modo Depuración (Debug){/accent}

Muchos programas instan compilados, guardados, cierres pre-render y puestas forzadas de pruebas del juego maestro completo externamente acoplado con tu herramienta. Aquí, todo Storyarn expide tu propio depurador {accent}Debugger{/accent} interno y al unísono: pasa paso, evalúa si funcionó un trazo, pausa en interrupciones exactos y ve todos los factores modificables sin un ápice de salir o programar un compilador. 

Añadidos de Depuradoras:

- Posicionamiento "Avanza nodo" manual (Step)
- Marcha atrás.
- Control de ritmo visual milisegundos si lo hace Automático veloz
- Saltador exacto para originar pruebas concretas saltando a aquel bloque en particular del canvas.
- Tablas cuádruples explicativas (Console log rules con marcajes exactas e historiales para evaluar). Así detectaremos por dónde cruzan y por qué no evalúa bien cada variable fallida. Y listados visuales completos.

Ver y cambiar valores mutables dentro de la línea activa en test te ayudará a probar al vuelo las bifurcaciones y rutas lógicas que quieras inspeccionar saltándote el pre-procesar.
Guía extendida revisable bajo su rúbrica [Guía Debug Mode](/es/narrative-design/debug-mode).
