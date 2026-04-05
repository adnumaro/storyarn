%{
title: "Visión General de las Escenas",
category_label: "Diseño de Escenas",
order: 1,
description: "Mapea tu mundo con lienzos espaciales, zonas, pines y conexiones."
}

---

Las Escenas son **lienzos espaciales** para mapear tu mundo de juego. Construidas sobre un lienzo de Leaflet.js con soporte completo para pan, zoom y minimapa, te permiten diseñar ubicaciones, definir áreas interactivas, dibujar conexiones entre lugares y —de manera única— explorar el resultado como lo haría un jugador.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El lienzo del editor de escenas mostrando un mapa del mundo con zonas, pines, conexiones y la barra de herramientas inferior
</div>

## Cuándo usar Escenas

- **Mapas del mundo** -- diseños de continentes, regiones o ciudades con una imagen de fondo
- **Diseño de niveles** -- planos de habitaciones con conexiones navegables entre áreas
- **Jerarquías de ubicación** -- desglose desde el plano de una taberna hasta habitaciones individuales
- **Mapas de exploración interactivos** -- áreas navegables por el jugador con visibilidad y acciones controladas por variables

## Elementos del lienzo

### Zonas

Las Zonas son **regiones poligonales** dibujadas en el lienzo. Los vértices se almacenan como coordenadas porcentuales (0--100) relativas a las dimensiones de la escena, por lo que se escalan con cualquier imagen de fondo.

- **Formas** -- dibuja zonas como rectángulos, triángulos, círculos o polígonos libres
- **Estilo** -- color de relleno, color de borde, ancho de borde, estilo de borde (sólido, discontinuo, punteado) y opacidad
- **Objetivos** -- vincula una zona a un flujo u otra escena (para navegación en profundidad o 'drill-down')
- **Acciones** -- `none`, `instruction` (ejecutar asignaciones de variables al entrar) o `display` (mostrar el valor de una variable)
- **Condiciones** -- oculta o deshabilita una zona en base a condiciones de variables, usando el mismo constructor de condiciones que los flujos
- **Tooltips** -- texto dinámico al colocar el cursor encima (hover) para dar mayor contexto
- **Bloqueo** -- bloquea una zona para evitar ediciones accidentales

### Pines

Los Pines son **marcadores de puntos** para ubicaciones específicas. Soportan cuatro tipos: `location`, `character`, `event` y `custom`.

- **Tamaños** -- pequeño, mediano o grande
- **Objetivos** -- enlazan a una hoja, flujo, escena o URL externa
- **Vinculación de hojas** -- crea un pin directamente desde una hoja (personajes, objetos) para enlazarlo automáticamente
- **Acciones y condiciones** -- el mismo sistema que las zonas (`instruction`, `display`, `hide`, `disable`)
- **Iconos personalizados** -- usa cualquier nombre de icono o sube un asset de icono personalizado
- **Conexiones** -- los pines sirven como puntos finales para las conexiones visuales de la escena

### Conexiones

Las Conexiones son **líneas visuales entre dos pines**, que representan caminos, rutas o relaciones.

- **Dirección** -- bidireccional (por defecto) o unidireccional
- **Estilo** -- estilo de línea (sólida, discontinua, punteada), ancho de línea y color
- **Etiquetas** -- texto opcional con interruptor de mostrar/ocultar
- **Puntos intermedios** -- añade puntos intermedios (waypoints) para curvar la ruta de conexión (hasta 50 puntos intermedios)

### Anotaciones

Las Anotaciones son **etiquetas de texto** colocadas directamente en el lienzo para notas de diseño, recordatorios o comentarios del equipo.

- **Tamaños de fuente** -- pequeña, mediana o grande
- **Colores** -- color de texto personalizable
- **Bloqueo** -- bloquea para evitar movimientos accidentales

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Un primer plano de los elementos del lienzo: una zona estilizada con tooltip, un pin de personaje vinculado a una hoja, una conexión discontinua con etiqueta y una anotación
</div>

## Capas

Las Escenas soportan múltiples **capas** para organizar el contenido. Cada escena comienza con una capa por defecto.

- **Alternar visibilidad** -- muestra u oculta capas de forma independiente para visualizar diferentes aspectos de la misma escena
- **Asignación de capas** -- cada zona, pin y anotación pertenece a una capa determinada
- **{accent}Niebla de guerra{/accent}** -- habilita niebla por capa con color y opacidad personalizable, cubriendo áreas sin explorar hasta que el jugador las alcance

## Herramientas de dibujo

El dock inferior proporciona **10 herramientas** organizadas en grupos:

| Grupo           | Herramientas                                  | Propósito                                                |
| --------------- | --------------------------------------------- | -------------------------------------------------------- |
| **Navegación**  | Seleccionar, Pan (Desplazar)                  | Seleccionar elementos o desplazarse por el lienzo        |
| **Formas**      | Rectángulo, Triángulo, Círculo, Forma libre   | Dibujar zonas poligonales en el lienzo                   |
| **Elementos**   | Pin libre, Pin desde hoja                     | Colocar marcadores fijos (libres o desde una hoja)       |
| **Texto**       | Anotación                                     | Añadir notas de texto directamente en el lienzo          |
| **Enlaces**     | Conector                                      | Dibujar líneas entre dos pines para definir trayectos    |
| **Medición**    | Regla                                         | Medir distancias de punto a punto                        |

El editor conmuta entre **Modo Edición** (dock visible, elementos alterables) y **Modo Vista** (solo lectura, lienzo limpio).

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  La barra de herramientas del dock inferior muestra todos los grupos de herramientas: Seleccionar, Desplazar, desplegable de formas, desplegable de pines, Anotación, Conector y Regla
</div>

## {accent}Inspección de zonas (Drill-down){/accent}

Haz doble clic en una zona para **explorarla internamente como una escena secundaria**. Storyarn hace lo siguiente automáticamente:

1. Recorta la imagen de fondo de la escena principal al tamaño de los límites o delimitadores de la zona
2. Amplía (o interpola) esa región recortada a un mínimo de 1000px (conservando nitidez) para que el detalle sobreviva al zoom
3. Crea la nueva escena anidada (child scene) usando ese recorte como fondo principal
4. Normaliza los vértices de la zona dentro del espacio de coordenadas de esa nueva escena secundaria

Esto genera **jerarquías** y niveles naturales— un mapa global se ramifica en zonas continentales, y al seleccionarlas entras a la provincia, luego a la ciudad, luego de la ciudad a un edificio o interior. Cada uno poseyendo una estructura independiente con sus propios pines y capas.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Secuencia de drill-down: mapamundi general, zona resaltada y transición directa al mapa local interior resultante.
</div>

## Acciones y condiciones

Tanto zonas como pines aceptan **acciones** y **condiciones**, entrelazando factores espaciales con tu sistema de variables lógicas.

### Acciones

| Tipo de acción  | Comportamiento                                                                                                              |
| --------------- | --------------------------------------------------------------------------------------------------------------------------- |
| **None**        | Ninguna acción ejecutada (por defecto)                                                                                      |
| **Instruction** | Ejecuta asignaciones de valores al impactar con el elemento. Emplea la misma lógica de "Action Builder" vista en los flujos.|
| **Display**     | Dibuja el estado del valor solicitado directamente por referencia de senda, (p.ej., `personaje.moisés.vida`).               |

### Condiciones

Aplica lógicas al pin/zona bajo las mismas reglas condicionales de flujo. Al reprobar (dar falso):

- **Ocultar** (por defecto) -- la propia identidad del ítem o zona será borrada íntegramente
- **Deshabilitar** -- prevalece visible de manera tenue pero rechaza las interacciones lúdicas

Esta función construye escenarios donde ciertos candados visuales, murallas evaluadoras u ocultadores reaccionan conforme juegues (p. ej., gruta indetectable sin iluminar variables puras previas).

## {accent}Modo Exploración{/accent}

**Ningún mecanismo de diseño en todo el medio lo hace igual.**

Experimenta usando **el Modo Explorador inmersivo y a pantalla completa**. Permítele interactuar contigo como un producto de videojuego total final. Sin configuraciones extra de vistas o previas. Simulando lo narrativo en vida plena.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El visor central indicando botones superiores junto al encendido/apagado formalizador del esquema delimitador de cuadrículas invisibles en el juego.
</div>

### Cómo opera internamente

1. **Inicia** presionando Play con su símbolo correspondiente del escenario primario.
2. **Navega**: pulsa donde creas pertinente según lo trazado. Condicionantes reales se actualizarán y verás todo variar on-the-fly.
3. **Acciones directas**: Un tap sobre áreas instructoras o expositivas causan sumas automáticas, mostrando data mutante sin pausa en tu pantalla.
4. **Flujos anidados**: Pulsa en sitios entrelazados con líneas de diálogos interactivos formales. Oscurecerá sin re-generar nada y aparecerá flotante todo el peso de menús, retornando posteriormente intacto sin alterar un frame de tus ventanas web originarias.
5. **Navega Escenas**: Hacer clic en una zona vinculada a otra escena navega a esa escena secundaria sin interrupciones.
6. **Variables Resilientes**: Los estados se mantienen durante toda la exploración de la sesión.
7. **Visibilidad Zonal**: Usando sus botones, disuelve e ignora trazados estáticos hasta confirmar exactitud artística ideal de juego libre sin líneas superpuestas de diseño.
8. **Asistentes de mando**: Aprovecha hotkeys en vez del cursor ratonil para mover opciones ágiles de testing acelerado.

### Sobreponer diálogos y fluidez

Dentro de visualizaciones escenificadas, se acatan flujos sin pérdida. Cajas parlantes emergerán como en tu "Story Player" con opciones del usuario. Terminado, un cierre retornará sus focos del mapa en reposo sumado a efectos guardados.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Un render visual que conjuga oscurecidos con ventanajes interactores flotados durante intercesiones.
</div>

## Menú Suspendido (Flotante)

Tocar atributos evoca comandos relacionales estáticos tipo un cuadro aéreo "FigJam":

- **Zonas** -- tintes plenos, nivel translúcido, márgenes, selector-escala o candado general, más inspecciones descendientes.
- **Pines/Anclas** -- títulos identificadores fijos, clavijas o iconografías, medidas y cierres generalizados por color o base inmovilizadora.
- **Lazos de Unión** -- matizaciones rayado cruzado ancho, nombres optativos o candado direccional biplaza o único.
- **Notas de Post** -- tamaños legibilidad paleta central protecciones anti-fugas.

Todos los condicionamientos absolutos radicarán centralizados al abrir barras laterales (side panel) del editor matriz.

## Extraer Imágenes

Retira toda composición escénica a **PNG** o **SVG** bajo la cabecilla de comando pertinente en tus mandos del escenario cabecero capturando totalidades vectoriales purificantes.

## Categorización Múltiple de Escenas

Similares parámetros atañen estas carpetas globales al árbol directivo originario principal, registrando manualidades e inspectores en nidos lógicos "Jerárquicos Parentales-Derivados".
Adueñado de "Claves Racionales" (`mapamundi-completo`) agiliza las intercomunicaciones referenciadoras sumando opcionales coeficientes multiplicadores en regletas si optases por usos rigurosos o métricas para sus barras herramientas.
