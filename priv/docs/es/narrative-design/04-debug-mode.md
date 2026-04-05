%{
title: "Modo Depuración (Debug)",
category_label: "Diseño Narrativo",
order: 4,
description: "Prueba y verifica tus flujos con este depurador interno integrado."
}

---

El editor de flujos incluye un {accent}depurador (debugger){/accent} integrado que te permite simular cómo se ejecuta un flujo -- paso a paso, con visibilidad completa de los valores de las variables, rutas de decisión e historial de ejecución. Esto es algo que ninguna otra herramienta de diseño narrativo ofrece: puedes verificar toda tu lógica ramificada sin salir del editor, sin exportar nada y sin usar un motor de juego.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El editor de flujos con el panel de depuración abierto en la parte inferior, mostrando la pestaña de la consola con los registros de ejecución
</div>

---

## Iniciar una sesión de depuración

1. Abre un flujo en el editor
2. Haz clic en el botón **Depurar (Debug)** de la barra de herramientas
3. El panel de depuración aparecerá acoplado en la parte inferior del lienzo

El depurador se inicializa en el nodo **Entrada (Entry)** del flujo, cargando todas las variables del proyecto con sus valores actuales de las hojas vinculadas de inicio.

---

## Controles

La barra de control se sitúa en la parte superior del panel de depuración con las siguientes acciones:

| Botón        | Acción        | Qué hace                                                                                    |
| ------------ | ------------- | ------------------------------------------------------------------------------------------- |
| Play / Pausa | **Auto-play** | Avanza automáticamente el flujo a la velocidad configurada, pausándose en opciones de diálogo y puntos de interrupción (breakpoints) |
| Paso         | **Step**      | Avanza exactamente un nodo hacia adelante                                                   |
| Paso atrás   | **Step Back** | Rebobina al estado anterior (deshace el último paso)                                        |
| Reiniciar    | **Reset**     | Reinicia la sesión desde el nodo de inicio, restableciendo todas las variables a sus valores iniciales |
| Detener      | **Stop**      | Finaliza la sesión de depuración y cierra el panel                                          |

Cuando el depurador llega a un **nodo de diálogo con opciones de respuesta**, se detiene y presenta dichas opciones como botones en la consola. Las opciones que no cumplen los parámetros (con condicionales fallidos) aparecen atenuadas grises e inhábiles en vez de ocultas, para mayor claridad. Pulsa una respuesta autorizada para seguir con tu testeo narrativo de esa rama concreta.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Botones para depuradora retrograda y testeo unitario focalizado.
</div>

---

## Probar saltándose bloques

El campo **Begin/Comenzar** sitúa un listado con el plano global, permite omitir la necesidad obligatoria de "empezar en el Principio". Puedes lanzarte a depurar la red justo en la última conversación con el jefe villano final sin pasar tediosos menús u opciones de nodos intermedios. Simplemente pulsa el nudo central requerido en tu desplegable de Begin y evalúa en un segundo ese fragmento de misión exacto.

---

## Velocimetría

La métrica temporal rige las cadencias bajo tu slider inferior en "MS" u milisegundos. Avanza rapidísimo un nodo a casi imperceptible velocidad, ideal para redes sin bifurcaciones largas repletas de textos estáticos y parará ante tu decisión discursiva próxima. O ralentízalo logrando observar el "cómo transita la ruta o camino de las tuberías visualmente" sin volverte loco. 

---

## Mapeado visual vivo 

Además del listado general consola-textual inferior, la flecha y trazados encenderán dinámicamente un contorno e interior fosforescente y focal central remitiéndote justo por donde camina la trama como un GPS encendido que recalcula trayectos auto-fijándose en tu lente.

---

## Cuatro pilares informativos

Contarás inferiormente en base con estas pestañas especializadas. 

### Console (Consola general)

Impresión algorítmica cronometrada, expondrá cada nodo, si algo intercedió y lo supero o algo dictaminó una barrera falsa (Fails) indicándote "El usuario requería poseer Gema (True) y obtuvo (False)". Así previenes paros absurdos durante el juego descubriendo aquí el intríngulis, junto al logeo de advertencias como bloqueos irresolubles o falta terminales si te olvidases ligar nodos (Alertas color carmesí/amarillo).

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Ventana base de diagnóstico evaluando una ramificación condicionada de tu partida virtual y visualizando en directo si poseía tu test un objeto (Item=false) y falló una derivación por ello
</div>

### Variables

Pilar clave para testear sobre la marcha; rastrea y permite cambiar bajo doble pulsado el dato activo actual transmutado de tu héroe, y someter la partida "a qué sucedería" si fueras rico, le clicas 90 Monedas y sigues avanzando como si la regla fluyese, validando sus vertientes ricas por tu intrusismo sin re-iniciar desde 0. Te alertará y distinguirá con rombos o indicativo azulino o dorado todos los factores transformados natural o artificialmente dentro del propio testing desde su primer estado nativo de base (Iniciales) hasta su presente transmutado. 

### History (Histórico mutable) 

Lista exhaustiva informadora registrando el trazo exacto temporal para verificar "quiénes o en donde muté las monedas para volverme pobre, bajo qué nodo perdí dinero" e impedir errores cruzados al crear docenas instruccionales para un mismo dato de misión por toda tu interfaz. 

### Path (Trazos logarítimicos de avance y Paradas o "Breakpoints")

Al apretar frente a la esfera hueca del índice referencial temporal de ruta dictaminas "Detente en Seco" en aquél bloque puntual para evaluar su antes/después durante las transiciones Auto-Avanzables rápidas de testeo sin pausa previas. Es un alto en el camino voluntario como en los lenguajes puros que te dejará repasar variables antes del clímax para entender y proseguir, iluminado el punto fijado en rojo total para tus bloques en sus indicadores circulares, como en cualquier IDE de programación formal.

## Pila de profundidad cruzada a flujos extra (Call Stack)

De adentrarse mediante la Caja subflujo a un mundo u arbol foráneo. Un listado relacional referenciará un índice superpuesto y "ruta de miga de pan o breadcrumb": `Base Central -> Mision Foránea A -> Actual nodo`. Tras concluir saltando fuera del mismo el rastro regresará atándose naturalmente por donde partió hacia tu bloque final predispuesto.

Los ciclos interminables bucle ("Infinitud Logarítimica") están precavidos previniendo crasheos saltando alarmaciones y deteniéndote reventar memorias parándose la maquinara tras advertir exceso de rondas cíclicas sin escapes (Topes artificiales a 1000 vueltas). 
El cuadro y panel permite su encogimiento visual para adaptar el canvas para tus ojos y seguir navegando, readaptándose por memoria sin necesidad reestructurarlo manualmente.
