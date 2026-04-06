/**
 * Shared TypeScript interfaces for flow node Vue components and toolbar sections.
 */

import type { NodeConfig, NodeData } from "./lib/node-configs";

// ---------------------------------------------------------------------------
// Rete node data shape — the `data` prop passed by rete-vue-plugin to each
// node component.  This mirrors the FlowNode class fields that Vue reads.
// ---------------------------------------------------------------------------

export interface ReteSocket {
  name: string;
}

export interface RetePort {
  socket: ReteSocket;
  label?: string;
}

export interface ReteNodeData {
  id: string;
  nodeType: string;
  nodeData: NodeData;
  selected?: boolean;
  inputs: Record<string, RetePort>;
  outputs: Record<string, RetePort>;
}

/** The `emit` callback provided by rete-vue-plugin for socket drag events. */
export type ReteEmitFn = (data: { type: string; [key: string]: unknown }) => void;

// ---------------------------------------------------------------------------
// Sheet / avatar structures that flow through sheetsMap and sheetAvatars
// ---------------------------------------------------------------------------

export interface SheetAvatar {
  id: number;
  url: string;
  name: string;
}

export interface SheetMapEntry {
  id: number;
  name: string;
  color?: string;
  avatar_url?: string;
  avatars?: SheetAvatar[];
  banner_url?: string;
}

export interface SheetAvatarEntry {
  id: number;
  name: string;
  avatars?: {
    id: number;
    name: string;
    position?: number;
    asset?: { url: string };
  }[];
}

// ---------------------------------------------------------------------------
// Hub data
// ---------------------------------------------------------------------------

export interface HubMapEntry {
  hub_id: string;
  label?: string;
  jumpCount?: number;
  color_hex?: string | null;
}

// ---------------------------------------------------------------------------
// Project flow (for subflow toolbar)
// ---------------------------------------------------------------------------

export interface ProjectFlow {
  id: number;
  name: string;
}

// ---------------------------------------------------------------------------
// Subflow exit
// ---------------------------------------------------------------------------

export interface SubflowExit {
  id: number;
  label?: string;
  exit_mode?: string;
}

// ---------------------------------------------------------------------------
// Referencing flow / jump
// ---------------------------------------------------------------------------

export interface ReferencingFlow {
  flow_id: number;
  flow_name: string;
  flow_shortcut?: string;
  node_type?: string;
}

export interface ReferencingJump {
  node_id: number | string;
  label?: string;
}

// ---------------------------------------------------------------------------
// Condition types used in ConditionNode
// ---------------------------------------------------------------------------

export interface ConditionRule {
  id?: string;
  sheet?: string;
  variable?: string;
  operator?: string;
  value?: string | number | boolean | null;
  label?: string;
}

export interface ConditionBlock {
  id?: string;
  type: "block" | "group";
  label?: string;
  rules?: ConditionRule[];
  blocks?: ConditionBlock[];
}

export interface Condition {
  logic?: "all" | "any";
  rules?: ConditionRule[];
  blocks?: ConditionBlock[];
}

// ---------------------------------------------------------------------------
// Instruction assignment
// ---------------------------------------------------------------------------

export interface InstructionAssignment {
  sheet?: string;
  variable?: string;
  operator?: string;
  value?: string | number | boolean | null;
  value_type?: string;
  value_sheet?: string;
}

// ---------------------------------------------------------------------------
// Dialogue response
// ---------------------------------------------------------------------------

export interface DialogueResponse {
  id: string;
  text?: string;
  has_type_warnings?: boolean;
  condition?: unknown;
  instruction_assignments?: unknown[];
}

// ---------------------------------------------------------------------------
// Flow context (injected via provide/inject)
// ---------------------------------------------------------------------------

export interface FlowContextInjection {
  editingNodeId: string | null;
  onInlineEditSave: ((reteNodeId: string, field: string, value: unknown) => void) | null;
  sheetsMap: Record<string, SheetMapEntry>;
  hubsMap: Record<string, HubMapEntry>;
  labels: Record<string, string>;
  lod: string;
  nodeDataVersion: number;
}

// ---------------------------------------------------------------------------
// Exit label (SubflowNode)
// ---------------------------------------------------------------------------

export interface ExitLabel {
  id: number;
  label?: string;
  exit_mode?: string;
}
