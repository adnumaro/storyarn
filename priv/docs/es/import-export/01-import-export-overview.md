%{
title: "Importar y exportar",
category_label: "Importar y exportar",
order: 1,
description: "Mueve proyectos narrativos entre Yarn Spinner, Storyarn y los principales motores de juego."
}

---

Storyarn puede importar un {accent}proyecto de Yarn Spinner{/accent} existente y exportar contenido narrativo a {accent}6 formatos{/accent} para los principales motores y sistemas de diálogo.

## Importar desde Yarn Spinner

Abre **Ajustes del proyecto > Importar y exportar** y sube un archivo fuente `.yarn` o un `.zip` con los fuentes `.yarn` del proyecto. Storyarn valida y previsualiza el paquete antes de modificar el contenido. La política de conflictos predeterminada conserva ambas versiones renombrando lo importado; también puedes omitir el contenido coincidente o sobrescribirlo.

El importador convierte:

- Los nodos de Yarn en Flujos de Storyarn.
- Los diálogos y opciones anidadas en nodos de diálogo, hub y respuesta.
- Las ramas `if`, `elseif` y `else` en condiciones de Storyarn cuando cada expresión tiene un equivalente seguro.
- Las declaraciones literales, asignaciones compatibles e interpolaciones de variables en una ficha **Yarn Variables** y expresiones de Storyarn.
- Los comandos `jump`, `detour`, `return` y `stop` en los nodos de control de flujo correspondientes.
- Los prefijos de hablante como `Guía: Bienvenido` en fichas de personaje cuando se pueden inferir de forma segura.
- Los identificadores de línea de Yarn en identificadores de localización de Storyarn.

El título exacto y sensible a mayúsculas `Start` es el único nodo de Yarn candidato a flujo principal. Una importación aditiva conserva el flujo principal actual; si el proyecto no tiene ninguno, `Start` pasa a serlo cuando ese nodo se importa realmente (la estrategia de omisión puede descartar un `Start` en conflicto). Si se sobrescribe el flujo principal actual, su reemplazo importado hereda ese rol. El reemplazo completo aplica la regla después de retirar el grafo narrativo anterior: `Start` será principal si existe y, si no existe, Storyarn no elegirá otro flujo por su orden en el archivo. La previsualización muestra el resultado esperado según el estado actual del proyecto; Storyarn vuelve a comprobar la regla bajo el bloqueo del proyecto cuando se ejecuta la importación en segundo plano.

Los comandos personalizados con efectos externos y sin equivalente en Storyarn se conservan como nodos de anotación visibles y aparecen como advertencias en la previsualización. La lógica que controla ramas o estado se trata de forma más estricta: si una condición, Smart Variable, asignación o destino de control de flujo no puede reproducirse de forma segura, la validación rechaza la importación antes de almacenar un plan o modificar el proyecto.

### Flujo de importación seguro

1. Selecciona un archivo `.yarn` o `.zip`. El tamaño máximo es de 50 MB.
2. Pulsa **Validar y previsualizar**. Antes de extraer un ZIP se comprueban sus rutas, número de entradas, tamaño expandido, ratio de compresión, codificación de texto y tamaño de cada archivo.
3. Revisa el número de entidades, los conflictos de atajos y las advertencias de compatibilidad.
4. Mantén el modo predeterminado **Añadir a este proyecto** o elige **Reemplazar contenido narrativo** cuando el ZIP contenga exactamente un archivo `.yarnproject` válido.
5. En una importación aditiva, elige **Omitir**, **Sobrescribir** o **Conservar ambos** para los conflictos e inicia la importación.
6. El plan de importación cifrado se procesa en segundo plano. Puedes salir de la página y volver cuando termine.

Solo los propietarios del proyecto pueden preparar o ejecutar una importación. Storyarn vuelve a comprobar el permiso dentro del trabajo en segundo plano. Las importaciones fallidas usan una transacción de base de datos, por lo que no conservan contenido parcial.

### Reemplazar un proyecto existente

El reemplazo completo solo se ofrece para un ZIP de proyecto Yarn explícito que contenga un único `.yarnproject` válido. Un archivo `.yarn` suelto o un ZIP de proyecto implícito se puede añadir, pero no puede reemplazar el proyecto actual.

Antes del reemplazo, Storyarn crea un snapshot completo normal y visible, y espera hasta que esté verificado y se pueda recuperar. Mientras se construye, no modifica nada. Después comprueba que el proyecto siga coincidiendo exactamente con el snapshot y, en una única transacción de base de datos, mueve las Fichas, Flujos, Escenas, idiomas y textos de localización activos a la papelera o archivo recuperable antes de importar el proyecto Yarn. Se conservan los assets, ajustes del proyecto, miembros, snapshots, entradas del glosario, contenido que ya estaba en la papelera y el historial de versiones de entidades. Si falla el snapshot, la recuperación no está disponible, el proyecto cambia tras la captura o falla la materialización, el reemplazo se detiene sin conservar cambios parciales. El snapshot de recuperación se conserva después de un reemplazo correcto; los reemplazos fallidos, cancelados o caducados eliminan su snapshot sin usar mediante una limpieza durable en segundo plano.

### Límites actuales del importador de Yarn

- Los CSV de tablas de localización de Yarn todavía no se importan. Se conservan los identificadores de línea para poder conectar las traducciones en un flujo posterior.
- Los comandos personalizados con efectos externos se importan como anotaciones para revisión manual. Las interpolaciones dinámicas, las marcas de Yarn y las etiquetas distintas de los identificadores de línea que no sean compatibles permanecen visibles en el texto importado y se marcan para revisión. Las funciones personalizadas usadas en condiciones, las Smart Variables de Yarn 3, las asignaciones a variables no declaradas y otras expresiones de estado o control de flujo no compatibles bloquean la importación en vez de debilitarse o descartarse.
- Los grupos de líneas, los grupos de nodos y las cláusulas `when` de los storylets de Yarn 3 todavía no se convierten. Los archivos que los usan se rechazan porque aplanar sus reglas de selección cambiaría qué diálogo aparece. Los bloques `once` con estado se rechazan por el mismo motivo.
- Las fichas de hablante importadas solo contienen el nombre inferido; complétalas después con el esquema propio de tu proyecto. Las expresiones de hablante dinámicas permanecen en el texto del diálogo y se marcan para revisión en vez de enlazarse a una ficha de personaje.
- No se importan imágenes, audio, assets de Unity, recursos de Godot ni bytecode compilado de Yarn.
- El modo de reemplazo requiere espacio suficiente en el workspace para que Storyarn cree y verifique el snapshot completo de recuperación. Si no puede completar ese punto de recuperación, el proyecto existente permanece intacto.

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

<img src="/images/docs/export-panel-current.png" alt="La pagina de exportacion mostrando el selector de formato, casillas de seleccion de contenido y opciones de modo de recursos" loading="lazy">

## Como exportar

1. Navega a **Importar y exportar** desde la barra lateral de tu proyecto.
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

<img src="/images/docs/export-validation-current.png" alt="Resultados de validación con advertencias sobre nodos desconectados, diálogos vacíos, hablantes faltantes, textos sin traducir y fichas sin referencias" loading="lazy">

## Otras vias de exportacion

Mas alla de la pagina principal de Importar y exportar, Storyarn ofrece funciones de intercambio especializadas en otras areas:

**Intercambio de localización** -- Desde la página de Localización puedes exportar traducciones como Excel (.xlsx) o CSV filtrado por idioma. Conserva las columnas ID y Source Hash sin cambios y utiliza **Importar CSV** para aplicar los valores devueltos de Translation y Status. El hash evita que un archivo obsoleto sobrescriba traducciones después de cambiar el contenido fuente. Consulta la [Vista general de Localización](/docs/localization/localization-overview) para obtener más detalles.
