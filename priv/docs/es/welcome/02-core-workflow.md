%{
title: "Flujo de trabajo principal",
category_label: "Bienvenido",
order: 2,
description: "Cómo cobra vida un proyecto típico en Storyarn."
}

---

Cada equipo utiliza Storyarn de forma diferente, pero a continuación te explicamos cómo suele ser el flujo de un proyecto típico, desde su inicio hasta el lanzamiento.

---

## Prepara tu espacio

Crea un **espacio de trabajo** (workspace) para tu equipo. Cada espacio de trabajo cuenta con sus propios miembros y accesos por rol: los propietarios (owners) lo gestionan todo, los administradores envían invitaciones, los miembros normales crean proyectos y los visores tienen acceso de solo lectura.

Dentro de un espacio de trabajo, crea un **proyecto**. Cada proyecto es autónomo y autosuficiente: tiene sus propias Hojas, Flujos, Escenas, Guiones, Localización y recursos multimedia. Los proyectos también tienen sus propios niveles de pertenencia: los propietarios configuran sus ajustes, los editores crean contenido y los visores revisan.

Invita a tus compañeros por correo electrónico. Recibirán un enlace seguro de acceso y, una vez aceptado, estarán dentro con el rol que hayas asignado.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Panel del espacio de trabajo — tarjetas de proyectos, avatares de los miembros, y el botón de "Nuevo Proyecto"
</div>

---

## Define tu mundo mediante Hojas (Sheets)

Empieza con las **Hojas**: contenedores de datos bien estructurados para todo el mundo del juego. Puedes crear una hoja por cada personaje, objeto, ubicación, facción o misión.

Cada campo dentro de una hoja es un **bloque**. Existen 10 tipos de bloques: texto, texto enriquecido, número, booleano, selección única, selección múltiple, fecha, tabla, fórmula y referencia. A menos que marques un bloque como una **constante**, este se convierte automáticamente en una **variable**, que luego podrás referenciar o llamar desde flujos, condiciones y hasta otras hojas.

Las variables siguen un patrón: `{atajo_de_hoja}.{nombre_variable}`. Por ejemplo, el bloque "Salud" asociado en la hoja de `pj.jaime` se transforma en la variable `pj.jaime.salud`. Así de sencillo. Modifica ese valor una vez y cualquier flujo que dependa de él verá el cambio enseguida.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Editor de tablas — perfil de personaje con bloques de número y selectores, mostrando la insignia con el nombre de cada variable sobre los campos
</div>

Las **Tablas** no son más que cuadrículas incrustadas dentro de una misma hoja — un patrón perfecto para inventarios, árboles de habilidades o matrices de afinidad. Una celda se convierte en su propia variable. Las **Fórmulas** por otro lado, te permiten calcular operaciones matemáticas con todo el resto de variables del juego, incluso si se encuentran cruzadas en diferentes hojas.

Organiza las hojas en árboles de jerarquía. Saca partido a la **Herencia de propiedades** para derramar grandes plantillas de bloques desde padres a hijos — puedes crear un "Personaje Base" con vida, armadura y daño, y por el mero hecho de agrupar al resto de personajes como hijos, todos heredarán esos campos instantáneamente. Y desde luego, cada hijo conservará sus propios números y valores sin mezclar nada.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Hoja con un bloque de tabla — columnas para nombre de ítem, cantidad y daño, con una columna especial que computa en fórmula el DPS total
</div>

---

## Construye relatos ramificados a través de Flujos (Flows)

Los **Flujos** son diagramas de nodos visuales encargados de materializar toda tu lógica relacional. Hay nueve herramientas base distintas para cubrir todas tus necesidades:

- **Diálogo** — Intervenciones puras de personajes con posibilidad interactiva de respuesta para el jugador. Cada rama tiene a su vez sus propias instrucciones y condiciones internas.
- **Condición (Condition)** — Bifurcadores del camino según los valores exactos en los que estén las variables concretas (y todo con un editor 100% visual y sin código).
- **Instrucción (Instruction)** — Modifican las variables indicadas durante la narración cada vez que el "hilo" pasa por encima simulando su lectura en el juego final.
- **Hub y Saltos (Jumps)** — Tejen rutas, ciclos y reencuentros, evitando el caos lógico.
- **Sub-flujo (Subflow)** — Permite que un flujo termine conectando o engullendo todo el trabajo reciclable hecho previamente dentro de otro flujo.
- **Enunciado Escénico (Slug Line)** — Encabezados específicos para sincronizarse perfectamente en integraciones con Guiones estandarizados a película.
- **Entrada y Salida (Entry / Exit)** — Dicen por dónde empieza a ejecutarse un grafo lógico narrativo exacto, controlando de qué manera sale y cómo se encadena de seguir con otro flujo posteriormente.

Conecta nodos de forma intuitiva trazando el recorrido entre terminales, escribe los textos en el panel lateral... y relájate si tienes equipo. Storyarn tiene coautoría online, así que verás los cursores del resto del equipo moverse en vivo. En ningún momento machacarás el contenido del otro, los auto-bloqueos en vivo de grafos evitan accidentes.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Editor de flujos — árbol de diálogo con un nodo inicial, abriendose en decisiones de diálogos, decisiones por bifurcación condición logica e instrucciones para modificar la vida
</div>

### Pruébalo sin tener que escapar del editor

Aquí es donde Storyarn entra en la ventaja. La mayoría de los demás editores fuerzan a los desarrolladores a exportar en seco los datos e incluirlos dentro del motor de juego solo para comprobar si el diálogo se siente coherente. Storyarn elimina ese roce directamente mediante herramientas integradas nativas:

El **Story Player** es exactamente la misma prueba del jugo pero a pantalla completa y emulada. Vivirás el trabajo narrativo como lo experimenta el jugador: líneas con avatares del orador encendidos, respuestas numeradas listas, o los fondos traslúcidos reaccionando. Para más comodidad, el automatismo pasará directo tras detectar cambios invisibles, frenando y pausándose donde haya bifurcación humana necesaria. Existe un atajo para habilitar el "Modo Experto" para revelar temporalmente y sin dolor todas aquellas frases secundarias secretas o candados que a raíz de condiciones complejas se hallan inactivas en el panel en esta jugada (si quieres ser omnipotente).

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Story Player — ventana inmersiva visualizando un globo de texto con la imagen del actor, tres respuestas de botones numerados y un desenfoque apagado con arte de pantalla de ambiente
</div>

El **Modo Debug**, reservado para comprobaciones meticulosas de "código". Recorre los globos de diálogo nodo a nodo prestando absoluta atención a todo detalle de las variables de fondo mientras mutan paralelamente en un panel externo técnico y depurado. Haz trampa, toquetea sin querer de nuevo el atributo variable en vivo sin importarte si las reglas han dictado antes otra constante. Dispondrás de Log general, un histórico secuencial de lo avanzado y trazador en árbol de ruta para entender cualquier malformación subyacente y dar con el fallo de porqué este PNJ no te ha regalado la espada oxidada de una buena vez tras el flujo número dieciocho.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Debug Mode — Visión de la interfaz en modo depuración iluminando en flúor o resaltando lo ejecutado; la consola inferior detallando la tabla de variables tocadas en color distinto
</div>

---

## Mapea el mapa visual mediante Escenas (Scenes)

Sube una ilustración como lienzo interactivo. La función para crear áreas de geometría o la opción de clavar marcadores geográficos son solo utilidades básicas, junto con rutas entre marcadores para crear vías trazadas visuales del punto A hacia el Punto B. O un texto como aclaración geográfica simple en general.

Todos y cada uno de aquellos puntos sobre la Escena visual tampoco son inertes o pura ilustración. Asígnale **condicionalidades lógicas** (Conditions) a cualquier esquina, para ocultarla por desdén durante un suceso u horas avanzadas del juego final. Agrega **instrucciones lógicas directas** sobre un clic. Haz interconexiones transversales y directrices que aterricen hacia Flujos, hojas estáticas o cruces hacia otra Escena por entero.

Haz doble clic al interior de una de las mallas dibujadas superpuestas y prepárate a bucear para crear jerarquías. Extraeremos una sección de alta resolución simulando a Google Maps y permitiéndote un descenso del Continente → Región o zona natural → Ciudad y muros → Posada y Edificio con pisos → Cuarto oscuro.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Editor de Escenas — ilustración aérea central, polígonos translucidos coloreados, alfileres representativos marcando el nombre de individuos en el mapa y capas en la caja de control.
</div>

### Modo Exploración global interactivo

De nuevo lo integrador. Como en los Flujos, activa a toda pantalla el mundo ilustrado de tu escenario gráfico, usa un puntero, simula y siente los impactos superpuestos sobre un plano real en tiempo presente. Activa eventos encubiertos (como de diálogos automáticos y rutas ocultadas previamente que logras encender según has logrado conseguir una espada mágica), mientras navegas en Escenas conectadas a los pasillos del calabozo inferior, comprobando una fidelidad máxima, cruzando las variables generales que han sido cargadas a tus espaldas con sus traducciones.

No, eso tampoco te lo hacen otras alternativas de autor interactivo del mercado visual.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Exploration Mode — Todo el escenario de la escena con un desenfoque y con un pop-up integrado por capas enseñando parte de un nodo en curso
</div>

---

## Escribe la película final vía Guiones

Los **Guiones** devuelven la atención en seco pero efectiva y estructurada de la vieja y nostálgica escuela estricta y analógica. Un texto pulido, libre de ramas lilosas, presentable y listo para repartir por 18 tipos de cabezales literales para la acción teatral: un guionista puro de película y papel. Disfrutando o de texto lineal narrativo simple de guion, de acotación u órdenes de rodaje, de respuestas y bifurcaciones textuales emuladas en jerarquía vertical y visual lineal de diálogo humano.

La sincronización final en este documento formal está de forma oculta en contacto con tus cajas de Flujos 2D de diseño. Toda línea del Guion es un reflejo o un espejo al interior bidireccional sobre tus bloques gráficos... Las modificaciones hechas al guion plano viajan al editor complejo visual interconectando de ramas, y toda interconexión de aristas y cables actualizará y se re-dibujará inteligentemente por un escritor como formato de página limpia en texto llano, permitiendo cruces de libros interconectados al estilo *Elige Tu Propia Aventura*.

De y ahcia Fountain a Final Draft / Highland y otras plataformas líderes en Hollywood para exportar.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Editor Visual de Guion Screenplay — Script puramente literario blanco roto maquetado, mostrando sangrías de acotaciones, personajes centralizados y líneas interactivas incrustadas.
</div>

---

## Localiza y traduce rápido todo tu trabajo

Cuando las tramas de una rama particular estén por concluir y se estabilicen oficialmente terminadas, las herramientas de automatismo para **Localización** capturarán silenciosamente la cadena literal de cada uno de los diálogos sueltos del mapa interno: en anotaciones en guion y directivas del director gráfico, sobre la simple UI del juego interno, los catálogos enumerables, cada panel... Todo.

Engancha y nutre gratuitamente el motor neurálgico de **DeepL interactivo**, permitiendo la primera racha rápida, torpe y de choque mediante traducción IA de todos los párrafos. Forja un **Glosario integral de control** transversal del guion si quieres de todos y cada uno de los términos particulares inventados del folclore (evitando el fallo "espada láser / sable" intermitente y tedioso por parte de cualquier contratado lingüista humano) y analiza barras fluidas a escala mundial progresivas y fraccionadas para medir el logro temporal al traducir textos generales.

Extrae un XLSX o CSV si se contrata un agencia en el extranjero externa al ecosistema de este entorno (y luego reincorpórala sin complicaciones ni traumas visuales u orgánicos, con alertas automatizadas si ha quedado obsoleto al cruzarse en base temporal).

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Traductor Interno — Vista general en un glosario con indicadores visuales radiales y el idioma de control a doble columna (Inglés-Español), marcando en aspas las versiones rotas.
</div>

---

## Exportación formal para desarrolladores e integración vital

Listos. Tu guion relacional está forjado. ¿Cómo llega tu producto interactivo visual y tu base de datos de control unificado a las vísceras matemáticas de tu motor para programación técnica? Con solo unas mecánicas unificadas para el desarrollador:

- **Storyarn base JSON** — Seguridad máxima cruda JSON para importar o de copia integral paralela en local si huye o pierde control el creador principal.
- **Los lenguajes líderes Ink / Yarn Spinner**, plugins JSON de Unity, soporte nativo a Godot por Dialogic y su arquitectura local profunda, estructuras amables por CSV a la Unreal Engine u orientadas al Articy nativo si este también rula internamente en su casa.
- **Fountain formato estándar textual bruto** — Única vía hacia guion PDF formal.
- **Tablas crudas CSV intercontinentales o Excel**.

Tienes opciones pre-análisis. Opta sobre exportados con enlaces limpios que resguarden imágenes e integridad local, base 64 integrada si exiges empaquetar de bulto... Tienes la validación obligatoria "Antes de Vuelo", con cortinillas informáticas que alertan lógicas perdidas huérfanas en hojas y grafos desorientados inaccesibles y sin encadenar por humano o que a estas horas aún claman y se ahogan, vacíos sobre el silencio y falta de un traductor contratado de último momento. Todo queda controlado antes del salto letal al Engine definitivo de mercado.

---

## El centro neurálgico coautor online

Tardarán meses en acabar esta obra. Es algo lógico, vitalicio durante la escritura conjunta. Aquí brilla la arquitectura conectada global interna. Podrás controlar tu ratón con visibilidad directa sobre quienes toquetean una caja en el cuadro visual tuyo. Notificaciones de globo en vivo indicarán un compañero borrando un flujo o acoplando uno mayor; todos los paneles parpadeando por candados temporales que blindarán automáticamente archivos visuales donde un integrante trabaja con afán, protegiendo interconexión sobre sobrescrituras inútiles dolorosas sin conflicto de fusión git manual pesada.

Para culminar y resguardar todavía más sobre intrusismo y negligencia, todo se ata a lo primero visto: Visor (nadie pincha si este rol está encima de tu cabeza, pero puedes merodear libre analizando flujos terminados en la lejanía digital virtual del diagrama general de equipo), o un editor global raso. Los perfiles supremos del proyecto mandan, blindando su temática técnica, plugins integradores e instalando la directriz máxima externa. Todo fluye, a favor de los constructores interactivos.
