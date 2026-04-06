%{
title: "Flujo de trabajo principal",
category_label: "Bienvenida",
order: 2,
description: "Cómo se desarrolla un proyecto típico en Storyarn."
}

---

Cada equipo usa Storyarn de forma diferente, pero así es como un proyecto típico avanza desde la configuración hasta la entrega.

---

## Configura tu espacio

Crea un **espacio de trabajo (workspace)** para tu equipo. Cada espacio de trabajo tiene sus propios miembros con acceso basado en roles — los propietarios gestionan todo, los administradores manejan las invitaciones, los miembros crean proyectos y los observadores tienen acceso de solo lectura.

Dentro de un espacio de trabajo, crea un **proyecto**. Cada proyecto es independiente — con sus propias fichas, flujos, escenas, guiones, localización y recursos. Los proyectos también tienen su propia membresía: los propietarios configuran los ajustes, los editores crean contenido y los observadores revisan.

Invita a compañeros de equipo por email. Reciben un enlace con token, lo aceptan, y ya están dentro — con el rol que elegiste.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Panel del espacio de trabajo — tarjetas de proyectos, avatares de miembros y el botón "Nuevo proyecto"
</div>

---

## Define tu mundo con Fichas

Empieza con las **Fichas (Sheets)** — contenedores de datos estructurados para todo el mundo de tu juego. Crea una ficha para cada personaje, objeto, ubicación, facción o misión.

Cada campo en una ficha es un **bloque (block)**. Hay 10 tipos de bloques: texto, texto enriquecido, número, booleano, selección, selección múltiple, fecha, tabla, fórmula y referencia. A menos que marques un bloque como **constante**, se convierte automáticamente en una **variable** — referenciable desde flujos, condiciones y otras fichas.

Las variables siguen el patrón `{atajo_de_hoja}.{nombre_de_variable}`. Un bloque de Salud en la ficha `mc.jaime` se convierte en `mc.jaime.health`. Cambia ese valor una sola vez y cada flujo que lo comprueba ve la actualización de inmediato.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Editor de fichas — perfil de personaje con bloques de número y selección, mostrando la insignia del nombre de variable en cada campo
</div>

Las **Tablas** son cuadrículas de hoja de cálculo dentro de una ficha — perfectas para inventarios, árboles de habilidades o matrices de relaciones. Cada celda se convierte en su propia variable. Las **Fórmulas** te permiten calcular valores a partir de otras variables, incluso entre fichas distintas.

Organiza las fichas en una jerarquía de árbol. Usa la **herencia de propiedades** para propagar bloques de fichas padre a hijas — crea una "Base de Personaje" con salud, nivel y facción, y cada personaje hijo hereda esos campos automáticamente, cada uno con sus propios valores.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Hoja con un bloque de tabla — columnas para nombre del objeto, cantidad y daño, con una columna de fórmula calculando el DPS total
</div>

---

## Construye narrativas ramificadas con Flujos

Los **Flujos (Flows)** son grafos visuales de nodos donde tu historia toma forma. Nueve tipos de nodos cubren todo:

- **Diálogo** — discurso de personaje con respuestas opcionales del jugador, cada una con sus propias condiciones e instrucciones
- **Condición** — ramifica según valores de variables usando un constructor visual (sin código)
- **Instrucción** — modifica variables cuando el flujo pasa por el nodo
- **Hub y Salto (Jump)** — crea bucles y puntos de convergencia para narrativas no lineales
- **Subflujo (Subflow)** — incrusta flujos reutilizables dentro de otros, con una pila de llamadas completa
- **Encabezado de escena (Slug Line)** — encabezados de escena para integración con guiones
- **Entrada (Entry) y Salida (Exit)** — define dónde empiezan y terminan los flujos, con modos de salida para encadenar flujos

Conecta nodos arrastrando entre puertos. Edita el contenido en el panel lateral. Colabora en tiempo real — ve los cursores de tus compañeros y el bloqueo automático previene ediciones conflictivas.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Editor de flujos — árbol de diálogo con un nodo de Entrada ramificándose a través de nodos de Diálogo, Condición (verdadero/falso) e Instrucción hasta dos nodos de Salida
</div>

### Prueba sin salir del editor

Aquí es donde Storyarn se destaca. Otras herramientas te obligan a exportar a un motor de juego solo para ver si tu diálogo funciona. Storyarn tiene dos herramientas de prueba integradas:

El **Reproductor de Historia** es una reproducción cinematográfica a pantalla completa. Experimentas tu flujo exactamente como lo haría un jugador — diapositivas de diálogo con avatares de los personajes, opciones de respuesta numeradas, fondos de escena atenuados detrás del texto. Avanza automáticamente a través de condiciones e instrucciones, y se detiene en las decisiones. Cambia al **modo Análisis** para ver respuestas ocultas e insignias de condiciones. Navega hacia atrás en el historial para probar caminos diferentes.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Reproductor de Historia — diapositiva de diálogo con nombre y avatar del personaje, tres opciones de respuesta numeradas y un fondo de escena atenuado detrás
</div>

El **Modo Depuración** es tu inspector paso a paso. Avanza nodo por nodo, observa cómo cambian las variables en tiempo real en el panel de Variables, rastrea la ruta de ejecución completa y establece puntos de interrupción. Ajusta los valores de las variables sobre la marcha y vuelve a ejecutar para probar ramas alternativas. Cuatro pestañas — Consola, Variables, Historial y Ruta — te dan visibilidad completa de lo que tu flujo está haciendo y por qué.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Modo Depuración — lienzo del flujo con un nodo activo resaltado y el panel de depuración debajo mostrando la pestaña de Variables con valores actuales y un valor modificado resaltado
</div>

---

## Mapea tu mundo con Escenas

Las **Escenas (Scenes)** son mapas interactivos donde tu mundo se vuelve espacial. Sube una imagen de fondo, dibuja zonas poligonales para áreas, coloca pines para personajes y puntos de interés, añade conexiones entre pines y anota con etiquetas de texto.

Las zonas y los pines no son solo visuales — son interactivos. Adjunta **condiciones** para ocultar o deshabilitar elementos según el estado del juego. Adjunta **instrucciones** para modificar variables al hacer clic. Vincúlalos a flujos, fichas u otras escenas.

Haz doble clic en una zona para **profundizar** — Storyarn extrae el área de la zona de la imagen de fondo, crea una escena hija y te permite seguir haciendo zoom. Construye jerarquías de mundo completas: continente > región > ciudad > edificio > habitación.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Editor de escenas — mapa de fantasía de fondo con zonas coloreadas para regiones, pines de personajes con etiquetas y el panel de capas a la izquierda
</div>

### Modo Exploración

El **Modo Exploración** es donde todo cobra sentido. Recorre tu mundo en una vista inmersiva a pantalla completa. Haz clic en zonas para activar flujos que se superponen sobre el mapa atenuado — tu arte, personajes, diálogos, variables y traducciones funcionando en un solo lugar. Navega entre escenas, ejecuta asignaciones de variables y observa cómo las condiciones actualizan la visibilidad de las zonas en tiempo real.

Ninguna otra herramienta de diseño narrativo hace esto.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Modo Exploración — mapa de escena atenuado con una superposición de diálogo de flujo mostrando texto del personaje y opciones de respuesta sobre el mundo
</div>

---

## Escribe guiones con Guiones

Los **Guiones (Screenplays)** llevan tu narrativa al formato de guion estándar de la industria. Un editor basado en bloques con 18 tipos de elementos — desde encabezados de escena y diálogos hasta condiciones interactivas, instrucciones y respuestas ramificadas.

Los guiones **se sincronizan bidireccionalmente con los flujos**. Empuja cambios del guion al flujo, o tira actualizaciones del flujo al guion. Las opciones de respuesta se ramifican en **páginas vinculadas** — guiones hijos que reflejan la estructura ramificada de tu flujo.

Exporta a formato **Fountain** para Final Draft, Highland o cualquier herramienta de escritura de guiones compatible. Importa archivos Fountain para traer guiones existentes a Storyarn.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Editor de guiones — guion formateado con encabezado de escena, nombre de personaje, bloque de diálogo y un elemento de respuesta con opciones ramificadas
</div>

---

## Localiza todo

Cuando tu contenido esté listo, las herramientas de **Localización** extraen automáticamente cada texto traducible — líneas de diálogo, acotaciones, texto de menú, etiquetas de fichas y valores de bloques.

Configura la **integración con DeepL** para traducción automática como primer paso. Mantén un **glosario** para terminología consistente entre idiomas (nombres de personajes, términos del juego, nombres propios). Haz seguimiento del progreso por idioma con informes que muestran conteos de palabras por personaje, estado de traducción y progreso de doblaje.

Exporta traducciones como **Excel** o **CSV** para traductores profesionales. Impórtalas de vuelta cuando estén listas. El sistema detecta cambios en el texto fuente y marca automáticamente las traducciones obsoletas para revisión.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Localización — lista de idiomas con barras de progreso y el editor de traducción mostrando el texto fuente junto a la versión traducida
</div>

---

## Exporta y comparte

Cuando sea hora de publicar, exporta tu proyecto completo o partes individuales:

- **Storyarn JSON** — copia de seguridad completa del proyecto, reimportable
- **Ink, Yarn, Unity JSON, Godot Dialogic, Unreal CSV, Articy XML** — formatos específicos de motores
- **Fountain** — exportación de guion
- **Excel / CSV** — datos de localización

Elige cómo manejar los recursos: solo referencias, incrustados (Base64) o empaquetados como ZIP con una carpeta de recursos. La validación previa a la exportación, opcional, detecta referencias rotas, nodos inalcanzables y traducciones faltantes antes de que lleguen a tu motor.

---

## Colabora en tiempo real

A lo largo de todo esto, tu equipo trabaja junto. En el editor de flujos, ve quién está en línea con indicadores de presencia, observa los cursores en vivo mientras tus compañeros trabajan y deja que el bloqueo automático de nodos prevenga ediciones conflictivas. Las notificaciones mantienen a todos informados de los cambios.

Los roles mantienen todo organizado — los editores crean contenido, los observadores revisan sin riesgo de cambios accidentales y los propietarios gestionan los ajustes, el tema y las integraciones del proyecto.
