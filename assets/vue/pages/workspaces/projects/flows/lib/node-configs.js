/**
 * Node type configurations for the V2 flow editor.
 *
 * Pure metadata — no Lit templates, no shadow DOM rendering.
 * Vue node components handle all rendering independently.
 */

export const NODE_CONFIGS = {
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
	slug_line: {
		label: "Slug Line",
		color: "#78716c",
		inputs: ["input"],
		outputs: ["output"],
	},
	annotation: {
		label: "Note",
		color: "#fbbf24",
		inputs: [],
		outputs: [],
	},
};

/**
 * Creates dynamic outputs for node types that support them.
 * Used by FlowNode constructor to create the right sockets.
 */
export function createDynamicOutputs(type, data) {
	if (type === "dialogue" && data.responses?.length > 0) {
		return data.responses.map((r) => r.id);
	}
	if (type === "subflow" && data.exit_pins?.length > 0) {
		return data.exit_pins.map((p) => p.id || p);
	}
	return null;
}

/**
 * Determines if a node needs full rebuild (socket structure changed).
 * Only returns true for changes that add/remove sockets.
 */
export function needsRebuild(type, oldData, newData) {
	if (type === "dialogue") {
		const oldResp = oldData?.responses || [];
		const newResp = newData.responses || [];
		if (oldResp.length !== newResp.length) {
			return true;
		}
		for (let i = 0; i < oldResp.length; i++) {
			if (oldResp[i].id !== newResp[i].id) {
				return true;
			}
		}
		return false;
	}
	if (type === "condition") {
		// Switch mode changes output count (true/false vs per-rule outputs)
		if (oldData?.switch_mode !== newData.switch_mode) {
			return true;
		}
		if (oldData?.switch_mode) {
			const oldRules = oldData?.condition?.rules || [];
			const newRules = newData.condition?.rules || [];
			if (oldRules.length !== newRules.length) {
				return true;
			}
		}
		return false;
	}
	if (type === "subflow") {
		const oldPins = oldData?.exit_pins || [];
		const newPins = newData.exit_pins || [];
		if (oldPins.length !== newPins.length) {
			return true;
		}
		return false;
	}
	// All other types have fixed sockets — never rebuild
	return false;
}
