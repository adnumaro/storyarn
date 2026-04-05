%{
title: "Tu primera hoja",
category_label: "Inicio Rápido",
order: 2,
description: "Crea una hoja de personaje y comprende cómo funcionan las variables."
}

---

Las Hojas (Sheets) son la columna vertebral geométrica de la base de datos de tu proyecto. Cada campo diminuto que añadas a la estructura de una hoja se convierte en el esqueleto de una  {accent}variable{/accent} universal; los demás flujos del resto del ecosistema podrán leerla o verla mutar activamente durante las partidas.

## Crea la Hoja (Sheet)

Entra en el interior de tu proyecto y elige la pestaña de **Hojas** en el menú lateral de herramientas. Haz clic en el gran botón de **Nueva Hoja** encima del panel izquierdo con esquemas en forma de árbol.

Una nueva hoja se creará mostrando su nombre por defecto provisorio. Haz clic directo al mismo título enorme cabecera para renombrarla — por ejemplo, escribe "Jaime". El {accent}atajo{/accent} (shortcut interno que se aprecia en renglones debajo del nombre título) será auto-generado dinámicamente mediante formato simple de letras y barras bajas al instante. Claro que si a ti no te gusta ese atajo podrás refinarlo tu mismo — en el peculiar caso que estemos con nuestro personaje "Jaime", el atajo manual `pj.jaime` resulta extraordinario porque esto logra establecerte tu propio sistema natural y ordenado para encontrar todas tus variables internas sin perderte luego.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Una nueva pantalla de hoja con el título principal "Jaime" y el recuadro gris identificador atajo "mc.jaime" visible abajo
</div>

## Incorpora bloques

Haz clic en el diminuto símbolo **+** posicionado al fondo final por abajo de tu hoja recién creada. Eso abrirá un veloz anillo de menú. Los distintos tipos de bloques han sido seccionados inteligentemente bajo un par de categorías lógicas principales:

**Bloques Simples Base** — Caja de Texto simple, Texto Enriquecido multilínea, Número, Casilla Selectora fija, Casilla Bio Selectora múltiple lista, Fecha, Interruptores (Sí/No) Booleano, y los Enlaces cruzados de Referencia de punteros directos.

**Datos Estructurados Densos** — Cuadrículas de Matrices Tabulares (Tabla generalizada), Álbumes o visuales artísticos fotográficos de Galería en bloque.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Menú flotante selector mostrando Bloques Base estáticos a la izquierda y Datos en bloque listados en columna
</div>

Intentemos agregar los siguientes de forma rápida a nuestro buen personaje Jaime:

1. Elige una casilla tipo estadística de **Número** etiquetándola en base con la nomenclatura "Salud". Dale clic y establécele su magnitud número al estado virgen en `100`. Acabas de ensamblar tu propia constante variable llamada universalmente `pj.jaime.salud`.

2. Carga en pantalla y elige esta vez la pastilla **Menú de Selección (Select)** con su nombre respectivo y etiqueato: "Clase Principal". Introdúcete al pequeño panel de engrane del panel de Configuración e inyecta palabras elegibles base (como "Guerrero pesado", "Mago rúnico" y también "Granuja infiltrador o pícaro" como quieras y consideres el folclore). ¡Boom!, esto te dará una etiqueta interactiva global al aire llamada `pj.jaime.clase_principal`.

3. Terminaremos poniendo por fin una celda básica cruda **Interruptor Si/No (Booleano)** designando con texto "Sigue vivo" junto al bloque mismo en vivo. Acciona y gíralo tú encendido en posición visual verde luz con su puntero de acción a tope. Variables interactivas creadas con valor cierto `pj.jaime.sigue_vivo`.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Detalle en hoja con una ranura "Salud" de magnitud cien y lista cargando con sus casillas Boolean "Sigue Vivo" verde habilitado
</div>

## Constantes inmutables frente a variables modulares ágiles 

Ten predeterminado que por costumbre y base todos y cada de tu gran abarque base y su gran cantidad de ranuras de bloque base a bloque visual será una variable — las escasas particularidades excepciones son los Bloques puramente de {accent}Cruces Referenciales{/accent} con enlaces externos sin sentido y fotos arte {accent}Galerías y Medios visuales de estantes{/accent}, que no arrojan valor lógico a flujos.

En ocasiones tu afán narrativo en hojas necesitará rellenarse con texto literario e historia lore personal sobre datos narrativos puros "que el programador o motor lógico jamás tendrá uso pero se verán hermosos y se consultarán". Dale su respeto: apaga y anula temporalmente la casilla lógica pulsando "es constante estática bloqueada narrativa sin valor juego" (Is Constant). Solo se queda de guía o aclaratoria a usuarios, impidiendo aglomeración inútil y confusa durante programación fluida general donde a ti poco uso lógico matemático extra tendrían.

## Cómo operan e intentan trabajar juntas las dinámicas matemáticas Variables bases  

Cualquier fragmento no-marcado bloque perene pasará instantáneamente y de lleno al ecosistemas global interconectivo variables usando como eslabón el canon métrica en red `{atajo_interno_hoja}.{nombre_variable_con_guiones_bajo}`:

| Categoría Bloque  | Variable General Resultante  | Matriz Sub Tipo |
| -------- | ------------------- | ------- |
| Salud   | `pj.jaime.salud`   | numerical (número)  |
| Clase    | `pj.jaime.clase_principal`    | string select (texto cerrado) |
| Sigue Vivo | `pj.jaime.sigue_vivo` | estatus sí/no boolean logico puro |

El {accent}nombre codificado auto-generado interno formal de variable{/accent} siempre sigue la forma y trazo natural inferior del código etiqueta visible superficial y literal de humano (letras sin mayúscula, guion interno sustituyen espacio normal en blanco). Se da la capacidad que manipules reescribas esta variante visual cruda particular interna tú al engrane particular del menú. Ciertas traducciones necesitan a un identificador interno de referencia diferente de su aspecto frontal por si algo requiriere programación lógica muy fina externa compleja superior de exportaciones externas a Godot / y software y motores propios Unreal externos.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Detalle en el panel global derecho extra con variables codificadas grises mostrando de que tratan internamente al abrir configuración de atributos variables
</div>

Para nuestra siguiente lección formal práctica usaremos este número abstracto métrico puramente `pj.jaime.salud` con tal lograr que este número mágico base logre obligar de forzoso y dinámico un bifurcado lógico y visual a uno real durante su trama global dentro nuestro Flujo relacional orgánico.
