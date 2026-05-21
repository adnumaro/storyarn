%{
title: "Importar y Exportar",
category_label: "Importar y Exportar",
order: 1,
description: "Lleva tu contenido dentro y fuera de Storyarn en formatos compatibles con los principales motores de juego."
}

---

Storyarn puede exportar tu contenido narrativo a {accent}7 formatos{/accent} que cubren todos los principales motores de juego y sistemas de dialogo. Ya sea que trabajes con Unity, Unreal, Godot, o uses Ink o Yarn Spinner como runtime, Storyarn tiene un serializador listo para tu pipeline.

## Formatos de exportacion

| Formato                   | Extension | Motor / Herramienta                    | Contenido soportado                                      |
| ------------------------- | --------- | -------------------------------------- | -------------------------------------------------------- |
| **Storyarn JSON**         | `.json`   | Storyarn (copia de seguridad completa) | Fichas, Flujos, Escenas, Guiones, Localizacion, Recursos |
| **Ink**                   | `.ink`    | Runtime Ink de Inkle                   | Flujos, Fichas                                           |
| **Yarn Spinner**          | `.yarn`   | Yarn Spinner (Unity, Godot)            | Flujos, Fichas                                           |
| **Unity Dialogue System** | `.json`   | Unity (Pixel Crushers, etc.)           | Flujos, Fichas                                           |
| **Godot Dialogic**        | `.dtl`    | Plugin Dialogic para Godot 4           | Flujos, Fichas                                           |
| **Unreal Engine**         | `.csv`    | Unreal Engine (Data Tables)            | Flujos, Fichas                                           |
| **articy:draft**          | `.xml`    | Importacion XML de articy:draft        | Flujos, Fichas                                           |

El formato {accent}Storyarn JSON{/accent} es el unico que soporta el proyecto completo -- todos los tipos de entidad incluyendo escenas, guiones y datos de localizacion. Los formatos especificos de motor se centran en flujos y fichas, que es lo que los runtimes de juego necesitan para dialogos y estado de variables.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  La pagina de exportacion mostrando el selector de formato con los 7 formatos, casillas de seleccion de contenido y opciones de modo de recursos
</div>

## Como exportar

1. Navega a **Exportar e Importar** desde la barra lateral de tu proyecto.
2. **Elige un formato** -- Selecciona entre los 7 formatos disponibles. Las casillas de contenido se actualizan para mostrar que secciones soporta ese formato.
3. **Selecciona secciones de contenido** -- Marca o desmarca Fichas, Flujos, Escenas, Guiones y Localizacion. Las secciones no soportadas por el formato seleccionado se deshabilitan.
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

## Importar

Storyarn puede importar datos de proyecto desde archivos {accent}.storyarn.json{/accent} -- el mismo formato producido por la exportacion Storyarn JSON. Esto es util para migrar proyectos entre espacios de trabajo, restaurar copias de seguridad o fusionar contenido de diferentes miembros del equipo.

### Flujo de trabajo de importacion

1. **Subir** -- Selecciona un archivo `.json` (maximo 50 MB). Haz clic en "Subir y previsualizar" para analizarlo.

2. **Previsualizar** -- Storyarn te muestra lo que contiene el archivo: conteos de fichas, flujos, nodos, escenas, guiones y recursos. Si algun shortcut de entidad entra en conflicto con contenido existente en tu proyecto, se lista aqui.

3. **Resolver conflictos** -- Cuando se detectan conflictos de shortcuts, elige una estrategia:

| Estrategia        | Comportamiento                                                           |
| ----------------- | ------------------------------------------------------------------------ |
| **Omitir**        | Mantiene las entidades existentes, ignora las importaciones en conflicto |
| **Sobreescribir** | Reemplaza las entidades existentes con los datos importados              |
| **Renombrar**     | Importa con un nuevo shortcut para evitar la colision                    |

4. **Ejecutar** -- Haz clic en Importar para aplicar. La importacion se ejecuta dentro de una {accent}transaccion de base de datos{/accent}, por lo que es todo o nada. Si algun paso falla, todo se revierte y recibes un mensaje de error explicando que salio mal.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El paso de previsualizacion de importacion mostrando conteos de entidades, conflictos de shortcuts detectados y el selector de estrategia de resolucion de conflictos
</div>

### Medidas de seguridad de importacion

- **Limite de 50 MB de tamano de archivo** -- Se aplica al momento de la subida.
- **Validacion de estructura JSON** -- El archivo debe ser un objeto JSON valido con las claves de nivel superior esperadas.
- **Limites de conteo de entidades** -- Previene la importacion de conjuntos de datos excesivamente grandes que podrian afectar el rendimiento.
- **Ejecucion transaccional** -- Todo o nada. Sin importaciones parciales.
- **Permisos de edicion requeridos** -- Solo propietarios y editores del proyecto pueden importar. Los lectores ven un estado bloqueado.

## Otras vias de exportacion

Mas alla de la pagina principal de Exportar e Importar, Storyarn ofrece funciones de exportacion especializadas en otras areas:

**Exportacion de localizacion** -- Desde la pagina de Localizacion, exporta traducciones como Excel (.xlsx) o CSV filtrado por idioma. Importa archivos CSV traducidos de vuelta con emparejamiento por ID. Consulta la [Vista general de Localizacion](/docs/localization/localization-overview) para mas detalles.

**Exportacion de guion** -- Exporta guiones individuales a formato Fountain (.fountain) para usar en herramientas de escritura de guion como Final Draft, Highland o WriterSolo. Importa archivos Fountain existentes para crear nuevos guiones en Storyarn.
