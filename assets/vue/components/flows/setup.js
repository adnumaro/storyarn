/**
 * Rete.js plugin creation and configuration for the flow canvas (V2 — Vue renderer).
 *
 * Replaces LitPlugin with VuePlugin. All other plugins are identical to V1 setup.js.
 */

import { NodeEditor } from "rete";
import { AreaExtensions, AreaPlugin } from "rete-area-plugin";
import { Presets as ArrangePresets, AutoArrangePlugin } from "rete-auto-arrange-plugin";
import { ConnectionPlugin, Presets as ConnectionPresets } from "rete-connection-plugin";
import { ContextMenuPlugin } from "rete-context-menu-plugin";
import { HistoryPlugin } from "rete-history-plugin";
import { MinimapPlugin } from "rete-minimap-plugin";
import { createApp, reactive } from "vue";
import { Presets as VuePresets, VuePlugin } from "rete-vue-plugin";

import FlowConnection from "./components/FlowConnection.vue";
import FlowNode from "./components/FlowNode.vue";
import FlowSocket from "./components/FlowSocket.vue";

import { createContextMenuItems } from "@/js/flow_canvas/context_menu_items.js";
import { createFlowHistoryPreset } from "@/js/flow_canvas/history_preset.js";
import { useMagneticConnection } from "@/js/flow_canvas/magnetic-connection/index.js";

// Shared reactive state injected into every node/socket/connection Vue app instance.
// Keys match the provide/inject keys used by FlowNode.vue.
export const FLOW_CONTEXT_KEY = Symbol("flowContext");

/**
 * Creates and configures all Rete.js plugins with Vue renderer.
 * @param {HTMLElement} container - The DOM container element
 * @param {Object} hook - The FlowCanvas hook instance
 * @returns {{ editor, area, connection, minimap, render }}
 */
export function createPlugins(container, hook) {
  const editor = new NodeEditor();
  const area = new AreaPlugin(container);
  const connection = new ConnectionPlugin();
  const contextMenu = hook.readonly
    ? null
    : new ContextMenuPlugin({ items: createContextMenuItems(hook) });
  const history = new HistoryPlugin({ timing: 200 });
  const arrange = new AutoArrangePlugin();
  const minimap = new MinimapPlugin();
  // Shared reactive context available to all node/socket/connection Vue instances
  const flowContext = reactive({
    sheetsMap: hook.sheetsMap || {},
    hubsMap: hook.hubsMap || {},
    labels: hook.labels || {},
    lod: "full",
    editingNodeId: null,
    onInlineEditSave: null,
    nodeDataVersion: 0,
  });
  hook._flowContext = flowContext;

  const render = new VuePlugin({
    setup(context) {
      // Guard: context can be null for some internal plugin renders
      if (!context) return createApp({ render: () => null });
      const app = createApp(context);
      app.provide(FLOW_CONTEXT_KEY, flowContext);
      return app;
    },
  });

  // Configure auto-arrange plugin
  arrange.addPreset(ArrangePresets.classic.setup());

  // Configure connection plugin
  connection.addPreset(ConnectionPresets.classic.setup());

  // Configure Vue render plugin with custom components
  render.addPreset(
    VuePresets.classic.setup({
      customize: {
        node(context) {
          if (!context.payload) return null;
          return FlowNode;
        },
        socket(context) {
          if (!context.payload) return null;
          return FlowSocket;
        },
        connection(context) {
          if (!context.payload) return null;
          // Skip magnetic connection preview (rendered by connection plugin internally)
          if (context.payload.isMagnetic) return null;
          return FlowConnection;
        },
      },
    }),
  );

  // Context menu render preset — uses raw HTML (framework-agnostic)
  // This is identical to V1 since it creates DOM elements directly.
  render.addPreset({
    update(context) {
      if (context.data.type === "contextmenu") {
        return { items: context.data.items, onHide: context.data.onHide };
      }
    },
    render(context) {
      if (context.data.type === "contextmenu") {
        return renderContextMenu(context.data);
      }
    },
  });

  // Minimap render preset
  render.addPreset(VuePresets.minimap.setup({ size: 200 }));

  // Register plugins
  editor.use(area);

  // Intercept socket "rendered" events during bulk load (same as V1)
  area.addPipe((context) => {
    if (hook._deferSocketCalc && context.type === "rendered" && context.data?.type === "socket") {
      hook._deferredSockets.push(context);
      return undefined;
    }
    if (
      context.type === "rendered" &&
      context.data?.type === "socket" &&
      !hook._isRecalculatingSockets
    ) {
      if (!hook._socketRenderedEvents) hook._socketRenderedEvents = [];
      hook._socketRenderedEvents.push(context);
    }
    return context;
  });

  area.use(connection);
  area.use(render);

  // Magnetic connection (same as V1)
  useMagneticConnection(connection, {
    async createConnection(from, to) {
      if (hook.readonly) return;
      if (from.side === to.side) return;
      const [source, target] = from.side === "output" ? [from, to] : [to, from];
      const sourceNode = editor.getNode(source.nodeId);
      const targetNode = editor.getNode(target.nodeId);

      if (sourceNode && targetNode) {
        await editor.addConnection({
          id: `${Date.now()}`,
          source: source.nodeId,
          sourceOutput: source.key,
          target: target.nodeId,
          targetInput: target.key,
        });
      }
    },
    display(from, to) {
      return from.side !== to.side;
    },
    offset(socket, position) {
      const socketRadius = 10;
      return {
        x: position.x + (socket.side === "input" ? -socketRadius : socketRadius),
        y: position.y,
      };
    },
  });

  if (contextMenu) area.use(contextMenu);
  area.use(arrange);

  if (!hook.readonly) {
    history.addPreset(createFlowHistoryPreset(hook));
  }

  return { editor, area, connection, history, arrange, minimap, render };
}

/**
 * Enables zoom, pan, and selectable nodes, then fits view to content.
 */
export async function finalizeSetup(area, editor, hasNodes) {
  AreaExtensions.selectableNodes(area, AreaExtensions.selector(), {
    accumulating: AreaExtensions.accumulateOnCtrl(),
  });

  if (hasNodes) {
    setTimeout(async () => {
      if (!area || area.destroyed) return;
      await AreaExtensions.zoomAt(area, editor.getNodes());
      requestAnimationFrame(async () => {
        if (!area || area.destroyed) return;
        await AreaExtensions.zoomAt(area, editor.getNodes());
      });
    }, 100);
  }
}

// --- Context menu rendering (framework-agnostic DOM) ---

function renderContextMenu({ items, onHide }) {
  const container = document.createElement("div");
  container.className = "flow-context-menu";
  renderMenuItems(container, items, onHide);
  return container;
}

function renderMenuItems(parent, items, onHide) {
  for (const item of items) {
    if (item.subitems?.length) {
      const wrapper = document.createElement("div");
      wrapper.className = "flow-cm-parent";

      const btn = document.createElement("button");
      btn.className = "flow-cm-item has-sub";
      btn.addEventListener("pointerdown", (e) => e.stopPropagation());
      if (item.icon) {
        btn.insertAdjacentHTML("beforeend", `<span class="flow-cm-icon">${item.icon}</span>`);
      }
      btn.insertAdjacentText("beforeend", item.label);
      wrapper.appendChild(btn);

      const sub = document.createElement("div");
      sub.className = "flow-cm-submenu";
      renderMenuItems(sub, item.subitems, onHide);
      wrapper.appendChild(sub);

      parent.appendChild(wrapper);
    } else {
      const btn = document.createElement("button");
      btn.className = `flow-cm-item ${item.key === "delete" ? "danger" : ""}`;
      btn.addEventListener("click", (e) => {
        e.stopPropagation();
        item.handler();
        onHide();
      });
      btn.addEventListener("pointerdown", (e) => e.stopPropagation());
      btn.addEventListener("wheel", (e) => e.stopPropagation());
      if (item.icon) {
        btn.insertAdjacentHTML("beforeend", `<span class="flow-cm-icon">${item.icon}</span>`);
      }
      btn.insertAdjacentText("beforeend", item.label);
      parent.appendChild(btn);
    }
  }
}

// Inject global rete styles (V2: uses Tailwind v4 CSS variables)
const reteStyles = document.createElement("style");
reteStyles.textContent = `
  rete-root[fragment] {
    display: block;
  }

  [id^="flow-canvas-"] {
    background-color: var(--color-background, #0a0a0a);
    background-image:
      radial-gradient(circle at center, color-mix(in oklch, var(--color-foreground, #fafafa) 8%, transparent) 1.5px, transparent 1.5px);
    background-size: 24px 24px;
  }

  .flow-context-menu {
    background-color: var(--color-background, #0a0a0a);
    border: 1px solid var(--color-border, #27272a);
    border-radius: 8px;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.25);
    padding: 4px 0;
    min-width: 180px;
    margin-top: -10px;
    margin-left: -90px;
  }

  .flow-cm-item {
    display: flex;
    align-items: center;
    gap: 8px;
    width: 100%;
    padding: 6px 12px;
    font-size: 13px;
    line-height: 1.4;
    text-align: left;
    color: var(--color-foreground, #fafafa);
    background: none;
    border: none;
    cursor: pointer;
    transition: background-color 0.1s;
  }

  .flow-cm-icon {
    display: flex;
    align-items: center;
    flex-shrink: 0;
    opacity: 0.6;
  }

  .flow-cm-item:hover {
    background-color: var(--color-accent, #27272a);
  }

  .flow-cm-item.danger {
    color: var(--color-destructive, #f87171);
  }

  .flow-cm-item.danger:hover {
    background-color: color-mix(in oklch, var(--color-destructive, #f87171) 10%, transparent);
  }

  .flow-cm-item.has-sub::after {
    content: '\\25B8';
    margin-left: auto;
    padding-left: 12px;
    opacity: 0.4;
  }

  .flow-cm-parent {
    position: relative;
  }

  .flow-cm-submenu {
    display: none;
    position: absolute;
    left: 100%;
    top: -4px;
    background-color: var(--color-background, #0a0a0a);
    border: 1px solid var(--color-border, #27272a);
    border-radius: 8px;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.25);
    padding: 4px 0;
    min-width: 150px;
  }

  .flow-cm-parent:hover > .flow-cm-submenu {
    display: block;
  }
`;
document.head.appendChild(reteStyles);
