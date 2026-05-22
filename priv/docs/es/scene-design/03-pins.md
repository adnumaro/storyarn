%{
title: "Pines",
category_label: "Diseño de Escenas",
order: 3,
description: "Coloca marcadores puntuales para personajes, ubicaciones, eventos, fichas, flujos, escenas y referencias externas."
}

---

Los pines son marcadores puntuales colocados sobre una escena. Úsalos para ubicaciones exactas: posición de un personaje, objeto de misión, punto de viaje, lugar importante, evento o nota personalizada.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Escena con pines de ubicación, personaje, evento y personalizado usando colores y tamaños distintos
</div>

## Tipos de pin

| Tipo | Uso típico |
| ---- | ---------- |
| **Location** | Lugares, puertas, salidas, etiquetas de mapa |
| **Character** | NPCs, miembros del grupo, enemigos, encuentros sociales |
| **Event** | Eventos temporales, beats de misión, triggers |
| **Custom** | Marcadores propios del proyecto |

## Crear pines

Crea un pin libre desde la barra inferior, o crea un pin desde una ficha cuando el marcador deba representar un personaje, objeto, ubicación u otra entidad ya existente.

Los pines vinculados a fichas ayudan a mantener el mapa conectado con los datos del mundo.

## Targets

Los pines pueden enlazar a:

- Una ficha
- Un flujo
- Otra escena
- Una URL externa

## Apariencia

Los pines pueden definir etiqueta, tipo, tamaño, color, icono, asset de icono, capa y bloqueo. Usa tamaño y color de forma consistente para que el mapa se pueda leer sin abrir cada pin.

## Comportamiento en runtime

Como las zonas, los pines pueden usar acciones y condiciones: lanzar flujos, mostrar variables, ejecutar instrucciones, ocultarse hasta que una condición sea verdadera o aparecer deshabilitados.
