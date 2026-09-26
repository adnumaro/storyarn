%{
title: "Decisiones",
category_label: "Brainstorming",
order: 5,
description: "Registra lo que el equipo acordó hacer, qué contenido cambia, quién es responsable y hasta dónde se ha aplicado."
}

---

Una {accent}decisión{/accent} registra lo que tu equipo acordó hacer después de explorar: un verbo, el contenido al que afecta, una conclusión y las notas o grupos de los que sale. Queda vinculada a ese contenido, para que quien trabaja en él pueda ver el acuerdo, aplicarlo y decir cuándo está hecho.

Las decisiones son opcionales. Nada en una sesión crea ni acepta una decisión automáticamente: agrupar notas, escribir una síntesis o cerrar una ronda nunca lo hace.

## Qué contiene una decisión

| Campo                                   | Obligatorio | Qué recoge                                                                                                                                         |
| --------------------------------------- | :---------: | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Fuentes**                             |     Sí      | Las notas y grupos compartidos de los que sale la decisión, entre 1 y 20. La versión que consultaste se guarda con la decisión.                    |
| **Conclusión**                          |     Sí      | Lo que se acordó, con palabras sencillas. El título se toma de su primera línea hasta que lo editas tú.                                            |
| **Esta decisión significa que vamos a** |     Sí      | Un verbo: **Crear**, **Cambiar**, **Probar**, **Mantener** o **Descartar**.                                                                        |
| **Afecta a**                            |     No      | Hasta cinco Fichas, Flujos o Escenas que la decisión cambia. Para algo que todavía no existe, elige **Algo nuevo…** y dale una etiqueta y un tipo. |
| **Motivo**                              |     No      | Por qué el equipo eligió esto.                                                                                                                     |
| **Responsable**                         |     Sí      | El editor que acepta la decisión. Se propone por defecto el responsable de decisiones de la sesión.                                                |
| **Siguiente acción**                    |     No      | Qué pasa a continuación en el editor y, si quieres, quién lo hace.                                                                                 |
| **Sustituye a una decisión**            |     No      | Una decisión aceptada de la misma sesión que esta sustituye cuando se acepte.                                                                      |

El verbo le dice a todo el mundo qué esperar:

| Verbo         | Significado                                                     |
| ------------- | --------------------------------------------------------------- |
| **Crear**     | Se crea algo nuevo en el contenido.                             |
| **Cambiar**   | El contenido existente se edita para ajustarse.                 |
| **Probar**    | Un prototipo o una prueba de juego antes de comprometerse.      |
| **Mantener**  | Confirma lo que ya existe; normalmente no hay nada que aplicar. |
| **Descartar** | Descarta una opción; normalmente no hay nada que aplicar.       |

## Propón una decisión

Puedes empezar una decisión de tres maneras:

- **Desde una selección.** Selecciona notas compartidas en el lienzo y elige **Proponer una decisión** en la barra de selección. La selección pasa a ser las fuentes.
- **Desde un grupo.** Selecciona un grupo y elige **Convertir en decisión** en su cabecera. El grupo pasa a ser la fuente y su síntesis rellena la conclusión.
- **Desde el panel.** Abre **Decisiones** en la cabecera, selecciona **Nueva propuesta** y usa **Añadir fuentes** para buscar entre las notas y grupos compartidos de la sesión.

Mientras el formulario está abierto, el mismo botón de la barra de selección pasa a decir **Añadir a la propuesta**: selecciona más notas y úsalo para añadirlas como fuentes.

<img src="/images/docs/brainstorming/brainstorming-decision-form.webp" alt="El formulario de nueva propuesta con dos fuentes de la Ronda 2, una conclusión, el verbo Cambiar seleccionado, el campo Afecta a vacío y el botón Registrar decisión" loading="lazy">

Solo las notas ya compartidas pueden ser fuentes. Las notas de una ronda privada están disponibles en cuanto la ronda se revela.

## Registra o propón

Lo que hace el botón principal depende de quién es responsable:

- **Registrar decisión** aparece cuando el responsable eres tú. La decisión se propone y se acepta en un solo paso.
- **Proponer** aparece cuando el responsable es otra persona. La decisión queda a la espera, marcada como **Pendiente de ti** en su panel, y recibe un aviso en su bandeja de notificaciones.

Si eres responsable pero quieres que el equipo la revise antes, elige **Guardar como propuesta**. Registrar o proponer nunca cambia tu contenido.

Solo el responsable puede aceptar una propuesta, con **Aceptar decisión** en su detalle. Ser propietario del proyecto, facilitador o responsable de decisiones de la sesión no te permite aceptar en nombre de otra persona. No hay votaciones ni rechazos: una propuesta que el equipo no quiere se retira.

## El panel de decisiones

**Decisiones** en la cabecera abre el panel de la sesión. Las decisiones se ordenan según lo que necesita atención: las pendientes de ti, las que faltan por aplicar, las propuestas abiertas y, al final, las que ya están hechas. Las retiradas y las sustituidas se guardan al final bajo **Retiradas**.

<img src="/images/docs/brainstorming/brainstorming-decisions-panel.webp" alt="El panel de decisiones con una propuesta pendiente de ti y una decisión aceptada con uno de sus dos contenidos por aplicar" loading="lazy">

Cada tarjeta muestra un único estado: **Pendiente de ti**, **Propuesta**, **Decisión aceptada**, **1 de 2 por aplicar**, **Retirada** o **Sustituida**. También muestra el verbo, el contenido afectado con su estado de aplicación, las fuentes y la ronda a la que pertenece la decisión.

Abre una tarjeta para ver la decisión completa: qué significa, la pregunta de la ronda, la conclusión y el motivo, y cada fuente con el texto exacto que se consultó. Si una nota fuente ha cambiado desde entonces, aparece marcada. Cuando propones una revisión, **Actualizar fuentes** adopta la versión actual de esas notas.

<img src="/images/docs/brainstorming/brainstorming-decision-detail.webp" alt="El detalle de la decisión The player chooses who keeps the light, con su verbo Cambiar, el Flujo y la Ficha afectados, la pregunta de la ronda, la conclusión, el motivo y las fuentes" loading="lazy">

## Aplicación

Una decisión aceptada registra, para cada contenido al que afecta, si el cambio ya se ha hecho:

| Estado                     | Significado                                                |
| -------------------------- | ---------------------------------------------------------- |
| **No aplicada**            | Todavía no se ha declarado nada. Es el estado por defecto. |
| **Aplicada en parte**      | Parte del cambio ya está en el contenido.                  |
| **Aplicada**               | El cambio está en el contenido.                            |
| **Sin cambios necesarios** | El contenido ya encajaba, o no necesita nada.              |

Cualquier editor puede declarar un estado con **Marcar como aplicada**, con una nota breve opcional como «Added trust_tobin as a three-state select». **Ir a aplicar** abre el contenido afectado con la decisión al lado; consulta [Decisiones en tu contenido](/docs/brainstorming/decisions-in-your-content). Una decisión sin contenido afectado se puede cerrar con **Declarar que no hacen falta cambios**.

<img src="/images/docs/brainstorming/brainstorming-decision-application.webp" alt="El bloque de aplicación con Act 3 endings sin aplicar, con Ir a aplicar y Marcar como aplicada, y Mara aplicada por Tomás Rivera con una nota; debajo, la siguiente acción y la conversación" loading="lazy">

Una declaración es una afirmación de tu equipo, no una comprobación: Storyarn nunca lee ni cambia el contenido para verificarla, y nunca aplica una decisión automáticamente. Cada declaración queda en el historial de la decisión con quién la hizo y cuándo.

## Habla sobre una decisión

Cada decisión tiene su propia **Conversación** bajo el bloque de aplicación. Pregunta, menciona a tus compañeros con **@** y resuelve el hilo cuando esté cerrado. Las tarjetas muestran cuántos mensajes tiene la conversación.

Conversar y decidir van por separado a propósito: resolver la conversación nunca acepta la decisión, y aceptar la decisión nunca resuelve la conversación.

## Revisa, retira o sustituye

Las decisiones nunca se eliminan ni se rechazan. Cambian mediante registros nuevos, y el **Historial de la decisión** los conserva todos.

- **Proponer una revisión** escribe una versión nueva de una decisión aceptada. El acuerdo anterior sigue vigente hasta que se acepta la revisión. Al aceptarla, la aplicación empieza de cero: todo el contenido afectado vuelve a **No aplicada**, y las declaraciones anteriores se quedan en el historial.
- **Retirar** está disponible para quien escribió la propuesta actual y para el propietario del proyecto. Retirar una revisión mantiene vigente el acuerdo anterior. Retirar una propuesta que nunca se aceptó da por cerrada la decisión como **Retirada**.
- **Sustituye a una decisión**, en el formulario, nombra una decisión aceptada de la misma sesión. Cuando se acepta la nueva decisión, la anterior pasa a **Sustituida**: de solo lectura y vinculada a su sustituta.

## Las decisiones en el lienzo

Cada ronda termina en un carril con las decisiones que salieron de ella, con una etiqueta como «Decisiones · Ronda 2 · 3». Las tarjetas aparecen en el mismo orden que en el panel, con conectores finos hasta las fuentes que puedes ver.

<img src="/images/docs/brainstorming/brainstorming-decision-lane.webp" alt="El carril de decisiones al final de la Ronda 2 con tres tarjetas de decisión; la tarjeta seleccionada resalta sus conectores hasta la nota en rombo y el grupo de arriba" loading="lazy">

- Selecciona una tarjeta para resaltar sus fuentes en el lienzo.
- Haz doble clic en una tarjeta, o pulsa **Enter**, para abrirla en el panel.
- Deja el puntero sobre una nota para ver las decisiones que respalda, y elige una para abrirla.

<img src="/images/docs/brainstorming/brainstorming-decision-hover.webp" alt="Al pasar el cursor sobre una nota aparece una tarjeta que indica que respalda una decisión, The player chooses who keeps the light, con su estado de aplicación" loading="lazy">

Una decisión pertenece a la ronda más reciente entre sus fuentes.

## Límites

Una sesión puede tener hasta 100 decisiones. Cada versión de una decisión tiene entre 1 y 20 fuentes y hasta 5 contenidos afectados.
