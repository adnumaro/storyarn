%{
title: "Análisis estructural",
category_label: "Diseño narrativo",
order: 5,
description: "Hallazgos deterministas sobre la estructura del flow, con evidencia, limitaciones y descarte reversible."
}

---

El análisis estructural inspecciona la **forma del grafo de un flow** e informa de problemas que puede demostrar: entradas ausentes, ramas inalcanzables, callejones sin salida, pins rotos y referencias obsoletas. Cada hallazgo es determinista: el mismo flow produce siempre los mismos hallazgos, calculados solo a partir de tu grafo.

El análisis es una **capacidad gratuita**: no hace ninguna llamada a IA, no consume cuota de IA y funciona incluso con todos los proveedores de IA desactivados.

---

## Ejecutar un análisis

Abre el panel desde el **indicador de salud** en la barra del editor de flows, o ejecuta **Analizar el flow actual** desde la paleta de comandos. Ambos calculan una instantánea fresca de hallazgos del flow actual.

El panel separa los hallazgos en dos categorías:

- **Estructura** — nodos Entry ausentes o duplicados, nodos inalcanzables desde Entry, nodos aislados, callejones sin salida, pins de salida obligatorios sin conectar, conexiones sobre pins eliminados y hubs a los que nada llega.
- **Referencias** — nodos jump, subflow y exit cuyo destino ya no existe o nunca se definió.

Los avisos editoriales (texto de diálogo vacío, condiciones incompletas, speaker ausente) permanecen en el popover de salud de la barra: tratan de completitud del contenido, no de estructura.

## Leer un hallazgo

Al seleccionar un hallazgo verás:

- **Qué se detectó** — el hecho determinista, por ejemplo qué nodo no tiene conexión de salida.
- **Limitaciones** — lo que la regla _no_ demuestra. La alcanzabilidad es topológica: las condiciones no se evalúan, así que un nodo que el análisis considera alcanzable puede seguir siendo inalcanzable al jugar.
- **Evidencia** — los nodos y conexiones que sostienen la conclusión. **Ir a** centra el lienzo en un nodo o resalta la conexión exacta.

## Cuando el flow cambia

La instantánea es explícita. Si la estructura del flow cambia con el panel abierto, el panel marca el análisis como **desactualizado** y ofrece reanalizar: nunca mezcla en silencio resultados antiguos con evidencia nueva.

Un hallazgo desaparece al reanalizar cuando el problema subyacente ya no existe. No hay nada que "marcar como arreglado": la resolución se deriva del grafo.

## Descartar un hallazgo

A veces la detección es correcta pero la estructura es intencionada, o la regla no aplica a cómo funciona tu proyecto. **Descartar hallazgo** registra esa decisión para todo el proyecto, con un motivo obligatorio:

| Motivo                  | Cuándo usarlo                                                              |
| ----------------------- | -------------------------------------------------------------------------- |
| Diseño intencionado     | La estructura existe y es deliberada                                       |
| La regla no aplica aquí | El tipo de flow o las convenciones del proyecto hacen la regla irrelevante |
| Falta contexto          | Algo externo a Storyarn invalida la conclusión                             |
| Detección incorrecta    | La evidencia o la conclusión es errónea para estos datos                   |
| Hallazgo duplicado      | Otro hallazgo ya cubre el mismo problema                                   |
| Otro motivo             | Cualquier otro caso — requiere una nota                                    |

Los descartes son **reversibles** (restáuralos desde la pestaña Descartados), compartidos con todo el proyecto y registrados con quién descartó y por qué. Un descarte aplica a la ocurrencia exacta sobre la que se hizo: si la regla se actualiza o la estructura circundante cambia, el hallazgo se reactiva en el siguiente análisis.

Descartar y restaurar requieren permiso de edición sobre el flow. Los usuarios con rol de lectura pueden abrir el panel, inspeccionar hallazgos y navegar la evidencia, pero no cambiar disposiciones.

## Alcance

El análisis estructural se ejecuta en el editor normal de flows, un flow a la vez. Las vistas compactas y de comparación enlazan de vuelta al editor en lugar de incrustar el panel. El análisis semántico de proyecto completo, la satisfacibilidad de condiciones y la puntuación de calidad narrativa quedan fuera de alcance por diseño.
