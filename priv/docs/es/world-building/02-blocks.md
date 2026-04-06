%{
title: "Bloques y Variables",
category_label: "Construcción de Mundos",
order: 2,
description: "Cómo los bloques definen tu estructura de datos y se convierten en variables para los flujos."
}

---

Los bloques (blocks) son los {accent}campos{/accent} de una ficha. Cada bloque tiene un tipo y una etiqueta. A menos que se marque como constante o use un tipo que no genera variables, un bloque se convierte automáticamente en una **variable** que los flujos pueden leer y modificar.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Una ficha con varios bloques de distintos tipos: texto, número, selección, booleano, mostrando sus etiquetas y valores actuales.
</div>

---

## Tipos de bloques

Storyarn admite {accent}10 tipos de bloques{/accent}:

| Tipo                   | Descripción                                                                          | ¿Variable?            | Ejemplo de valor                        |
| ---------------------- | ------------------------------------------------------------------------------------ | --------------------- | --------------------------------------- |
| **Texto**              | Entrada de texto corto o de una sola línea con placeholder opcional                  | Sí                    | `"Jaime"`                               |
| **Texto Enriquecido**  | Texto formateado con negrita, cursiva, listas, enlaces                               | Sí                    | `"<p>Un guerrero valiente...</p>"`      |
| **Número**             | Entrada numérica con restricciones opcionales de mín, máx y paso                     | Sí                    | `42`                                    |
| **Booleano**           | Interruptor. Admite modo de dos estados (true/false) o tres estados (true/false/nil) | Sí                    | `true`                                  |
| **Selección**          | Elección única de una lista de opciones definida                                     | Sí                    | `"warrior"`                             |
| **Selección Múltiple** | Múltiples elecciones de una lista definida (etiquetas)                               | Sí                    | `["fire", "ice"]`                       |
| **Fecha**              | Selector de fecha                                                                    | Sí                    | `"2024-03-15"`                          |
| **Tabla**              | Cuadrícula tipo hoja de cálculo con columnas tipadas y filas con nombre              | Sí (a nivel de celda) | Ver [Tablas](/es/world-building/tables) |
| **Referencia**         | Enlace a otra hoja o flujo                                                           | **No**                | --                                      |
| **Galería**            | Colección de imágenes de recursos subidos                                            | **No**                | --                                      |

Los bloques de referencia y galería se excluyen del sistema de variables porque no llevan un valor significativo en tiempo de ejecución.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El menú selector de tipos de bloque mostrando los 10 tipos con sus iconos.
</div>

---

## Nombrado de variables

Las variables siguen el patrón `{atajo_de_hoja}.{nombre_de_variable}`.

El nombre de variable se {accent}genera automáticamente{/accent} a partir de la etiqueta del bloque: los espacios se convierten en guiones bajos, los caracteres acentuados se transliteran a ASCII y todo se pone en minúsculas.

| Etiqueta      | Nombre de variable | Referencia completa (en `mc.jaime`) |
| ------------- | ------------------ | ----------------------------------- |
| Health Points | `health_points`    | `mc.jaime.health_points`            |
| Clase Social  | `clase_social`     | `mc.jaime.clase_social`             |
| Is Alive      | `is_alive`         | `mc.jaime.is_alive`                 |

Puedes personalizar el nombre de variable después de crearlo. Si una ficha ya tiene una variable con el mismo nombre (p.ej., por herencia), Storyarn añade un sufijo numérico para mantener los nombres únicos.

---

## Constantes

Marca un bloque como {accent}constante{/accent} para excluirlo del sistema de variables. Las constantes son para datos estáticos que los flujos nunca necesitan comprobar o modificar: descripciones de personajes, texto de ambientación, entradas de lore, imágenes de referencia.

Un bloque constante sigue mostrándose en la ficha y se incluye en las capturas de versión — simplemente no aparecerá en el selector de variables al construir condiciones o instrucciones en los flujos.

---

## Configuración de bloques

Cada tipo de bloque tiene sus propias opciones de configuración:

- **Texto** -- texto de placeholder.
- **Número** -- placeholder, valores mínimo, máximo y de paso para validación de entrada.
- **Booleano** -- modo de dos estados (true/false) o tres estados (true/false/sin asignar).
- **Selección / Selección Múltiple** -- una lista de opciones, cada una con una clave y un valor de visualización.
- **Tabla** -- visualización plegable, más definiciones de columnas y filas (ver [Tablas](/es/world-building/tables)).
- **Referencia** -- tipos de destino permitidos (hoja, flujo).

---

## Alcance de propiedades

Cada bloque tiene un {accent}alcance (scope){/accent} que controla la herencia:

- **Propio (Self)** -- el bloque solo existe en esta hoja. Es el valor predeterminado.
- **Hijos (Children)** -- la definición del bloque se propaga en cascada a todas las fichas descendientes. Cada hija obtiene una instancia con el mismo tipo, etiqueta y configuración pero su propio valor independiente.

Cuando un bloque padre con alcance "hijos" se actualiza (etiqueta, tipo, opciones), todas las instancias hijas no desvinculadas se sincronizan automáticamente. Si el tipo cambia, los valores de las hijas se restablecen al valor predeterminado del nuevo tipo.

Puedes **desvincular (detach)** una instancia heredada para que deje de sincronizarse con el padre. Un bloque desvinculado mantiene su configuración actual y puede editarse independientemente. Puedes **volver a vincularlo (re-attach)** más tarde para resincronizarlo con la definición del padre.

---

## Bloques obligatorios

Marcar un bloque como {accent}obligatorio (required){/accent} lo señala para el seguimiento de completitud. Los bloques obligatorios que estén vacíos se resaltarán, ayudándote a identificar fichas incompletas de un vistazo.

La marca de obligatorio también se hereda: cuando un bloque padre con alcance "hijos" es obligatorio, todas las instancias hijas heredan esa obligación.

---

## Disposición en columnas

Los bloques pueden organizarse en una {accent}disposición multicolumna{/accent} usando grupos de columnas. Dentro de un grupo, los bloques pueden colocarse en las posiciones 0, 1 o 2, permitiendo hasta tres bloques lado a lado para disposiciones de hoja más compactas.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Una ficha con bloques organizados en disposición de dos columnas, mostrando Name y Class lado a lado, con Health y Level debajo.
</div>
