%{
title: "Capturas y papelera",
category_label: "Gestión de proyectos",
order: 5,
description: "Crea copias del proyecto y recupera o elimina contenido compatible."
}

---

Storyarn ofrece dos herramientas de recuperación complementarias:

- Las **Capturas** conservan el estado del proyecto en un momento determinado.
- La **Papelera** guarda las entidades compatibles que se han eliminado de forma lógica.

Usa una captura antes de una migración amplia o un cambio estructural. Usa la Papelera cuando solo necesites recuperar un elemento eliminado.

## Capturas del proyecto

Abre **Ajustes del proyecto > Capturas**. Introduce un título y una descripción opcionales y selecciona **Crear captura**. La creación está sujeta al límite del plan que se muestra en Control de versiones y Límites de uso.

La creación de la captura continúa en segundo plano. Storyarn genera un único archivo ZIP privado y solo marca la captura como lista después de verificar el archivo y su manifiesto. El tamaño almacenado corresponde al ZIP más ese pequeño manifiesto; Storyarn no conserva junto al ZIP una segunda copia de cada archivo de la captura.

Cada captura muestra su número de versión, título, creador cuando está disponible, fecha, tamaño almacenado y recuentos de entidades. Las acciones disponibles son:

- **Descargar** una captura lista y verificada como archivo ZIP privado. Storyarn comprueba tus permisos en cada solicitud y el navegador descarga después el archivo persistido directamente desde el almacenamiento privado.
- **Eliminar** permanentemente la captura.

La restauración de capturas de proyecto no está disponible actualmente en la interfaz. Conserva los archivos descargados como copias de seguridad del proyecto; las versiones de entidad y la Papelera ofrecen las rutas de restauración dentro del producto que se describen a continuación.

## Capturas automáticas y versiones de entidades

En **Ajustes del proyecto > Control de versiones** puedes activar las capturas diarias del proyecto de forma independiente al versionado automático de Fichas, Flujos y Escenas.

Las versiones de entidad sirven para revisar o recuperar un único elemento. Las capturas del proyecto son copias descargables más amplias. Sus límites de uso se contabilizan por separado.

## Papelera

Abre **Ajustes del proyecto > Papelera** para revisar Fichas, Flujos, Escenas y otros tipos compatibles eliminados de forma lógica. Puedes:

- Buscar por nombre.
- Filtrar por tipo.
- Recorrer resultados paginados.
- Restaurar un elemento.
- Eliminar permanentemente un elemento.
- Vaciar toda la papelera.

Restaurar devuelve el elemento al contenido activo del proyecto. La eliminación permanente y **Vaciar papelera** no se pueden deshacer desde esta interfaz. Estas acciones destructivas solo están disponibles para usuarios con permisos de administración.

## Secuencia de recuperación recomendada

1. Revisa la Papelera cuando falte un único elemento.
2. Consulta el historial de versiones cuando el elemento exista, pero su contenido sea incorrecto.
3. Usa una captura descargada como copia de seguridad del proyecto cuando haya varias entidades relacionadas.
4. Descarga las capturas importantes antes de eliminarlas o realizar una migración de riesgo.
