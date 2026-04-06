%{
title: "Condiciones e Instrucciones",
category_label: "Diseno Narrativo",
order: 3,
description: "Ramifica tu narrativa con condiciones y modifica el estado del juego con instrucciones."
}

---

Las Condiciones (Conditions) leen tus variables para tomar decisiones. Las Instrucciones (Instructions) escriben en tus variables para cambiar el estado del juego. Juntas, son la forma en que los flujos interactuan con los datos de tu mundo -- el puente entre la narrativa y la logica del juego.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Un nodo de condicion conectado a dos ramas de dialogo (salidas Verdadero y Falso)
</div>

---

## Nodos de condicion

Un nodo de condicion evalua reglas contra las variables de tu proyecto y dirige el flujo a diferentes salidas segun el resultado.

El {accent}**Constructor de Condiciones**{/accent} es una interfaz completamente visual -- no necesitas codigo. Haz doble clic en un nodo de condicion (o haz clic en el boton de configuracion en su barra de herramientas) para abrir el panel del constructor. Cada regla sigue tres pasos:

1. **Elige una variable** -- selecciona una hoja y variable (p. ej., `mc.jaime.health`)
2. **Elige un operador** -- los operadores disponibles dependen del tipo de la variable
3. **Establece un valor** de comparacion

---

## Operadores por tipo de variable

Diferentes tipos de variables soportan diferentes operadores de comparacion:

| Tipo de variable          | Operadores disponibles                                                                                        |
| ------------------------- | ------------------------------------------------------------------------------------------------------------- |
| **Numero**                | igual, no igual, mayor que, mayor o igual que, menor que, menor o igual que, no esta establecido               |
| **Texto / Texto enriquecido** | igual, no igual, contiene, empieza con, termina con, esta vacio, no esta establecido                      |
| **Booleano**              | es verdadero, es falso, no esta establecido                                                                    |
| **Seleccion**             | igual, no igual, no esta establecido                                                                           |
| **Seleccion multiple**    | contiene, no contiene, esta vacio, no esta establecido                                                         |
| **Fecha**                 | igual, antes de, despues de, no esta establecido                                                               |

---

## Grupos logicos

Combina multiples reglas con logica **Todas (AND)** o **Alguna (OR)**:

> _"Cumplir **todas** las reglas: Jaime tiene mas de 50 de salud Y tiene la llave"_
> Ambas deben ser verdaderas para que la condicion se cumpla.

> _"Cumplir **alguna** de las reglas: El jugador es un Mago O tiene el pergamino de hechizo"_
> Basta con que una se cumpla.

Tambien puedes agrupar reglas en **bloques** para logica anidada mas compleja. Selecciona varias reglas y haz clic en **Agrupar seleccion** para combinarlas en un subgrupo con su propio selector AND/OR.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El panel del Constructor de Condiciones mostrando reglas agrupadas con selectores de logica AND/OR
</div>

---

## Modos de salida

Los nodos de condicion soportan dos modos de salida, que se alternan desde la barra de herramientas:

### Modo booleano (predeterminado)

La condicion se evalua como **Verdadero** o **Falso**. El nodo tiene dos pines de salida y el flujo sigue el que corresponda. Es la configuracion mas comun para ramificaciones simples de si/no.

### Modo switch

Cada regla (o bloque de reglas) crea su propio pin de salida con etiqueta. El flujo sigue la **primera salida que coincida**. Esto es util para ramificaciones multiples -- como comprobar la clase de un personaje con salidas separadas para Guerrero, Mago y Picaro.

En modo switch, cada bloque de condicion tiene un campo de **etiqueta** que se convierte en el nombre del pin de salida en el lienzo. La barra de herramientas muestra un icono de division cuando el modo switch esta activo.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Un nodo de condicion en modo switch con tres pines de salida etiquetados (Guerrero, Mago, Picaro)
</div>

---

## Nodos de instruccion

Los nodos de instruccion **modifican variables** cuando el flujo pasa a traves de ellos. Haz doble clic en un nodo (o haz clic en el boton de configuracion) para abrir el {accent}Constructor de Instrucciones{/accent}.

Cada instruccion es una **frase en lenguaje natural** que se lee como un comando:

| Operacion           | Frase                                                | Efecto                        | Tipos de variable   |
| ------------------- | ---------------------------------------------------- | ----------------------------- | ------------------- |
| **Establecer**      | Establecer `mc.jaime` . `health` a `75`              | Asigna un valor               | Todos los tipos     |
| **Sumar**           | Sumar `100` a `mc.jaime` . `gold`                    | Suma al valor actual          | Numero              |
| **Restar**          | Restar `25` de `mc.jaime` . `health`                 | Resta del valor actual        | Numero              |
| **Establecer true** | Establecer `quest.door` . `unlocked` a verdadero     | Pone el booleano a verdadero  | Booleano            |
| **Establecer false**| Establecer `quest.door` . `unlocked` a falso         | Pone el booleano a falso      | Booleano            |
| **Alternar**        | Alternar `quest.door` . `unlocked`                   | Invierte el valor booleano    | Booleano            |
| **Limpiar**         | Limpiar `mc.jaime` . `notes`                         | Elimina el valor              | Texto, Texto enriquecido |

Un solo nodo de instruccion puede contener **multiples asignaciones** que se ejecutan en orden. Haz clic en **Agregar asignacion** para crear una nueva fila.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El Constructor de Instrucciones con tres asignaciones: Establecer salud, Sumar oro, Alternar flag de mision
</div>

---

## Referencias a variables en instrucciones

Por defecto, los valores de las instrucciones son **literales** -- escribes un numero o texto directamente. Pero puedes cambiar cualquier campo de valor a una **referencia de variable**, que lee el valor actual de otra variable en tiempo de ejecucion.

> _Ejemplo: Establecer `mc.jaime` . `health` a `mc.jaime` . `max_health`_
> Esto copia el valor de max_health en health.

Haz clic en el icono de alternancia junto al campo de valor para cambiar entre modo de valor literal y modo de referencia de variable.

---

## Cuando usar instrucciones en linea vs. nodos dedicados

Las respuestas de dialogo soportan condiciones e instrucciones en linea para casos simples (consulta la [guia de Nodos de Dialogo](/es/narrative-design/dialogue-nodes)). Usa nodos de Condicion e Instruccion dedicados cuando:

- La misma condicion es comprobada por **multiples caminos** en el flujo
- La logica involucra **multiples reglas** con agrupacion AND/OR compleja
- Varias variables necesitan **cambiar juntas** como un unico paso logico
- Quieres que la logica sea **visible en el lienzo** para facilitar la depuracion y la colaboracion
- Necesitas **modo switch** para ramificacion multiple

Como regla general: si la logica pertenece a una respuesta especifica, ponla en linea. Si pertenece a la estructura del flujo, usa un nodo.
