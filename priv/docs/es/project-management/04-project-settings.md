%{
title: "Ajustes del proyecto",
category_label: "Gestión de proyectos",
order: 4,
description: "Configura detalles, acceso, localización, versionado, límites y mantenimiento del proyecto."
}

---

Abre **Ajustes** desde la barra lateral del proyecto para configurar su comportamiento global. Las acciones disponibles dependen del rol que tengas en el proyecto.

## General

La página General incluye:

- Nombre, descripción, tipo y subtipo del proyecto.
- Publicación de plantillas para crear o actualizar una plantilla privada.
- El idioma fuente utilizado actualmente por Localización.
- Selección personal de apariencia clara, oscura o del sistema.
- Colores principal y de acento del proyecto, con opción para restaurar los valores predeterminados.
- Una acción de mantenimiento para reparar referencias de variables.
- Eliminación del proyecto dentro de la zona de peligro.

Eliminar un proyecto lo retira del espacio de trabajo activo y te devuelve a su dashboard. Trátalo como una acción administrativa y comprueba antes los requisitos de recuperación.

## Control de versiones

Control de versiones ofrece interruptores independientes para:

- Capturas diarias del proyecto.
- Versiones automáticas de Flujos.
- Versiones automáticas de Escenas.
- Versiones automáticas de Fichas.

La página también muestra el uso actual frente al límite del plan para capturas del proyecto y versiones con nombre de entidades. Guarda después de cambiar los interruptores.

## Límites de uso

Límites de uso es una página de solo lectura. Muestra el plan activo y el consumo de elementos del proyecto, capturas, versiones con nombre, almacenamiento del espacio, proyectos y miembros. El total de elementos se desglosa en fichas, flujos, escenas y nodos de flujo. Una etiqueta avisa cuando un límite está próximo o se ha alcanzado.

## Proveedor de localización

Usa los ajustes de **Localización** para introducir una clave API de DeepL, elegir el endpoint Free o Pro, probar la conexión y consultar el uso de caracteres comunicado por el proveedor. Consulta [Vista general de Localización](/docs/localization/localization-overview) para conocer el flujo de traducción.

## Miembros

La lista muestra cada miembro del proyecto y su rol. Las invitaciones de proyecto pueden conceder acceso de **Editor** u **Observador**. Los propietarios no se pueden retirar desde esta lista y el usuario actual no puede eliminarse a sí mismo mediante la acción de retirada.

La membresía del espacio de trabajo y la del proyecto son independientes. Una persona debe poder acceder al espacio antes de que el permiso de proyecto resulte útil. Consulta [Crear un espacio de trabajo](/docs/quick-start/create-workspace#acceso-a-nivel-de-proyecto).

## Exportación

La página de Exportación configura el formato para el motor, las secciones incluidas, el tratamiento de recursos, el formato de salida y la validación previa. Consulta la guía de [Exportación](/docs/import-export/import-export-overview).

Las capturas y la papelera se explican en [Capturas y papelera](/docs/project-management/recovery-and-trash).
