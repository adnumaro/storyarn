%{
title: "IA en Storyarn",
category_label: "IA",
order: 1,
description: "Cómo funcionan las capacidades de IA de Storyarn: cuentas de proveedor conectadas, acciones de IA en la paleta de comandos y qué se ejecuta dónde.",
feature_flag: :ai_integrations
}

---

Las capacidades de IA de Storyarn se están desplegando gradualmente. Esta sección las documenta a medida que están disponibles.

## Integraciones de proveedores de IA

Conecta tus propias cuentas de proveedores de IA (claves API) en **Ajustes de cuenta → AI Integrations**. Abrir esta página y cambiar una clave requiere autenticación reciente. Las claves se validan antes de guardarse, se cifran en reposo, son privadas para su propietario y se pueden revocar en cualquier momento.

Conectar una clave no envía datos del proyecto automáticamente ni la habilita para un espacio de trabajo.

## Claves personales de IA

El propietario siempre puede usar sus propias conexiones personales en un espacio que posee. En **Ajustes del espacio → General**, puede permitir o desactivar de forma independiente la **IA personal para otros miembros**. Al activarla, los miembros autorizados pueden elegir explícitamente un proveedor compatible que hayan conectado ellos mismos.

Antes de emitir una ruta personal, Storyarn muestra el proveedor, el modelo, el alcance de datos del proyecto, la capacidad y la clase de coste. Debes dar tu consentimiento para ese espacio y esa conexión. El consentimiento deja de ser válido si desconectas la clave, cambia la política del espacio o Storyarn actualiza el texto informativo.

- El proveedor factura a tu propia cuenta. Las ejecuciones personales nunca consumen la asignación de Storyarn AI.
- El contenido autorizado de la tarea sale de Storyarn y se procesa en la infraestructura del proveedor. La ubicación, la retención y el posible uso para entrenar modelos dependen de tu cuenta y de las condiciones del proveedor. Storyarn no puede garantizar retención cero ni exclusión del entrenamiento con claves personales.
- Tu clave solo puede ejecutar una acción que tú inicies. Nunca se comparte con otro miembro ni se utiliza en automatizaciones programadas.
- Storyarn nunca cambia silenciosamente entre tu clave y Storyarn AI. Tú eliges quién paga y la ruta.
- Un rechazo del proveedor normalmente no desconecta la clave. Un fallo de autenticación sí lo hace, porque la credencial ya no es utilizable.

Desconectar un proveedor en **Ajustes de cuenta → AI Integrations** revoca todos los consentimientos activos de esa conexión. También puedes revocar un consentimiento sin desconectar la clave cuando una acción de IA compatible muestre ese control.

## Acciones de IA

Las acciones de IA aparecen como comandos en la paleta de comandos a medida que se publican. Antes de ejecutarse, cada acción indica qué datos envía, quién paga y dónde aparecerá el resultado. Las vistas previas generadas siguen siendo privadas para quien inicia la acción hasta que se aplican o adjuntan explícitamente al proyecto.
