# Phase 1: Foundation — NuxtUI + Base Components + Storybook

## Goal
Set up the Vue component infrastructure with NuxtUI, build all reusable base components, configure Storybook for isolated development, and verify the integration with Phoenix LiveView works correctly.

## Prerequisites
- [x] LiveVue installed and working
- [x] Vite configured alongside esbuild
- [x] `Select.vue` prototype validated
- [x] `LiveVue.Encoder` derived for all Ecto schemas
- [ ] NuxtUI standalone installed

## 1.1 NuxtUI Standalone Setup

### Install
```bash
npm install @nuxt/ui-vue reka-ui
```

### Configure
- Add NuxtUI's Tailwind plugin to `assets/vite.config.mjs`
- Create `assets/vue/plugins/nuxt-ui.js` — register NuxtUI plugin with Vue app
- Update `assets/vue/index.js` — add `app.use(nuxtUI)` in setup
- Create Storyarn theme override (`assets/vue/theme/storyarn.ts`) mapping NuxtUI design tokens to Storyarn's color palette (base-100, base-200, primary, etc.)

### CSS Isolation Strategy
- NuxtUI styles load via Vite only (v2 pages)
- DaisyUI styles load via Tailwind CLI (all pages, including v2 — harmless since NuxtUI uses `data-ui` selectors)
- No class name conflicts because NuxtUI components use `U` prefix and data attributes
- v2 pages opt-in via layout: `Layouts.vue_app` (new layout without DaisyUI component usage)

## 1.2 Storybook Setup

### Install
```bash
npm install -D @storybook/vue3-vite @storybook/addon-essentials
npx storybook@latest init --type vue3 --builder vite
```

### Configure
- `.storybook/main.ts` — point to `assets/vue/**/*.stories.ts`
- `.storybook/preview.ts` — import Storyarn CSS + NuxtUI theme
- Add `storybook` script to `package.json`
- Stories colocated with components: `Select.stories.ts` next to `Select.vue`

### Verify
- Storybook runs independently on port 6006
- NuxtUI components render with Storyarn theme
- LiveVue integration: create a "LiveView Connected" story that verifies `$live` mock works

## 1.3 Base Components (NuxtUI Wrappers)

Rebuild all base components using NuxtUI primitives. Each gets a Storybook story.

### Form Components
| Component | NuxtUI Base | Purpose | Story Variants |
|-----------|------------|---------|----------------|
| `SSelect.vue` | `USelect` + `USelectMenu` | Single/multi select with search, infinite scroll | static, server search, multi, disabled |
| `SInput.vue` | `UInput` | Text/number input with label, error state | text, number, placeholder, disabled, error |
| `STextarea.vue` | `UTextarea` | Multi-line text | basic, with label, disabled |
| `SCheckbox.vue` | `UCheckbox` | Boolean toggle | checked, unchecked, indeterminate, disabled |
| `SToggle.vue` | `UToggle` | Switch toggle | on, off, disabled, with label |
| `SButton.vue` | `UButton` | Action button | primary, ghost, error, sizes, icon-only |
| `SBadge.vue` | `UBadge` | Status/tag badge | colors, sizes, removable |
| `SSlider.vue` | `USlider` | Range slider | basic, with ticks, disabled |

### Overlay Components
| Component | NuxtUI Base | Purpose | Story Variants |
|-----------|------------|---------|----------------|
| `SPopover.vue` | `UPopover` | Floating popover (config panels, color pickers) | positions, with form, nested |
| `SModal.vue` | `UModal` | Confirmation/detail dialogs | confirm, form, danger |
| `STooltip.vue` | `UTooltip` | Hover tooltips | positions, delay |
| `SSidebar.vue` | `USlideover` | Right-side sliding panel | basic, with scroll, close-on-outside |
| `SDropdown.vue` | `UDropdownMenu` | Context menu / dropdown | basic, with icons, nested groups |
| `SContextMenu.vue` | `UContextMenu` | Right-click menu | basic, with keyboard shortcuts |

### Layout Components
| Component | NuxtUI Base | Purpose | Story Variants |
|-----------|------------|---------|----------------|
| `SToolbar.vue` | custom | Floating toolbar (appears on hover) | basic, with dividers, pinned |
| `SDock.vue` | custom | Bottom dock bar (scene/flow tools) | with tools, active state |
| `SPanel.vue` | custom | Resizable side panel | left, right, with header |
| `STabs.vue` | `UTabs` | Tab navigation | basic, with icons, vertical |
| `STree.vue` | custom | Tree navigation (sheets, flows, scenes) | basic, with drag, search |

### Domain Components (Storyarn-specific)
| Component | Purpose | Dependencies |
|-----------|---------|-------------|
| `ConditionBuilder.vue` | Variable condition editor (if X > Y then...) | SSelect, SInput, SButton |
| `InstructionBuilder.vue` | Variable assignment editor (set X = Y) | SSelect, SInput, SButton |
| `ExpressionEditor.vue` | Formula/expression editor with CodeMirror | SInput, SPopover |
| `ColorPicker.vue` | Color selection with presets | SPopover, vanilla-colorful |
| `EditableText.vue` | Click-to-edit text (titles, shortcuts) | SInput |
| `SaveIndicator.vue` | Save status display (idle/saving/saved) | SBadge |
| `AvatarGroup.vue` | Online user avatars | custom |

## 1.4 LiveView Integration Layer

### Composables
| Composable | Purpose |
|-----------|---------|
| `useLive()` | Wrapper around `useLiveVue()` with typed pushEvent |
| `useServerSearch(searchFn)` | Server-side search with debounce + pagination |
| `useUndoRedo()` | Undo/redo stack management |
| `usePresence(scope)` | Collaboration presence tracking |
| `useKeyboard(bindings)` | Keyboard shortcut management |
| `useSortable(options)` | Drag-and-drop reordering via native drag API |
| `useFloating(options)` | Floating UI positioning (if not using NuxtUI popovers) |

### Event Contract
Define a typed event system between Vue and LiveView:
```typescript
// assets/vue/types/events.ts
interface LiveEvents {
  // Scene events
  'update_pin': { id: number, field: string, value: any }
  'update_zone': { id: number, field: string, value: any }
  'create_pin': { position_x: number, position_y: number, layer_id: number }
  'delete_pin': { id: number }
  // ... all events from show.ex handle_event clauses
}
```

## 1.5 Theme Configuration

### Storyarn Design Tokens → NuxtUI Theme
```typescript
// assets/vue/theme/storyarn.ts
export default {
  colors: {
    primary: 'var(--color-primary)',      // from DaisyUI/Tailwind
    neutral: 'var(--color-base-content)',
    surface: 'var(--color-base-100)',
    surfaceAlt: 'var(--color-base-200)',
    border: 'var(--color-base-300)',
    error: 'var(--color-error)',
    warning: 'var(--color-warning)',
    info: 'var(--color-info)',
    success: 'var(--color-success)',
  },
  // Map NuxtUI component variants to Storyarn look
}
```

## Deliverables
- [ ] NuxtUI installed, themed, rendering in `/dev/vue-test`
- [ ] Storybook running with all base components
- [ ] All form/overlay/layout components built and tested in Storybook
- [ ] ConditionBuilder and InstructionBuilder working in Storybook
- [ ] Composables (useLive, useServerSearch, useUndoRedo) tested
- [ ] No CSS conflicts between NuxtUI and DaisyUI on existing pages

## Estimated Scope
~35 Vue components + ~7 composables + Storybook setup + NuxtUI theme
