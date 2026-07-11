%{
title: "Capturas y papelera",
category_label: "Gestión de proyectos",
order: 5,
description: "Crea copias del proyecto, restaura un estado conocido y recupera o elimina contenido."
}

---

Storyarn ofrece dos herramientas de recuperación complementarias:

- Las **Capturas** conservan el estado del proyecto en un momento determinado.
- La **Papelera** guarda las entidades compatibles que se han eliminado de forma lógica.

Usa una captura antes de una migración amplia o un cambio estructural. Usa la Papelera cuando solo necesites recuperar un elemento eliminado.

## Capturas del proyecto

Abre **Ajustes del proyecto > Capturas**. Introduce un título y una descripción opcionales y selecciona **Crear captura**. La creación está sujeta al límite del plan que se muestra en Control de versiones y Límites de uso.

Cada captura muestra su número de versión, título, creador cuando está disponible, fecha, tamaño almacenado y recuentos de entidades. Las acciones disponibles son:

- **Descargar** el archivo almacenado.
- **Restaurar** el proyecto a esa captura.
- **Eliminar** permanentemente la captura.

La restauración afecta a todo el proyecto y se ejecuta bajo un bloqueo. Las demás acciones de restauración quedan deshabilitadas mientras está en curso. Borra un bloqueo obsoleto solo después de confirmar que no sigue ejecutándose ningún trabajo de restauración.

Restaurar puede sustituir los datos actuales por el estado de la captura. Crea primero una captura nueva si existe la posibilidad de que necesites volver al estado actual.

## Capturas automáticas y versiones de entidades

En **Ajustes del proyecto > Control de versiones** puedes activar las capturas diarias del proyecto de forma independiente al versionado automático de Fichas, Flujos y Escenas.

Las versiones de entidad sirven para revisar o recuperar un único elemento. Las capturas del proyecto son puntos de recuperación más amplios. Sus límites de uso se contabilizan por separado.

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
3. Usa una captura del proyecto cuando varias entidades relacionadas deban volver a un estado anterior coherente.
4. Descarga las capturas importantes antes de eliminarlas o realizar una migración de riesgo.
