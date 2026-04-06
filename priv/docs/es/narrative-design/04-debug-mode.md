%{
title: "Modo de depuracion",
category_label: "Diseno Narrativo",
order: 4,
description: "Prueba y verifica tus flujos con el depurador integrado."
}

---

El editor de flujos incluye un {accent}depurador{/accent} integrado que te permite simular como se ejecuta un flujo -- paso a paso, con visibilidad completa de los valores de las variables, los caminos de decision y el historial de ejecucion. Esto es algo que ninguna otra herramienta de diseno narrativo ofrece: puedes verificar toda tu logica de ramificacion sin salir del editor, sin exportar y sin un motor de juego.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El editor de flujos con el panel de depuracion abierto en la parte inferior, mostrando la pestana de consola con registros de ejecucion
</div>

---

## Iniciar una sesion de depuracion

1. Abre un flujo en el editor
2. Haz clic en el boton **Debug** en la barra de herramientas
3. El panel de depuracion aparece anclado en la parte inferior del lienzo

El depurador se inicializa en el nodo de **Entrada** del flujo, cargando todas las variables del proyecto con sus valores actuales desde las fichas.

---

## Controles

La barra de controles se encuentra en la parte superior del panel de depuracion con las siguientes acciones:

| Boton        | Accion                      | Que hace                                                                                                               |
| ------------ | --------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Play / Pausa | **Reproduccion automatica** | Avanza el flujo automaticamente a la velocidad configurada, pausando en decisiones de dialogo y puntos de interrupcion |
| Paso         | **Paso**                    | Avanza exactamente un nodo hacia adelante                                                                              |
| Paso atras   | **Paso atras**              | Retrocede al estado anterior (deshace el ultimo paso)                                                                  |
| Reiniciar    | **Reiniciar**               | Reinicia la sesion desde el nodo de inicio, restableciendo todas las variables a sus valores iniciales                 |
| Detener      | **Detener**                 | Finaliza la sesion de depuracion y cierra el panel                                                                     |

Cuando el depurador llega a un **nodo de dialogo con respuestas**, se detiene y presenta las opciones disponibles como botones en la consola. Las respuestas cuyas condiciones no se cumplen aparecen en gris y deshabilitadas. Haz clic en una respuesta valida para continuar la ejecucion por ese camino.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  La barra de controles de depuracion mostrando los botones Paso, Paso atras, Reiniciar, Detener con indicador de estado y contador de pasos
</div>

---

## Iniciar desde cualquier nodo

No estas limitado a iniciar desde el nodo de Entrada. El desplegable **Inicio** en la barra de controles lista todos los nodos del flujo. Selecciona un nodo diferente para comenzar a depurar desde ese punto -- la sesion se reinicia y comienza en el nodo seleccionado.

Esto es invaluable para probar una rama especifica en lo profundo de un flujo complejo sin tener que avanzar por docenas de nodos para llegar ahi.

---

## Control de velocidad

El **control de velocidad** determina la rapidez con que avanza la reproduccion automatica, con un rango de **200ms** (5 pasos por segundo, rapido) a **3000ms** (un paso cada 3 segundos, lento). La velocidad actual se muestra junto al control.

Usa una velocidad rapida para recorrer rapidamente un flujo largo, o una velocidad lenta para observar cada paso con detenimiento. La reproduccion automatica pausa automaticamente en puntos de interrupcion y en nodos de dialogo que requieren una respuesta.

---

## Resaltado del nodo activo

El nodo actualmente activo se **resalta en el lienzo** en tiempo real. Toda la ruta de ejecucion tambien se traza visualmente, para que puedas ver el camino completo tomado a traves del flujo. La conexion activa entre los dos ultimos nodos tambien se resalta.

El lienzo se centra automaticamente en el nodo activo mientras avanzas por el flujo, para que nunca pierdas de vista donde estas.

---

## Las cuatro pestanas

El panel de depuracion tiene cuatro pestanas de informacion, cada una ofreciendo una vista diferente del estado de ejecucion.

### Consola

Un registro con marcas de tiempo de todo lo que ocurre durante la ejecucion. Cada entrada muestra:

- **Marca de tiempo** en segundos (p. ej., `0.012s`)
- **Icono de nivel** -- informacion (azul), advertencia (amarillo) o error (rojo)
- **Etiqueta del nodo** -- que nodo produjo la entrada
- **Mensaje** -- que ocurrio (condicion evaluada, instruccion ejecutada, error encontrado)

Para evaluaciones de condiciones, la consola muestra **detalles por regla**: que variable se comprobo, cual era el valor esperado, cual era el valor real y si la regla paso o fallo. Es la forma mas rapida de entender por que una condicion tomo una rama especifica.

Cuando el depurador esta esperando una respuesta, las opciones disponibles aparecen en la parte inferior de la pestana de consola como botones clicables.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  La pestana de Consola mostrando entradas con marcas de tiempo con detalles de reglas de condicion (variable, esperado, real, paso/fallo)
</div>

### Variables

Una tabla en vivo de **cada variable** del proyecto, con cinco columnas:

| Columna      | Muestra                                                                     |
| ------------ | --------------------------------------------------------------------------- |
| **Variable** | La referencia completa (shortcut de ficha + nombre de variable)             |
| **Tipo**     | El tipo de bloque de la variable (numero, booleano, texto, seleccion, etc.) |
| **Inicial**  | El valor cuando se inicio la sesion de depuracion                           |
| **Anterior** | El valor antes del cambio mas reciente                                      |
| **Actual**   | El valor en vivo en este momento                                            |

Las variables modificadas se resaltan -- los valores modificados por instrucciones aparecen en **amarillo**, y los valores que sobreescribes manualmente aparecen en **azul**. Un indicador de diamante marca las variables cuyo valor actual difiere de su valor inicial.

La pestana de Variables incluye dos herramientas de filtrado:

- **Filtro de busqueda** -- escribe para filtrar variables por nombre
- **Solo modificadas** -- muestra solo las variables que han sido modificadas durante la sesion

Los anchos de columna son **redimensionables** -- arrastra los bordes de las columnas para ajustarlos.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  La pestana de Variables mostrando una tabla con columnas Inicial, Anterior y Actual, con valores modificados resaltados
</div>

### Historial

Un registro cronologico de **cada cambio de variable** que ocurrio durante la sesion. Cada entrada muestra:

- **Marca de tiempo** -- cuando ocurrio el cambio
- **Nodo** -- que nodo causo el cambio (o "(sobreescritura del usuario)" si lo editaste manualmente)
- **Cambio** -- la referencia de la variable, valor anterior, flecha y valor nuevo
- **Origen** -- "instr" (cambiado por un nodo de instruccion) o "user" (cambiado por edicion manual)

Esto es util para rastrear exactamente cuando y donde una variable se establecio a un valor inesperado.

### Ruta

Una traza visual de **cada nodo visitado**, en orden de ejecucion. Cada entrada muestra:

- **Numero de paso** -- conteo secuencial
- **Punto de interrupcion** -- haz clic para alternar un punto de interrupcion en este nodo
- **Icono de tipo de nodo** -- el icono del tipo de nodo
- **Etiqueta del nodo** -- el contenido de texto del nodo (truncado)
- **Resultado** -- lo que produjo el nodo (resultado de condicion, efecto de instruccion, etc.)

El nodo actual se resalta en la ruta. Al depurar entre subflujos, aparecen **separadores de flujo** en la ruta mostrando marcadores "Entrando en subflujo" y "Retornando al padre", con entradas indentadas para mostrar la profundidad de la pila de llamadas.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  La pestana de Ruta mostrando la traza de ejecucion con numeros de paso, puntos de interrupcion y un separador de subflujo
</div>

---

## {accent}Puntos de interrupcion{/accent}

Haz clic en el **punto** junto a cualquier nodo en la pestana Ruta para establecer un {accent}punto de interrupcion{/accent}. Los puntos de interrupcion activos aparecen como circulos rojos solidos; los no establecidos son circulos vacios que se vuelven rojos al pasar el cursor.

Cuando la reproduccion automatica esta en marcha y la ejecucion llega a un nodo con un punto de interrupcion, se **detiene automaticamente** y la reproduccion automatica se pausa. Esto te permite recorrer grandes secciones de un flujo a velocidad y detenerte precisamente donde necesitas inspeccionar.

Los puntos de interrupcion tambien se indican visualmente en los nodos del lienzo, para que puedas ver de un vistazo que nodos causaran una pausa.

---

## {accent}Editar variables durante la sesion{/accent}

Haz clic en el **valor actual** de cualquier variable en la pestana Variables para editarlo en linea. El tipo de campo se adapta a la variable:

- Las variables de **Numero** tienen un campo numerico
- Las variables **Booleanas** tienen un desplegable verdadero/falso
- Las de **Texto** y otros tipos tienen un campo de texto

Pulsa Enter para confirmar o Escape para cancelar. El cambio se registra en la pestana Historial con una etiqueta de origen "user", y el valor actual de la variable se vuelve **azul** para indicar una sobreescritura manual.

Despues de cambiar una variable, puedes **reiniciar** y volver a ejecutar el flujo para ver como se comporta con el nuevo valor, o simplemente continuar avanzando desde la posicion actual. Es la forma mas rapida de probar escenarios "que pasaria si" sin modificar los datos reales de tus fichas.

---

## Depuracion entre flujos

Cuando el depurador entra en un **nodo de subflujo**, navega automaticamente al flujo referenciado y continua la ejecucion dentro de el. Aparece una **barra de migas de pan** sobre los controles mostrando la pila de llamadas:

> _Flujo padre > Subflujo > Actual_

El depurador mantiene el estado completo entre flujos -- variables, historial de ejecucion, registro de consola y puntos de interrupcion se mantienen. Cuando un subflujo llega a un nodo de Salida con modo "Retornar al llamador", el depurador navega de vuelta al flujo padre y continua desde el pin de salida del nodo de subflujo.

Reiniciar siempre regresa al **flujo raiz** -- el flujo donde se inicio originalmente la sesion de depuracion.

---

## Proteccion contra bucles infinitos

El depurador incluye un **limite de pasos** (mostrado en el banner de advertencia) para proteger contra bucles infinitos. Si la ejecucion supera el limite, la reproduccion automatica se detiene y aparece una advertencia con la opcion de **Continuar (+1000 pasos)**. Esto extiende el limite y te permite seguir depurando si el bucle es intencional o si el flujo simplemente tiene muchos pasos.

---

## Redimensionar el panel

El panel de depuracion se puede **redimensionar verticalmente** arrastrando el asa en el borde superior. Arrastralo hacia arriba para ver mas informacion, o hacia abajo para ver mas del lienzo. El panel mantiene su altura hasta que lo redimensiones de nuevo.

---

## Consejos para una depuracion efectiva

- **Usa puntos de interrupcion** para saltar secciones que ya funcionan correctamente y detenerte en la logica que quieres verificar
- **Filtra por variables modificadas** para ver rapidamente que cambiaron las instrucciones
- **Edita variables** para probar casos limite (salud en cero, inventario vacio, valores maximos)
- **Inicia desde un nodo especifico** para ir directamente a la seccion en la que estas trabajando
- **Revisa la Consola** para ver los detalles de las reglas de condicion cuando una rama toma un camino inesperado -- muestra exactamente que reglas pasaron y fallaron, con valores reales vs. esperados
- **Usa Paso atras** cuando te pierdas algo -- puedes retroceder y reexaminar sin reiniciar toda la sesion
