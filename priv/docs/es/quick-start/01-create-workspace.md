%{
title: "Crear un espacio de trabajo",
category_label: "Inicio Rápido",
order: 1,
description: "Configura tu espacio de trabajo y crea tu primer proyecto en menos de 5 minutos."
}

---

Un {accent}espacio de trabajo (workspace){/accent} es la base de operaciones de tu equipo. Contiene todos tus proyectos y controla quién tiene acceso a ellos.

Este Inicio Rápido construye una ruta pequeña y completa:

1. Crear un espacio de trabajo y un proyecto.
2. Crear una ficha de personaje con variables.
3. Usar esas variables en un flujo ramificado.
4. Probar el flujo con el Story Player y el Modo Depuración.
5. Exportar el proyecto para llevarlo a tu pipeline de producción.

## Crea tu espacio de trabajo

Después de iniciar sesión, serás redirigido a tu espacio de trabajo predeterminado. Si aún no tienes uno, llegarás a la página de **Crear un nuevo espacio de trabajo**.

Rellena el {accent}nombre del espacio de trabajo{/accent} y una descripción opcional. Un slug de URL se genera automáticamente a partir del nombre. Haz clic en **Crear espacio de trabajo** para continuar.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El formulario "Crear un nuevo espacio de trabajo" con los campos de nombre y descripción
</div>

## Crea un proyecto

Desde el panel del espacio de trabajo, haz clic en el botón **Nuevo Proyecto** en la barra de herramientas superior derecha. Aparece un modal con dos campos: **Nombre del Proyecto** y una **Descripción** opcional.

Cada proyecto está completamente aislado, con sus propias fichas, flujos, escenas, localización y recursos. Un espacio de trabajo puede contener tantos proyectos como necesites.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El panel del espacio de trabajo mostrando la cuadrícula de proyectos y el botón "Nuevo Proyecto" en la barra de herramientas
</div>

Después de crearlo, entrarás directamente al editor de fichas del proyecto.

Para este tutorial, quédate en el nuevo proyecto y continúa con [Tu primera ficha](/docs/quick-start/first-sheet). Crearás los datos de personaje que el flujo leerá en el siguiente paso.

## Invita a tu equipo

Ve a **Ajustes > Espacios de trabajo > [Tu Espacio] > Miembros** y haz clic en **Invitar**. Introduce una dirección de email y elige un rol:

- {accent}Propietario (Owner){/accent} -- control total, incluida la eliminación
- {accent}Administrador (Admin){/accent} -- gestionar miembros, crear y eliminar proyectos
- {accent}Miembro (Member){/accent} -- editar contenido en los proyectos a los que tenga acceso
- {accent}Observador (Viewer){/accent} -- acceso de solo lectura en todas partes

Las invitaciones expiran después de 7 días y pueden revocarse en cualquier momento.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  La página de miembros del espacio de trabajo con el formulario de invitación, la lista de miembros y las invitaciones pendientes
</div>

## Acceso a nivel de proyecto

Dentro de cada proyecto, puedes refinar los permisos aún más. Un Miembro del espacio de trabajo puede ser Editor en un proyecto pero Observador en otro. Los roles de proyecto son:

- {accent}Propietario (Owner){/accent} -- control total del proyecto
- {accent}Editor{/accent} -- crear y editar todo el contenido
- {accent}Observador (Viewer){/accent} -- acceso de solo lectura

Gestiona los miembros del proyecto desde la página de **Ajustes** del proyecto.
