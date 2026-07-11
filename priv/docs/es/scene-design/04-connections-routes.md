%{
title: "Conexiones y rutas",
category_label: "Diseño de Escenas",
order: 4,
description: "Conecta pines con caminos, etiquetas, dirección, estilos de línea, edición de waypoints y rutas de patrulla."
}

---

Las conexiones son líneas de ruta sobre la escena. Úsalas para caminos, enlaces de viaje, rutas de patrulla, rutas comerciales, relaciones, dependencias de misión o cualquier asociación que convenga ver en el mapa.

<img src="/images/docs/scenes-editor-current.png" alt="Editor de mapas con la herramienta de conexión disponible para rutas ancladas y libres" loading="lazy">

## Crear Conexiones

Usa la herramienta de conector desde la barra de escena. Una ruta puede conectar pines, puntos libres del mapa o un pin con un punto libre.

1. Haz clic en el pin o punto del mapa donde empieza la ruta.
2. Haz clic en el pin o punto del mapa donde termina la ruta.
3. Pulsa Escape para cancelar mientras estás dibujando.

Cuando una ruta está anclada a un pin, ese extremo sigue al pin si se mueve. Si haces clic directamente sobre el mapa, ese extremo queda como punto libre y permanece donde lo colocaste. Una ruta no puede conectar un pin consigo mismo.

## Apariencia

Selecciona una conexión para editar su estilo desde la barra flotante.

- **Etiqueta** nombra la ruta o relación.
- **Mostrar etiqueta** controla si el nombre aparece sobre la línea.
- **Color, grosor y estilo de línea** ayudan a separar caminos principales, rutas opcionales y relaciones no físicas.
- **Bidireccional** controla si la conexión tiene flechas en ambos sentidos o solo desde el origen hasta el destino.

## Dirección

| Dirección         | Significado                                                                                                       |
| ----------------- | ----------------------------------------------------------------------------------------------------------------- |
| **Bidireccional** | La ruta o relación funciona en ambos sentidos. Las patrullas pueden recorrerla en cualquiera de los dos sentidos. |
| **Una dirección** | La ruta o relación tiene una sola dirección, desde el primer punto hasta el último punto.                         |

Usa la dirección cuando la conexión deba comunicar intención: un camino de solo ida, una dependencia, el orden de una patrulla o una relación que se lee desde un lado.

## Waypoints

Los waypoints permiten curvar una conexión alrededor de elementos del mapa. Úsalos cuando una ruta deba seguir una carretera, pasillo, costa o camino diseñado en vez de ser una línea recta.

Haz doble clic en una conexión para editar su trazado:

- Haz clic en un punto intermedio para añadir un waypoint.
- Arrastra un waypoint para cambiar la forma de la ruta.
- Ctrl-clic o Cmd-clic sobre un waypoint lo elimina.
- Usa **Enderezar camino** en el panel lateral para dejar la ruta directa. En rutas libres, se conservan los puntos inicial y final.

Una ruta siempre conserva al menos dos puntos. Si la ruta no está anclada a pines, sus extremos libres se mantienen como puntos del recorrido para que la ruta siga siendo válida.

Mantén las rutas legibles. Demasiados waypoints pueden hacer que la edición sea más difícil; usa los necesarios para comunicar el camino y nada más.

## Paradas

Los pines y waypoints de una ruta pueden configurarse como paradas. Úsalas cuando una patrulla deba pausar en un puesto de guardia, checkpoint, puerta, puerto, cruce de caminos o cualquier punto relevante del recorrido.

El panel lateral permite marcar el pin inicial, el pin final y cada waypoint como parada, además de definir la duración de la pausa en cada una. En rutas con extremos libres, esos extremos aparecen como puntos del recorrido y también pueden usarse como paradas.

## Rutas de Patrulla

Las conexiones también pueden definir el camino de un pin no jugable con patrulla activada. La patrulla empieza en ese pin, sigue los puntos conectados en orden de ruta e incluye los waypoints que haya entre pines o puntos libres.

Los waypoints intermedios dan forma al movimiento y también pueden convertirse en paradas.

## Qué no hacen

Las conexiones explican rutas y relaciones en el mapa. No ejecutan instrucciones, no abren flujos y no navegan a escenas por sí solas. Si una ruta debe bloquearse, ocultarse o cambiar de estado durante la exploración, configura esa lógica en los elementos relacionados: condiciones en pines o zonas, y acciones cuando el comportamiento pertenezca a una zona.
