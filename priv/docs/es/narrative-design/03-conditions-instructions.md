%{
title: "Condiciones e Instrucciones",
category_label: "Diseño Narrativo",
order: 3,
description: "Ramifica tu narrativa con condiciones y modifica el estado del juego con instrucciones."
}

---

Las Condiciones (Conditions) leen tus variables para tomar decisiones. Las Instrucciones (Instructions) escriben en tus variables para cambiar el estado del juego. Juntas, son la forma en que los flujos interactúan con los datos de tu mundo: el puente entre la narrativa y la lógica del juego.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Un nodo de condición conectado a dos ramas de diálogo (salidas Verdadero y Falso)
</div>

---

## Nodos de condición

Un nodo de condición evalúa reglas contra las variables de tu proyecto y dirige el flujo a diferentes salidas según el resultado.

El {accent}**Constructor de Condiciones**{/accent} es una interfaz completamente visual: no necesitas código. Haz doble clic en un nodo de condición (o haz clic en el botón de configuración en su barra de herramientas) para abrir el panel del constructor. Cada regla sigue tres pasos:

1. **Elige una variable** -- selecciona una ficha y variable (p. ej., `mc.jaime.health`)
2. **Elige un operador** -- los operadores disponibles dependen del tipo de variable
3. **Establece un valor** de comparación

---

## Operadores por tipo de variable

Diferentes tipos de variables soportan diferentes operadores de comparación:

| Tipo de variable        | Operadores disponibles                                                                                           |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------- |
| **Número**              | igual, no igual, mayor que, mayor o igual que, menor que, menor o igual que, no está establecido                 |
| **Texto / enriquecido** | igual, no igual, contiene, empieza con, termina con, está vacío, no está establecido                             |
| **Booleano**            | es verdadero, es falso, no está establecido                                                                      |
| **Selección**           | igual, no igual, no está establecido                                                                             |
| **Selección múltiple**  | contiene, no contiene, está vacío, no está establecido                                                           |
| **Fecha**               | igual, antes de, después de, no está establecido                                                                 |

---

## Grupos lógicos

Combina múltiples reglas con lógica **Todas (AND)** o **Alguna (OR)**:

> _"Cumplir **todas** las reglas: Jaime tiene más de 50 de salud Y tiene la llave"_
> Ambas deben ser verdaderas para que la condición se cumpla.

> _"Cumplir **alguna** de las reglas: el jugador es un Mago O tiene el pergamino de hechizo"_
> Basta con que una se cumpla.

También puedes agrupar reglas en **bloques** para lógica anidada más compleja. Selecciona varias reglas y haz clic en **Agrupar selección** para combinarlas en un subgrupo con su propio selector AND/OR.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El panel del Constructor de Condiciones mostrando reglas agrupadas con selectores de lógica AND/OR
</div>

---

## Modos de salida

Los nodos de condición soportan dos modos de salida, que se alternan desde la barra de herramientas:

### Modo booleano (predeterminado)

La condición se evalúa como **Verdadero** o **Falso**. El nodo tiene dos pines de salida y el flujo sigue el que corresponda. Es la configuración más común para ramificaciones simples de sí/no.

### Modo switch

Cada regla (o bloque de reglas) crea su propio pin de salida con etiqueta. El flujo sigue la **primera salida que coincida**. Esto es útil para ramificaciones múltiples, como comprobar la clase de un personaje con salidas separadas para Guerrero, Mago y Pícaro.

En modo switch, cada bloque de condición tiene un campo de **etiqueta** que se convierte en el nombre del pin de salida en el lienzo. La barra de herramientas muestra un icono de división cuando el modo switch está activo.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Un nodo de condición en modo switch con tres pines de salida etiquetados (Guerrero, Mago, Pícaro)
</div>

---

## Nodos de instrucción

Los nodos de instrucción **modifican variables** cuando el flujo pasa a través de ellos. Haz doble clic en un nodo (o haz clic en el botón de configuración) para abrir el {accent}Constructor de Instrucciones{/accent}.

Cada instrucción es una **frase en lenguaje natural** que se lee como un comando:

| Operación         | Frase                                   | Efecto                 | Tipos de variable |
| ----------------- | --------------------------------------- | ---------------------- | ----------------- |
| **Establecer**    | Establecer `mc.jaime` . `health` a `75` | Asigna un valor        | Todos los tipos   |
| **Sumar**         | Sumar `100` a `mc.jaime` . `gold`       | Suma al valor actual   | Número            |
| **Restar**        | Restar `25` de `mc.jaime` . `health`    | Resta del valor actual | Número            |
| **Establecer sí** | Establecer `quest.door` . `unlocked` a true | Pone el booleano a true | Booleano       |
| **Establecer no** | Establecer `quest.door` . `unlocked` a false | Pone el booleano a false | Booleano     |
| **Alternar**      | Alternar `quest.door` . `unlocked`      | Invierte el booleano   | Booleano          |
| **Limpiar**       | Limpiar `mc.jaime` . `notes`            | Elimina el valor       | Texto, enriquecido |

Un solo nodo de instrucción puede contener **múltiples asignaciones** que se ejecutan en orden. Haz clic en **Agregar asignación** para crear una nueva fila.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El Constructor de Instrucciones con tres asignaciones: establecer salud, sumar oro y alternar un flag de misión
</div>

---

## Referencias a variables en instrucciones

Por defecto, los valores de las instrucciones son **literales**: escribes un número o texto directamente. Pero puedes cambiar cualquier campo de valor a una **referencia de variable**, que lee el valor actual de otra variable en tiempo de ejecución.

> _Ejemplo: establecer `mc.jaime` . `health` a `mc.jaime` . `max_health`_
> Esto copia el valor de max_health en health.

Haz clic en el icono de alternancia junto al campo de valor para cambiar entre modo de valor literal y modo de referencia de variable.

---

## Cuándo usar instrucciones en línea vs. nodos dedicados

Las respuestas de diálogo soportan condiciones e instrucciones en línea para casos simples (consulta la [guía de Nodos de Diálogo](/docs/narrative-design/dialogue-nodes)). Usa nodos de Condición e Instrucción dedicados cuando:

- La misma condición es comprobada por **múltiples caminos** en el flujo
- La lógica involucra **múltiples reglas** con agrupación AND/OR compleja
- Varias variables deben **cambiar juntas** como un solo paso lógico
- Quieres que la lógica sea **visible en el lienzo** para depuración y colaboración
- Necesitas **modo switch** para ramificaciones múltiples

Como regla práctica: si la lógica pertenece a una respuesta concreta, ponla en línea. Si pertenece a la estructura del flujo, usa un nodo.
