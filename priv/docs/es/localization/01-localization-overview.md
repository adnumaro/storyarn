%{
title: "Vista general de Localizacion",
category_label: "Localizacion",
order: 1,
description: "Traduce tu proyecto a multiples idiomas con extraccion automatica, DeepL y glosarios."
}

---

El sistema de localizacion de Storyarn te da control total sobre la traduccion de tu contenido narrativo -- desde lineas de dialogo y opciones de respuesta hasta nombres de fichas y etiquetas de bloques. Gestiona la {accent}extraccion automatica de texto{/accent}, traduccion automatica via DeepL, aplicacion de glosarios, seguimiento de doblaje y reportes de progreso detallados.

## Como funciona

El flujo de trabajo de localizacion tiene cuatro etapas, cada una disenada para minimizar el esfuerzo manual manteniendo el control de los traductores.

### 1. Configura tus idiomas

Abre **Localizacion** en la barra lateral de tu proyecto. El idioma fuente de tu proyecto se detecta automaticamente desde la configuracion de tu espacio de trabajo y se muestra como una insignia principal. Anade idiomas destino desde una lista curada de {accent}45 idiomas soportados{/accent} que cubren todos los mercados principales de localizacion de juegos -- desde ingles, espanol y japones hasta arabe, tailandes y chino (simplificado/tradicional).

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  La pagina principal de localizacion mostrando la insignia del idioma fuente, chips de idiomas destino con botones de eliminar y el desplegable de Agregar idioma
</div>

### 2. Extrae el contenido traducible

Haz clic en **Sincronizar** para escanear todo tu proyecto y extraer cada texto traducible. El extractor obtiene contenido de cuatro tipos de fuente:

| Fuente             | Que se extrae                                                                                                                    |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| **Nodos de flujo** | Texto de dialogo, acotaciones, texto de menu, textos de respuestas individuales, descripciones de slug line, etiquetas de salida |
| **Fichas**         | Nombre de ficha, descripcion de ficha                                                                                            |
| **Bloques**        | Etiquetas de bloque, valores de contenido de texto, etiquetas de opciones de seleccion                                           |
| **Flujos**         | Nombre de flujo, descripcion de flujo                                                                                            |

Cada texto extraido recibe un hash SHA-256 de su contenido fuente. Cuando vuelves a sincronizar, Storyarn detecta cambios -- si el texto fuente ha sido modificado desde la ultima traduccion, el sistema puede marcarlo para re-traduccion. La extraccion es idempotente: ejecutarla multiples veces nunca crea duplicados gracias a la logica de upsert.

Los nodos de dialogo tambien rastrean el **ID de ficha del hablante**, para que los reportes puedan desglosar conteos de palabras por personaje.

### 3. Traduce

Tienes tres vias para completar las traducciones:

**Edicion manual** -- Abre cualquier entrada de texto para editar la traduccion directamente. Ideal para adaptacion creativa, matices culturales y pulido final.

**Integracion con DeepL** -- Conecta tu clave API de DeepL en la configuracion del proyecto para activar la traduccion automatica. Puedes traducir una entrada individual (haz clic en el icono de destello) o traducir por lotes todos los textos pendientes de un idioma con un solo clic.

Internamente, la traduccion de DeepL es {accent}compatible con HTML{/accent}: el texto enriquecido de los nodos de dialogo se envia con `tag_handling: "html"` para que el formato se preserve. Los marcadores de posicion de variables como `{character_name}` se envuelven en `<span translate="no">` antes de enviar y se desenvuelven despues -- asi vuelven intactos. Las solicitudes por lotes se dividen en grupos de 50 textos (el limite por solicitud de DeepL). Tus entradas de glosario se aplican automaticamente durante la traduccion.

**Exportar para traductores externos** -- Descarga un archivo Excel (.xlsx) o CSV filtrado por idioma, estado o tipo de fuente. Envialo a tu equipo de traduccion y luego importa el archivo completado de vuelta. La importacion empareja filas por ID y actualiza traducciones y estados.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  La tabla de traducciones mostrando texto fuente, traduccion, insignias de estado, conteos de palabras y botones de accion (editar, traducir con DeepL)
</div>

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

- Icono de tipo de fuente (nodo de flujo, bloque, ficha, flujo)
- Texto fuente (HTML eliminado para la vista previa)
- Traduccion actual con una insignia "MT" si es traduccion automatica
- Insignia de estado
- Conteo de palabras

## Glosario

El glosario asegura {accent}terminologia consistente{/accent} en todas las traducciones. Cada entrada mapea un termino fuente a un termino destino para un par de idiomas especifico.

| Campo                              | Proposito                                                                         |
| ---------------------------------- | --------------------------------------------------------------------------------- |
| **Termino fuente**                 | El termino en tu idioma fuente                                                    |
| **Termino destino**                | La traduccion requerida                                                           |
| **Idioma fuente / Idioma destino** | El par de idiomas al que aplica esta entrada                                      |
| **Contexto**                       | Notas de uso para traductores                                                     |
| **No traducir**                    | Cuando esta habilitado, el termino se mantiene tal cual (nombres propios, marcas) |

Las entradas del glosario se aplican automaticamente durante la traduccion con DeepL mediante la API de Glosarios de DeepL. Al traducir manualmente, el glosario sirve como referencia.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  La interfaz de gestion de glosarios mostrando una lista de pares de terminos con notas de contexto
</div>

## Reportes

El reporte de localizacion te da una vista panoramica del progreso de traduccion. Proporciona cuatro tipos de datos:

**Progreso por idioma** -- Para cada idioma destino, ve el numero total de entradas de texto, cuantas han alcanzado el estado "final" y el porcentaje de completado.

**Conteo de palabras por hablante** -- Para cualquier idioma, ve cuantas palabras y lineas tiene cada personaje (ficha de hablante). Util para estimar tiempo y coste de grabacion de doblaje.

**Progreso de doblaje** -- Rastrea el estado de VO en cuatro etapas: ninguno, necesario, grabado y aprobado. Cada entrada de texto de nodos de dialogo tiene su propio estado de VO independiente del estado de traduccion.

**Desglose de contenido** -- Ve cuantas entradas de texto provienen de cada tipo de fuente (nodos de flujo, bloques, fichas, flujos) para un idioma dado.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  La pagina de reportes de localizacion mostrando barras de progreso por idioma, tabla de conteo de palabras por hablante y desglose de estado de VO
</div>

## Exportar e importar

**Exportar** -- Descarga traducciones como Excel (.xlsx) o CSV, filtrado por idioma. La exportacion incluye: ID, tipo de fuente, ID de fuente, campo de fuente, locale, texto fuente (HTML eliminado), traduccion, estado, conteo de palabras, flag de traduccion automatica y notas del traductor/revisor (solo Excel).

**Importar** -- Sube un archivo CSV con como minimo una columna de ID. El importador empareja cada fila con una entrada de texto existente por ID, luego actualiza la traduccion y/o el estado. Estados validos para importacion: `pending`, `draft`, `in_progress`, `review`, `final`. Las filas con traducciones vacias o estados no reconocidos se omiten. La importacion reporta cuantas entradas se actualizaron, se omitieron y cualquier error encontrado.
