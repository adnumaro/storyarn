%{
translation_key: "introducing-storyarn",
title: "Presentamos Storyarn: una plataforma conectada para el diseño narrativo",
seo_title: "Storyarn: plataforma de diseño narrativo",
description: "Storyarn conecta construcción de mundos, narrativa ramificada, escenas, pruebas, localización y exportación dentro de un mismo proyecto.",
author: "Equipo de Storyarn",
image: "/images/docs/project-dashboard-current.png",
image_alt: "Panel de un proyecto de Storyarn con fichas, flujos, escenas, progreso de localización, avisos y actividad reciente",
tags: ["Storyarn", "Diseño narrativo", "Desarrollo de videojuegos"]
}

---

Hoy abrimos Storyarn a todo el mundo.

Storyarn es una plataforma de diseño narrativo para equipos que crean historias interactivas. Conecta construcción de mundos, diálogos ramificados, escenas, pruebas, localización y exportación dentro de un mismo proyecto, para que las relaciones que hacen funcionar una historia no se pierdan al pasar de una herramienta a otra.

El registro está abierto, no hace falta invitación y Storyarn es gratuito durante el acceso anticipado.

Este primer artículo no es un tutorial. Explica la decisión de producto que hay detrás de la plataforma: las historias interactivas suelen construirse con varias herramientas capaces, pero la historia tiene que seguir comportándose como un único sistema. Storyarn se centra en las conexiones que resultan más difíciles de conservar cuando el mundo, el diálogo, el estado, las escenas, la localización y la implementación viven en lugares diferentes.

## El problema no es escribir la frase

Pensemos en un intercambio breve en el que el jugador pregunta a un personaje por una ubicación oculta.

La respuesta solo aparece cuando ese personaje confía lo suficiente en el jugador. Elegirla cambia el estado de una misión. La ubicación pasa a estar disponible en el mapa. La frase necesita traducción, su voz debe poder seguirse durante producción y el resultado final tiene que llegar al juego en un formato que el runtime pueda interpretar.

Escribir la frase es la parte más pequeña de esa decisión.

A los equipos no les faltan herramientas especializadas. El personaje y su mundo pueden desarrollarse en Notion o World Anvil. La conversación puede diseñarse en Arcweave o articy:draft, o implementarse con Yarn Spinner o Ink. El estado puede estar representado en la herramienta narrativa y de nuevo en el motor, mientras la localización sigue su propio flujo. Algunos equipos eligen una sola herramienta; otros las combinan deliberadamente porque cada una resuelve una parte distinta del problema.

Eso no convierte el proceso en anticuado ni significa que esas herramientas sean insuficientes. La fragilidad aparece en las conexiones. Una condición cambia de nombre en el diálogo, pero no en la integración con el motor. Una decisión sobre el personaje evoluciona en la biblia del mundo mientras una rama conserva una premisa anterior. La ubicación existe en el mundo, pero ninguna ruta alcanzable llega a revelarla. Una persona encargada de la traducción recibe la frase sin el estado o el contexto que le da sentido.

Los equipos mantienen esas conexiones mediante identificadores estables, convenciones de nombres, código de integración, documentación, revisiones y personas que saben dónde cruza cada dependencia de una herramienta a otra. Esa coordinación funciona, pero se vuelve más costosa a medida que el proyecto crece y más disciplinas dependen de las mismas decisiones.

Storyarn nace justo en ese espacio entre herramientas.

## Un modelo narrativo conectado

La idea central es sencilla: el personaje, su grado de confianza, la conversación, la ubicación y la frase localizada no deberían convertirse en cinco representaciones que el equipo tenga que reconciliar continuamente a mano.

En Storyarn pueden formar parte del mismo modelo.

Las [Fichas](/docs/world-building/sheets-overview) describen las partes estructuradas del mundo: personajes, lugares, facciones, objetos, misiones y los campos que importan al proyecto. Los [Flujos](/docs/narrative-design/flows-overview) utilizan esos datos directamente en diálogos, respuestas, condiciones e instrucciones. Las [Escenas](/docs/scene-design/scenes-overview) dan un contexto espacial al contenido narrativo. La localización conserva la identidad y el origen del texto que verá el jugador, en lugar de recibir una colección anónima de cadenas.

No son miniproductos independientes agrupados detrás del mismo inicio de sesión. Un campo definido para un personaje puede ser consultado por una condición de un Flujo y modificado por una instrucción. Una escena puede conducir a ese Flujo durante la exploración. Cuando cambia el diálogo original, el flujo de localización puede señalar que la traducción existente necesita revisión.

El producto está en la conexión.

<figure>
  <img src="/images/docs/project-dashboard-current.png" alt="Panel de Storyarn que reúne datos del mundo, flujos, escenas, localización, validación y actividad en un mismo proyecto" loading="lazy">
  <figcaption>El proyecto se trata como un único sistema narrativo, no como una capa más añadida a una cadena de herramientas especializadas.</figcaption>
</figure>

Esto cambia las preguntas que puede hacerse un equipo. Ya no solo «¿dónde está esta frase?», sino «¿qué permite que aparezca?», «¿qué cambia al elegirla?», «¿dónde puede encontrarla el jugador?», «¿qué traducción procede de ella?» y «¿conservará el proyecto exportado todas esas relaciones?».

También mantiene la intención creativa cerca del trabajo. El grafo no debería depender de una nota separada para explicar qué significa una condición. El contexto del mundo y el estado ejecutable no deberían alejarse el uno del otro. Una entrega no debería comenzar reconstruyendo relaciones a partir de identificadores, exportaciones y convenciones privadas.

## Una misma decisión a través de todo el proyecto

Volvamos a la ubicación oculta.

El grado de confianza del personaje se define una sola vez como un dato estructurado en Storyarn. La conversación consulta exactamente ese campo. Si se cumple el requisito, la respuesta aparece; elegirla puede actualizar la misión y revelar la ubicación. La escena sitúa ese lugar en el mundo y el diálogo conserva la identidad de su texto original cuando pasa al flujo de localización.

Lo importante no es que Storyarn tenga un editor de Fichas, un lienzo de nodos y un mapa. Lo importante es que la misma decisión mantiene su identidad al atravesar los tres, sin tener que traducirse a una nueva convención privada en cada frontera.

<figure>
  <img src="/images/docs/flows-editor-current.png" alt="Editor de Flujos de Storyarn con nodos conectados de diálogo, respuesta, condición, instrucción y salida" loading="lazy">
  <figcaption>Un Flujo mantiene el texto junto al estado y las consecuencias que lo convierten en interactivo.</figcaption>
</figure>

Eso no elimina la complejidad. La narrativa ramificada contiene estado, dependencias, estructuras reutilizables, consecuencias diferidas y casos límite. Ocultarlo haría que la herramienta pareciera más sencilla, pero volvería menos fiable la producción.

El trabajo de Storyarn es mantener esa complejidad visible y navegable. Quien escribe puede permanecer dentro de la conversación mientras diseño narrativo inspecciona sus reglas. El equipo de localización puede consultar el contexto original. Ingeniería puede recibir un modelo coherente en lugar de varias exportaciones cuyas relaciones deban reconstruirse durante la integración.

Las distintas disciplinas no necesitan interfaces idénticas. Sí necesitan estar trabajando sobre la misma historia.

## Probar la historia antes de llegar al motor

Una historia interactiva no está terminada porque todos sus nodos contengan texto. Tiene que poder ejecutarse.

El [Story Player](/docs/narrative-design/flows-overview#story-player) de Storyarn ejecuta un Flujo tal y como lo experimentaría el jugador, utilizando sus condiciones y cambios de estado reales. El [Modo Depuración](/docs/narrative-design/debug-mode) muestra la lógica que hay debajo: la ruta activa, las variables actuales, los puntos de interrupción y el motivo por el que una rama se ha alcanzado o ha quedado fuera.

Son dos tipos de información distintos. Story Player ayuda al equipo a valorar ritmo, decisiones y contexto. Modo Depuración permite comprender el comportamiento del sistema.

<figure>
  <img src="/images/docs/flows-debug-current.png" alt="Modo de depuración de Storyarn con la ruta narrativa activa, la consola de ejecución y las variables del proyecto" loading="lazy">
  <figcaption>La narrativa puede jugarse e inspeccionarse mientras todo el contexto de diseño sigue disponible.</figcaption>
</figure>

El motor del juego sigue siendo el dueño de la realidad final. La interfaz, la animación, el audio, el guardado, la entrada y la integración definitiva deben probarse allí. Pero el motor no debería ser el primer lugar en el que diseño narrativo descubre que una rama es inalcanzable o que una condición está consultando el valor equivocado.

Antes de [exportar](/docs/import-export/import-export-overview), Storyarn valida el proyecto conectado en busca de referencias rotas, rutas inalcanzables, puntos de entrada ausentes, contenido incompleto y otros problemas que son más fáciles de resolver mientras el contexto narrativo sigue presente. Después puede preparar el proyecto para formatos como Ink, Yarn Spinner, Unity Dialogue System, Godot Dialogic, Unreal Engine y articy:draft.

La exportación no elimina el trabajo de integración. Le proporciona una fuente mejor.

## La beta abierta es donde el modelo se encuentra con proyectos reales

Storyarn ya permite estructurar mundos, construir y ejecutar Flujos ramificados, organizar espacios narrativos, gestionar localización, validar proyectos y preparar exportaciones. También es una beta abierta: las funcionalidades cambiarán, aparecerán asperezas y las producciones reales pondrán a prueba supuestos que nunca aparecen en los ejemplos ordenados.

Por eso lo abrimos ahora.

Queremos descubrir en qué puntos los equipos narrativos todavía necesitan salir de la plataforma. ¿Qué herramienta especializada sigue conservando una parte crucial del proceso? ¿Qué relación todavía no puede expresarse? ¿Qué conexión se vuelve incómoda al cruzar de una herramienta a otra? ¿Qué entrega al motor sigue perdiendo contexto? ¿Qué parte del proceso de escritura se siente limitada en lugar de acompañada?

No esperamos que Storyarn sustituya todas las herramientas que un equipo valora. Queremos reducir la cantidad de modelo narrativo que debe reconstruirse cada vez que el trabajo pasa de una a otra.

Storyarn está pensado para diseño narrativo, escritura de videojuegos, construcción de mundos, localización y pequeños estudios que necesitan algo más que un editor de diálogos, pero no quieren enterrar su proceso creativo bajo maquinaria empresarial.

No intentamos que la narrativa interactiva parezca más sencilla de lo que es. Estamos construyendo un lugar donde su complejidad pueda permanecer conectada, comprobable y comprensible desde la primera idea hasta el juego.
