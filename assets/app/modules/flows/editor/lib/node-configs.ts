/**
 * Node type configurations for the V2 flow editor.
 *
 * Pure metadata — no Lit templates, no shadow DOM rendering.
 * Vue node components handle all rendering independently.
 */

export type FlowNodeType =
  | "entry"
  | "exit"
  | "dialogue"
  | "condition"
  | "instruction"
  | "hub"
  | "jump"
  | "subflow"
  | "annotation"
  | "sequence";

export interface NodeConfig {
  label: string;
  color: string;
  inputs: string[];
  outputs: string[];
  dynamicOutputs?: boolean;
}

export interface NodeData {
  responses?: { id: string }[];
  exit_pins?: ({ id: string | number } | string | number)[];
  exit_labels?: ({ id: string | number } | string | number)[];
  condition?: { rules?: { id?: string }[] };
  switch_mode?: boolean;
  [key: string]: unknown;
}

export const NODE_CONFIGS: Record<FlowNodeType, NodeConfig> = {
  entry: {
    label: "Entry",
    color: "#22c55e",
    inputs: [],
    outputs: ["output"],
  },
  exit: {
    label: "Exit",
    color: "#22c55e",
    inputs: ["input"],
    outputs: [],
  },
  dialogue: {
    label: "Dialogue",
    color: "#3b82f6",
    inputs: ["input"],
    outputs: ["output"],
    dynamicOutputs: true,
  },
  condition: {
    label: "Condition",
    color: "#eab308",
    inputs: ["input"],
    outputs: ["true", "false"],
  },
  instruction: {
    label: "Instruction",
    color: "#ec4899",
    inputs: ["input"],
    outputs: ["output"],
  },
  hub: {
    label: "Hub",
    color: "#8b5cf6",
    inputs: ["input"],
    outputs: ["output"],
  },
  jump: {
    label: "Jump",
    color: "#8b5cf6",
    inputs: ["input"],
    outputs: [],
  },
  subflow: {
    label: "Subflow",
    color: "#6366f1",
    inputs: ["input"],
    outputs: ["output"],
    dynamicOutputs: true,
  },
  annotation: {
    label: "Note",
    color: "#fbbf24",
    inputs: [],
    outputs: [],
  },
  sequence: {
    label: "Sequence",
    color: "#a78bfa",
    inputs: [],
    outputs: [],
  },
};

/**
 * Creates dynamic outputs for node types that support them.
 * Used by FlowNode constructor to create the right sockets.
 */
export function createDynamicOutputs(type: string, data: NodeData): string[] | null {
  if (type === "dialogue" && data.responses && data.responses.length > 0) {
    return data.responses.map((r) => r.id);
  }
  if (type === "subflow" && data.exit_pins && data.exit_pins.length > 0) {
    return data.exit_pins.map(subflowExitPinId);
  }
  if (type === "subflow" && data.exit_labels && data.exit_labels.length > 0) {
    return data.exit_labels.map(subflowExitPinId);
  }
  return null;
}

function subflowExitPinId(pin: { id: string | number } | string | number): string {
  const id = typeof pin === "object" ? pin.id : pin;
  const value = String(id);
  return value.startsWith("exit_") ? value : `exit_${value}`;
}

/**
 * Determines if a node needs full rebuild (socket structure changed).
 * Only returns true for changes that add/remove sockets.
 */
function dialogueNeedsRebuild(oldData: NodeData | null, newData: NodeData): boolean {
  const oldResp = oldData?.responses || [];
  const newResp = newData.responses || [];
  if (oldResp.length !== newResp.length) return true;
  for (let i = 0; i < oldResp.length; i++) {
    if (oldResp[i].id !== newResp[i].id) return true;
  }
  return false;
}

function getRuleCount(data: NodeData | null): number {
  return data?.condition?.rules?.length ?? 0;
}

function conditionNeedsRebuild(oldData: NodeData | null, newData: NodeData): boolean {
  if (Boolean(oldData?.switch_mode) !== Boolean(newData.switch_mode)) return true;
  if (!newData.switch_mode) return false;
  return getRuleCount(oldData) !== getRuleCount(newData);
}

function subflowNeedsRebuild(oldData: NodeData | null, newData: NodeData): boolean {
  const oldPins = subflowOutputPins(oldData);
  const newPins = subflowOutputPins(newData);

  return oldPins.length !== newPins.length || oldPins.some((pin, index) => pin !== newPins[index]);
}

function subflowOutputPins(data: NodeData | null): string[] {
  if (!data) return [];
  if (data.exit_pins && data.exit_pins.length > 0) return data.exit_pins.map(subflowExitPinId);
  if (data.exit_labels && data.exit_labels.length > 0)
    return data.exit_labels.map(subflowExitPinId);
  return [];
}

type RebuildChecker = (oldData: NodeData | null, newData: NodeData) => boolean;

const REBUILD_CHECKERS: Record<string, RebuildChecker> = {
  dialogue: dialogueNeedsRebuild,
  condition: conditionNeedsRebuild,
  subflow: subflowNeedsRebuild,
};

/**
 * Determines if a node needs full rebuild (socket structure changed).
 * Only returns true for changes that add/remove sockets.
 */
export function needsRebuild(type: string, oldData: NodeData | null, newData: NodeData): boolean {
  const checker = REBUILD_CHECKERS[type];
  // Types without a checker have fixed sockets — never rebuild
  return checker ? checker(oldData, newData) : false;
}
