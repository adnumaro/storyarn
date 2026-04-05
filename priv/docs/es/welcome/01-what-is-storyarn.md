%{
title: "¿Qué es Storyarn?",
category_label: "Bienvenido",
order: 1,
description: "Un resumen de Storyarn y lo que puede hacer por tus proyectos narrativos."
}

---

Storyarn es una **plataforma de diseño narrativo** para diseñadores de juegos y narradores interactivos. Reúne todo tu trabajo narrativo en un solo lugar: personajes, diálogos, mapas del mundo, guiones y traducciones.

Ya sea que estés construyendo un RPG, una novela visual o un juego de aventuras, Storyarn te da las herramientas para diseñar tu historia de forma visual y colaborativa.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Resumen del proyecto — barra lateral con iconos de herramientas, una hoja abierta en el editor
</div>

---

## ¿Por qué Storyarn?

Hay herramientas por ahí que hacen algo de lo que hace Storyarn. Hojas de cálculo para datos de personajes. Aplicaciones de diagramas de flujo para árboles de diálogo. Scripts personalizados para localización. Quizás has usado una de las pocas herramientas dedicadas al diseño narrativo, y te encontraste peleando contra una interfaz que parece diseñada en 2008, o chocando contra un muro de complejidad antes siquiera de poder empezar a construir.

**Te mereces algo mejor.** Si alguna vez has sentido que tus herramientas narrativas te retrasan (demasiado aparatosas, demasiado fragmentadas, demasiado difíciles de aprender), Storyarn fue hecho para ti.

Una única plataforma. Todo conectado. Define las estadísticas de un personaje en una **Hoja** (Sheet), referéncialas en un **Flujo** (Flow) para crear un diálogo ramificado, sitúa esa localización en un mapa de la **Escena** (Scene), exporta el texto como un **Guion** (Screenplay) y tradúcelo todo con las herramientas de **Localización** (Localization). Cambia un valor una vez, y todos los flujos que lo comprueban reflejarán la actualización al instante.

---

## Herramientas principales

<h3><span class="docs-tool-icon"><svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M10 9H8"/><path d="M16 13H8"/><path d="M16 17H8"/></svg></span> Hojas (Sheets)</h3>

Contenedores de datos estructurados para todo tu mundo: perfiles de personajes, catálogos de objetos, detalles de ubicaciones, registro de misiones. Cada campo se convierte en una **variable** que los flujos, las escenas y las condiciones pueden leer y modificar. Organiza el contenido en carpetas, hereda propiedades entre hojas y registra todos los cambios gracias al control de versiones integrado.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Editor de tablas — perfil de personaje con bloques de texto, número y selectos, una sección de propiedades heredadas y un bloque de tabla
</div>

<h3><span class="docs-tool-icon"><svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="6" x2="6" y1="3" y2="15"/><circle cx="18" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="M18 9a9 9 0 0 1-9 9"/></svg></span> Flujos (Flows)</h3>

Grafos de nodos visuales para lógica narrativa y diálogos con ramificaciones. Nueve tipos de nodos, desde diálogo y condiciones hasta saltos y sub-flujos. Prueba tu trabajo al instante con el **Story Player** (ejecución cinemática completa) y el **Modo Debug** (ejecución paso a paso con inspección de variables en vivo). Sin necesidad de exportar: verifica tu lógica en el mismo lugar donde la escribes.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Editor de flujos — árbol de diálogo ramificado con nodos de diálogo, condición e instrucción conectados
</div>

<h3><span class="docs-tool-icon"><svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="3 6 9 3 15 6 21 3 21 18 15 21 9 18 3 21"/><line x1="9" x2="9" y1="3" y2="18"/><line x1="15" x2="15" y1="6" y2="21"/></svg></span> Escenas (Scenes)</h3>

Mapas interactivos para tu mundo. Dibuja áreas, coloca marcadores de personajes y conecta las ubicaciones visualmente. Las áreas ejecutan asignaciones de variables, evalúan condiciones y descienden a escenas secundarias. El **Modo Exploración** es donde todo cobra sentido: una experiencia inmersiva para el jugador donde caminas por tu mundo, activas flujos como pantallas superpuestas sobre el mapa, y ves tu arte, tus personajes y tus diálogos traducidos, todo funcionando en un mismo sitio. Ninguna otra herramienta de diseño narrativo hace esto.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Editor de escenas — mapa del mundo con áreas coloreadas, puntos de interés de personajes, conexiones y el panel de capas
</div>

<h3><span class="docs-tool-icon"><svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 21h12a2 2 0 0 0 2-2v-2H10v2a2 2 0 1 1-4 0V5a2 2 0 1 0-4 0v3h4"/><path d="M19 17V5a2 2 0 0 0-2-2H4"/><path d="M15 8h-5"/><path d="M15 12h-5"/></svg></span> Guiones (Screenplays)</h3>

Escribe y lee tu texto narrativo utilizando el formato de guion estándar de la industria. Cuenta con soporte nativo Fountain para importar/exportar hacia herramientas profesionales, con una sincronización automática y bidireccional respecto a tus diagramas de flujo.

<h3><span class="docs-tool-icon"><svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m5 8 6 6"/><path d="m4 14 6-6 2-3"/><path d="M2 5h12"/><path d="M7 2h1"/><path d="m22 22-5-10-5 10"/><path d="M14 18h6"/></svg></span> Localización (Localization)</h3>

Extrae todas las líneas de diálogo automáticamente. Traduce todo utilizando la integración nativa de DeepL, gestiona diccionarios glosario para mayor consistencia en los nombres, y monitoriza tu progreso por cada idioma mediante informes técnicos detallados.

---

## ¿Para quién es?

Storyarn está pensado para cualquier involucrado en la creación de ficción interactiva — diseñadores narrativos, escritores de videojuegos, creadores de mundos (*world builders*), equipos de localización, y pequeños estudios que prefieren centralizar la producción con una única herramienta, en lugar de dispersarla entre cinco diferentes.
