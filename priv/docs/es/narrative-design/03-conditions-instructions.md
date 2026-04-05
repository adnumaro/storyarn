%{
title: "Condiciones e Instrucciones",
category_label: "Diseño Narrativo",
order: 3,
description: "Ramifica tu narrativa en base a condiciones y modifica el estado del juego con instrucciones."
}

---

Las condiciones leen tus variables para tomar decisiones. Las instrucciones escriben en tus variables para cambiar el estado del juego. Juntas, son la forma en que los flujos interactúan con los datos de tu mundo -- el puente entre la narrativa y la lógica del juego.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Un nodo de condición conectado a dos ramas de diálogo (salidas Verdadero y Falso)
</div>

---

## Nodos de Condición

Un nodo de condición evalúa reglas contra las variables de tu proyecto y enruta el flujo hacia diferentes salidas según el resultado.

El {accent}**Constructor de Condiciones (Condition Builder)**{/accent} es una interfaz completamente visual -- no se necesita código. Haz doble clic en un nodo de condición (o haz clic en el botón de ajustes en su barra de herramientas) para abrir el panel del constructor. Cada regla sigue tres pasos:

1. **Elegir una variable** -- selecciona una hoja y la variable requerida (ej., `mc.jaime.health`)
2. **Elegir un operador** -- los operadores disponibles dependen del tipo de la variable
3. **Establecer un valor** con el que comparar

---

## Operadores por tipo de variable

Los diferentes tipos de variables admiten diferentes operadores de comparación:

| Tipo de variable      | Operadores disponibles                                                                             |
| --------------------- | -------------------------------------------------------------------------------------------------- |
| **Número**            | es igual a, distinto de, mayor que, mayor o igual, menor que, menor o igual, no está asignado (is not set) |
| **Texto / T. Enriquecido**| es igual a, distinto de, contiene, empieza por, termina en, está vacío, no está asignado               |
| **Booleano**          | es verdadero, es falso, no está asignado                                                           |
| **Selección**         | es igual a, distinto de, no está asignado                                                          |
| **Selección múltiple**| contiene, no contiene, está vacío, no está asignado                                                |
| **Fecha**             | es igual a, antes, después, no está asignado                                                       |

---

## Grupos lógicos

Combina múltiples reglas con lógica {accent}Todos (AND){/accent} o {accent}Cualquiera (OR){/accent}:

> _"Cumplir **todas** las reglas: Jaime tiene más de 50 de vida AND posee la llave"_
> Ambas deben ser ciertas para que la condición se apruebe.

> _"Cumplir **cualquiera** de las reglas: El jugador es un Mago OR tiene el pergamino de hechizos"_
> Cualquiera de las dos es suficiente.

También puedes agrupar reglas en **bloques** para lógicas anidadas de base amplia y combinatoria más compleja visualizable por líneas e indentación general. El icono conmutador permite cambiar AND o OR generales para todos.

---

## Modos y tipos de Salidas Multiples

Estos nodos se rellenarán interiormente según ordenes si bifurcan binariamente a "verdadero y falso" en modo Booleano, o si habilitases un tipo expansivo mayor conocido por **modo Switch**.

- Con el Switch mode, tus bloques actitudinales generarán su puerto o pin expulsor privativo titulado por su etiqueta para desembocar la historia pluralmente según un descarte enumerativo, en el caso que se presentase "Ladrón" lo mandará al carril del Ladrón pero si la ficha de rol detecta el primero como verdadero (p.e. Bárbaro es tu variable primaria encendida) desechará el resto de carriles conectores de salida tras pasar Bárbaro.  

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Un nodo de condición de modo Switch habilitando listados separados bajo etiquetas diferenciadas.
</div>

---

## Nodos Lógicos y Multi-Instruccionales

Su par correlativo son los nodos de Instrucción los que influyen para asentar datos tras las decisiones de aquellos. 
Bajo un interfaz casi natural leeremos su instrucción general en el constructor, con formatos simples (e.g., *Suma `10` al estado `vida`* de un bloque específico que vincules a tu red de mundos variables).
Las multiplicaciones, set de verdadero/falso, sumatorios se compondrán por hileras en cascada acumulativas e impactarán una tras otra linealmente cuando el espectador en modo juego interactúe de forma ciega pasándolas para llegar a su posterior rama discursiva de respuesta o texto.  

| Operación   | Oración  Literal                        | Efecto                      | Tipo admitidos |
| ------------- | ------------------------------------- | --------------------------- | --------------- |
| **Set**       | Set `mc` . `oro` to `2`               | Inserta / Fija base numérico | Todos           |
| **Suma**      | Add `3` a `inventario`                | Adiciona sobre existentes    | Numéricos       |
| **Falso/Verd**| Fija a condicional flag para booleanos| Set/Interruptores (Toggle)   | Booleanos       |

*Conmutadores referenciales* logran transvasar datos iguales de una barra e interconectar o sustituior valores. Si el maná pasase a requerir valor máximo tu interruptor inserta un "lee max_mana de ficha y asientalo como base vida al regenerarte". 

## Diferencias referenciales embebidas (Inline instructions)
Los atajos condicionales descritos y embebidos en tus ventanas del jugador a pie de cada Diálogo limitarán enormemente el tedio de crear "condiciones" a cada respuesta minúscula, relegando el nodo grande como éste presente artículo al orden imperante para macro logísticas, agrupaciones serias complejas y rutas que afecten al macro mundo estructural por fuera de los meros matices intermedios en breves interacciones de parlamentos.  
