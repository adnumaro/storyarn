/**
 * Custom Rete.js node class for the V2 flow editor.
 *
 * Uses Vue-native node-configs.js instead of V1 node definitions (no Lit dependency).
 */

import { ClassicPreset } from "rete";
import { NODE_CONFIGS, createDynamicOutputs } from "./node-configs.js";

export class FlowNode extends ClassicPreset.Node {
	width = 190;
	height = 130;

	/**
	 * @param {string} type - Node type
	 * @param {string|number} id - Database ID
	 * @param {object} data - Node data
	 */
	constructor(type, id, data = {}) {
		const config = NODE_CONFIGS[type] || NODE_CONFIGS.dialogue;
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
