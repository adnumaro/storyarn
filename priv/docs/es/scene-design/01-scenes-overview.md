%{
title: "Vista general de Escenas",
category_label: "Diseño de Escenas",
order: 1,
description: "Mapea tu mundo con lienzos espaciales, zonas, pines y conexiones."
}

---

Las Escenas (Scenes) son **lienzos espaciales** para mapear tu mundo de juego. Construidas sobre un lienzo Leaflet.js con soporte completo de desplazamiento, zoom y minimapa, te permiten disponer ubicaciones, definir areas interactivas, dibujar conexiones entre lugares y -- de forma unica -- explorar el resultado como lo haria un jugador.

<div class="docs-alert docs-alert-warning">
  <svg class="docs-alert-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21.73 18-8-14a2 2 0 0 0-3.46 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg>
  <p><strong>Documentación en construcción.</strong> La feature de Escenas está evolucionando activamente. Esta página describe la dirección y las piezas principales, pero algunos detalles de interfaz, acciones y modo de exploración pueden cambiar.</p>
</div>

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El lienzo del editor de escenas mostrando un mapa del mundo con zonas, pines, conexiones y la barra de herramientas inferior
</div>

## Cuando usar Escenas

- **Mapas del mundo** -- disenos de continentes, regiones o ciudades con una imagen de fondo
- **Bocetos de diseno de niveles** -- distribucion de salas con conexiones navegables entre areas
- **Jerarquias de ubicaciones** -- profundiza desde el plano de una taberna hasta habitaciones individuales
- **Mapas de exploracion interactivos** -- areas navegables por el jugador con visibilidad y acciones basadas en variables

## Elementos del lienzo

### Zonas

Las zonas son **regiones poligonales** dibujadas en el lienzo. Los vertices se almacenan como coordenadas porcentuales (0--100) relativas a las dimensiones de la escena, por lo que escalan con cualquier imagen de fondo.

- **Formas** -- dibuja zonas como rectangulos, triangulos, circulos o poligonos libres
- **Estilo** -- color de relleno, color de borde, grosor de borde, estilo de borde (solido, discontinuo, punteado) y opacidad
- **Destinos** -- vincula una zona a un flujo o a otra escena (para navegacion con profundizacion)
- **Acciones** -- `ninguna`, `instruccion` (ejecuta asignaciones de variables al entrar) o `mostrar` (muestra el valor de una variable)
- **Condiciones** -- oculta o deshabilita una zona segun condiciones de variables, usando el mismo constructor de condiciones que los flujos
- **Tooltips** -- texto emergente para contexto adicional
- **Bloqueo** -- bloquea una zona para prevenir ediciones accidentales

### Pines

Los pines son **marcadores de punto** para ubicaciones especificas. Soportan cuatro tipos: `ubicacion`, `personaje`, `evento` y `personalizado`.

- **Tamanos** -- pequeno, mediano o grande
- **Destinos** -- vincula a una ficha, flujo, escena o URL externa
- **Vinculacion con ficha** -- crea un pin directamente desde una ficha (personajes, objetos) para vincularlo automaticamente
- **Acciones y condiciones** -- mismo sistema que las zonas (`instruccion`, `mostrar`, `ocultar`, `deshabilitar`)
- **Iconos personalizados** -- usa cualquier nombre de icono o sube un recurso de icono personalizado
- **Conexiones** -- los pines sirven como extremos para las conexiones de escena

### Conexiones

Las conexiones son **lineas visuales entre dos pines**, representando caminos, rutas o relaciones.

- **Direccion** -- bidireccional (predeterminado) o unidireccional
- **Estilo** -- estilo de linea (solido, discontinuo, punteado), grosor de linea y color
- **Etiquetas** -- etiqueta de texto opcional con alternancia mostrar/ocultar
- **Waypoints** -- anade puntos intermedios para curvar el trazado de una conexion (hasta 50 waypoints)

### Anotaciones

Las anotaciones son **etiquetas de texto** colocadas directamente en el lienzo para notas de diseno, recordatorios o feedback del equipo.

- **Tamanos de fuente** -- pequeno, mediano o grande
- **Colores** -- color de texto personalizable
- **Bloqueo** -- bloquea para prevenir movimientos accidentales

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Vista de cerca de elementos del lienzo: una zona con estilo y tooltip, un pin de personaje vinculado a una ficha, una conexion discontinua con etiqueta y una anotacion
</div>

## Capas

Las escenas soportan multiples **capas** para organizar el contenido. Cada escena comienza con una capa predeterminada.

- **Alternancia de visibilidad** -- muestra u oculta capas de forma independiente para ver diferentes aspectos de la misma escena
- **Asignacion de capa** -- cada zona, pin y anotacion pertenece a una capa
- **{accent}Niebla de guerra{/accent}** -- habilita niebla por capa con color y opacidad personalizables, cubriendo areas inexploradas hasta que el jugador las alcanza

## Herramientas de dibujo

La barra inferior proporciona **10 herramientas** organizadas en grupos:

| Grupo              | Herramientas                          | Proposito                                                    |
| ------------------ | ------------------------------------- | ------------------------------------------------------------ |
| **Navegacion**     | Seleccionar, Desplazar                | Selecciona elementos o desplazate por el lienzo              |
| **Formas de zona** | Rectangulo, Triangulo, Circulo, Libre | Dibuja zonas poligonales en el lienzo                        |
| **Elementos**      | Pin libre, Pin desde ficha            | Coloca marcadores de punto (libres o vinculados a una ficha) |
| **Texto**          | Anotacion                             | Anade notas de texto directamente en el lienzo               |
| **Vinculacion**    | Conector                              | Dibuja conexiones entre dos pines                            |
| **Medicion**       | Regla                                 | Mide distancias entre dos puntos                             |

El editor alterna entre **Modo edicion** (barra visible, elementos editables) y **Modo visualizacion** (solo lectura, lienzo limpio).

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  La barra de herramientas inferior mostrando todos los grupos de herramientas: Seleccionar, Desplazar, desplegable de Formas de zona, desplegable de Pin, Anotacion, Conector y Regla
</div>

## {accent}Profundizacion en zonas{/accent}

Haz doble clic en una zona para **profundizar en ella como una escena hija**. Storyarn automaticamente:

1. Recorta la imagen de fondo de la escena padre al cuadro delimitador de la zona
2. Escala la region recortada a un minimo de 1000px (con nitidez) para que el detalle se preserve incluso a niveles profundos de zoom
3. Crea una nueva escena hija con la imagen extraida como fondo
4. Normaliza los vertices de la zona al espacio de coordenadas de la escena hija

Esto te permite construir **jerarquias de ubicaciones** de forma natural -- un mapa del mundo con zonas de continentes, cada continente profundizando a un mapa regional, cada region a una ciudad, cada ciudad al plano de un edificio. Cada nivel tiene sus propias zonas, pines, conexiones y capas.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Secuencia de profundizacion: mapa del mundo con una zona resaltada, luego la escena hija mostrando la region recortada y escalada con sus propias zonas y pines
</div>

## Acciones y condiciones

Tanto las zonas como los pines soportan **acciones** y **condiciones** que vinculan elementos espaciales con tu sistema de variables.

### Acciones

| Tipo de accion  | Comportamiento                                                                                                                                   |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Ninguna**     | Sin accion (predeterminado)                                                                                                                      |
| **Instruccion** | Ejecuta asignaciones de variables al hacer clic en el elemento. Usa el mismo constructor de asignaciones que los nodos de instruccion de flujos. |
| **Mostrar**     | Muestra el valor actual de una variable en el elemento. Referencia una variable por su ruta completa (p. ej., `mc.jaime.health`).                |

### Condiciones

Adjunta una condicion a cualquier zona o pin usando el constructor de condiciones. Cuando la condicion se evalua como falsa:

- **Ocultar** (predeterminado) -- el elemento se elimina completamente del lienzo
- **Deshabilitar** -- el elemento permanece visible pero no se puede interactuar con el

Esto te permite crear puertas bloqueadas que se desbloquean cuando se activa un flag de mision, NPCs que aparecen solo despues de un evento narrativo, o areas que se vuelven accesibles segun el progreso del jugador.

## {accent}Modo de exploracion{/accent}

**Ninguna otra herramienta de diseno narrativo hace esto.**

El Modo de exploracion es una **experiencia inmersiva a pantalla completa** que te permite navegar tu escena como lo haria un jugador. No es una vista previa -- es una simulacion en vivo de tu narrativa espacial.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Modo de exploracion mostrando el mapa a pantalla completa con zonas interactivas resaltadas, la barra de herramientas superior y la alternancia de visibilidad de zonas
</div>

### Como funciona

1. **Lanza** el Modo de exploracion desde la cabecera de la escena.
2. **Navega** haciendo clic en zonas y pines del mapa. Las condiciones se evaluan en tiempo real -- los elementos ocultos desaparecen, los elementos deshabilitados se muestran en gris.
3. **Ejecuta acciones** -- hacer clic en una zona o pin de instruccion modifica variables inmediatamente. Hacer clic en un elemento de tipo mostrar muestra el valor de la variable.
4. **Lanza flujos** -- hacer clic en una zona o pin vinculado a un flujo abre una **superposicion de dialogo de flujo** sobre el mapa atenuado. El flujo se reproduce en el lugar (sin cambio de URL), incluyendo saltos y retornos entre flujos completos mediante la pila de llamadas del motor.
5. **Navega entre escenas** -- hacer clic en una zona vinculada a otra escena navega a esa escena hija de forma fluida.
6. **El estado de las variables persiste** entre interacciones dentro de la misma sesion de exploracion.
7. **Alterna la visibilidad de zonas** con el boton de la barra de herramientas para ver u ocultar los limites de las zonas.
8. **Controles de teclado** -- usa atajos de teclado para navegar e interactuar.

### Superposicion de flujo

Cuando se lanza un flujo durante la exploracion, el mapa se atenua y el dialogo del flujo aparece como una superposicion. Ves la misma experiencia de reproductor por diapositivas que en el Story Player, con texto de dialogo, informacion del hablante y opciones del jugador. Cuando el flujo termina, vuelves al mapa con cualquier cambio de variables aplicado.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Modo de exploracion con una superposicion de flujo: el mapa esta atenuado en el fondo y una diapositiva de dialogo con opciones del jugador se muestra en el centro
</div>

## Barra de herramientas flotante

Cuando seleccionas un elemento en el lienzo, aparece una **barra de herramientas flotante estilo FigJam** encima de el con controles de edicion rapida especificos para ese tipo de elemento:

- **Zonas** -- color de relleno, opacidad, estilo de borde, color de borde, selector de capa, alternancia de bloqueo, boton de profundizacion
- **Pines** -- etiqueta, selector de tipo de pin, color, tamano, selector de capa, alternancia de bloqueo
- **Conexiones** -- estilo de linea, color, etiqueta, alternancia de direccion
- **Anotaciones** -- texto, tamano de fuente, color, alternancia de bloqueo

Las propiedades avanzadas como destinos, condiciones y acciones se editan en el **panel lateral** que se abre al seleccionar un elemento.

## Exportar

Exporta cualquier escena a formato **PNG** o **SVG** directamente desde la cabecera de la escena. La exportacion captura la vista actual del lienzo incluyendo todas las capas visibles, zonas, pines, conexiones y anotaciones.

## Organizacion de escenas

Como todas las entidades de Storyarn, las escenas soportan una **estructura de arbol** en la barra lateral. Este arbol refleja tanto la organizacion manual como las jerarquias de profundizacion -- las zonas que profundizan en escenas hijas crean relaciones padre-hijo automaticamente.

Cada escena tiene un **shortcut** (p. ej., `world-map`) para referencias cruzadas, y una **escala** opcional con unidad y valor personalizados para la herramienta de regla.
