/**
 * Rete.js plugin creation and configuration for the flow canvas.
 */

import { LitPlugin, Presets as LitPresets } from "@retejs/lit-plugin";
import { html } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { NodeEditor } from "rete";
import { AreaExtensions, AreaPlugin } from "rete-area-plugin";
import { Presets as ArrangePresets, AutoArrangePlugin } from "rete-auto-arrange-plugin";
import { ConnectionPlugin, Presets as ConnectionPresets } from "rete-connection-plugin";
import { ContextMenuPlugin } from "rete-context-menu-plugin";
import { HistoryPlugin } from "rete-history-plugin";
import { MinimapPlugin } from "rete-minimap-plugin";

import { createContextMenuItems } from "./context_menu_items.js";
import { createFlowHistoryPreset } from "./history_preset.js";
import { useMagneticConnection } from "./magnetic-connection/index.js";

/**
 * Creates and configures all Rete.js plugins.
 * @param {HTMLElement} container - The DOM container element
 * @param {Object} hook - The FlowCanvas hook instance (for sheetsMap + connectionDataMap)
 * @returns {{ editor, area, connection, minimap, render }}
 */
export function createPlugins(container, hook) {
  const editor = new NodeEditor();
  const area = new AreaPlugin(container);
  const connection = new ConnectionPlugin();
  const contextMenu = new ContextMenuPlugin({ items: createContextMenuItems(hook) });
  const history = new HistoryPlugin({ timing: 200 });
  const arrange = new AutoArrangePlugin();
  const minimap = new MinimapPlugin();
  const render = new LitPlugin();

  // Configure auto-arrange plugin
  arrange.addPreset(ArrangePresets.classic.setup());

  // Configure connection plugin
  connection.addPreset(ConnectionPresets.classic.setup());

  // Configure Lit render plugin with custom components
  render.addPreset(
    LitPresets.classic.setup({
      customize: {
        node(context) {
          const node = context.payload;
          return ({ emit }) => {
            const nodeData = {
              ...node,
              nodeData: { ...node.nodeData },
              _updateTs: node._updateTs || 0,
            };
            return html`
              <storyarn-node
                .data=${nodeData}
                .emit=${emit}
                .sheetsMap=${hook.sheetsMap}
                .hubsMap=${hook.hubsMap}
                .lod=${hook.currentLod || "full"}
              ></storyarn-node>
            `;
          };
        },
        socket(context) {
          return () => html`
            <storyarn-socket .data=${context.payload}></storyarn-socket>
          `;
        },
        connection: (context) => {
          const conn = context.payload;
          if (conn.isMagnetic) {
            return ({ path }) => html`
              <storyarn-magnetic-connection .path=${path}></storyarn-magnetic-connection>
            `;
          }
          return ({ path }) => {
            const connData = hook.connectionDataMap.get(conn.id);
            return html`
              <storyarn-connection
                .path=${path}
                .data=${connData}
              ></storyarn-connection>
            `;
          };
        },
      },
    }),
  );

  // Context menu render preset — custom rendering (not LitPresets.contextMenu)
  // to avoid shadow-DOM styling issues with rete-context-menu-* elements.
  render.addPreset({
    update(context) {
      if (context.data.type === "contextmenu") {
        return { items: context.data.items, onHide: context.data.onHide };
      }
    },
    render(context) {
      if (context.data.type === "contextmenu") {
        const { items, onHide } = context.data;
        const renderItems = (list) =>
          list.map((item) => {
            const icon = item.icon
              ? html`<span class="flow-cm-icon">${unsafeSVG(item.icon)}</span>`
              : "";
            if (item.subitems?.length) {
              return html`
                <div class="flow-cm-parent">
                  <button
                    class="flow-cm-item has-sub"
                    @pointerdown=${(e) => e.stopPropagation()}
                  >
                    ${icon} ${item.label}
                  </button>
                  <div class="flow-cm-submenu">${renderItems(item.subitems)}</div>
                </div>
              `;
            }
            return html`
              <button
                class="flow-cm-item ${item.key === "delete" ? "danger" : ""}"
                @click=${(e) => {
                  e.stopPropagation();
                  item.handler();
                  onHide();
                }}
                @pointerdown=${(e) => e.stopPropagation()}
                @wheel=${(e) => e.stopPropagation()}
              >
                ${icon} ${item.label}
              </button>
            `;
          });
        return html`
          <div class="flow-context-menu">${renderItems(items)}</div>
        `;
      }
    },
  });

  // Minimap render preset
  render.addPreset(LitPresets.minimap.setup({ size: 200 }));

  // Register plugins
  editor.use(area);

  // Intercept socket "rendered" events during bulk load to prevent per-socket
  // forced reflows in getElementCenter(). Events are queued and flushed in a
  // single batch after all nodes are added (before connections).
  // MUST be added BEFORE area.use(connection) — the connection plugin calls
  // DOMSocketPosition.attach() which adds BaseSocketPosition's pipe to area.
  // Our pipe must precede it to block events before getElementCenter() runs.
  area.addPipe((context) => {
    if (hook._deferSocketCalc && context.type === "rendered" && context.data?.type === "socket") {
      hook._deferredSockets.push(context);
      return undefined;
    }
    return context;
  });

  area.use(connection);
  area.use(render);

  // Magnetic connection — enlarges socket drop area for easier connecting
  useMagneticConnection(connection, {
    async createConnection(from, to) {
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

  area.use(contextMenu);
  area.use(arrange);
  // History preset — wires pipes on the editor and area for connection/drag tracking.
  // Needs hook reference for isLoadingFromServer guard.
  history.addPreset(createFlowHistoryPreset(hook));

  // Minimap and history are deferred — caller must do area.use() after initial load
  // to avoid per-node updates during bulk addNode.

  return { editor, area, connection, history, arrange, minimap, render };
}

/**
 * Enables zoom, pan, and selectable nodes, then fits view to content.
 * @param {Object} area - The AreaPlugin instance
 * @param {Object} editor - The NodeEditor instance
 * @param {boolean} hasNodes - Whether the flow has nodes to fit
 */
export async function finalizeSetup(area, editor, hasNodes) {
  AreaExtensions.selectableNodes(area, AreaExtensions.selector(), {
    accumulating: AreaExtensions.accumulateOnCtrl(),
  });

  if (hasNodes) {
    setTimeout(async () => {
      await AreaExtensions.zoomAt(area, editor.getNodes());
      // Second zoomAt after a frame so Lit's <rete-minimap> Shadow DOM
      // is committed and its container query resolves for node scaling.
      requestAnimationFrame(async () => {
        await AreaExtensions.zoomAt(area, editor.getNodes());
      });
    }, 100);
  }
}

// Inject global rete styles
const reteStyles = document.createElement("style");
reteStyles.textContent = `
  #flow-canvas {
    background-color: oklch(var(--b2, 0.2 0 0));
    background-image:
      radial-gradient(circle at center, oklch(var(--bc, 0.8 0 0) / 0.08) 1.5px, transparent 1.5px);
    background-size: 24px 24px;
  }

  .flow-context-menu {
    background-color: oklch(var(--b1, 0.25 0 0));
    border: 1px solid oklch(var(--b3, 0.18 0 0));
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
    color: oklch(var(--bc, 0.9 0 0));
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
    background-color: oklch(var(--b2, 0.22 0 0));
  }

  .flow-cm-item.danger {
    color: oklch(var(--er, 0.65 0.2 25));
  }

  .flow-cm-item.danger:hover {
    background-color: oklch(var(--er, 0.65 0.2 25) / 0.1);
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
    background-color: oklch(var(--b1, 0.25 0 0));
    border: 1px solid oklch(var(--b3, 0.18 0 0));
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
