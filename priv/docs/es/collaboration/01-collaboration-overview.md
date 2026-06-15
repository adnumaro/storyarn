%{
title: "Colaboración en tiempo real",
category_label: "Colaboración",
order: 1,
description: "Trabaja con tu equipo en tiempo real -- presencia, cursores y bloqueo."
}

---

Storyarn esta disenado para equipos. El {accent}Editor de Flujos{/accent} soporta colaboracion en tiempo real completa -- puedes ver quien esta en linea, seguir sus cursores por el lienzo y editar nodos sin conflictos gracias al bloqueo automatico.

Las funciones de colaboracion estan disponibles actualmente en el Editor de Flujos, donde el lienzo interactivo y la edicion basada en nodos son los que mas se benefician de la coordinacion en tiempo real. Los demas editores, como fichas y escenas, usan guardado optimista estandar.

## Presencia

Cuando abres un flujo, cada companero de equipo trabajando en el mismo flujo ve tu avatar aparecer en la lista de usuarios en linea. A cada usuario se le asigna un {accent}color deterministico{/accent} de una paleta de 12 colores disenada para visibilidad tanto en temas claros como oscuros. Tu color se mantiene consistente entre sesiones -- se deriva de tu ID de usuario, asi que tus companeros siempre te reconocen por el mismo color.

El sistema de presencia funciona con Phoenix Presence, lo que significa que gestiona las desconexiones de forma elegante. Si cierras la pestana o pierdes la conexion, tu avatar desaparece automaticamente.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  La cabecera del editor de flujos mostrando avatares de usuarios en linea, cada uno con su color de colaboracion asignado
</div>

## Seguimiento de cursores

Mientras mueves el raton por el lienzo del flujo, tus companeros ven un {accent}cursor en vivo{/accent} etiquetado con tu email y dibujado en tu color asignado. Las posiciones de los cursores se transmiten en tiempo real via PubSub, por lo que el movimiento se siente instantaneo.

Cuando abandonas el flujo (navegas a otro sitio o cierras la pestana), tu cursor desaparece del lienzo de los demas inmediatamente.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El lienzo del flujo con dos cursores remotos visibles, cada uno etiquetado con el nombre del usuario y mostrado en su color de colaboracion
</div>

## Bloqueo de nodos

Para prevenir ediciones conflictivas, Storyarn usa {accent}bloqueo automatico de nodos{/accent}. Cuando seleccionas un nodo, se adquiere un bloqueo para ti de forma transparente. Los demas miembros del equipo ven un indicador de bloqueo en ese nodo mostrando tu email y color -- pueden ver el nodo pero no pueden editarlo mientras tu bloqueo esta activo.

Detalles clave sobre el bloqueo:

- **Adquisicion automatica** -- Los bloqueos se adquieren en el momento en que seleccionas un nodo. No requiere accion manual.
- **Tiempo de espera de 30 segundos** -- Los bloqueos expiran tras 30 segundos de inactividad. Un mecanismo de heartbeat renueva el bloqueo mientras trabajas activamente.
- **Liberacion automatica** -- Los bloqueos se liberan cuando deseleccionas el nodo, navegas a otro flujo o te desconectas.
- **Gestion de conflictos** -- Si intentas seleccionar un nodo que alguien mas ha bloqueado, veras quien tiene el bloqueo para que puedas coordinarte.
- **Limpieza de bloqueos expirados** -- Un proceso en segundo plano se ejecuta cada 10 segundos para limpiar bloqueos expirados, asegurando que los bloqueos obsoletos nunca bloqueen a tu equipo.

Solo el titular del bloqueo puede liberarlo. Esto previene condiciones de carrera donde dos usuarios podrian intentar editar el mismo nodo simultaneamente.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Un nodo de flujo con un indicador de bloqueo mostrando el nombre de otro usuario y su color, indicando que esta siendo editado actualmente
</div>

## Cambios remotos y notificaciones

Cuando un companero hace un cambio -- creando, actualizando o eliminando un nodo -- el lienzo del flujo se {accent}actualiza automaticamente{/accent} para todos. Los datos del flujo se recargan y el lienzo se rerenderiza para que siempre veas el estado mas reciente.

Las notificaciones de colaboracion aparecen brevemente para informarte de lo que ocurrio:

- Bloqueo adquirido o liberado en un nodo
- Nodo creado, actualizado, movido o eliminado
- Conexion anadida o eliminada

Las notificaciones muestran el email del usuario y se colorean con su color de colaboracion. Se descartan automaticamente tras unos segundos.

## La paleta de colores

Storyarn asigna a cada usuario uno de 12 colores basado en su ID de usuario. La paleta usa colores de peso 500 de Tailwind para una visibilidad fuerte:

red, orange, amber, lime, green, teal, cyan, blue, indigo, violet, fuchsia, pink

Una variante mas clara de cada color (peso 300) tambien esta disponible para elementos sutiles como estelas de cursor.

## Roles y permisos

La colaboracion respeta la jerarquia de roles del proyecto. Todos los roles pueden ver la presencia, los cursores y las notificaciones. Solo los usuarios con permisos de edicion (Propietario, Editor) pueden adquirir bloqueos y hacer cambios. Los Lectores ven todo en tiempo real pero no pueden modificar nada -- la adquisicion de bloqueos se deniega en el servidor, no solo se oculta en la interfaz.

| Rol             | Ve presencia | Ve cursores | Puede editar nodos |
| --------------- | :----------: | :---------: | :----------------: |
| **Propietario** |      Si      |     Si      |         Si         |
| **Editor**      |      Si      |     Si      |         Si         |
| **Lector**      |      Si      |     Si      |         No         |
