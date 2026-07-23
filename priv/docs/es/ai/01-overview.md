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

Conectar una clave no envía datos del proyecto automáticamente ni la habilita para un espacio de trabajo. Cada proveedor conectado incluye una lista de workspaces en esta página. Habilita solo aquellos en los que Storyarn pueda ofrecer esa conexión como ruta de IA. La misma clave cifrada sigue asociada a tu cuenta; Storyarn no la copia ni la comparte con el workspace.

## Claves personales de IA

El owner siempre puede asignar sus propias conexiones personales a un workspace que posee. En **Ajustes del workspace → General**, puede permitir o desactivar de forma independiente la **IA personal para otros miembros**. Al activarla, los miembros autorizados pueden asignar un proveedor compatible que hayan conectado ellos mismos. Esta política nunca les da acceso a la clave de otra persona.

La conexión, la asignación al workspace y el consentimiento de la tarea son controles independientes:

1. **Conexión:** guardas y validas tu clave personal del proveedor.
2. **Asignación al workspace:** eliges dónde se puede ofrecer esa conexión.
3. **Consentimiento de la tarea:** antes de enviar contenido del proyecto, Storyarn muestra el proveedor, el modelo, el alcance de datos, la capacidad y la clase de coste.

El consentimiento es específico para el workspace y la conexión del proveedor. Deja de ser válido si eliminas la asignación, desconectas la clave, cambia la política del workspace o Storyarn actualiza el texto informativo. Volver a habilitar una conexión exige un consentimiento nuevo; una autorización anterior nunca se recupera de forma silenciosa.

- El proveedor factura a tu propia cuenta. Las ejecuciones personales nunca consumen la asignación de Storyarn AI.
- El contenido autorizado de la tarea sale de Storyarn y se procesa en la infraestructura del proveedor. La ubicación, la retención y el posible uso para entrenar modelos dependen de tu cuenta y de las condiciones del proveedor. Storyarn no puede garantizar retención cero ni exclusión del entrenamiento con claves personales.
- Tu clave solo puede ejecutar una acción que tú inicies. Nunca se comparte con otro miembro ni se utiliza en automatizaciones programadas.
- Storyarn nunca cambia silenciosamente entre tu clave y Storyarn AI. Tú eliges quién paga y la ruta.
- Un rechazo del proveedor normalmente no desconecta la clave. Un fallo de autenticación sí lo hace, porque la credencial ya no es utilizable.

Deshabilitar un workspace elimina esa asignación y revoca sus consentimientos activos. Desconectar un proveedor en **Ajustes de cuenta → AI Integrations** elimina todas sus asignaciones a workspaces y revoca todos los consentimientos activos de esa conexión. También puedes revocar un consentimiento sin desconectar la clave cuando una acción de IA compatible muestre ese control.

## Acciones de IA

Las acciones de IA aparecen como comandos en la paleta de comandos a medida que se publican. Antes de ejecutarse, cada acción indica qué datos envía, quién paga y dónde aparecerá el resultado. Las vistas previas generadas siguen siendo privadas para quien inicia la acción hasta que se aplican o adjuntan explícitamente al proyecto.
