# Phase 3: Sheet Editor V2 — Full Vue Migration

## Goal

Create a complete Vue-based sheet editor at `/v2/.../sheets/:id` with all block types, toolbar, config popovers, inheritance, tables, galleries, formulas, and undo/redo. This is the component that had the 400ms+ reflow problem — Vue eliminates it entirely.

## Prerequisites

- [ ] Phase 1 complete (base components)
- [ ] Phase 2 validates the LiveVue architecture at scale

## 3.1 Route & LiveView Shell

### Route

```elixir
live "/v2/workspaces/:workspace_slug/projects/:project_slug/sheets/:id",
     SheetLive.ShowV2, :show
```

### LiveView (`sheet_live/show_v2.ex`)

```elixir
def render(assigns) do
  ~H"""
  <.vue
    v-component="SheetEditor"
    v-socket={@socket}
    id="sheet-editor"
    sheet={@sheet}
    blocks={@blocks}
    inherited_groups={@inherited_groups}
    children={@children}
    project={@project}
    workspace={@workspace}
    can_edit={@can_edit}
    project_variables={@project_variables}
  />
  """
end
```

## 3.2 Sheet Layout

```
┌──────────────────────────────────────────────┐
│ SheetHeader (banner, avatar, title, shortcut) │
├────────────┬─────────────────────────────────┤
│            │ Tabs: Content | References |     │
│ TreePanel  │        Audio | History          │
│ (sheets    ├─────────────────────────────────┤
│  tree)     │ ContentTab                      │
│            │  ├─ InheritedBlocks (grouped)   │
│            │  ├─ OwnBlocks (sortable)        │
│            │  │  ├─ BlockWrapper (per block)  │
│            │  │  │  ├─ BlockToolbar           │
│            │  │  │  └─ BlockContent           │
│            │  │  └─ ...                       │
│            │  └─ AddBlockButton               │
│            ├─────────────────────────────────┤
│            │ FormulaSidebar (right panel)     │
└────────────┴─────────────────────────────────┘
```

## 3.3 Block Components

### Block Wrapper

| Component                | Purpose                                                       |
| ------------------------ | ------------------------------------------------------------- |
| `BlockWrapper.vue`       | Selection ring, drag handle, scope indicator, toolbar trigger |
| `BlockToolbar.vue`       | Constant toggle, variable name, scope buttons, config gear    |
| `BlockConfigPopover.vue` | Type-specific config (dispatches to sub-components)           |

### Block Types

| Component              | Block Type     | NuxtUI Components Used                      |
| ---------------------- | -------------- | ------------------------------------------- |
| `TextBlock.vue`        | `text`         | SInput                                      |
| `NumberBlock.vue`      | `number`       | SInput (type=number)                        |
| `RichTextBlock.vue`    | `rich_text`    | TipTap Vue integration                      |
| `SelectBlock.vue`      | `select`       | SSelect                                     |
| `MultiSelectBlock.vue` | `multi_select` | SSelect (multi mode)                        |
| `BooleanBlock.vue`     | `boolean`      | SToggle / tri-state custom                  |
| `DateBlock.vue`        | `date`         | SInput (type=date)                          |
| `ReferenceBlock.vue`   | `reference`    | SSelect (server search)                     |
| `TableBlock.vue`       | `table`        | Full table with columns, rows, cell editors |
| `GalleryBlock.vue`     | `gallery`      | Image grid with upload, reorder, lightbox   |

### Table Sub-Components

| Component              | Purpose                                                                    |
| ---------------------- | -------------------------------------------------------------------------- |
| `TableHeader.vue`      | Column headers with resize, dropdown menu                                  |
| `TableRow.vue`         | Row with cells, drag handle, row menu                                      |
| `TableCell.vue`        | Cell editor dispatcher (text, number, select, boolean, reference, formula) |
| `TableCellSelect.vue`  | Select/multi-select inside table cell                                      |
| `TableCellFormula.vue` | Formula display with click-to-edit                                         |
| `TableColumnMenu.vue`  | Column type, rename, delete, options                                       |
| `TableRowMenu.vue`     | Row rename, delete, move                                                   |

### Config Popover Sub-Components

| Component           | For Block Types      |
| ------------------- | -------------------- |
| `TextConfig.vue`    | text, rich_text      |
| `NumberConfig.vue`  | number               |
| `SelectConfig.vue`  | select, multi_select |
| `BooleanConfig.vue` | boolean              |
| `DateConfig.vue`    | date                 |

## 3.4 Inheritance System

| Component                   | Purpose                                    |
| --------------------------- | ------------------------------------------ |
| `InheritedSection.vue`      | Grouped inherited blocks from parent sheet |
| `InheritedBlockWrapper.vue` | Override/detach/reattach controls          |
| `PropagationModal.vue`      | Propagate changes to child sheets          |

## 3.5 Other Tabs

| Component           | Tab                                          |
| ------------------- | -------------------------------------------- |
| `ReferencesTab.vue` | Variable usage, backlinks, scene appearances |
| `AudioTab.vue`      | Audio asset selection for dialogue           |
| `HistoryTab.vue`    | Version history with compare/restore         |

## 3.6 Key Interactions (All Client-Side in Vue)

### Block Selection

- Click block → selection ring (Vue reactive state, no server roundtrip)
- Click outside → deselect
- Keyboard arrows → move selection up/down

### Block Value Editing

- Select pick → instant UI update, fire-and-forget to server
- Text input → debounced blur save
- Number input → debounced blur save with clamping
- Boolean toggle → instant flip, async save
- Rich text → TipTap onUpdate, debounced save

### Block Reordering

- Drag handle → Vue Sortable, optimistic reorder, server sync
- Column groups → drag between columns

### Toolbar Actions

- All instant in Vue, async save to server
- Config popovers open/close as Vue state (no server involvement)

## 3.7 Formula System

| Component                    | Purpose                                            |
| ---------------------------- | -------------------------------------------------- |
| `FormulaSidebar.vue`         | Expression input, binding selectors, LaTeX preview |
| `FormulaPreview.vue`         | KaTeX rendering of formula                         |
| `FormulaBindingSelector.vue` | Variable/column binding per symbol                 |

## 3.8 Undo/Redo

- `useUndoRedo()` composable manages stack in Vue
- Push actions from block operations
- Undo/redo dispatch events to server
- Keyboard: Ctrl+Z / Ctrl+Shift+Z

## Deliverables

- [ ] `/v2/.../sheets/:id` route working
- [ ] All 10 block types rendering and editing
- [ ] Block selection, reordering, toolbar, config popovers
- [ ] Table blocks with all cell types and column management
- [ ] Gallery blocks with upload and lightbox
- [ ] Inheritance (inherited blocks, detach, reattach, propagate)
- [ ] Formula sidebar with expression editing
- [ ] All tabs (content, references, audio, history)
- [ ] Undo/redo
- [ ] Zero reflow delay on any interaction
- [ ] Feature parity with current sheet editor

## Estimated Scope

~40 Vue components + TipTap integration + formula system
