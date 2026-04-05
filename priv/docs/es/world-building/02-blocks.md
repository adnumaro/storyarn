%{
title: "Bloques y Variables",
category_label: "Construcción de Mundos",
order: 2,
description: "Cómo los bloques definen tu estructura de datos y se convierten en variables para los flujos."
}

---

Los bloques son los {accent}campos{/accent} de una hoja. Cada bloque tiene un tipo y una etiqueta. A menos que se marque como constante o se use un tipo que no sea variable, un bloque se convierte automáticamente en una **variable** que los flujos pueden leer y modificar.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Una hoja con varios bloques de diferentes tipos: texto, número, selección, booleano, mostrando sus etiquetas y valores actuales.
</div>

---

## Tipos de bloques

Storyarn soporta {accent}10 tipos de bloques{/accent}:

| Tipo             | Descripción                                                                        | ¿Variable?       | Ejemplo de valor                        |
| ---------------- | ---------------------------------------------------------------------------------- | ---------------- | --------------------------------------- |
| ** Texto**       | Entrada de texto corta o de una sola línea con marcador de posición opcional        | Sí               | `"Jaime"`                               |
| **Texto Enriquecido** | Texto formateado con negrita, cursiva, listas, enlaces                          | Sí               | `"<p>Un guerrero valiente...</p>"`      |
| **Número**       | Entrada numérica con restricciones opcionales de min, max y paso                   | Sí               | `42`                                    |
| **Booleano**     | Interruptor (Toggle). Soporta modos de dos estados (true/false) o tres (true/false/nil) | Sí          | `true`                                  |
| **Selección**    | Elección única de una lista de opciones definida                                   | Sí               | `"guerrero"`                            |
| **Selección Múltiple** | Múltiples elecciones de una lista definida (etiquetas o tags)                  | Sí               | `["fuego", "hielo"]`                    |
| **Fecha**        | Selector de fecha (Date picker)                                                    | Sí               | `"2024-03-15"`                          |
| **Tabla**        | Cuadrícula estilo hoja de cálculo con columnas tipadas y filas con nombre          | Sí (nivel de celda)| Ver [Tablas](/es/world-building/tables)|
| **Referencia**   | Enlace a otra hoja o flujo                                                         | **No**           | --                                      |
| **Galería**      | Colección de imágenes a partir de archivos subidos                                 | **No**           | --                                      |

Los bloques de referencia y galería se excluyen del sistema de variables porque no contienen un valor significativo en tiempo de ejecución.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  El menú selector de tipo de bloque mostrando los 10 tipos con sus iconos.
</div>

---

## Nombramiento de variables

Las variables siguen el patrón `{hoja_shortcut}.{nombre_variable}`.

El nombre de la variable se {accent}autogenera{/accent} a partir de la etiqueta del bloque: los espacios se convierten en guiones bajos, los caracteres acentuados se transliteran a ASCII y todo se pone en minúsculas.

| Etiqueta      | Nombre de variable | Referencia completa (en `mc.jaime`) |
| ------------- | ------------------ | ----------------------------------- |
| Health Points | `health_points`    | `mc.jaime.health_points`            |
| Clase Social  | `clase_social`     | `mc.jaime.clase_social`             |
| Is Alive      | `is_alive`         | `mc.jaime.is_alive`                 |

Puedes personalizar el nombre de la variable después de su creación. Si una hoja ya tiene una variable con el mismo nombre (ej. por herencia), Storyarn añade un sufijo numérico para mantener los nombres únicos.

---

## Constantes

Marca un bloque como {accent}constante{/accent} para excluirlo del sistema de variables. Las constantes son para datos estáticos que los flujos nunca necesitan comprobar o modificar: descripciones de personajes, texto de ambientación, entradas de lore, imágenes de referencia.

Un bloque constante se sigue mostrando en la hoja y se incluye en las instantáneas de versiones (snapshots) -- simplemente no aparecerá en el selector de variables al construir condiciones o instrucciones en los flujos.

---

## Configuración de bloques

Cada tipo de bloque tiene sus propias opciones de configuración:

- **Texto** -- texto temporal (placeholder).
- **Número** -- valores placeholder, mínimo, máximo y nivel de incremento (step) para validación.
- **Booleano** -- modo de dos estados (true/false) o tres estados (true/false/no asignado).
- **Selección / Selección Múltiple** -- una lista de opciones, cada una con una clave (key) y un valor para mostrar.
- **Tabla** -- visualización plegable, además de definiciones de columnas y filas (ver [Tablas](/es/world-building/tables)).
- **Referencia** -- tipos de objetivos permitidos (hoja, flujo).

---

## Alcance de la propiedad (Scope)

Cada bloque tiene un {accent}alcance{/accent} que controla la herencia:

- **Propio (Self)** -- el bloque solo existe en esta hoja. Este es el valor por defecto.
- **Hijos (Children)** -- la definición del bloque cae en cascada a todas las hojas descendientes. Cada hijo obtiene una instancia con el mismo tipo, etiqueta y configuración pero con su propio valor independiente.

Cuando se actualiza un bloque padre con alcance "hijos" (etiqueta, tipo, opciones), todas las instancias hijas no desvinculadas se sincronizan automáticamente. Si el tipo cambia, los valores de los hijos se restablecen al valor por defecto para el nuevo tipo.

Puedes **desvincular (detach)** una instancia heredada para evitar que se sincronice con el padre. Un bloque desvinculado mantiene su configuración actual y puede editarse independientemente. Puedes **volver a vincularlo** más tarde para resincronizarlo con la definición del padre.

---

## Bloques obligatorios

Marcar un bloque como {accent}obligatorio (required){/accent} lo marca para el seguimiento de compleción. Los bloques obligatorios que estén vacíos se resaltarán, ayudándote a identificar de un vistazo las hojas incompletas.

El flag de obligatorio también se hereda: cuando un bloque padre con alcance "hijos" es obligatorio, todas las instancias hijas heredan esa obligación.

---

## Diseño de columnas

Los bloques pueden organizarse en un {accent}diseño de múltiples columnas{/accent} utilizando grupos de columnas. Dentro de un grupo, los bloques pueden colocarse en las posiciones de columna 0, 1 o 2, permitiendo hasta tres bloques uno al lado del otro para diseños de hoja más compactos.

<div class="docs-image-placeholder">
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
  Una hoja con bloques organizados en un diseño de dos columnas, mostrando Nombre y Clase uno al lado del otro, con Vida y Nivel debajo de ellos.
</div>
