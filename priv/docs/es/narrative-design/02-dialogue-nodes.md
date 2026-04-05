%{
title: "Nodos de Diálogo",
category_label: "Diseño Narrativo",
order: 2,
description: "Discurso de los personajes, respuestas del jugador y configuración de diálogos."
}

---

Los nodos de diálogo son el tipo de nodo más común. Representan **lo que dice un personaje** y, opcionalmente, **lo que el jugador puede responder**. Cada nodo de diálogo puede ser tan simple como una sola línea de texto o tan rico como un compás narrativo completamente configurado con personaje, acotaciones y múltiples ramas de respuesta.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Un nodo de diálogo seleccionado en el editor de flujos con el panel lateral abierto mostrando todos los campos
</div>

---

## Escribiendo diálogos

Selecciona un nodo de diálogo para abrir el panel lateral. Encontrarás los siguientes campos:

- **Orador (Speaker)** -- enlace a una hoja de personaje de tu proyecto. El nombre y el avatar del personaje aparecen en el nodo en el lienzo, y el contexto del orador se usa para la extracción de traducciones y exportaciones de guiones (screenplay).
- **Texto** -- la línea de diálogo en sí. Este es un campo de texto enriquecido con formato (negrita, cursiva, subrayado, tachado, enlaces). Admite variables de mención de personajes para texto dinámico.
- **Acotaciones (Stage Directions)** -- notas de actuación opcionales que acompañan la línea (p. ej., "suspira profundamente", "se gira hacia la ventana"). Aparecen en las exportaciones de guion.
- **Texto en el Menú** -- una versión reducida o alternativa de la línea para los menús de elección, útil cuando el texto completo del diálogo es demasiado largo para mostrarse como una opción para elegir por el jugador.

---

## Editor de guiones (Screenplay editor)

Haz doble clic en un nodo de diálogo (o haz clic en el botón de ajustes en la barra de herramientas) para abrir el {accent}**editor de guiones**{/accent} -- un modo de escritura a pantalla completa que muestra todos los campos de diálogo en un diseño simplificado enfocado a escrbir fluido. Es la forma más rápida de volcar y revisar los contenidos del diálogo sin desviar la mirada en revisar interconexiones y lienzos.

---

## Audio y campos técnicos

- **Audio** -- adjunta un archivo de audio para un doblaje de voz (voiceover). Cuando un archivo de audio está enlazado, aparece un icono de audio en el nodo en el lienzo indicando este hecho.
- **ID Técnico** -- un identificador único para integrarlo dentro del motor de juego de tu preferencia. Pulsa en generar (varita mágica) para que tome parte automática de identificativos descriptivos enlazables y de rastreo único (e.j., `taberna_mision_cantinero_3`). Puedes teclear o establecer propios si lo deseas.
- **ID de Localización** -- generado de manera autómata y vital. La maquinaria y su sistema rastreará los traslados léxicos vinculándolo por esto. No puede, de normal, ni será necesario modificarse. 

---

## Reemplazo de retrato (Image override)

Si se configuran galerías pre-adjuntas en las fojas (hojas base de oradores) se liberará una facultad llamada **revisor fotográfico** en su lista para este bloque.  Esto fuerza una estampa temporal como cara retratada frente al usual para exhibir en tu reproductor la variedad emocional deseada sin re-escribir su retrato primario generalizado del personaje.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Selección previsualizable sobre caras cambiables al nodo individualizado según el listado del actor originario en hoja global vinculada.
</div>

---

## Opciones y Respuestas

Dicha ventana te otorga derivaciones: **opciones / opciones elegibles de jugador**. Aquellas portarían sus enlaces separando trazados dependientes al resultado del cliqueo. Muestra en lista lo establecido y ordena la visión real para las interacciones que se observan al ejecutarlas de orden estricto de arriba abajo. Los botones agregan o suprimen los caminos, siendo reajustados para el motor los enlaces dibujados o borrados en tu canvas al hacer esto. 

---

## Condicionantes de la Elecciones

La misma facultad para prohibir nodos entra aquí para ocultarlas **como derivaciones condicionales directas** sin reasignarlas artificialmente a "nodos constructores condicionales" en línea, que saturarían de flechas la vista. 
El modo interno es análogo y emplea idénticos menús. Si reprueba y fallan los valores exigidos de los datos del proyecto, no son proyectados (desaparecen) o si prefieres prever las tramas inalcanzables, habilitar la pre-vista y *Análisis Mode (Analizar)* te permite contemplarlas expuestas como tachadas en gris sin acceso. Un glifo y un icono avisa desde tu vista principal que aquella opción dispone de condicional o llave subyacente para no perderse rastro a simple vista.

---

## Instrucciones In-line de respuesta (Atajos)

A colación de sus condicionales, idénticamente suceden afectaciones al elegirse dicho sendero: Las **instrucciones de respuesta** asimilan cálculos (Suma, Multiplica, Restablece verdaderos). 

Agilizar los datos base sin nodos satelitales, logran sumar limpieza y ligereza si los resultados lógicos y simples sólo suceden para ser impactados bajo aquél hilo sin repetición compleja en múltiples vías unificadas. Mismos listados informantes en el canvas demuestran qué lazo guarda estos procesos silenciosos empotrados e intrínsecos de dichas respuestas opcionales de interatuación de diálogos. 

---

## Vínculos referenciales Personificados

Al adherir en todo acto discursivo a tus pre-trazados fichados (Oradores):
- **Facilitas su visibilidad visual:** Al imprimir rótulo fotográfico avatar originario.  
- Acompaña descripciones referenciadas sobre el **intérprete originario en base datos** para un posterior entendimiento preciso a los Equipos de Traducciones de localización léxico-cultural sin error a equivoco de quién emitió en tu guión un exabrupto en cierto caso en un listado Excel plano.
- Redactores directores y cineastas recibirán su guión con los formatos referenciales al exportarlos. 

Podrás incluir entidades inanimadas (Tótems discursivos), NPCs o Personajes Estelares sin restrincción mientras hayan sido formados y pre-listados en su carpeta "Sheets" originaria.
