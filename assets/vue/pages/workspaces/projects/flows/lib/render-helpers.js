/**
 * Shared rendering utilities for flow node Vue components.
 * Port of assets/js/flow_canvas/nodes/render_helpers.js to Vue-compatible functions.
 */

/**
 * CSS gradient for node headers — solid left fading to lighter right.
 */
export function headerStyle(color) {
	return `background: linear-gradient(to right, ${color} 40%, color-mix(in oklch, ${color} 85%, white) 100%)`;
}

/**
 * Resolve node color from type-specific data, falling back to config default.
 */
export function resolveNodeColor(
	nodeType,
	nodeData,
	configColor,
	sheetsMap,
	hubsMap,
) {
	const d = nodeData || {};

	if (nodeType === "dialogue" && d.speaker_sheet_id) {
		const sheet = sheetsMap?.[String(d.speaker_sheet_id)];
		if (sheet?.color) {
			return sheet.color;
		}
	}

	if (nodeType === "slug_line" && d.location_sheet_id) {
		const sheet = sheetsMap?.[String(d.location_sheet_id)];
		if (sheet?.color) {
			return sheet.color;
		}
	}

	if ((nodeType === "hub" || nodeType === "exit") && d.color_hex) {
		return d.color_hex;
	}

	if (nodeType === "exit" && d.outcome_color) {
		return d.outcome_color;
	}

	if (nodeType === "jump" && d.target_hub_id && hubsMap) {
		const hub = hubsMap[d.target_hub_id];
		if (hub?.color_hex) {
			return hub.color_hex;
		}
	}

	if (nodeType === "annotation") {
		return d.color || "#fbbf24";
	}

	return configColor;
}

/**
 * Strip HTML tags and extract plain text for preview.
 */
export function stripHtml(html) {
	if (!html) {
		return "";
	}
	return html
		.replace(/<br\s*\/?>/gi, "\n")
		.replace(/<\/p>\s*<p[^>]*>/gi, "\n")
		.replace(/<[^>]*>/g, "")
		.replace(/&amp;/g, "&")
		.replace(/&lt;/g, "<")
		.replace(/&gt;/g, ">")
		.replace(/&nbsp;/g, " ")
		.trim();
}

/**
 * Truncate text for node preview.
 */
export function previewText(text, maxLen = 120) {
	const stripped = stripHtml(text);
	if (!stripped) {
		return "";
	}
	return stripped.length > maxLen ? `${stripped.slice(0, maxLen)}…` : stripped;
}

/**
 * Format condition operator to symbol.
 */
const OPERATOR_SYMBOLS = {
	equals: "=",
	not_equals: "≠",
	greater_than: ">",
	less_than: "<",
	greater_than_or_equal: "≥",
	less_than_or_equal: "≤",
	contains: "∋",
	not_contains: "∌",
	starts_with: "⊢",
	ends_with: "⊣",
	is_empty: "is empty",
	is_not_empty: "is not empty",
	is_true: "is true",
	is_false: "is false",
};

export function getOperatorSymbol(op) {
	return OPERATOR_SYMBOLS[op] || op;
}

/**
 * Format a condition rule to readable string.
 */
export function formatRule(rule) {
	const ref = rule.variable_ref || "?";
	const parts = ref.split(".");
	const sheet = parts.length > 1 ? parts[0] : "";
	const variable = parts.length > 1 ? parts.slice(1).join(".") : ref;
	const symbol = getOperatorSymbol(rule.operator);
	const noValueOps = ["is_empty", "is_not_empty", "is_true", "is_false"];

	if (noValueOps.includes(rule.operator)) {
		return sheet ? `${sheet}.${variable} ${symbol}` : `${variable} ${symbol}`;
	}

	const val =
		rule.value_type === "variable" && rule.value_ref
			? rule.value_ref
			: (rule.value ?? "");

	return sheet
		? `${sheet}.${variable} ${symbol} ${val}`
		: `${variable} ${symbol} ${val}`;
}

/**
 * Format a condition rule to short string (variable + symbol + truncated value).
 */
export function formatRuleShort(rule) {
	const ref = rule.variable_ref || "?";
	const parts = ref.split(".");
	const variable = parts.length > 1 ? parts.slice(1).join(".") : ref;
	const symbol = getOperatorSymbol(rule.operator);
	const noValueOps = ["is_empty", "is_not_empty", "is_true", "is_false"];

	if (noValueOps.includes(rule.operator)) {
		return `${variable} ${symbol}`;
	}

	let val =
		rule.value_type === "variable" && rule.value_ref
			? rule.value_ref
			: String(rule.value ?? "");
	if (val.length > 10) {
		val = `${val.slice(0, 10)}…`;
	}

	return `${variable} ${symbol} ${val}`;
}

/**
 * Format an instruction assignment to readable string.
 */
export function formatAssignment(assignment) {
	const ref = assignment.variable_ref || "?";
	const op = assignment.operator || "set";

	if (op === "toggle") {
		return `Toggle ${ref}`;
	}
	if (op === "clear") {
		return `Clear ${ref}`;
	}

	let val;
	if (assignment.value_type === "variable" && assignment.value_ref) {
		val = assignment.value_ref;
	} else if (typeof assignment.value === "boolean") {
		val = assignment.value ? "true" : "false";
	} else {
		val = assignment.value ?? "";
	}

	const opLabels = {
		set: "Set",
		add: "Add",
		subtract: "Subtract",
		multiply: "Multiply",
		divide: "Divide",
		append: "Append",
		prepend: "Prepend",
	};

	const label = opLabels[op] || "Set";

	if (op === "set") {
		return `${label} ${ref} to ${val}`;
	}
	if (["add", "subtract"].includes(op)) {
		return `${label} ${val} to ${ref}`;
	}
	return `${label} ${ref} by ${val}`;
}
