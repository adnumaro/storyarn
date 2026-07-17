import { describe, expect, it, vi } from "vitest";

import { FlowNode } from "@modules/flows/editor/lib/flow-node";
import { resolveNodeColor } from "@modules/flows/editor/lib/render-helpers";
import { buildHubsMap } from "@modules/flows/editor/composables/useFlowCanvas";
import {
  editorHandlers,
  type FlowContext,
  type HookProxy,
} from "@modules/flows/editor/services/editorHandlers";

describe("Hub color propagation", () => {
  it("rebuilds the Hub map after node_updated so a Jump inherits the new color", async () => {
    const hub = new FlowNode("hub", 1, {
      hub_id: "checkpoint",
      label: "Checkpoint",
      color: "#3b82f6",
      color_hex: "#3b82f6",
    });
    hub.id = "node-1";

    const jump = new FlowNode("jump", 2, { target_hub_id: "checkpoint" });
    jump.id = "node-2";

    const nodeMap = new Map<string | number, FlowNode>([
      [1, hub],
      [2, jump],
    ]);
    const flowContext = {
      editingNodeId: null,
      hubsMap: buildHubsMap(nodeMap),
      nodeDataVersion: 0,
    } as FlowContext;
    const rebuildHubsMap = vi.fn(async () => {
      flowContext.hubsMap = buildHubsMap(nodeMap);
    });
    const hook = {
      _flowContext: flowContext,
      nodeMap,
      rebuildHubsMap,
      syncNodeSize: vi.fn().mockResolvedValue(undefined),
    } as unknown as HookProxy;

    await editorHandlers(hook).handleNodeUpdated({
      id: 1,
      data: {
        hub_id: "checkpoint",
        label: "Checkpoint",
        color: "#22c55e",
        color_hex: "#22c55e",
      },
    });

    expect(rebuildHubsMap).toHaveBeenCalledOnce();
    expect(resolveNodeColor("jump", jump.nodeData, "#8b5cf6", {}, flowContext.hubsMap)).toBe(
      "#22c55e",
    );
  });
});
