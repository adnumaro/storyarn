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
 * @param {Object} hook - The FlowCanvas hook instance (for pagesMap + connectionDataMap)
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
              _updateTs: node._updateTs || Date.now(),
            };
            return html`
              <storyarn-node
                .data=${nodeData}
                .emit=${emit}
                .pagesMap=${hook.pagesMap}
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

  // Register plugins
  editor.use(area);
  area.use(connection);
  area.use(render);
  area.use(minimap);

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

  .rete-minimap {
    position: absolute;
    right: 16px;
    bottom: 16px;
    width: 180px;
    height: 120px;
    background: oklch(var(--b1, 0.25 0 0) / 0.9);
    border: 1px solid oklch(var(--bc, 0.8 0 0) / 0.2);
    border-radius: 8px;
    box-shadow: 0 4px 12px rgb(0 0 0 / 0.15);
    overflow: hidden;
    z-index: 10;
    backdrop-filter: blur(8px);
  }

  .rete-minimap .mini-node {
    border-radius: 2px;
    opacity: 0.8;
  }

  .rete-minimap .mini-viewport {
    border: 2px solid oklch(var(--p, 0.6 0.2 250));
    background: oklch(var(--p, 0.6 0.2 250) / 0.1);
    border-radius: 3px;
  }
`;
document.head.appendChild(reteStyles);
