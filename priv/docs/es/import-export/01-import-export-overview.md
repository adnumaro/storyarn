%{
title: "Exportar",
category_label: "Exportar",
order: 1,
description: "Lleva tu contenido de Storyarn a formatos compatibles con los principales motores de juego."
}

---

Storyarn puede exportar tu contenido narrativo a {accent}6 formatos{/accent} que cubren los principales motores de juego y sistemas de dialogo. Ya sea que trabajes con Unity, Unreal, Godot, o uses Ink o Yarn Spinner como runtime, Storyarn tiene un serializador listo para tu pipeline.

## Formatos de exportacion

| Formato                   | Extension | Motor / Herramienta             | Contenido soportado |
| ------------------------- | --------- | ------------------------------- | ------------------- |
| **Ink**                   | `.ink`    | Runtime Ink de Inkle            | Flujos, Fichas      |
| **Yarn Spinner**          | `.yarn`   | Yarn Spinner (Unity, Godot)     | Flujos, Fichas      |
| **Unity Dialogue System** | `.json`   | Unity (Pixel Crushers, etc.)    | Flujos, Fichas      |
| **Godot Dialogic**        | `.dtl`    | Plugin Dialogic para Godot 4    | Flujos, Fichas      |
| **Unreal Engine**         | `.csv`    | Unreal Engine (Data Tables)     | Flujos, Fichas      |
| **articy:draft**          | `.xml`    | Importacion XML de articy:draft | Flujos, Fichas      |

Los formatos de motor se centran en flujos y fichas, que es lo que los runtimes de juego necesitan para dialogos, ramas y estado de variables. Las escenas y la localizacion tienen herramientas propias dentro de sus areas de trabajo cuando necesitas preparar contenido espacial o traducciones.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  La pagina de exportacion mostrando el selector de formato, casillas de seleccion de contenido y opciones de modo de recursos
</div>

## Como exportar

1. Navega a **Exportar** desde la barra lateral de tu proyecto.
2. **Elige un formato** -- Selecciona entre los formatos disponibles. Las casillas de contenido se actualizan para mostrar que secciones soporta ese formato.
3. **Selecciona secciones de contenido** -- Marca o desmarca Fichas, Flujos, Escenas y Localizacion. Las secciones no soportadas por el formato seleccionado se deshabilitan.
4. **Elige el modo de recursos** -- Controla como se gestionan los archivos de recursos (imagenes, audio):

| Modo de recursos     | Comportamiento                                                                                 |
| -------------------- | ---------------------------------------------------------------------------------------------- |
| **Solo referencias** | Las URLs de recursos se incluyen en la salida (predeterminado, archivo mas pequeno)            |
| **Incrustados**      | Los recursos se codifican en Base64 en linea (archivo mas grande, completamente autocontenido) |
| **Empaquetados**     | La salida es un archivo ZIP con una carpeta de recursos junto al archivo de datos              |

5. **Configura opciones** -- Activa "Validar antes de exportar" y "Formato legible de salida" segun necesites.
6. **Descargar** -- Haz clic en el boton de descarga para obtener tu archivo.

## Validacion pre-exportacion

Antes de descargar, puedes ejecutar la validacion para detectar problemas que causarian errores en tu juego. Haz clic en **Validar** para comprobar tu proyecto. El validador ejecuta 9 comprobaciones y reporta hallazgos en tres niveles de severidad:

**Errores** (probablemente rompan tu juego):

- Flujos sin nodo de Entrada
- Referencias rotas: nodos de salto apuntando a hubs inexistentes y nodos de subflujo referenciando flujos eliminados

**Advertencias** (problemas potenciales):

- Nodos huerfanos sin conexiones
- Nodos inalcanzables (no alcanzables desde la Entrada via recorrido BFS)
- Nodos de dialogo vacios (sin contenido de texto)
- Nodos de dialogo sin hablante asignado
- Cadenas de referencia circular de subflujos (A referencia B referencia A)
- Traducciones faltantes para idiomas configurados

**Informacion** (vale la pena saber):

- Fichas huerfanas sin referencias desde ningun flujo o escena

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Resultados de validacion mostrando una mezcla de errores (referencias rotas), advertencias (nodos huerfanos, dialogos vacios) e informacion (fichas sin referencias)
</div>

## Otras vias de exportacion

Mas alla de la pagina principal de Exportar, Storyarn ofrece funciones de exportacion especializadas en otras areas:

**Exportacion de localizacion** -- Desde la pagina de Localizacion, exporta traducciones como Excel (.xlsx) o CSV filtrado por idioma. Importa archivos CSV traducidos de vuelta con emparejamiento por ID. Consulta la [Vista general de Localizacion](/docs/localization/localization-overview) para mas detalles.
