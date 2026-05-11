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
import { ContextMenuPlugin } from "rete-context-menu-plugin";
import { HistoryPlugin } from "rete-history-plugin";
import { MinimapPlugin } from "rete-minimap-plugin";
import { ScopesPlugin } from "rete-scopes-plugin";
import { VuePlugin, Presets as VuePresets } from "rete-vue-plugin";
import { createApp, reactive } from "vue";

import { i18n } from "@/app/i18n";
import FlowConnection from "../components/entities/rete/FlowConnection.vue";
import FlowNode from "../components/entities/rete/FlowNode.vue";
import FlowSocket from "../components/entities/rete/FlowSocket.vue";
import Sequence from "../components/entities/nodes/SequenceNode.vue";

import { createContextMenuItems } from "../lib/context_menu_items";
import { FLOW_CONTEXT_KEY } from "../lib/flow-context";
import { flowContextMenuPreset } from "../lib/context_menu_preset";
import { flowScopesPreset } from "../lib/flow-scopes-preset";
import {
  installReparentModifierListeners,
  reparentGestureActive,
} from "../lib/flow-reparent-state";
import type { FlowSchemes, FlowAreaExtra } from "../lib/rete-schemes";
import type { FlowContext, HookProxy } from "./editorHandlers";
import { historyPreset } from "./historyPreset";
import { magneticConnection } from "./magneticConnection";

interface PluginSet {
  editor: NodeEditor<FlowSchemes>;
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>;
  connection: ConnectionPlugin<FlowSchemes>;
  history: HistoryPlugin<FlowSchemes>;
  arrange: AutoArrangePlugin<FlowSchemes>;
  minimap: MinimapPlugin<FlowSchemes>;
  render: VuePlugin<FlowSchemes, FlowAreaExtra>;
  scopes: ScopesPlugin<FlowSchemes>;
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
    selectedReteNodeId: null,
    selectedReteIds: new Set<string | number>(),
    canEdit: !hook._readonly,
    toolbarProps: {},
    zoom: 1,
  });
  hook._flowContext = flowContext;

  const render = new VuePlugin<FlowSchemes, FlowAreaExtra>({
    setup(context) {
      // Guard: context can be null for some internal plugin renders
      if (!context) return createApp({ render: () => null });
      const app = createApp(context);
      app.use(i18n);
      app.config.globalProperties.$live = {
        pushEvent: hook.pushEvent,
        handleEvent: hook.handleEvent,
        upload: () => {},
      };
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
          // Sequences (rete-scopes parent nodes) render as bounding boxes.
          // They share the FlowNode class but are discriminated by nodeType.
          if (context.payload.nodeType === "sequence") return Sequence;
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

  // Custom context menu preset (shadcn-styled; routes rete-context-menu-plugin
  // signals to FlowRendererContextMenu.vue). The plugin itself is attached to
  // `area` below (readonly flows skip it per v1 behaviour).
  render.addPreset(flowContextMenuPreset());

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

  // Scopes plugin — Sequences render as parent bounding boxes that contain
  // their member nodes. Nodes declare their parent via the `parent` field
  // (set from `node.parent_id` at load time).
  //
  // We use `flowScopesPreset` instead of `ScopesPresets.classic.setup()` so
  // drag-reparenting only fires when Cmd/Ctrl is held (see
  // `flow-scopes-preset.ts` + `flow-reparent-state.ts`). Without the
  // modifier, rete-scopes still auto-resizes the sequence during translate
  // (`resizeParent` on `nodetranslated` is attached by the plugin itself,
  // not the preset), so the user gets "drag outside = sequence grows".
  //
  // `exclude` gates that auto-resize to reparent gestures. When the user
  // holds Cmd/Ctrl while dragging, we want the sequence bbox to stay put
  // so they can actually cross its border. Otherwise the sequence chases
  // the node out, the pointer stays "inside" at drop time, and
  // `reassignParent` sees the same sequence as overlay → no reparent
  // happens. Without the modifier, `exclude` returns false and the
  // grow-to-fit behaviour kicks in normally.
  //
  // `size` clamps the empty-children branch of `resizeParent`. When a
  // sequence has no children it would otherwise shrink to just the
  // padding (~40x60) which looks like a lost icon. We clamp to the
  // server's default sequence_config dimensions so an orphaned sequence
  // has the same footprint as a freshly-created one — discoverable,
  // obvious drop-target for the next node.
  const EMPTY_SEQUENCE_MIN_WIDTH = 300;
  const EMPTY_SEQUENCE_MIN_HEIGHT = 200;
  const scopes = new ScopesPlugin<FlowSchemes>({
    exclude: () => reparentGestureActive.value,
    size: (_id, size) => ({
      width: Math.max(size.width, EMPTY_SEQUENCE_MIN_WIDTH),
      height: Math.max(size.height, EMPTY_SEQUENCE_MIN_HEIGHT),
    }),
  });
  scopes.addPreset(
    flowScopesPreset<FlowSchemes>({
      onReparented: (nodeId, newParentId) => {
        const rawNodeId = nodeId.replace(/^node-/, "");
        const rawParentId = newParentId ? newParentId.replace(/^node-/, "") : null;
        hook.pushEvent("node_reparented", {
          id: rawNodeId,
          parent_id: rawParentId,
        });
      },
      onParentMoved: (nodeId, x, y) => {
        // Sequence auto-repositioned to fit its remaining children after a
        // reparent. The translate call already fired `nodetranslated` which
        // goes through `throttleNodeMoved` → `node_dragging` (broadcast
        // only). Push `node_moved` here so the shift survives a reload.
        const rawNodeId = nodeId.replace(/^node-/, "");
        hook.pushEvent("node_moved", {
          id: rawNodeId,
          position_x: x,
          position_y: y,
        });
      },
    }),
  );
  area.use(scopes);

  // Modifier listeners for the reparent gesture. Idempotent — no-op if
  // already installed (e.g. on hot reload).
  installReparentModifierListeners();

  // Rete context menu plugin (skipped in readonly flows).
  if (!hook.readonly) {
    const contextMenu = new ContextMenuPlugin<FlowSchemes>({
      items: createContextMenuItems(hook),
    });
    area.use(contextMenu);
  }

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

  return { editor, area, connection, history, arrange, minimap, render, scopes };
}

export interface SelectionHandles {
  /** Shared selector instance — used for programmatic add/remove/unselectAll. */
  selector: ReturnType<typeof AreaExtensions.selector>;
  /**
   * Selects a node by id, optionally accumulating into the current selection.
   * Matches the return signature of `AreaExtensions.selectableNodes` — rete
   * narrows `nodeId` to `string` because the node view map is keyed on the
   * stringified id.
   */
  select: (nodeId: string, accumulate: boolean) => Promise<void>;
  /** Unselects a node by id. See `select` for the id-type rationale. */
  unselect: (nodeId: string) => Promise<void>;
}

/**
 * Enables zoom, pan, and selectable nodes, then fits view to content.
 * Returns the selector + select/unselect functions so marquee selection
 * (drag-rectangle) can feed into the same selector the click handler uses.
 *
 * Also monkey-patches the selector so every add/remove/unselectAll/pick
 * syncs `flowContext.selectedReteIds` — the reactive set FlowNode.vue
 * reads to render the selection ring. Patching the selector catches ALL
 * selection changes (click-pick via rete internals, marquee via our
 * composable, keyboard via future hooks) with a single hook point.
 */
export async function finalizeSetup(
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>,
  editor: NodeEditor<FlowSchemes>,
  hasNodes: boolean,
  flowContext?: FlowContext,
): Promise<SelectionHandles> {
  const selector = AreaExtensions.selector();

  if (flowContext) {
    const sync = () => {
      flowContext.selectedReteIds = new Set(
        Array.from(selector.entities.values()).map((e) => e.id),
      );
    };
    const origAdd = selector.add.bind(selector);
    const origRemove = selector.remove.bind(selector);
    const origUnselectAll = selector.unselectAll.bind(selector);
    const origPick = selector.pick.bind(selector);
    selector.add = async (
      entity: Parameters<typeof origAdd>[0],
      accumulate: Parameters<typeof origAdd>[1],
    ) => {
      // Preserve multi-selection on re-pick. Rete's core.add calls
      // `unselectAll()` whenever `accumulate` is false, which is the default
      // when Ctrl isn't held. That wipes the marquee/Shift-built selection
      // the moment the user pointer-downs one of the selected nodes to
      // drag it, because `nodepicked` → `add(id, accumulate=false)`. Match
      // the UX of Figma/Illustrator: if the picked entity is ALREADY in the
      // selector, treat the pick as accumulating so the rest of the group
      // isn't cleared. Also covers the "multi-select sequence + children
      // then drag" flow (pre-resize-reactivity fix this looked like "the
      // children visually leave the sequence"; really they were just being
      // deselected while drag kept working).
      const key = `${entity.label}_${entity.id}`;
      const alreadySelected = selector.entities.has(key);
      const r = await origAdd(entity, accumulate || alreadySelected);
      sync();
      return r;
    };
    selector.remove = async (...args: Parameters<typeof origRemove>) => {
      const r = await origRemove(...args);
      sync();
      return r;
    };
    selector.unselectAll = async () => {
      const r = await origUnselectAll();
      sync();
      return r;
    };
    selector.pick = (...args: Parameters<typeof origPick>) => {
      const r = origPick(...args);
      sync();
      return r;
    };
  }

  // Preserve selection on right-click context menu. Rete's selectableNodes
  // pipe treats every non-drag pointerup as "click on empty area" and calls
  // `unselectAll()`, which clears the marquee selection when the user
  // right-clicks a node to open the context menu. Filter pointerup events
  // whose matching pointerdown was button=2 (right). Pipe added BEFORE
  // selectableNodes so it runs first in the chain.
  let rightClickSession = false;
  area.addPipe((context) => {
    if (!context || typeof context !== "object" || !("type" in context)) return context;
    const ctx = context as { type: string; data?: { event?: PointerEvent } };
    if (ctx.type === "pointerdown") {
      rightClickSession = ctx.data?.event?.button === 2;
    } else if (ctx.type === "pointerup" && rightClickSession) {
      rightClickSession = false;
      // Skip: prevents selectableNodes' unselectAll from running.
      return undefined;
    }
    return context;
  });

  const { select, unselect } = AreaExtensions.selectableNodes(area, selector, {
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

  return { selector, select, unselect };
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

  /* Lift minimap above the bottom-right toolbar buttons (button row:
     bottom-3 + size-8 = 44px from bottom; leave a small gap). */
  .minimap {
    bottom: 56px !important;
    right: 14px !important;
  }
`;
document.head.appendChild(reteStyles);
