/**
 * Custom Rete.js node class for the V2 flow editor.
 *
 * Uses Vue-native node-configs.ts instead of V1 node definitions (no Lit dependency).
 */

import { ClassicPreset } from "rete";
import { createDynamicOutputs, NODE_CONFIGS, type NodeData } from "./node-configs";

export class FlowNode extends ClassicPreset.Node {
  width = 190;
  height = 130;
  nodeType: string;
  nodeId: string | number;
  nodeData: NodeData;
  _updateTs?: number;

  constructor(type: string, id: string | number, data: NodeData = {}) {
    const config = NODE_CONFIGS[type as keyof typeof NODE_CONFIGS] || NODE_CONFIGS.dialogue;
    super(config.label);

    this.nodeType = type;
    this.nodeId = id;
    this.nodeData = data;

    for (const inputName of config.inputs) {
      this.addInput(
        inputName,
        new ClassicPreset.Input(new ClassicPreset.Socket("flow"), inputName, true),
      );
    }

    const dynamicOutputs = createDynamicOutputs(type, data);

    if (dynamicOutputs) {
      for (const outputName of dynamicOutputs) {
        this.addOutput(outputName, new ClassicPreset.Output(new ClassicPreset.Socket("flow")));
      }
    } else {
      for (const outputName of config.outputs) {
        this.addOutput(outputName, new ClassicPreset.Output(new ClassicPreset.Socket("flow")));
      }
    }
  }
}
