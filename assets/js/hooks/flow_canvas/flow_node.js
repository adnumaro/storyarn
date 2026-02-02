/**
 * Custom Rete.js node class for flow canvas nodes.
 */

import { ClassicPreset } from "rete";
import { NODE_CONFIGS } from "./node_config.js";

/**
 * FlowNode extends the classic Rete.js Node with custom properties
 * for our narrative flow editor.
 */
export class FlowNode extends ClassicPreset.Node {
  /**
   * @param {string} type - Node type (dialogue, hub, condition, instruction, jump)
   * @param {string|number} id - Database ID of the node
   * @param {object} data - Node data (varies by type)
   */
  constructor(type, id, data = {}) {
    const config = NODE_CONFIGS[type] || NODE_CONFIGS.dialogue;
    super(config.label);

    this.nodeType = type;
    this.nodeId = id;
    this.nodeData = data;

    // Add inputs
    for (const inputName of config.inputs) {
      this.addInput(inputName, new ClassicPreset.Input(new ClassicPreset.Socket("flow")));
    }

    // Add outputs - check for dynamic outputs (responses in dialogue nodes)
    if (config.dynamicOutputs && type === "dialogue" && data.responses?.length > 0) {
      // Add one output per response
      for (const response of data.responses) {
        this.addOutput(response.id, new ClassicPreset.Output(new ClassicPreset.Socket("flow")));
      }
    } else {
      // Add default outputs
      for (const outputName of config.outputs) {
        this.addOutput(outputName, new ClassicPreset.Output(new ClassicPreset.Socket("flow")));
      }
    }
  }
}
