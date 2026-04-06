/**
 * Shared Rete.js type definitions for the flow editor.
 *
 * Defines FlowSchemes which parameterizes all Rete plugins (NodeEditor,
 * AreaPlugin, ConnectionPlugin, etc.) with the project's FlowNode type.
 */

import { ClassicPreset, type GetSchemes } from "rete";
import type { VueArea2D } from "rete-vue-plugin";
import type { MinimapExtra } from "rete-minimap-plugin";
import type { FlowNode } from "./flow-node";

/** Connection type for FlowNode-based graphs, includes ConnectionExtra for compatibility */
export type FlowConnection = ClassicPreset.Connection<FlowNode, FlowNode> & {
  isPseudo?: boolean;
};

/** Scheme type that parameterizes all Rete plugins */
export type FlowSchemes = GetSchemes<FlowNode, FlowConnection>;

/** Extra area signals (Vue rendering + minimap) */
export type FlowAreaExtra = VueArea2D<FlowSchemes> | MinimapExtra;
