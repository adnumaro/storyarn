%{
title: "Recursos",
category_label: "Gestión de proyectos",
order: 2,
description: "Sube, localiza, inspecciona, reutiliza y elimina con seguridad imágenes y audio del proyecto."
}

---

El espacio de **Recursos (Assets)** es la biblioteca multimedia compartida de un proyecto. Ábrelo desde la barra lateral para gestionar imágenes y audio por separado de las fichas, flujos y escenas que los utilizan.

## Subir archivos

Usa **Subir** en la barra superior y elige un archivo. El cargador estándar admite:

- Imágenes: JPEG, PNG, GIF y WebP.
- Audio: MP3, WAV, OGG y WebM.

El cargador del dashboard admite archivos de hasta **20 MB**. El almacenamiento disponible también depende del plan del espacio de trabajo; consulta **Ajustes del proyecto > Límites de uso** si una subida se rechaza porque se ha alcanzado el límite.

Las subidas realizadas desde un editor de imágenes específico, como el avatar o banner de una ficha o el fondo de una escena, pueden utilizar otro flujo que prepara una variante adecuada de la imagen.

## Encontrar recursos

Usa la búsqueda lateral para filtrar por nombre de archivo. Los filtros separan **Todos**, **Imágenes**, **Audio** y otros archivos almacenados. Los contadores indican los totales actuales del proyecto.

Cada tarjeta muestra una vista previa cuando está disponible, el nombre, el tamaño y el tipo. Al seleccionar una tarjeta se abre el panel de detalles.

## Detalles y usos

El panel de detalles muestra el tipo MIME, tamaño, fecha de subida, una vista previa o reproductor de audio y los usos conocidos. Los enlaces de uso pueden llevar a:

- Nodos de flujo que utilizan audio.
- Avatares y banners de fichas.
- Fondos de escenas.
- Iconos de pines de escena.

Sigue estos enlaces antes de sustituir o eliminar un recurso. Identifican el contenido que puede necesitar una actualización.

## Reutilizar recursos

Los selectores de recursos de Fichas, Flujos y Escenas leen la misma biblioteca del proyecto. Reutilizar un archivo existente evita duplicados y mantiene útil el seguimiento de usos.

## Eliminar recursos

Solo los usuarios con permiso de edición pueden eliminar un recurso. Storyarn muestra una confirmación y avisa cuando existen usos conocidos. La eliminación del archivo almacenado es permanente, por lo que conviene actualizar o retirar primero sus usos y revisar después el contenido afectado.

La exportación puede conservar las URL como referencias, incrustar los archivos en Base64 o incluirlos en un ZIP. Consulta [Exportar](/docs/import-export/import-export-overview#como-exportar).
