%{
title: "Vista general de Brainstorming",
category_label: "Brainstorming",
order: 1,
description: "Explora ideas con tu equipo en un lienzo compartido y convierte lo que acordéis en decisiones que llegan a tus fichas, flujos y escenas."
}

---

Brainstorming es donde tu equipo explora ideas narrativas antes de que se conviertan en contenido de producción. Una {accent}sesión{/accent} es un lienzo compartido de notas, organizado en rondas, donde cada persona escribe, se agrupa lo que va junto y se registra lo que habéis acordado hacer.

<img src="/images/docs/brainstorming/brainstorming-board.webp" alt="Una sesión de brainstorming con la cabecera de una ronda, un grupo de notas con su síntesis, una nota descartada, una conexión y el carril de decisiones de la ronda al final" loading="lazy">

## Por qué hacer brainstorming dentro de Storyarn

Una pizarra de uso general es la herramienta adecuada para diagramas libres, talleres y todo lo que queda fuera de tu historia. El brainstorming de Storyarn tiene un trabajo más concreto: conoce tu proyecto. Una sesión puede empezar desde una Ficha, un Flujo o una Escena, y cada acuerdo nombra el contenido que cambia. Esa decisión aparece después en el editor de ese contenido hasta que alguien la marca como aplicada, así que el resultado de una sesión no se queda en un tablero que nadie vuelve a abrir.

## Cómo se organiza una sesión

| Pieza             | Qué hace                                                                                                                                      | Sigue leyendo                                                                 |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| **Notas**         | Aportaciones breves que escribes, mueves, das forma, coloreas y conectas en el lienzo.                                                        | [Lienzo y notas](/docs/brainstorming/canvas-and-notes)                        |
| **Rondas**        | Franjas horizontales del lienzo, cada una con su propia pregunta. Una ronda puede ser privada hasta que se revela y puede tener cuenta atrás. | [Rondas, privacidad y temporizador](/docs/brainstorming/rounds-privacy-timer) |
| **Grupos**        | Marcos alrededor de notas relacionadas, con una síntesis escrita de lo que tienen en común.                                                   | [Grupos y síntesis](/docs/brainstorming/groups-and-synthesis)                 |
| **Decisiones**    | Lo que el equipo acordó hacer, sobre qué contenido y hasta dónde se ha aplicado.                                                              | [Decisiones](/docs/brainstorming/decisions)                                   |
| **Exploraciones** | Sesiones vinculadas a una Ficha, un Flujo o una Escena, y las decisiones sobre ese contenido, visibles desde su editor.                       | [Decisiones en tu contenido](/docs/brainstorming/decisions-in-your-content)   |

Ninguna de estas piezas es obligatoria. Una sesión puede ser una sola ronda de notas sueltas o tres rondas que terminan en decisiones aceptadas. Añades estructura cuando te ayuda.

## Crea una sesión

Selecciona **Nueva sesión** en el dashboard de Brainstorming, o el **+** junto a **Sesiones** en la barra lateral. La sesión se abre al instante como «Sesión sin título», con una ronda y el lienzo vacío. Haz doble clic en cualquier sitio para escribir tu primera nota.

<img src="/images/docs/brainstorming/brainstorming-empty-session.webp" alt="Una sesión de brainstorming nueva y sin título, con el lienzo vacío invitando a hacer doble clic para escribir" loading="lazy">

Abre **Detalles y ajustes de la sesión** desde el icono de ajustes de la cabecera para darle un título, un objetivo y algo de contexto. El objetivo y el contexto son opcionales; ayudan a quien se incorpora más tarde a entender para qué es la sesión.

También puedes empezar una sesión desde el contenido que quieres cambiar. **Explorar cambios** en una Ficha, un Flujo o una Escena crea una sesión con ese contenido como contexto de partida. Consulta [Decisiones en tu contenido](/docs/brainstorming/decisions-in-your-content).

La paleta de comandos también sirve: busca una sesión por su título para abrirla, o ejecuta **Nueva sesión** desde cualquier parte de un proyecto que puedas editar.

## El dashboard de Brainstorming

El dashboard lista las sesiones abiertas del proyecto. Una sesión con decisiones muestra un breve resumen, como `4 decisiones · 1 espera tu aceptación · 1 por aplicar`, para que veas dónde hace falta tu atención sin abrirlas una a una. La pestaña **Decisiones** lista todas las decisiones del proyecto y se describe en [Decisiones en tu contenido](/docs/brainstorming/decisions-in-your-content#el-dashboard-de-decisiones).

<img src="/images/docs/brainstorming/brainstorming-dashboard.webp" alt="El dashboard de Brainstorming con tres sesiones; una de ellas resume cuatro decisiones, una pendiente de ti y una por aplicar" loading="lazy">

La barra lateral muestra las mismas sesiones. Despliega una sesión para ver sus rondas, nombradas por su pregunta, y su lista **Para después**. Usa el filtro de la parte superior de la barra lateral para alternar entre sesiones **Abiertas**, **Archivadas** y **Reemplazadas**.

## Responsabilidades en una sesión

Una sesión tiene dos responsabilidades, ambas asignadas en **Detalles y ajustes de la sesión**. Solo pueden tenerlas personas que puedan editar el proyecto.

| Responsabilidad               | Qué significa                                                                                                                                                                                                                                                                                            |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Facilitador**               | Dirige la sesión: edita su título y sus ajustes, escribe la pregunta de cada ronda, abre y cierra rondas, hace privada una ronda y la revela, maneja el temporizador y archiva la sesión. Quien crea una sesión es su primer facilitador; el papel se puede pasar a otra persona con permiso de edición. |
| **Responsable de decisiones** | La persona que se propone por defecto como responsable de las decisiones nuevas. No da ningún permiso para gestionar la sesión.                                                                                                                                                                          |

El resto participa según su rol en el proyecto:

| Rol en el proyecto | En una sesión                                                                                                                |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| **Propietario**    | Todo lo que puede hacer un editor, además de facilitar cualquier sesión y reasignar cualquiera de las dos responsabilidades. |
| **Editor**         | Crea sesiones, escribe notas, las agrupa, comenta, propone decisiones y marca hasta dónde se han aplicado.                   |
| **Lector**         | Consulta las sesiones, notas, grupos y decisiones a los que tiene acceso. No puede escribir.                                 |

Los permisos se comprueban en el servidor en cada cambio; no basta con ocultar controles en la interfaz.

## Archiva una sesión

Cuando una sesión ha terminado, el facilitador o el propietario del proyecto puede seleccionar **Archivar sesión** en **Detalles y ajustes de la sesión**. Una sesión archivada sigue siendo legible, con sus notas, grupos, decisiones e historial. Sus decisiones siguen apareciendo en el contenido al que afectan.

Archivar también pone fin a la privacidad de todas las rondas privadas: desde ese momento cuentan como reveladas, aunque las notas que nunca se compartieron no se publican. El facilitador puede **Reabrir sesión** más adelante para seguir trabajando.
