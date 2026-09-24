%{
title: "Decisiones en tu contenido",
category_label: "Brainstorming",
order: 6,
description: "Empieza exploraciones desde una Ficha, un Flujo o una Escena, y encuentra, aplica y sigue las decisiones que le afectan."
}

---

Brainstorming se conecta con el resto de tu proyecto en los dos sentidos. Puedes empezar una sesión desde el contenido que quieres cambiar, y las decisiones que afectan a una Ficha, un Flujo o una Escena aparecen en su editor, en tu bandeja de notificaciones, en el dashboard y en la paleta de comandos hasta que se aplican.

## Explora cambios desde tu contenido

Los editores de Fichas, Flujos y Escenas tienen una bombilla a la izquierda de su cabecera, con la etiqueta **Explorar cambios**. Abre el diálogo de **Exploraciones**, que tiene tres partes:

- **Contexto de partida**: un resumen del contenido, como su nombre, su shortcut y su descripción. Se guarda con la sesión como referencia; no es una copia editable y no cambia el original.
- **Decisiones sobre** el contenido, cuando las hay. Consulta [más abajo](#decisiones-en-el-editor).
- **Exploraciones vinculadas**: las sesiones que ya exploran este contenido. Selecciona **Retomar** para continuar una, o **Ver** si la sesión está archivada.

<img src="/images/docs/brainstorming/brainstorming-explorations.webp" alt="El diálogo de Exploraciones abierto desde el Flujo Act 3 endings, con su contexto de partida, las decisiones sobre él y una exploración vinculada para retomar" loading="lazy">

Para empezar una sesión nueva sobre el contenido, selecciona **Nueva exploración**, dale un título y, si quieres, escribe qué te gustaría explorar; después selecciona **Crear y explorar**. Para añadir el contenido a una sesión que ya existe, selecciona **Vincular existente** y búscala por su título.

<img src="/images/docs/brainstorming/brainstorming-explore-new.webp" alt="El formulario de nueva exploración en el diálogo de Exploraciones de la Ficha Mara, con un título y la pregunta que se quiere explorar" loading="lazy">

Los lectores pueden abrir y retomar las exploraciones a las que tienen acceso, pero necesitan permiso de edición para crear o vincular una.

## Referencias dentro de una sesión

Una sesión puede tener a mano más partes del proyecto que su contenido de partida. **Referencias**, el botón de enlace de la esquina superior izquierda del lienzo, abre **Referencias de la sesión**, donde vinculas a la sesión Fichas, Flujos, Escenas, Recursos y textos localizados, cada uno con un propósito como **Referencia** o **Afecta a**. Una Ficha, un Flujo o una Escena vinculados así también muestran la sesión entre sus exploraciones vinculadas, con sus decisiones.

<img src="/images/docs/brainstorming/brainstorming-references.webp" alt="El panel de referencias de la sesión con los selectores de tipo de contenido y propósito, y una Escena vinculada, The lighthouse, sin cambios en su resumen" loading="lazy">

Cada referencia conserva el resumen que consultaste al vincularla. Si el contenido cambia después, la referencia indica **Los metadatos generales cambiaron desde que se vinculó**, y **Abrir contenido actual** te lleva a su editor. Vincular nunca cambia el contenido original.

## Decisiones en el editor

Cuando hay decisiones aceptadas con algo por aplicar en una Ficha, un Flujo o una Escena, su bombilla muestra un contador ámbar. Pasa el cursor por encima para leer un resumen, como «2 decisiones sobre Mara · 1 por aplicar».

El diálogo de **Exploraciones** lista las **Decisiones sobre** ese contenido: primero las que faltan por aplicar, después las propuestas abiertas, luego las ya aplicadas o que no necesitan cambios y, por último, las retiradas y las sustituidas. La lista incluye las decisiones que nombran el contenido en **Afecta a** y todas las decisiones de las sesiones que lo exploran.

Puedes abrir cualquiera en su sesión. En una decisión que aún falta por aplicar aquí, los editores también pueden:

- seleccionar **Marcar como aplicada** para declarar su estado sin salir del diálogo;
- seleccionar **Ir a aplicar** para trabajar en ella desde el editor.

## Aplica una decisión

**Ir a aplicar** abre el contenido afectado con la decisión fijada bajo la cabecera del editor: su título, su verbo, su conclusión y su sesión, junto al contenido que vas a cambiar.

<img src="/images/docs/brainstorming/brainstorming-apply-banner.webp" alt="El Flujo Act 3 endings abierto en su editor con la decisión The player chooses who keeps the light bajo la cabecera, con las opciones Marcar aplicada, Parcialmente y Sin cambios" loading="lazy">

Haz tus cambios y después elige **Marcar aplicada**, **Parcialmente** o **Sin cambios**, con una nota breve si quieres. Durante cinco segundos después de marcarla puedes pulsar **Deshacer**, que restaura el estado anterior; después el aviso se cierra solo. También puedes cerrarlo, y desaparece cuando pasas a otro contenido.

Storyarn nunca aplica una decisión por ti ni comprueba el contenido para saber si se ha aplicado. El estado es lo que declara tu equipo.

## Notificaciones

Las decisiones avisan a quien tiene que actuar, en la bandeja de notificaciones:

| Cuándo                                           | A quién se avisa                                                      |
| ------------------------------------------------ | --------------------------------------------------------------------- |
| Se propone una decisión                          | Al responsable, que tiene que aceptarla                               |
| Se acepta una decisión                           | A quien la propuso y a quien haya abierto una conversación sobre ella |
| Una decisión aceptada tiene una siguiente acción | A la persona encargada de esa acción, cuando se acepta la decisión    |
| Un contenido afectado se marca como aplicado     | Al responsable y a quien propuso la decisión por primera vez          |

Nunca recibes avisos de tus propias acciones. Las menciones y respuestas en la conversación de una decisión llegan como cualquier otra notificación de comentarios.

<img src="/images/docs/brainstorming/brainstorming-inbox.webp" alt="La bandeja de notificaciones con dos decisiones marcadas como aplicadas y una decisión propuesta para que la aceptes" loading="lazy">

## El dashboard de decisiones

La pestaña **Decisiones** del dashboard de Brainstorming lista todas las decisiones del proyecto, de todas las sesiones.

- Filtra por estado: **Propuestas**, **Aceptadas** o **Retiradas y sustituidas**.
- Filtra por aplicación: **Por aplicar**, **Aplicadas** o **Sin cambios necesarios**.
- Activa **Agrupar por contenido afectado** para ver, por cada Ficha, Flujo o Escena, las decisiones que le afectan y cuántas faltan por aplicar.

<img src="/images/docs/brainstorming/brainstorming-decisions-dashboard.webp" alt="La pestaña Decisiones del dashboard de Brainstorming agrupada por contenido afectado, con el Flujo Act 3 endings y la Ficha Mara listando cada uno la decisión que les afecta" loading="lazy">

## La paleta de comandos

Pulsa **Cmd/Ctrl+K** y escribe el nombre de una Ficha, un Flujo o una Escena. Bajo **Ir a**, la paleta muestra el contenido y, debajo, las decisiones que lo nombran, con su verbo, su estado y su sesión.

<img src="/images/docs/brainstorming/brainstorming-palette.webp" alt="La paleta de comandos buscando Mara y mostrando la Ficha, un Flujo y la decisión The player chooses who keeps the light" loading="lazy">

Las decisiones siguen las mismas reglas de acceso en todas partes: solo ves las decisiones, sesiones y fuentes que tienes permiso para leer.
