/**
 * Custom render preset for the rete-context-menu-plugin signals.
 *
 * rete-vue-plugin ships a default `VuePresets.contextMenu.setup()` that
 * renders the library's stock `Menu` component. We provide our own
 * FlowRendererContextMenu.vue to match shadcn styling while delegating event
 * interception to rete-context-menu-plugin (so we do NOT re-implement the
 * broken DOM-listener approach).
 */

import type { BaseSchemes } from "rete";
import type { RenderPreset } from "rete-vue-plugin";
import FlowRendererContextMenu from "../components/entities/rete/FlowRendererContextMenu.vue";
import type { FlowContextMenuItem } from "./context_menu_items";

/**
 * Flow-owned view of the context-menu render signal.
 *
 * rete-vue-plugin does not export this signal from its public API. Depending
 * on its private `_types` tree made Flows compile against an implementation
 * detail and dependency-cruiser could not resolve it.
 */
type FlowContextMenuRender =
  | {
      type: "render";
      data: {
        element: HTMLElement;
        filled?: boolean;
        type: "contextmenu";
        items: FlowContextMenuItem[];
        onHide(): void;
        searchBar?: boolean;
      };
    }
  | {
      type: "rendered";
      data: {
        element: HTMLElement;
        type: "contextmenu";
      };
    };

export function flowContextMenuPreset<
  Schemes extends BaseSchemes,
  K extends FlowContextMenuRender,
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
