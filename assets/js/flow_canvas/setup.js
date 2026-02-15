/**
 * Rete.js plugin creation and configuration for the flow canvas.
 */

import { LitPlugin, Presets as LitPresets } from "@retejs/lit-plugin";
import { html } from "lit";
import { NodeEditor } from "rete";
import { AreaExtensions, AreaPlugin } from "rete-area-plugin";
import { ConnectionPlugin, Presets as ConnectionPresets } from "rete-connection-plugin";
import { MinimapPlugin } from "rete-minimap-plugin";

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
  const minimap = new MinimapPlugin();
  const render = new LitPlugin();

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
  // Minimap is deferred — caller must do area.use(minimap) after initial load
  // to avoid per-node minimap updates during bulk addNode.

  return { editor, area, connection, minimap, render };
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
`;
document.head.appendChild(reteStyles);