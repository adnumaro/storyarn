%{
title: "Pines",
category_label: "Diseño de Escenas",
order: 3,
description: "Coloca marcadores puntuales para personajes, ubicaciones, eventos, fichas, flujos, personajes jugables y patrullas."
}

---

Los pines son marcadores puntuales colocados sobre una escena. Úsalos para señalar posiciones exactas: un personaje, una entrada, un objeto de misión, un punto de interés, un evento o una referencia personalizada.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Escena con pines de ubicación, personaje y evento, con un pin jugable y una ruta de patrulla
</div>

## Tipos de pin

| Tipo              | Uso típico                                              |
| ----------------- | ------------------------------------------------------- |
| **Ubicación**     | Lugares, puertas, salidas, etiquetas de mapa            |
| **Personaje**     | NPCs, miembros del grupo, enemigos, encuentros sociales |
| **Evento**        | Eventos temporales, beats de misión, triggers           |
| **Personalizado** | Marcadores propios del proyecto                         |

El tipo ayuda a leer el mapa y cambia el icono por defecto, pero no decide por sí solo qué ocurre en exploración.

## Crear pines

Crea un pin libre desde la barra inferior, o crea un pin desde una ficha cuando el marcador deba representar un personaje, objeto, ubicación u otra entidad ya existente.

Los pines vinculados a fichas mantienen la escena conectada con los datos del mundo. Si la ficha tiene avatar, el pin puede usarlo como imagen; si no, Storyarn muestra una marca visual simple para que el elemento siga siendo reconocible.

## Visual

La apariencia básica del pin se edita desde la barra del elemento:

- **Etiqueta** para nombrarlo en el mapa.
- **Tipo** para diferenciar ubicación, personaje, evento o marcador propio.
- **Color, opacidad y tamaño** para dar jerarquía visual.
- **Capa** para organizar visibilidad junto al resto de la escena.
- **Bloqueo** para evitar cambios accidentales.

En el panel lateral, la pestaña **Visual** permite asociar una ficha y subir un icono propio. Usa iconos ligeros en SVG, PNG o GIF cuando quieras que el pin represente una pieza concreta de la interfaz o del mundo.

## Comportamiento

La pestaña **Comportamiento** controla qué hace el pin en modo exploración.

- **Flujo** asigna un flujo que se abre encima de la escena al hacer clic en el pin.
- **Personaje jugable** convierte el pin en parte del grupo controlable.
- **Líder del grupo** marca cuál de los pines jugables recibe el movimiento principal.
- **Patrulla** permite que un pin no jugable se mueva siguiendo conexiones entre pines.

Un pin sin flujo puede seguir siendo útil como marcador visual, personaje jugable o patrulla, pero no actúa como punto clicable de diálogo en exploración.

## Reglas

La pestaña **Reglas** controla cuándo aparece o queda bloqueado el pin durante la exploración.

- **Oculto en exploración** oculta el pin en modo exploración, pero lo mantiene visible en el editor para poder seguir trabajando con él.
- **Condición** usa el [Editor de Condiciones](/docs/narrative-design/condition-editor) compartido.
- **Ocultar** oculta el pin cuando la condición no se cumple.
- **Desactivar** mantiene el pin visible, pero bloquea su interacción.

Usa estas reglas para NPCs que aparecen más tarde, puntos de interés desbloqueables, personajes temporalmente no disponibles o rutas que dependen del estado de la partida.

## Ajustes

La pestaña **Ajustes** reúne los datos de apoyo:

- **Atajo**, cuando existe, sirve para referenciar el pin desde condiciones e instrucciones.
- **Tooltip** muestra una ayuda breve al pasar por encima del pin.

## Cuándo usar pines y cuándo usar zonas

Usa pines para elementos puntuales: personajes, puertas, objetos, marcadores y puntos de ruta. Usa zonas cuando necesites un área: una región clicable, una zona transitable, una colección, una visualización de variable o una superficie con forma propia.
