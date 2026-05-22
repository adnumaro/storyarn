%{
title: "Nodos de Entrada y Salida",
category_label: "Diseño Narrativo",
section_label: "Tipos de nodos",
section_order: 1,
order: 1,
description: "Dónde empieza un flujo, cómo termina y cómo sus resultados conectan estructuras narrativas mayores."
}

---

Los nodos de Entrada y Salida definen los límites de un flujo. Son simples en el lienzo, pero son importantes porque deciden cómo empieza un flujo, cuándo termina y cómo otros flujos pueden llamarlo o volver desde él.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Lienzo de flujo con el nodo de Entrada conectado a una rama corta y varios nodos de Salida con etiquetas de resultado
</div>

## Nodos de Entrada

Cada flujo tiene un nodo de Entrada. Se crea con el flujo y no se puede eliminar. La ejecución empieza aquí cuando reproduces el flujo, lo depuras o entras en él desde un nodo Subflow.

Los nodos de Entrada son principalmente estructurales. Úsalos como primer punto de conexión del flujo y ramifica desde ahí hacia el primer diálogo, condición, secuencia o instrucción.

## Nodos de Salida

Los nodos de Salida marcan dónde termina un camino. Un flujo puede tener una salida o muchas, según cuánta información de resultado necesites exponer.

| Caso | Configuración de salida |
| ---- | ----------------------- |
| Una conversación simple termina | Una salida terminal |
| Una rama de misión tiene éxito o falla | Salidas separadas como `accepted`, `declined`, `completed` |
| Un subflujo reutilizable vuelve al flujo padre | Salidas configuradas para volver al llamador |
| Un flujo entrega la ejecución a otro flujo | Salida configurada para continuar a otro flujo |

## Modos de salida

| Modo | Comportamiento |
| ---- | -------------- |
| **Terminal** | Termina la ejecución actual. |
| **Continuar a flujo** | Entra en otro flujo después de terminar este camino. |
| **Volver al llamador** | Vuelve al flujo padre que entró mediante un nodo Subflow. |

## Etiquetas de resultado

Las etiquetas de resultado describen qué ha ocurrido en ese camino. Hacen que las salidas sean más legibles en el lienzo y dan pines de salida significativos a los flujos que usan este flujo como Subflow.

```text
accepted
refused
needs_payment
failed_check
```

## Patrón práctico

Para flujos pequeños, una salida terminal suele bastar. Para flujos reutilizables, define salidas alrededor de las decisiones que le importan al flujo llamador. Evita crear salidas para detalles internos que ningún flujo padre necesita conocer.
