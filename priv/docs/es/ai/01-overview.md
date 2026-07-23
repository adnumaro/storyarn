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

Conecta tus propias cuentas de proveedores de IA (claves API) en **Ajustes de cuenta → Integraciones IA**. El catálogo separa los proveedores conectados de los disponibles; selecciona uno para abrir su configuración. Abrir estos ajustes y cambiar una clave requiere autenticación reciente. Las claves se validan antes de guardarse, se cifran en reposo, son privadas para su propietario y se pueden revocar en cualquier momento.

Conectar una clave no envía datos del proyecto automáticamente ni la habilita para un espacio de trabajo. La pantalla de detalle de cada proveedor incluye una lista buscable de workspaces. Habilita solo aquellos en los que Storyarn pueda ofrecer esa conexión como ruta de IA. La misma clave cifrada sigue asociada a tu cuenta y puede servir a varios workspaces; Storyarn no la copia ni la comparte con un workspace.

Reemplazar una clave es una rotación sobre la conexión existente: Storyarn valida la candidata antes de cambiar la credencial guardada. Si la candidata es rechazada, la clave anterior sigue activa. Si una sustitución válida deja de ofrecer un modelo seleccionado, el rol afectado se mantiene visible como estado a reparar en lugar de cambiarse silenciosamente.

## Claves personales de IA

El owner siempre puede asignar sus propias conexiones personales a un workspace que posee. En **Ajustes del workspace → General**, puede permitir o desactivar de forma independiente la **IA personal para otros miembros**. Al activarla, los miembros autorizados pueden asignar un proveedor compatible que hayan conectado ellos mismos. Esta política nunca les da acceso a la clave de otra persona.

La conexión, la asignación al workspace, el modelo principal por rol y el consentimiento de la tarea son controles independientes:

1. **Conexión:** guardas y validas tu clave personal del proveedor.
2. **Asignación al workspace:** eliges dónde se puede ofrecer esa conexión.
3. **Modelo principal por rol:** en **Ajustes de cuenta → Mi equipo IA**, primero puedes ver todos tus workspaces y sus modelos por rol; al configurar uno, eliges un proveedor y un modelo principal para cada rol disponible en ese workspace.
4. **Consentimiento de la tarea:** antes de enviar contenido del proyecto, Storyarn muestra el proveedor, el modelo, el alcance de datos, la capacidad y la clase de coste.

Mi equipo IA tiene cuatro roles: **Asistente general**, **Asistente de
escritura**, **Ilustrador** y **Voz**. Asistente general se usa para trabajos
explícitos y acotados como resúmenes, explicaciones de análisis, conversión de
texto en estructura y acciones compatibles de la paleta de comandos. Asistente
de escritura se usa para transformaciones de diálogos y sugerencias del editor.
Elige **Configurar** desde la fila de un workspace para editarlo. El editor queda
fijado a ese workspace y no contiene un selector de workspace; vuelve al resumen
para abrir otro.

La misma conexión de proveedor puede usar modelos principales distintos para el mismo rol en diferentes workspaces. No existe un modelo personal predeterminado genérico. Un rol sin configurar o inválido pide que lo elijas o repares; Storyarn nunca sustituye automáticamente el modelo, el proveedor, quién paga ni el workspace.

Storyarn mantiene en la propia aplicación un catálogo revisado de modelos, por
lo que no tienes que configurar sus identificadores mediante ajustes de
despliegue. La lista completa del proveedor no se habilita automáticamente y la
lista disponible para tu clave puede ser menor según su cuenta, región o plan.

El catálogo distingue entre modelos **Ejecutables** y modelos **Solo
configuración**. Los modelos de texto ofrecidos para Asistente general y
Asistente de escritura tienen un adaptador de ejecución validado. Los modelos
actuales de imagen y voz pueden aparecer para que prepares Ilustrador y Voz,
pero se muestran como **Solo configuración** y no pueden ejecutarse, pedir
consentimiento para una tarea ni realizar una petición de generación con tu
clave hasta que Storyarn publique y valide la herramienta de imagen o voz.
Seleccionar uno solo guarda esa preferencia futura; no vuelve ejecutable el
modelo.

El consentimiento es específico para el workspace y la conexión del proveedor. Deja de ser válido si eliminas la asignación, desconectas la clave, cambia la política del workspace o Storyarn actualiza el texto informativo. Volver a habilitar una conexión exige un consentimiento nuevo; una autorización anterior nunca se recupera de forma silenciosa.

- El proveedor factura a tu propia cuenta. Las ejecuciones personales nunca consumen la asignación de Storyarn AI.
- El contenido autorizado de la tarea sale de Storyarn y se procesa en la infraestructura del proveedor. La ubicación, la retención y el posible uso para entrenar modelos dependen de tu cuenta y de las condiciones del proveedor. Storyarn no puede garantizar retención cero ni exclusión del entrenamiento con claves personales.
- Tu clave solo puede ejecutar una acción que tú inicies. Nunca se comparte con otro miembro ni se utiliza en automatizaciones programadas.
- Storyarn nunca cambia silenciosamente entre tu clave y Storyarn AI. Tú eliges quién paga y la ruta.
- Un rechazo del proveedor normalmente no desconecta la clave. Un fallo de autenticación sí lo hace, porque la credencial ya no es utilizable.

Deshabilitar un workspace elimina esa asignación y revoca sus consentimientos activos. Desconectar un proveedor en **Ajustes de cuenta → Integraciones IA** elimina todas sus asignaciones a workspaces y revoca todos los consentimientos activos de esa conexión. Los modelos principales afectados siguen visibles en **Mi equipo IA** para que puedas repararlos. También puedes revocar un consentimiento sin desconectar la clave cuando una acción de IA compatible muestre ese control.

## Acciones de IA

Las acciones de IA aparecen como comandos en la paleta de comandos a medida que se publican. Antes de ejecutarse, cada acción indica qué datos envía, quién paga y dónde aparecerá el resultado. Las vistas previas generadas siguen siendo privadas para quien inicia la acción hasta que se aplican o adjuntan explícitamente al proyecto.

Si se agota la asignación de Storyarn AI, la acción gestionada no se ejecuta.
Cuando existe una ruta personal compatible, Storyarn puede ofrecer **Usar mi
propia clave API**. Elegirla abre la información sobre los datos y la facturación
del proveedor; solo después de conceder el consentimiento actual de la tarea se
inicia una ejecución personal independiente. Storyarn nunca cambia
automáticamente quién paga, el proveedor, el modelo, la clave ni la ruta.
