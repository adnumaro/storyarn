%{
title: "Salud del flujo",
category_label: "Diseño Narrativo",
order: 5,
description: "Comprobaciones deterministas sobre el grafo de un flujo y el contenido de sus nodos, en el editor y en todo el proyecto."
}

---

La salud del flujo revisa dos cosas a la vez: la **forma del grafo** -- entradas ausentes, ramas inalcanzables, callejones sin salida, pines rotos, destinos que ya no existen -- y el **contenido de cada nodo** -- líneas de diálogo vacías, condiciones a medias, personajes sin asignar, referencias de variable obsoletas.

Ambas mitades comparten un único catálogo de comprobaciones, así que el editor de flujos y el panel de Flujos nunca pueden describir el mismo problema de forma distinta, ni ocultar uno que el otro sí muestra.

Cada comprobación es determinista: el mismo flujo produce siempre los mismos hallazgos, calculados solo a partir de tus datos. La salud del flujo es una **capacidad gratuita**: no hace ninguna llamada a IA, no consume cuota de IA y funciona incluso con todos los proveedores de IA desactivados.

---

## El indicador de salud

El indicador está en la **cabecera del editor de flujos**, justo después del contador de palabras: el mismo widget que usan las fichas y las escenas. Cuenta los hallazgos por severidad:

| Severidad        | Qué significa                                                      |
| ---------------- | ------------------------------------------------------------------ |
| **Errores**      | Configuración inválida: el flujo no puede ejecutarse tal como está |
| **Advertencias** | Autoría incompleta o arriesgada                                    |
| **Info**         | Válido, pero el nodo no hará nada en ejecución                     |

Cuando un flujo no tiene ningún hallazgo, el indicador se reduce a un check verde.

Ábrelo para ver los hallazgos agrupados por **ubicación** -- el propio flujo o un nodo concreto --, de modo que un nodo con tres problemas es una sola entrada con tres líneas debajo. Al seleccionar la entrada de un nodo, el **lienzo se centra en ese nodo**, lo resalta y lo selecciona. Los hallazgos que pertenecen al flujo y no a un nodo (sin nodo Entry, varios nodos Entry) se listan pero no son clicables: no hay ningún sitio al que ir.

La salud se recalcula mientras editas. No hay ningún análisis que lanzar ni instantánea que refrescar: lo que ves está siempre al día y un hallazgo desaparece en cuanto el problema subyacente deja de existir. No hay nada que "marcar como arreglado": la resolución se deriva del propio flujo.

El indicador forma parte del editor normal de flujos. Las vistas compacta y de comparación no lo incluyen; abre el flujo en el editor para revisar su salud.

---

## Comprobaciones sobre el grafo

Estas necesitan el grafo completo: la estructura y los destinos a los que apuntan tus nodos.

| Hallazgo                                               | Severidad   | Qué significa                                                         |
| ------------------------------------------------------ | ----------- | --------------------------------------------------------------------- |
| El flow no tiene nodo Entry                            | Error       | Nada declara dónde empieza la reproducción                            |
| El flow tiene _N_ nodos Entry                          | Error       | Más de un inicio; la alcanzabilidad se calcula desde todos ellos      |
| Conexión en un pin de salida eliminado: _pines_        | Error       | El pin del que parte la conexión ya no existe                         |
| Conexión en un pin de entrada inválido: _pines_        | Error       | El pin al que llega la conexión ya no es válido                       |
| Jump sin hub de destino                                | Error       | Al Jump nunca se le asignó destino                                    |
| Jump apunta a un hub inexistente                       | Error       | Su hub de destino ya no está en este flujo                            |
| Subflow sin flow referenciado                          | Error       | Al nodo Subflow nunca se le asignó un flujo                           |
| Subflow referencia un flow eliminado                   | Error       | El flujo referenciado ya no existe                                    |
| Exit sin flow referenciado                             | Error       | Un Exit en modo **Referencia a flujo** sin destino                    |
| Exit referencia un flow eliminado                      | Error       | El flujo de destino ya no existe                                      |
| Nodo inalcanzable desde Entry                          | Advertencia | Ningún camino de conexiones o jumps llega hasta él                    |
| Nodo sin conexiones                                    | Advertencia | Aislado en el lienzo, en ninguna dirección                            |
| Nodo sin conexión de salida                            | Advertencia | Un callejón sin salida alcanzable que no es un Exit                   |
| Pins de salida sin conexión: _pines_                   | Advertencia | Una rama quedó colgando: el pin Falso de una condición, una respuesta |
| Hub "_id del hub_" nunca alcanzado por conexión o jump | Advertencia | Nada apunta al Hub, así que nada puede converger en él                |

Lo que aquí aparece en _cursiva_ se rellena con tus propios datos: el número de nodos Entry, los nombres de los pines afectados, el id del hub. El mensaje nombra el pin o el hub exacto, así que no tienes que buscarlo en el lienzo.

La alcanzabilidad es **topológica**, nunca una evaluación simbólica de tus condiciones:

- una Entry: el recorrido empieza ahí;
- ninguna Entry: se informa del hallazgo de Entry ausente y no se afirma nada sobre alcanzabilidad;
- varias Entries: se informa del hallazgo y el recorrido empieza desde todas;
- los ciclos son válidos y el recorrido es seguro frente a ellos;
- un Jump cuenta como arista hacia su Hub, tanto para alcanzabilidad como para aislamiento.

---

## Comprobaciones de contenido

Estas leen los datos de un solo nodo.

| Hallazgo                                       | Severidad   | Qué significa                                                       |
| ---------------------------------------------- | ----------- | ------------------------------------------------------------------- |
| Referencia de variable obsoleta                | Error       | Una ficha o variable referenciada se renombró o se eliminó          |
| Advertencia de tipo de variable                | Advertencia | El valor asignado o comparado no encaja con el tipo de la variable  |
| Advertencia de tipo en asignación de respuesta | Advertencia | El mismo desajuste dentro de una respuesta de diálogo               |
| Sin texto de diálogo                           | Advertencia | El nodo de diálogo no tiene línea                                   |
| Falta el personaje del diálogo                 | Advertencia | No hay ninguna ficha asignada como hablante                         |
| Respuesta de diálogo vacía                     | Advertencia | Una opción de respuesta sin texto                                   |
| Condición de respuesta incompleta              | Advertencia | Una regla de respuesta a la que le falta variable, operador o valor |
| Asignación de respuesta incompleta             | Advertencia | Una asignación de respuesta a medio rellenar                        |
| Condición incompleta                           | Advertencia | Un nodo de condición con una regla sin terminar o un grupo vacío    |
| Asignación de instrucción incompleta           | Advertencia | Una asignación de instrucción a medio rellenar                      |
| La condición no tiene reglas                   | Info        | El nodo tomará siempre la misma rama                                |
| Sin asignaciones de instrucción                | Info        | El nodo no cambiará nada                                            |

---

## Lo que las comprobaciones no demuestran

Cada hallazgo afirma un hecho sobre tus datos. Ninguno lee tu intención, y varios son más estrechos de lo que parecen. Saber dónde se detiene cada comprobación es lo que hace que un hallazgo resulte útil en lugar de sonar a acusación.

| Comprobación                           | Lo que **no** hace                                                                                            |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| El flow no tiene nodo Entry            | Solo comprueba tipos de nodo; no juzga dónde debería empezar la historia.                                     |
| El flow tiene varios nodos Entry       | La alcanzabilidad se calcula desde todas las entries; no decide cuál es la correcta.                          |
| Nodo inalcanzable desde Entry          | Solo topológico: no evalúa condiciones, así que un nodo alcanzable puede seguir siendo inalcanzable al jugar. |
| Nodo sin conexiones                    | Solo cuenta conexiones válidas y enlaces de jump; no sabe si el nodo es un borrador mantenido a propósito.    |
| Nodo sin conexión de salida            | No evalúa condiciones; un final intencionado modelado sin nodo Exit también lo activa.                        |
| Pins de salida sin conexión            | Informa de pins obligatorios sin conectar; no distingue si la rama está sin terminar o abandonada.            |
| Conexión en un pin de salida eliminado | Compara conexiones almacenadas con los pins actuales; no puede recuperar qué significaba el pin eliminado.    |
| Conexión en un pin de entrada inválido | Compara conexiones almacenadas con las entradas actuales; no puede recuperar la intención original.           |
| Hub nunca alcanzado                    | Solo considera conexiones y jumps dentro del flujo; no detecta hubs usados por otros medios.                  |
| Jump sin hub de destino                | Solo comprueba el id de destino almacenado.                                                                   |
| Jump apunta a un hub inexistente       | Los hubs se comparan por id solo dentro de este flujo.                                                        |
| Subflow sin flow referenciado          | Solo comprueba la referencia almacenada.                                                                      |
| Subflow referencia un flow eliminado   | Comprueba que el flujo exista en este proyecto; no inspecciona su contenido.                                  |
| Exit sin flow referenciado             | Solo comprueba la referencia almacenada.                                                                      |
| Exit referencia un flow eliminado      | Comprueba que el flujo exista en este proyecto; no inspecciona su contenido.                                  |

Las comprobaciones de contenido son igual de literales: una línea de diálogo vacía se informa tanto si es un marcador de posición como si es un silencio deliberado, y una advertencia de tipo compara tipos declarados, no el valor que habrá en ejecución.

---

## En todo el proyecto

El **panel de Flujos** lista bajo **Problemas** todos los hallazgos de todos los flujos del proyecto, primero los errores, luego las advertencias y por último los informativos. Cada fila lleva su propio icono de severidad y nombra su ubicación -- el flujo, más el nodo cuando el hallazgo pertenece a uno. Al seguir una fila se abre ese flujo y, cuando el hallazgo pertenece a un nodo, además se **enfoca ese nodo en el lienzo**: aterrizas en el problema en lugar de en un lienzo que aún tienes que recorrer.

Es el mismo catálogo con las mismas palabras: el panel no puede informar de un problema que el editor oculte, ni ocultar uno del que el editor informe. El **panel del proyecto** agrupa esos mismos hallazgos un nivel más arriba, una línea por flujo: solo errores y advertencias, porque un hallazgo informativo no es algo sobre lo que el responsable del proyecto tenga que actuar.

Los resultados de los paneles se cachean unos segundos en lugar de recalcularse en cada pulsación, así que un hallazgo que acabas de arreglar puede seguir ahí un momento mientras el indicador del editor ya está al día.

---

## Alcance

Los hallazgos son informativos y siempre derivados. No hay forma de descartarlos, posponerlos ni darlos por vistos: la única manera de eliminar un hallazgo es cambiar el flujo para que deje de cumplirse. El análisis semántico de proyecto completo, la satisfacibilidad de condiciones y la puntuación de calidad narrativa quedan fuera de alcance por diseño.
