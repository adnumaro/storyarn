%{
title: "Flujo de trabajo principal",
category_label: "Bienvenida",
order: 3,
description: "Cómo se desarrolla un proyecto típico en Storyarn."
}

---

Cada equipo usa Storyarn de forma diferente, pero así es como un proyecto típico avanza desde la configuración hasta la entrega.

---

## Configura tu espacio

Crea un **espacio de trabajo (workspace)** para tu equipo. Cada espacio de trabajo tiene sus propios miembros con acceso basado en roles — los propietarios gestionan todo, los administradores manejan las invitaciones, los miembros crean proyectos y los observadores tienen acceso de solo lectura.

Dentro de un espacio de trabajo, crea un **proyecto**. Cada proyecto es independiente — con sus propias fichas, flujos, escenas, localización y recursos. Los proyectos también tienen su propia membresía: los propietarios configuran los ajustes, los editores crean contenido y los observadores revisan.

Invita a compañeros de equipo por email. Reciben un enlace con token, lo aceptan, y ya están dentro — con el rol que elegiste.

<img src="/images/docs/workspace-dashboard-current.png" alt="Panel del espacio de trabajo con la tarjeta del proyecto Veilbreak Demo y el botón New Project" loading="lazy">

---

## Define tu mundo con Fichas

Empieza con las **Fichas (Sheets)** — contenedores de datos estructurados para todo el mundo de tu juego. Crea una ficha para cada personaje, objeto, ubicación, facción o misión.

Cada campo en una ficha es un **bloque (block)**. Hay 10 tipos de bloques: texto, texto enriquecido, número, booleano, selección, selección múltiple, fecha, tabla, referencia y galería. Los bloques que admiten valores en tiempo de ejecución se convierten en **variables** salvo que los marques como constantes; los bloques de referencia y galería no son variables. Las columnas de tabla también admiten fórmulas para calcular valores de celdas.

Las variables siguen el patrón `{atajo_de_hoja}.{nombre_de_variable}`. Un bloque de Salud en la ficha `mc.jaime` se convierte en `mc.jaime.health`. Cambia ese valor una sola vez y cada flujo que lo comprueba ve la actualización de inmediato.

<img src="/images/docs/sheets-character-current.png" alt="Ficha de personaje de Kael con banner, avatar, campos heredados, bloques numéricos y bloques de selección" loading="lazy">

Las **Tablas** son cuadrículas de hoja de cálculo dentro de una ficha — perfectas para inventarios, árboles de habilidades o matrices de relaciones. Cada celda se convierte en su propia variable. Las **Fórmulas** te permiten calcular valores a partir de otras variables, incluso entre fichas distintas.

Organiza las fichas en una jerarquía de árbol. Usa la **herencia de propiedades** para propagar bloques de fichas padre a hijas — crea una "Base de Personaje" con salud, nivel y facción, y cada personaje hijo hereda esos campos automáticamente, cada uno con sus propios valores.

<img src="/images/docs/sheets/sheets-table.webp" alt="Bloque de tabla de ficha para estadísticas de personaje con columnas de base, modificador y total de fórmula" loading="lazy">

---

## Construye narrativas ramificadas con Flujos

Los **Flujos (Flows)** son grafos visuales de nodos donde tu historia toma forma. Diez tipos de nodos cubren todo:

- **Diálogo** — discurso de personaje con respuestas opcionales del jugador, cada una con sus propias condiciones e instrucciones
- **Condición** — ramifica según valores de variables usando un constructor visual (sin código)
- **Instrucción** — modifica variables cuando el flujo pasa por el nodo
- **Hub y Salto (Jump)** — crea bucles y puntos de convergencia para narrativas no lineales
- **Subflujo (Subflow)** — incrusta flujos reutilizables dentro de otros, con una pila de llamadas completa
- **Secuencia (Sequence)** — agrupa beats narrativos grandes y permite configurar capas visuales y audio
- **Anotación (Annotation)** — deja notas visuales en el lienzo sin afectar a la ejecución
- **Entrada (Entry) y Salida (Exit)** — define dónde empiezan y terminan los flujos, con modos de salida para encadenar flujos

Conecta nodos arrastrando entre puertos. Edita el contenido en el panel lateral. Colabora en tiempo real — ve los cursores de tus compañeros y el bloqueo automático previene ediciones conflictivas.

<img src="/images/docs/flows-editor-current.png" alt="Editor de flujos con un árbol de diálogo de Veilbreak y nodos de diálogo, hub, instrucción, salto, entrada y salida conectados" loading="lazy">

### Prueba sin salir del editor

Aquí es donde Storyarn se destaca. Otras herramientas te obligan a exportar a un motor de juego solo para ver si tu diálogo funciona. Storyarn tiene dos herramientas de prueba integradas:

El **Reproductor de Historia** es una reproducción cinematográfica a pantalla completa. Experimentas tu flujo exactamente como lo haría un jugador — diapositivas de diálogo con avatares de los personajes, opciones de respuesta numeradas, fondos de escena atenuados detrás del texto. Avanza automáticamente a través de condiciones e instrucciones, y se detiene en las decisiones. Cambia al **modo Análisis** para ver respuestas ocultas e insignias de condiciones. Navega hacia atrás en el historial para probar caminos diferentes.

<img src="/images/docs/flows-player-current.png" alt="Reproductor de Historia — diapositiva de diálogo con nombre y avatar del personaje, tres opciones de respuesta numeradas y un fondo de escena atenuado detrás" loading="lazy">

El **Modo Depuración** es tu inspector paso a paso. Avanza nodo por nodo, observa cómo cambian las variables en tiempo real en el panel de Variables, rastrea la ruta de ejecución completa y establece puntos de interrupción. Ajusta los valores de las variables sobre la marcha y vuelve a ejecutar para probar ramas alternativas. Cuatro pestañas — Consola, Variables, Historial y Ruta — te dan visibilidad completa de lo que tu flujo está haciendo y por qué.

<img src="/images/docs/flows-debug-current.png" alt="Modo Depuración mostrando la barra de depuración, las pestañas de ejecución y el nodo de flujo seleccionado" loading="lazy">

---

## Mapea tu mundo con Escenas

Las **Escenas (Scenes)** son mapas interactivos donde tu mundo se vuelve espacial. Sube una imagen de fondo, dibuja zonas poligonales para áreas, coloca pines para personajes y puntos de interés, añade conexiones entre pines y anota con etiquetas de texto.

Las zonas y los pines no son solo visuales — son interactivos. Adjunta **condiciones** para ocultar o deshabilitar elementos según el estado del juego. Adjunta **instrucciones** para modificar variables al hacer clic. Vincúlalos a flujos, fichas u otras escenas.

Haz doble clic en una zona para **profundizar** — Storyarn extrae el área de la zona de la imagen de fondo, crea una escena hija y te permite seguir haciendo zoom. Construye jerarquías de mundo completas: continente > región > ciudad > edificio > habitación.

<img src="/images/docs/scenes-editor-current.png" alt="Editor de escenas mostrando el mapa de Thyral con zonas coloreadas, pines de personajes, etiquetas y herramientas de escena" loading="lazy">

### Modo Exploración

El **Modo Exploración** es donde todo cobra sentido. Recorre tu mundo en una vista inmersiva a pantalla completa. Haz clic en zonas para activar flujos que se superponen sobre el mapa atenuado — tu arte, personajes, diálogos, variables y traducciones funcionando en un solo lugar. Navega entre escenas, ejecuta asignaciones de variables y observa cómo las condiciones actualizan la visibilidad de las zonas en tiempo real.

Ninguna otra herramienta de diseño narrativo hace esto.

<img src="/images/docs/scenes-exploration-current.png" alt="Modo Exploración mostrando el mapa de escena, pines interactivos y controles del jugador" loading="lazy">

---

## Gestiona los recursos

Abre **Recursos (Assets)** desde la barra lateral del proyecto para subir y organizar las imágenes y audios que utiliza tu proyecto. Busca por nombre, filtra por tipo y reutiliza los recursos en fichas, fondos de escenas, secuencias de flujos, diálogos y exportaciones.

<img src="/images/docs/assets-dashboard-current.png" alt="Página de Recursos del proyecto con búsqueda, filtros por tipo y tarjetas de imágenes y audios" loading="lazy">

Al exportar, elige si los recursos se mantienen como referencias, se incrustan en la salida o se empaquetan junto a ella.

---

## Localiza todo

Cuando tu contenido esté listo, las herramientas de **Localización** extraen automáticamente cada texto traducible — líneas de diálogo, acotaciones, texto de menú, etiquetas de fichas y valores de bloques.

Configura la **integración con DeepL** para traducción automática como primer paso. Haz seguimiento del progreso por idioma con informes que muestran conteos de palabras por personaje, estado de traducción y progreso de doblaje.

Exporta traducciones como **Excel** o **CSV** para traductores profesionales. El sistema detecta cambios en el texto fuente y marca automáticamente las traducciones obsoletas para revisión. Storyarn no ofrece actualmente una acción para importar CSV en la interfaz del proyecto, por lo que las traducciones devueltas deben introducirse desde el editor de traducciones.

<img src="/images/docs/localization-overview-current.png" alt="Dashboard de localización con progreso de Catalan, recuentos de palabras por hablante, progreso de doblaje y desglose de contenido" loading="lazy">

---

## Exporta y comparte

Cuando sea hora de publicar, exporta tu proyecto completo o partes individuales:

- **Ink, Yarn, Unity JSON, Godot Dialogic, Unreal CSV, Articy XML** — formatos específicos de motores
- **Excel / CSV** — datos de localización

Elige cómo manejar los recursos: solo referencias, incrustados (Base64) o empaquetados como ZIP con una carpeta de recursos. La validación previa a la exportación, opcional, detecta referencias rotas, nodos inalcanzables y traducciones faltantes antes de que lleguen a tu motor.

---

## Colabora en tiempo real

A lo largo de todo esto, tu equipo trabaja junto. En el editor de flujos, ve quién está en línea con indicadores de presencia, observa los cursores en vivo mientras tus compañeros trabajan y deja que el bloqueo automático de nodos prevenga ediciones conflictivas. Las notificaciones mantienen a todos informados de los cambios.

Los roles mantienen todo organizado — los editores crean contenido, los observadores revisan sin riesgo de cambios accidentales y los propietarios gestionan los ajustes, el tema y las integraciones del proyecto.
