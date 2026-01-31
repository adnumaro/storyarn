# Plan: Refactor a Sistema Notion-like

## Estado: ✅ FASE 1 COMPLETA | ✅ FASE 1.5 COMPLETA | ✅ FASE 2 COMPLETA | ✅ FASE 2.5 COMPLETA

Transformación del sistema de "Templates + Entities" a "Pages + Blocks" estilo Notion completada.

---

## Resumen del Cambio

**Antes:**
- Templates definen schemas rígidos
- Entities pertenecen a un template
- Campos predefinidos en el template
- Variables globales separadas

**Después:**
- Pages (nodos) en un árbol libre
- Cada page tiene bloques dinámicos
- Bloques se añaden on-the-fly con menú "/"
- Sin restricciones de tipos
- Sin sección de variables (todo es páginas y bloques)

---

## ✅ Completado (Fase 1)

### Migraciones de DB
- [x] Migración `20260130190929_refactor_to_pages_and_blocks.exs`
- [x] Renombrar `entities` → `pages`
- [x] Crear tabla `blocks`
- [x] Eliminar tabla `entity_templates`

### Schemas y Contextos
- [x] `lib/storyarn/pages/page.ex` - Schema de página
- [x] `lib/storyarn/pages/block.ex` - Schema de bloque
- [x] `lib/storyarn/pages.ex` - Contexto Pages con delegaciones
- [x] Bloques integrados en Pages context
- [x] `test/support/fixtures/pages_fixtures.ex` - Fixtures actualizados

### UI - Sidebar
- [x] Sidebar muestra árbol de páginas
- [x] Crear página desde sidebar (botón +)
- [x] Navegación al hacer click

### UI - Page View
- [x] `lib/storyarn_web/live/page_live/show.ex` - Vista de página
- [x] Header con icon + name editable inline
- [x] Lista de bloques

### UI - Bloques
- [x] Menú para añadir bloques
- [x] Componente TextBlock
- [x] Componente NumberBlock
- [x] Componente SelectBlock
- [x] Componente MultiSelectBlock

### Cleanup (Templates/Entities)
- [x] Eliminar `lib/storyarn/entities/entity.ex`
- [x] Eliminar `lib/storyarn/entities/entity_crud.ex`
- [x] Eliminar `lib/storyarn/entities/entity_template.ex`
- [x] Eliminar `lib/storyarn/entities/template_schema.ex`
- [x] Eliminar `lib/storyarn/entities/templates.ex`
- [x] Eliminar `lib/storyarn_web/live/entity_live/*`
- [x] Eliminar `lib/storyarn_web/live/template_live/*`
- [x] Eliminar `test/e2e/entities_e2e_test.exs`

---

## ✅ Completado (Fase 1.5) - Eliminar Variables

### Archivos eliminados
- [x] `lib/storyarn/entities/variable.ex` - Schema
- [x] `lib/storyarn/entities/variables.ex` - Contexto
- [x] `lib/storyarn/entities.ex` - Facade
- [x] `lib/storyarn/entities/` - Directorio completo
- [x] `lib/storyarn_web/live/variable_live/` - LiveView
- [x] `test/storyarn/entities_test.exs` - Tests
- [x] `test/support/fixtures/entities_fixtures.ex` - Fixtures
- [x] `test/storyarn_web/live/variable_live/` - Tests LiveView

### Archivos modificados
- [x] `lib/storyarn_web/router.ex` - Quitada ruta `/variables`
- [x] `lib/storyarn_web/components/project_sidebar.ex` - Quitado link Variables

### Migración
- [x] `20260131110443_drop_variables_table.exs` - Elimina tabla `variables`

### Verificación
- [x] 274 tests passing
- [x] Credo clean (no issues)

---

## Arquitectura Final

### Modelo de Datos

```
Project
└── Pages (árbol libre via parent_id)
    └── Blocks (contenido dinámico)
```

### Schema: Page

```elixir
schema "pages" do
  field :name, :string
  field :icon, :string, default: "page"
  field :position, :integer, default: 0

  belongs_to :project, Project
  belongs_to :parent, __MODULE__
  has_many :children, __MODULE__, foreign_key: :parent_id
  has_many :blocks, Block

  timestamps(type: :utc_datetime)
end
```

### Schema: Block

```elixir
@block_types ~w(text rich_text number select multi_select divider date)

schema "blocks" do
  field :type, :string
  field :position, :integer, default: 0
  field :config, :map, default: %{}
  field :value, :map, default: %{}

  belongs_to :page, Page

  timestamps(type: :utc_datetime)
end
```

### Ejemplos de Configuración de Bloques

```elixir
# Text block
%Block{
  type: "text",
  config: %{"label" => "Name", "placeholder" => "Enter name..."},
  value: %{"content" => "John Doe"}
}

# Number block
%Block{
  type: "number",
  config: %{"label" => "Age", "placeholder" => "0"},
  value: %{"content" => "25"}
}

# Select block
%Block{
  type: "select",
  config: %{
    "label" => "Status",
    "options" => [
      %{"key" => "active", "value" => "Active"},
      %{"key" => "inactive", "value" => "Inactive"}
    ]
  },
  value: %{"selected" => "active"}
}

# Multi-select block
%Block{
  type: "multi_select",
  config: %{
    "label" => "Tags",
    "options" => [
      %{"key" => "important", "value" => "Important"},
      %{"key" => "draft", "value" => "Draft"}
    ]
  },
  value: %{"content" => ["important", "draft"]}
}

# Divider block
%Block{
  type: "divider",
  config: %{},
  value: %{}
}

# Date block
%Block{
  type: "date",
  config: %{"label" => "Due Date"},
  value: %{"content" => "2026-02-15"}
}
```

### Tipos de Bloques

| Tipo           | Descripción                | Estado   |
|----------------|----------------------------|----------|
| `text`         | Input de texto simple      | ✅        |
| `rich_text`    | Editor WYSIWYG (TipTap)    | ✅        |
| `number`       | Input numérico             | ✅        |
| `select`       | Select simple (una opción) | ✅        |
| `multi_select` | Select múltiple (tags)     | ✅        |
| `divider`      | Separador horizontal       | ✅        |
| `date`         | Selector de fecha          | ✅        |

---

## URLs

| Ruta                                                               | Vista       | Descripción            |
|--------------------------------------------------------------------|-------------|------------------------|
| `workspaces/:workspace_slug/projects/:project_slug`                | Overview    | Dashboard del proyecto |
| `workspaces/:workspace_slug/projects/:project_slug/pages/:page_id` | Page editor | Editor Notion-like     |
| `workspaces/:workspace_slug/projects/:project_slug/settings`       | Settings    | Configuración          |

---

## ✅ Completado (Fase 2) - Page Tree Features

### Árbol de Páginas
- [x] Drag & drop para reordenar páginas
- [x] Mover página a otro padre (drag to nest)
- [x] Crear página hija desde árbol (botón +)
- [x] Búsqueda/filtro en el árbol
- [x] Preservar estado expand/collapse después de cambios
- [x] Breadcrumb de navegación

### Editor de Bloques
- [x] Drag & drop para reordenar bloques (SortableJS)
- [x] Componente RichTextBlock (TipTap) - Con toolbar y debounce
- [x] Guardado automático con debounce (500ms)
- [x] Indicador "guardando..." / "guardado"

---

## ✅ Completado (Fase 2.5) - Nuevos Bloques y Fixes

### Nuevos Tipos de Bloques
- [x] `divider` - Separador horizontal
- [x] `date` - Selector de fecha

### Bugs Corregidos
- [x] MultiSelect block - Rediseño completo con UI de tags y creación dinámica de opciones

---

## 🔲 Pendiente (Fase 3)

### Editor de Bloques - Mejoras
- [ ] Confirmación al eliminar bloques
- [ ] Atajos de teclado (Enter para añadir, Backspace para eliminar vacío)

### Nuevos Tipos de Bloques (Futuro)
- [ ] `image` - Imagen (upload/URL)
- [ ] `link` - Enlace interno/externo
- [ ] `callout` - Nota/callout
- [ ] `table` - Tabla simple
- [ ] `relation` - Relación a otra página

### Otras Mejoras
- [ ] Duplicar página
- [ ] Page templates (conjuntos de bloques predefinidos)
- [ ] Emoji picker para iconos de página
- [ ] Cover images para páginas
- [ ] Páginas recientes

---

## Archivos Clave

| Archivo                                          | Propósito            |
|--------------------------------------------------|----------------------|
| `lib/storyarn/pages.ex`                          | Contexto facade      |
| `lib/storyarn/pages/page.ex`                     | Schema de página     |
| `lib/storyarn/pages/block.ex`                    | Schema de bloque     |
| `lib/storyarn_web/live/page_live/show.ex`        | LiveView editor      |
| `lib/storyarn_web/components/project_sidebar.ex` | Sidebar con árbol    |
| `lib/storyarn_web/components/tree.ex`            | Componentes de árbol |
| `lib/storyarn_web/components/layouts.ex`         | `Layouts.project`    |
| `test/support/fixtures/pages_fixtures.ex`        | Test fixtures        |

---

## Decisiones Técnicas

### Editor WYSIWYG (Pendiente)

Opciones evaluadas:
1. **TipTap** - Basado en ProseMirror, muy flexible ← Recomendado
2. **Milkdown** - Markdown-first, ligero
3. **Quill** - Clásico, funciona bien

### Persistencia de Bloques

- Guardar en `phx-blur` para inputs simples
- Debounce de 500ms para rich text
- Indicador visual de estado de guardado

---

## Verificación

```bash
# Tests
mix test

# Calidad
mix credo --strict

# Verificación manual
# 1. Navegar a proyecto → sidebar muestra páginas
# 2. Crear página → aparece en árbol
# 3. Editar nombre inline
# 4. Añadir bloques via menú
# 5. Editar valores de bloques
```
