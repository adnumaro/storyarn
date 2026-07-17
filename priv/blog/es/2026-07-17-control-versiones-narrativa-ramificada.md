%{
translation_key: "version-control-branching-narratives",
title: "Volver atrás sin romper la historia",
seo_title: "Control de versiones para narrativa interactiva",
description: "Por qué el control de versiones sigue siendo difícil en narrativa interactiva y cómo Storyarn intenta recuperar contenido sin romper sus relaciones.",
author: "Equipo de Storyarn",
image: "/images/blog/version-control-branching-narratives.svg",
image_alt: "Tres momentos de una historia conectada y una revisión que muestra una relación rota antes de restaurarla",
tags: ["Control de versiones", "Diseño narrativo", "Colaboración", "Producción"]
}

---

Una restauración puede terminar sin errores y aun así romper una historia.

La conversación vuelve. Su hablante no. La condición sigue en el grafo, pero la variable que consultaba ya no existe. El botón decía «restaurar»; lo que recuperó fue solo una pieza del pasado.

En una historia interactiva casi nada vive aislado. Una frase puede estar vinculada a una traducción y a una grabación. Una elección depende de una variable. Un personaje reaparece en conversaciones, escenas y documentos que evolucionan a ritmos distintos. Recuperar texto es sencillo. Recuperar el significado que adquiría al relacionarse con todo lo demás no lo es.

El control de versiones lleva décadas intentando hacer que los cambios sean reversibles. Su historia explica por qué, al llegar al diseño narrativo, el problema se vuelve diferente.

## De los archivos a las historias conectadas

En 1972, Marc Rochkind creó SCCS en Bell Labs para controlar el código de grandes programas. El [artículo que publicó en 1975](https://doi.org/10.1109/TSE.1975.6312866) explicaba cómo conservar cada cambio, registrar quién lo hizo y recuperar cualquier revisión. Cincuenta años después, Rochkind reconoció en una [retrospectiva](https://www.mrochkind.com/mrochkind/docs/SCCSretro2.pdf) que el sistema no modelaba bien cómo trabajaban realmente los equipos.

Las herramientas posteriores añadieron ramas, fusiones y colaboración distribuida. Aunque sistemas como Git versionan instantáneas del repositorio, su comparación habitual sigue organizada en archivos y líneas. El diseño narrativo heredó esa infraestructura y también su desajuste: para un diseñador, lo que cambia suele ser una conversación, una escena o una decisión conectada con muchas otras.

En 2014, la comunidad de Twine ya describía esa tensión. El formato `.tws` conservaba el tablero visual, pero era difícil de comparar y fusionar; Twee ofrecía texto compatible con Git, pero el viaje de ida y vuelta podía [perder la posición de los pasajes](https://twinery.org/archive/forum/discussion/1403/preserving-twine-metadata-in-twee-sources.html). En 2017, investigadores de ETH Zurich, Disney Research y Rutgers presentaron un marco de [Story Version Control](https://la.disneyresearch.com/publication/story-version-control-and-graphical-visualization/) basado en eventos y participantes, con comparación visual, detección de conflictos y fusión de historias.

Poder regresar con confianza permite experimentar, repartir el trabajo y revisar decisiones sin mantener carpetas llenas de copias. En narrativa ramificada, donde una modificación puede alterar rutas, estado, localización y voz, el historial protege la producción y la libertad creativa.

## Guardar no es poder volver

Los problemas de persistencia no desaparecieron con el autosave. En 2016, usuarios de Inky reportaron [archivos cuyo contenido había desaparecido](https://github.com/inkle/inky/issues/38). En 2024, una carrera entre el guardado y el observador de archivos permitía borrar el proyecto al pulsar `Ctrl+S` rápidamente; la [incidencia se corrigió](https://github.com/inkle/inky/issues/508). En 2025 apareció un [reporte con pasos de reproducción](https://github.com/inkle/ink/issues/946) sobre corrupción de archivos Ink en subdirectorios profundos. Y en 2026 se reportó en Twine que ejecutar Play, Test o Export antes de que el cambio apareciera en el mapa podía utilizar [el estado anterior del pasaje](https://github.com/klembot/twinejs/issues/1689). Son casos cualitativos, pero muestran que la pregunta sigue abierta.

Parte de la confusión viene de llamar «seguridad» a mecanismos distintos. Guardar persiste el estado actual. Undo revierte una acción reciente. Un backup permite sobrevivir a una pérdida. Un historial conserva decisiones separadas en el tiempo y debería explicar qué cambia al recuperar una. Una aplicación puede ofrecer tres de esas capas y seguir dejando un hueco en la cuarta.

Los archivos de texto y Git aportan portabilidad, autoría y un formato independiente de la aplicación. Son una base valiosa. Sin embargo, Git puede decir qué líneas cambiaron; no sabe por sí solo si una condición dejó una rama inaccesible o si una traducción ya no corresponde a su original.

## Una historia se rompe entre objetos

Imaginemos que una diseñadora recupera la versión del martes de una conversación. En aquel momento, la capitana Ilya era su hablante y la variable `trust_ilya` decidía si aparecía una respuesta. El jueves el personaje fue sustituido, la variable se renombró y sus líneas ya habían empezado a localizarse.

Si la herramienta restaura únicamente los nodos, el lienzo puede parecer correcto mientras contiene dos ausencias y una traducción desconectada. Si restaura todo el proyecto, reaparecen la capitana y la variable, pero también puede desaparecer trabajo válido creado después. La dificultad no consiste en elegir entre un botón local y otro global. Consiste en saber qué relaciones pertenecían a aquella decisión y cuáles evolucionaron de forma independiente.

En 2024, un equipo que usaba Dialogue System for Unity preguntó cómo evitar que varios escritores se sobrescribieran. El soporte recomendó bases separadas y rangos de IDs distintos; el usuario advirtió que renumerarlos rompería referencias desde Lua, y la [respuesta confirmó que conservarlos era lo seguro](https://forum.pixelcrushers.com/post/best-practices-for-dialogue-system-version-control-13719816). Versionar contenido exige preservar también su identidad.

El mismo límite aparece en otras capas. LegendKeeper advierte que reimportar contenido crea [IDs y enlaces internos nuevos](https://www.legendkeeper.com/changelog/legendkeeper-0-16-1-0/), mientras articy:draft X ha corregido problemas de [serialización determinista](https://www.articy.com/help/adx/Changes_4_2.html) y de [locks y descartes](https://www.articy.com/help/adx/RecentChanges.html). Un archivo recuperable puede seguir generando cambios fantasma o referencias distintas.

También hay avances claros. Arcweave lanzó en 2025 un [historial del proyecto completo](https://arcweave.com/whats-new/articles/project-history-is-now-live-for-team-workspaces) cuya restauración crea una versión nueva en vez de borrar el trabajo posterior. No es una solución universal, sino otra elección de granularidad. La pregunta útil sigue siendo qué conserva una restauración: texto, identidad, relaciones, autoría y futuro.

## Cómo abordamos el problema en Storyarn

El historial de Storyarn no nació de esta investigación, pero estas fuentes nos ayudan a medirlo. Versionamos unidades que el diseñador reconoce: Fichas, Flujos y Escenas. Sus revisiones pueden nombrarse y compararse mediante cambios estructurados, sin leer JSON. En Fichas, restaurar conserva automáticamente el estado actual y registra el resultado. En Flujos y Escenas se puede guardar el estado actual antes de restaurar, pero esas dos entradas todavía no se generan de forma uniforme. El sistema también analiza parte de las relaciones externas.

Esa capa local convive con la Papelera y con capturas del proyecto. La [Papelera](/docs/project-management/recovery-and-trash) resuelve eliminaciones recientes sin convertirlas en versiones. Las capturas ofrecen un punto de recuperación más amplio cuando el problema atraviesa varias áreas. Separar esos mecanismos es intencional: corregir una conversación no debería obligar a retroceder el trabajo correcto de todo el equipo.

También tenemos límites. El análisis previo no cubre todas las formas de referencia y la captura automática no se activa de manera uniforme ante cualquier edición. Las capturas del proyecto no reproducen todavía un instante exacto: no recrean todo lo eliminado, no eliminan todo lo creado después ni incluyen cada área de la plataforma. No las presentamos como un rollback completo.

La dirección es sencilla de expresar, aunque difícil de implementar: una versión debe corresponder a una unidad narrativa comprensible, conservar el presente como estado recuperable y explicar el impacto sobre identidades y relaciones antes de ejecutar el cambio. Quizá no podamos reparar automáticamente a la capitana Ilya, `trust_ilya` y cada traducción, pero sí debemos detectarlos antes de mostrar un lienzo aparentemente correcto.

Si has vivido un caso en el que recuperar una versión rompió una referencia, una traducción o el trabajo de otra persona, nos interesa conocerlo. Los casos límite reales son los que convierten «volver atrás» en algo en lo que un equipo puede confiar.

## Fuentes y alcance

Las conversaciones e incidencias enlazadas son ejemplos cualitativos, no una medición de frecuencia ni una evaluación global de cada producto. Las funciones se contrastaron con documentación oficial disponible el 17 de julio de 2026.

Las afirmaciones sobre Storyarn se revisaron contra su [implementación del historial](https://github.com/adnumaro/storyarn/blob/main/lib/storyarn/versioning/version_crud.ex), el [análisis de dependencias](https://github.com/adnumaro/storyarn/blob/main/lib/storyarn/versioning/conflict_detector.ex), las [capturas del proyecto](https://github.com/adnumaro/storyarn/blob/main/lib/storyarn/versioning/builders/project_snapshot_builder.ex) y sus pruebas.
