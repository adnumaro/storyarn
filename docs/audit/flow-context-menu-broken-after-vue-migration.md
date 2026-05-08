# Flow context menu broken after Vue migration

**Severity:** Medium — user-visible regression blocking any right-click UX on the flow canvas.
**Found:** 2026-04-21, while verifying P-3 end-to-end (flow-player-redesign).
**Diagnosis confirmed:** 2026-04-21, after user pointed out v1 uses the rete-context-menu-plugin API.

## Symptom

Right-clicking on the flow canvas (node or empty area) shows the **native Chrome context menu** ("Atrás / Reenviar / Volver a cargar / Inspeccionar / ...") instead of the custom `FlowContextMenu.vue` menu. No JS console errors.

## Root cause

**Wrong architecture.** During the Vue migration, the custom `assets/app/modules/flows/components/FlowContextMenu.vue` was built as a Vue component that attaches a native `contextmenu` DOM listener on a parent `<div>`. That listener competes with rete.js, which manages its own event handling on the canvas, and loses.

v1 (`main` branch) uses `rete-context-menu-plugin` properly: wires `new ContextMenuPlugin({ items: createContextMenuItems(hook) })` in `assets/js/flow_canvas/setup.js` and provides items via `assets/js/flow_canvas/context_menu_items.js`. The plugin handles event interception internally; no manual DOM listeners are needed.

User, 2026-04-21: _"rete ya tiene un plugin de context menu: https://retejs.org/docs/guides/context-menu. Podemos crear el nuestro propio para que tenga los estilos que nosotros queremos. Es lo que habiamos hecho en v1 (rama main)."_

`rete-context-menu-plugin@^2.0.6` is already a declared dep in the project root `package.json`; it's just not wired up in v2 (`feat/live-vue-sheets`) flow setup.

## Initial hypotheses (ruled out — don't waste time on these)

Before consulting v1, I hypothesized the cause was either (1) rete capturing `contextmenu` in capture phase with `stopPropagation` or (2) Vue 3 prop timing making `containerRef.value` null at the child's `onMounted`. Both are **irrelevant** — the correct fix is not to patch the DOM listener but to delete it and wire the plugin properly.

## Scope of blocked features

Every existing right-click action is unreachable via UI until fixed:

- Duplicate / Copy ID / Delete (node)
- Add node submenu / Add note / Auto layout / Play preview / Start debugging (canvas)
- Per-node actions from v1 (locate referencing jumps / locate target hub / open referenced flow / generate technical ID / toggle switch mode / etc.)
- **Create sequence from here** (P-3 of flow-player-redesign, 2026-04-21) — backend verified via iex; UI entry point blocked.

## Correct fix (v1 pattern adapted to Vue)

Three pieces:

1. **Items function** — new `assets/app/modules/flows/lib/context_menu_items.ts`, ported from `main:assets/js/flow_canvas/context_menu_items.js`. Adapt for v2: remove `slug_line` (deleted 2026-04-20), add "Create sequence from here" for executable nodes, replace `hook.labels?.[key]` with `vue-i18n`'s `t` from `i18n.global`. Typed properly.

2. **Plugin wire-up** in `assets/app/modules/flows/reteSetup.ts`:

   ```ts
   import { ContextMenuPlugin } from "rete-context-menu-plugin";
   const contextMenu = new ContextMenuPlugin<FlowSchemes>({
     items: createContextMenuItems(hook),
   });
   area.use(contextMenu);
   render.addPreset(VuePresets.contextMenu.setup({ delay: 300 }));
   ```

3. **Rendering** — two options:
   - **Default** (`VuePresets.contextMenu.setup({ delay })`): uses rete-vue-plugin's bundled `Menu` component. Functional but unstyled to match shadcn — overrideable via CSS.
   - **Custom** — new `assets/app/modules/flows/components/FlowRendererContextMenu.vue` + bespoke render preset that routes the `contextmenu` render signal to our component. Full shadcn control.

### Implementation risks

1. **`context` param shape.** Items function receives `'root' | Schemes['Node']`. Rete `Node` has `.id`; `nodeType` / `nodeData` availability depends on how v2 constructs nodes (check `FlowSchemes` + `FlowNode` rete node class).
2. **HookProxy shape in v2 vs v1.** v1 items function used `hook.pushEvent`, `hook.area?.area?.pointer`, `hook.floatingToolbar?.show`, `hook.selectedNodeId`, `hook.sheetsMap`, `hook.performAutoLayout()`. v2 uses a reactive `flowContext` (`sheetsMap`, `selectedReteNodeId`, etc.) + hook methods. Mapping required.
3. **i18n outside Vue templates.** Items function is called outside reactive Vue scope; `$t` isn't available. Use `i18n.global.t` from the singleton.
4. **Toolbar / selection sync.** v1 items function side-effects on right-click to select the node and show the floating toolbar. In v2, this should update `flowContext.selectedReteNodeId` and push a `node_selected` event.

### Files to delete after fix ships

- `assets/app/modules/flows/components/FlowContextMenu.vue` (broken DOM-listener version)
- `<FlowContextMenu />` mount from `assets/app/modules/flows/components/FlowEditor.vue`

## Minimal reproduction

1. On `feat/live-vue-sheets`, open any flow.
2. Right-click anywhere on the canvas.
3. Native Chrome menu appears; custom menu never shows.

## Related context

Part of the ongoing Vue migration cleanup. User, 2026-04-21: _"Durante la migración de vue se rompió. Es en lo que estamos. Terminando de corregir la migración de cada una de las features a la vez que añadimos algunas features nuevas que tiene lógica añadir."_

## Recommended subfase split

- **4c1 — MVP (~90 min):** wire plugin + minimal items (Add node / Add annotation / Auto layout on canvas; Duplicate / Delete / Create sequence from here on node) + use default Vue `Menu` preset. Unblocks P-3 UI verification.
- **4c1-plus (~2h):** 4c1 + custom shadcn-styled `FlowRendererContextMenu.vue` (no subitems yet).
- **4c2 (~60-90 min):** full v1 parity — per-type items (locate hub, open referenced flow, generate technical_id, etc.) + subitem rendering. Can be deferred to migration tanda.
