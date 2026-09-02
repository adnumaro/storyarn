%{
title: "Snapshots y papelera",
category_label: "Gestión de proyectos",
order: 5,
description: "Crea copias del proyecto y recupera o elimina contenido compatible."
}

---

Storyarn ofrece dos herramientas de recuperación complementarias:

- La página **Snapshots** conserva el estado del proyecto en momentos determinados.
- La **Papelera** guarda las entidades compatibles que se han eliminado de forma lógica.

Usa una captura antes de una migración amplia o un cambio estructural. Usa la Papelera cuando solo necesites recuperar un elemento eliminado.

## Snapshots del proyecto

Abre **Ajustes del proyecto > Snapshots**. Introduce un título y una descripción opcionales y selecciona **Crear snapshot**. La creación está sujeta al límite del plan que se muestra en Control de versiones y Límites de uso.

La creación de la captura continúa en segundo plano. Storyarn genera un único archivo ZIP privado y solo marca la captura como lista después de verificar el archivo y su manifiesto. El tamaño almacenado corresponde al ZIP más ese pequeño manifiesto; Storyarn no conserva junto al ZIP una segunda copia de cada archivo de la captura.

Cada captura muestra su número de versión, título, creador cuando está disponible, fecha, tamaño almacenado y recuentos de entidades. Las acciones disponibles son:

- **Cancelar creación** mientras un snapshot esté pendiente, en construcción o en verificación, hasta que comience la finalización.
- **Restaurar** una captura lista y verificada que cumpla el contrato de restauración actual. Esta operación duradera se ejecuta en segundo plano y sustituye el grafo y los recursos activos del proyecto. Las Fichas, los Flujos, las Escenas y los recursos actuales pasan a la papelera recuperable; el proyecto y sus membresías se mantienen intactos.
- **Descargar** una captura lista y verificada como archivo ZIP privado. Storyarn comprueba tus permisos en cada solicitud y el navegador descarga después el archivo persistido directamente desde el almacenamiento privado.
- **Eliminar** permanentemente la captura.

La acción de restauración solo aparece en las capturas que cumplen los requisitos verificados. La restauración continúa de forma segura aunque salgas de la página, y la página Snapshots muestra su progreso y resultado.

## Capturas manuales y versiones automáticas de entidades

Las capturas del proyecto se crean manualmente desde **Ajustes del proyecto > Snapshots**. Storyarn no ofrece actualmente un interruptor ni un flujo productivo para crear capturas diarias del proyecto.

En **Ajustes del proyecto > Control de versiones** puedes activar las versiones automáticas de forma independiente para Fichas, Flujos y Escenas. Las versiones de entidad sirven para revisar o recuperar un único elemento. Las capturas abarcan todo el proyecto y también son copias descargables. Sus límites de uso se contabilizan por separado.

## Recuperar un proyecto desde un ZIP descargado

Un ZIP de captura descargado de Storyarn puede reconstruir el proyecto capturado como un proyecto nuevo dentro de un espacio de trabajo. Abre **Ajustes del espacio > Importaciones** en el espacio de destino, elige el ZIP y selecciona **Validar e importar**.

Storyarn valida el archivo y comprueba la capacidad de proyectos y almacenamiento del espacio antes de iniciar la importación en segundo plano. La página Importaciones muestra el progreso y el historial, y permite abrir el proyecto reconstruido cuando termina. Necesitas permiso para administrar el espacio seleccionado.

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
3. Restaura una captura verificada cuando necesites devolver el proyecto actual a un estado completo anterior.
4. Importa un ZIP de captura descargado desde los Ajustes del espacio cuando necesites reconstruir el proyecto capturado como un proyecto nuevo.
5. Descarga las capturas importantes antes de eliminarlas o realizar una migración de riesgo.
