%{
title: "Vista general de Localización",
category_label: "Localización",
order: 1,
description: "Traduce tu proyecto a múltiples idiomas con extracción automática, DeepL, revisión e informes."
}

---

El sistema de localización de Storyarn permite traducir el texto visible para el jugador que se envía a las exportaciones para motores, desde líneas de diálogo y opciones de respuesta hasta nombres de fichas y variables de texto en runtime. Gestiona la {accent}extracción automática de texto{/accent}, traducción automática mediante DeepL, seguimiento de doblaje e informes de progreso detallados.

## Como funciona

El flujo de trabajo de localizacion tiene cuatro etapas, cada una disenada para minimizar el esfuerzo manual manteniendo el control de los traductores.

### 1. Configura tus idiomas

Abre **Localización** en la barra lateral del proyecto. Si todavía no existe un idioma fuente, Storyarn lo inicializa a partir del idioma predeterminado del espacio de trabajo. El idioma fuente aparece en la barra lateral y puede cambiarse desde allí. Añade idiomas destino desde una lista de {accent}45 idiomas compatibles{/accent}, desde inglés, español y japonés hasta árabe, tailandés y chino simplificado o tradicional.

<img src="/images/docs/localization-overview-current.png" alt="Informe de localización con inglés como idioma fuente, catalán como idioma destino, progreso de traducción, palabras por hablante, estado de doblaje y desglose de fuentes runtime" loading="lazy">

### 2. Extrae el contenido traducible

Haz clic en **Sincronizar** para reconciliar la localización con el contrato de exportación runtime actual del proyecto. El extractor obtiene contenido de tres tipos de fuente:

| Fuente             | Qué se extrae                                                                                                                        |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| **Nodos de flujo** | Texto de diálogo, acotaciones, texto de menú, textos de respuestas individuales y etiquetas de salida                                |
| **Fichas**         | El nombre de cada ficha activa, utilizado como nombre de actor o hablante en runtime                                                 |
| **Bloques**        | `value.content` de bloques activos de texto o texto enriquecido, no constantes y con un nombre de variable runtime que no esté vacío |

Las escenas y los guiones no forman parte de la localización. También se excluyen los nombres y descripciones de flujos, las descripciones de fichas y los metadatos del editor, como etiquetas de bloque, placeholders y etiquetas de opciones, porque el contrato de exportación para motores no los emite como texto visible para el jugador.

Cada texto extraido recibe un hash SHA-256 de su contenido fuente. Cuando vuelves a sincronizar, Storyarn detecta cambios -- si el texto fuente ha sido modificado desde la ultima traduccion, el sistema puede marcarlo para re-traduccion. La extraccion es idempotente: ejecutarla multiples veces nunca crea duplicados gracias a la logica de upsert.

Los nodos de dialogo tambien rastrean el **ID de ficha del hablante**, para que los reportes puedan desglosar conteos de palabras por personaje.

### 3. Traduce

Tienes tres vias para completar las traducciones:

**Edicion manual** -- Abre cualquier entrada de texto para editar la traduccion directamente. Ideal para adaptacion creativa, matices culturales y pulido final.

**Integracion con DeepL** -- Conecta tu clave API de DeepL en la configuracion del proyecto para activar la traduccion automatica. Puedes traducir una entrada individual (haz clic en el icono de destello) o traducir por lotes todos los textos pendientes de un idioma con un solo clic.

Internamente, la traducción de DeepL es {accent}compatible con HTML{/accent}: el texto enriquecido de los nodos de diálogo se envía con `tag_handling: "html"` para conservar el formato. Los marcadores de variables como `{character_name}` se envuelven en `<span translate="no">` antes de enviarse y se desenvuelven después para que vuelvan intactos. Las solicitudes por lotes se dividen en grupos de 50 textos, el límite por solicitud de DeepL.

**Intercambio con traductores externos** -- Descarga un archivo Excel (.xlsx) o CSV filtrado por idioma, estado o tipo de fuente. Envíalo a tu equipo de traducción, conserva la columna ID y mantén la columna Source Hash para que Storyarn pueda rechazar filas cuyo texto fuente haya cambiado desde la exportación. La acción **Importar CSV** acepta el CSV devuelto y actualiza las traducciones y estados correspondientes.

<img src="/images/docs/localization-texts-current.png" alt="El espacio de traducción al catalán mostrando progreso, filtros y textos runtime de bloques, nodos de flujo y nombres de fichas con traducciones, estados y conteos de palabras" loading="lazy">

### 4. Revisa y finaliza

Cada entrada de texto sigue un {accent}flujo de trabajo de cinco etapas{/accent}:

| Estado          | Significado                                       |
| --------------- | ------------------------------------------------- |
| **Pendiente**   | Extraido pero aun no traducido                    |
| **Borrador**    | Traduccion automatica o primera pasada completada |
| **En progreso** | El traductor esta trabajando activamente en ello  |
| **Revision**    | Traduccion completada, pendiente de revision      |
| **Final**       | Aprobado y listo para exportar                    |

Las traducciones automaticas se establecen automaticamente con estado **Borrador**. Si el texto fuente cambia despues de la traduccion, el sistema puede detectar la discrepancia de hash para re-revision.

## Tabla de flujo de trabajo de traduccion

Filtra la tabla de traducciones por idioma, estado y tipo de fuente. Busca tanto en el texto fuente como en el traducido. La tabla esta paginada (50 entradas por pagina) y muestra:

- Icono de tipo de fuente (nodo de flujo, bloque o ficha)
- Texto fuente (HTML eliminado para la vista previa)
- Traduccion actual con una insignia "MT" si es traduccion automatica
- Insignia de estado
- Conteo de palabras

## Configuración de DeepL

Abre **Ajustes del proyecto > Localización** para introducir una clave API de DeepL, elegir el nivel Free o Pro, probar la conexión y consultar el uso del proveedor. Al guardar el proveedor se habilitan las acciones de traducción individual y por lotes en el espacio de Localización.

Abre **Glosario** desde la barra de herramientas de Localización para mantener términos de origen y destino, notas de contexto y términos que no deben traducirse. Con un proveedor DeepL activo puedes sincronizar el glosario para el par de idiomas seleccionado y utilizarlo durante la traducción automática.

<img src="/images/docs/localization-settings.png" alt="Configuración de Localización del proyecto con la clave API de DeepL y el selector de nivel de API" loading="lazy">

## Reportes

El reporte de localizacion te da una vista panoramica del progreso de traduccion. Proporciona cuatro tipos de datos:

**Progreso por idioma** -- Para cada idioma destino, ve el numero total de entradas de texto, cuantas han alcanzado el estado "final" y el porcentaje de completado.

**Conteo de palabras por hablante** -- Para cualquier idioma, ve cuantas palabras y lineas tiene cada personaje (ficha de hablante). Util para estimar tiempo y coste de grabacion de doblaje.

**Progreso de doblaje** -- Rastrea el estado de VO en cuatro etapas: ninguno, necesario, grabado y aprobado. Cada entrada de texto de nodos de dialogo tiene su propio estado de VO independiente del estado de traduccion.

**Desglose de contenido** -- Ve cuántas entradas de texto provienen de cada tipo de fuente (nodos de flujo, bloques y fichas) para un idioma dado.

<img src="/images/docs/localization-overview-current.png" alt="Informe de localización con idiomas de origen y destino, progreso de traducción, palabras por hablante y estado de doblaje" loading="lazy">

## Exportar traducciones

**Exportar** -- Descarga traducciones como Excel (.xlsx) o CSV, filtrado por idioma. La exportacion incluye: ID, tipo de fuente, ID de fuente, campo de fuente, locale, texto fuente (HTML eliminado), traduccion, estado, conteo de palabras, flag de traduccion automatica y notas del traductor/revisor (solo Excel).

La columna ID exportada identifica la fila de texto localizado existente. Consérvala sin cambios al intercambiar archivos con traductores. Para un intercambio seguro, mantén también **Source Hash**: la importación CSV lo valida e informa de las filas obsoletas en lugar de aplicar traducciones a un texto fuente que ya ha cambiado. Las importaciones están limitadas a 5 MB y pueden actualizar las columnas Translation y Status.
