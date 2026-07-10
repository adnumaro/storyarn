%{
title: "Nodos Sequence",
category_label: "Diseño Narrativo",
section_label: "Tipos de nodos",
section_order: 1,
order: 7,
description: "Agrupa nodos relacionados y construye composiciones visuales para el modo Play del flujo."
}

---

Los nodos Sequence son contenedores visuales para partes relacionadas de un flujo. Úsalos para agrupar un beat de escena, sección de conversación, preparación de combate, paso de tutorial o cualquier grupo de nodos que deba leerse como una unidad.

Las sequences también definen contexto de presentación para el Flow Player. Cuando la reproducción llega a un nodo dentro de una sequence, el player puede mostrar las capas visuales de esa sequence detrás del panel de diálogo y reproducir sus pistas de audio.

<img src="/images/docs/flows-editor-current.png" alt="Lienzo de flujo con un nodo Sequence que contiene nodos de diálogo, condición e instrucción" loading="lazy">

## Qué contiene una sequence

Una sequence puede contener otros nodos de flujo. Los nodos internos conservan su comportamiento normal; la sequence les da un límite visual y una superficie de configuración compartida.

Usa sequences para:

- Mantener legibles los grafos grandes.
- Nombrar un beat narrativo.
- Mover un grupo de nodos junto.
- Añadir capas visuales alrededor de un beat.
- Adjuntar pistas de audio a una sección agrupada.

## Presentación en Flow Player

En Flow Player, las sequences funcionan como una composición ligera de escenario. El nodo activo determina su cadena de sequences. Storyarn recoge las capas visuales y pistas de audio de cada sequence padre, después de cada sequence hija, y las renderiza juntas durante la reproducción.

Esto permite montar secuencias visuales sin salir del flujo:

| Tipo de capa  | Uso habitual                                                                                           |
| ------------- | ------------------------------------------------------------------------------------------------------ |
| **Backdrop**  | Imagen principal de fondo para el beat: un interior, campo de batalla, recuerdo o frame de cinemática. |
| **Character** | Arte de personaje colocado sobre el fondo, normalmente a la izquierda, centro o derecha.               |
| **Prop**      | Objetos, pistas, inserts tipo UI o detalles de escena que deben aparecer durante la sequence.          |
| **Overlay**   | Efectos a pantalla completa, iluminación, clima, viñetas o tratamientos de primer plano.               |

La UI de diálogo permanece por encima de la composición. Las capas visuales usan coordenadas normalizadas al viewport del player, así que la misma configuración escala entre tamaños de pantalla.

<img src="/images/docs/flows-player-current.png" alt="Flow Player mostrando un backdrop de sequence con capas de personaje encima y el panel de diálogo delante" loading="lazy">

## Sequences padre e hijas

Las sequences anidadas se componen de fuera hacia dentro. Las capas de la sequence padre se renderizan primero, y las capas de la sequence hija se renderizan por encima.

Úsalo cuando una sección grande tenga una presentación base compartida, pero un beat más pequeño necesite staging adicional:

```text
Sequence de conversación en taberna
  Backdrop: interior de taberna
  Music: tema de taberna

  Sequence hija de revelación secreta
    Overlay: iluminación más oscura
    Character: primer plano del NPC sospechoso
    SFX: cerradura de puerta
```

Cuando la reproducción entra en la sequence hija, el player conserva el contexto padre y añade las capas y pistas específicas de la hija.

## Envolver nodos

Selecciona uno o más nodos y envuélvelos en una sequence cuando formen un beat coherente. Los nodos seleccionados pasan a ser hijos de la nueva sequence.

Evita envolver partes no relacionadas solo porque estén cerca en el lienzo. Una buena sequence tiene un nombre significativo.

## Tamaño y anidación

Los límites de la sequence se adaptan a sus hijos, y el redimensionado manual se restringe para que el contenedor no pueda ser más pequeño que los nodos internos. Las sequences anidadas están soportadas, pero conviene usarlas con moderación.

## Capas visuales y pistas

Las sequences pueden tener capas visuales y pistas de audio. Selecciona una sequence y abre su panel de configuración para añadir capas de imagen o recursos de audio.

Las capas visuales soportan tipo, slot, modo de ajuste, opacidad y posición normalizada. Las capas de personaje tienen slots útiles como izquierda, centro y derecha; las capas de backdrop y overlay usan full-frame cover por defecto.

Las pistas de audio son loops de sequence para **music**, **ambience** y **sfx**. Úsalas para establecer el tono de un beat mientras se reproduce. Según la política del navegador, puede que el audio espere a una interacción del usuario antes de empezar.

Usa capas visuales y pistas cuando un beat agrupado necesite presentación o contexto temporal más rico que la simple organización del grafo.
