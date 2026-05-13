import type { NodeEditor } from "rete";
import type { AreaPlugin } from "rete-area-plugin";
import type { Ref, ShallowRef } from "vue";

import type { FlowNode } from "../lib/flow-node";
import type { NodeData } from "../lib/node-configs";
import type { FlowAreaExtra, FlowConnection, FlowSchemes } from "../lib/rete-schemes";
import type { SheetMapEntry } from "@modules/flows/types.ts";

export interface FlowCanvasOpts {
  pushEvent: (event: string, payload: Record<string, unknown>) => void;
  handleEvent: (event: string, callback: (data: Record<string, unknown>) => void) => void;
}

export interface ToolbarState {
  visible: boolean;
  nodeId: string | number | null;
  reteNodeId: string | null;
  nodeType: string | null;
  nodeData: NodeData | null;
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface InitOpts {
  sheetsMap?: Record<string, SheetMapEntry>;
  readonly?: boolean;
  userId?: number;
  userColor?: string;
}

export interface FlowData {
  nodes?: {
    type: string;
    id: string | number;
    data: NodeData;
    position?: { x: number; y: number };
    parent_id?: number | null;
  }[];
  connections?: {
    id: number;
    source_node_id: string | number;
    target_node_id: string | number;
    source_pin: string;
    target_pin: string;
    label?: string;
    condition?: unknown;
  }[];
}

export interface ConnectionData {
  id: number;
  source_node_id: string | number;
  target_node_id: string | number;
  source_pin: string;
  target_pin: string;
  label?: string;
  condition?: unknown;
}

export interface NodeServerData {
  type: string;
  id: string | number;
  data: NodeData;
  position?: { x: number; y: number };
  parent_id?: number | null;
}

export interface SequenceResizeDetail {
  reteId: string;
  nodeId: string | number;
  width: number;
  height: number;
  commit: boolean;
}

export interface SequenceGeometry {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface SequenceGeometryPatch extends SequenceGeometry {
  nodeId: string | number;
}

export interface SequenceExpansionOpts {
  allowModifier: boolean;
  track: boolean;
}

export type SequenceFitMode = "contain" | "fit";

export interface NodeView {
  position: { x: number; y: number };
  element: HTMLElement;
}

export interface NodeBounds {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export interface FlowCanvasReturn {
  editor: ShallowRef<NodeEditor<FlowSchemes> | null>;
  area: ShallowRef<AreaPlugin<FlowSchemes, FlowAreaExtra> | null>;
  loading: Ref<boolean>;
  toolbarState: ToolbarState;
  init(containerEl: HTMLElement, flowData: FlowData, opts?: InitOpts): Promise<void>;
  addNodeToEditor(nodeData: NodeServerData): Promise<FlowNode>;
  addConnectionToEditor(connData: ConnectionData): Promise<FlowConnection | undefined>;
  rebuildHubsMap(): Promise<void>;
  syncNodeSize(nodeId: string): Promise<void>;
  destroy(): void;
  setToolbarProps(props: Record<string, unknown>): void;
}
