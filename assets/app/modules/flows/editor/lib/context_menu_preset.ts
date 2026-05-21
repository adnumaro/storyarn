/**
 * Custom render preset for the rete-context-menu-plugin signals.
 *
 * rete-vue-plugin ships a default `VuePresets.contextMenu.setup()` that
 * renders the library's stock `Menu` component. We provide our own
 * FlowRendererContextMenu.vue to match shadcn styling while delegating event
 * interception to rete-context-menu-plugin (so we do NOT re-implement the
 * broken DOM-listener approach — see
 * docs/audit/flow-context-menu-broken-after-vue-migration.md).
 */

import type { BaseSchemes } from "rete";
import type { RenderPreset } from "rete-vue-plugin/_types/presets/types";
import type { ContextMenuRender } from "rete-vue-plugin/_types/presets/context-menu/types";
import FlowRendererContextMenu from "../components/entities/rete/FlowRendererContextMenu.vue";

export function flowContextMenuPreset<
  Schemes extends BaseSchemes,
  K extends ContextMenuRender,
>(): RenderPreset<Schemes, K> {
  return {
    update(context) {
      if (context.data.type !== "contextmenu") return;
      return {
        items: context.data.items,
        searchBar: context.data.searchBar,
        onHide: context.data.onHide,
      };
    },
    render(context) {
      if (context.data.type !== "contextmenu") return;
      return {
        component: FlowRendererContextMenu,
        props: {
          items: context.data.items,
          searchBar: context.data.searchBar,
          onHide: context.data.onHide,
        },
      };
    },
  };
}
