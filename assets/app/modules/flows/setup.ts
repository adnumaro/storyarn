/**
 * Rete.js plugin creation and configuration for the flow canvas (V2 -- Vue renderer).
 *
 * Replaces LitPlugin with VuePlugin. All other plugins are identical to V1 setup.js.
 */

import { ClassicPreset, NodeEditor } from "rete";
import { AreaExtensions, AreaPlugin } from "rete-area-plugin";
import { Presets as ArrangePresets, AutoArrangePlugin } from "rete-auto-arrange-plugin";
import {
  ConnectionPlugin,
  Presets as ConnectionPresets,
  type SocketData,
} from "rete-connection-plugin";
import { HistoryPlugin } from "rete-history-plugin";
import { MinimapPlugin } from "rete-minimap-plugin";
import { VuePlugin, Presets as VuePresets } from "rete-vue-plugin";
import { createApp, reactive } from "vue";

import { i18n } from "@app/i18n";
import FlowConnection from "./components/FlowConnection.vue";
import FlowNode from "./components/FlowNode.vue";
import FlowSocket from "./components/FlowSocket.vue";

import type { FlowSchemes, FlowAreaExtra } from "./lib/rete-schemes";
import type { FlowContext, HookProxy } from "./services/editorHandlers";
import { historyPreset } from "./services/historyPreset";
import { magneticConnection } from "./services/magneticConnection";

// Shared reactive state injected into every node/socket/connection Vue app instance.
// Keys match the provide/inject keys used by FlowNode.vue.
export const FLOW_CONTEXT_KEY = Symbol("flowContext");

interface PluginSet {
  editor: NodeEditor<FlowSchemes>;
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>;
  connection: ConnectionPlugin<FlowSchemes>;
  history: HistoryPlugin<FlowSchemes>;
  arrange: AutoArrangePlugin<FlowSchemes>;
  minimap: MinimapPlugin<FlowSchemes>;
  render: VuePlugin<FlowSchemes, FlowAreaExtra>;
}

/**
 * Creates and configures all Rete.js plugins with Vue renderer.
 */
export function createPlugins(container: HTMLElement, hook: HookProxy): PluginSet {
  const editor = new NodeEditor<FlowSchemes>();
  const area = new AreaPlugin<FlowSchemes, FlowAreaExtra>(container);
  const connection = new ConnectionPlugin<FlowSchemes>();
  const history = new HistoryPlugin<FlowSchemes>({ timing: 200 });
  const arrange = new AutoArrangePlugin<FlowSchemes>();
  const minimap = new MinimapPlugin<FlowSchemes>();
  // Shared reactive context available to all node/socket/connection Vue instances
  const flowContext: FlowContext = reactive({
    sheetsMap: hook.sheetsMap || {},
    hubsMap: hook.hubsMap || {},
    lod: "full",
    editingNodeId: null,
    onInlineEditSave: null,
    nodeDataVersion: 0,
  });
  hook._flowContext = flowContext;

  const render = new VuePlugin<FlowSchemes, FlowAreaExtra>({
    setup(context) {
      // Guard: context can be null for some internal plugin renders
      if (!context) return createApp({ render: () => null });
      const app = createApp(context);
      app.use(i18n);
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
          if ((context.payload as { isMagnetic?: boolean }).isMagnetic) return null;
          return FlowConnection;
        },
      },
    }),
  );

  // Minimap render preset
  render.addPreset(VuePresets.minimap.setup({ size: 200 }));

  // Register plugins
  editor.use(area);

  // Intercept socket "rendered" events during bulk load (same as V1)
  area.addPipe((context) => {
    // Rete area pipe context is a union type; cast needed to check event type discriminator
    const ctx = context as unknown as { type: string; data?: { type?: string } };
    if (hook._deferSocketCalc && ctx.type === "rendered" && ctx.data?.type === "socket") {
      hook._deferredSockets.push(context);
      return undefined;
    }
    if (ctx.type === "rendered" && ctx.data?.type === "socket" && !hook._isRecalculatingSockets) {
      if (!hook._socketRenderedEvents) hook._socketRenderedEvents = [];
      hook._socketRenderedEvents.push(context);
    }
    return context;
  });

  area.use(connection);
  area.use(render);

  // Magnetic connection (same as V1)
  magneticConnection(connection, {
    async createConnection(from: SocketData, to: SocketData) {
      if (hook.readonly) return;
      if (from.side === to.side) return;
      const [source, target] = from.side === "output" ? [from, to] : [to, from];
      const sourceNode = editor.getNode(source.nodeId);
      const targetNode = editor.getNode(target.nodeId);

      if (sourceNode && targetNode) {
        const conn = new ClassicPreset.Connection(sourceNode, source.key, targetNode, target.key);
        conn.id = `${Date.now()}`;
        await editor.addConnection(conn);
      }
    },
    display(from: SocketData, to: SocketData) {
      return from.side !== to.side;
    },
    offset(socket: SocketData, position: { x: number; y: number }) {
      const socketRadius = 10;
      return {
        x: position.x + (socket.side === "input" ? -socketRadius : socketRadius),
        y: position.y,
      };
    },
  });

  area.use(arrange);

  if (!hook.readonly) {
    history.addPreset(historyPreset(hook));
  }

  return { editor, area, connection, history, arrange, minimap, render };
}

/**
 * Enables zoom, pan, and selectable nodes, then fits view to content.
 */
export async function finalizeSetup(
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>,
  editor: NodeEditor<FlowSchemes>,
  hasNodes: boolean,
): Promise<void> {
  AreaExtensions.selectableNodes(area, AreaExtensions.selector(), {
    accumulating: AreaExtensions.accumulateOnCtrl(),
  });

  if (hasNodes) {
    setTimeout(async () => {
      if (!area || (area as { destroyed?: boolean }).destroyed) return;
      await AreaExtensions.zoomAt(area, editor.getNodes());
      requestAnimationFrame(async () => {
        if (!area || (area as { destroyed?: boolean }).destroyed) return;
        await AreaExtensions.zoomAt(area, editor.getNodes());
      });
    }, 100);
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
`;
document.head.appendChild(reteStyles);
