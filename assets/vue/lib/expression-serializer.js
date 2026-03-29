/**
 * Serializes condition/instruction data to DSL text for the Code view.
 *
 * Ported from lib/storyarn_web/components/expression_editor.ex
 */

const OPERATOR_SYMBOLS = {
	equals: "==",
	not_equals: "!=",
	greater_than: ">",
	less_than: "<",
	greater_than_or_equal: ">=",
	less_than_or_equal: "<=",
	contains: "contains",
	starts_with: "starts_with",
	ends_with: "ends_with",
	not_contains: "not_contains",
	before: "<",
	after: ">",
};

const INSTRUCTION_SYMBOLS = {
	set: "=",
	add: "+=",
	subtract: "-=",
	set_true: "= true",
	set_false: "= false",
	toggle: "toggle",
	clear: "clear",
};

function formatValue(value) {
	if (value == null) return "?";
	const str = String(value);
	// If it parses as a number, use it raw
	if (str !== "" && !Number.isNaN(Number(str))) return str;
	// Otherwise quote it
	const escaped = str.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
	return `"${escaped}"`;
}

function formatRule(rule) {
	const { sheet, variable, operator, value } = rule;
	if (!sheet || !variable) return "";
	const ref = `${sheet}.${variable}`;

	if (operator === "is_true") return ref;
	if (operator === "is_false") return `!${ref}`;
	if (operator === "is_nil") return `${ref} == nil`;
	if (operator === "is_empty") return `${ref} == ""`;

	const symbol = OPERATOR_SYMBOLS[operator] || operator;
	return `${ref} ${symbol} ${formatValue(value)}`;
}

function serializeBlock(block) {
	if (block.type === "group") {
		const joiner = block.logic === "any" ? " || " : " && ";
		const texts = (block.blocks || []).map(serializeBlock).filter(Boolean);
		if (texts.length === 0) return "";
		if (texts.length === 1) return texts[0];
		return `(${texts.join(joiner)})`;
	}

	// Regular block
	const joiner = block.logic === "any" ? " || " : " && ";
	const texts = (block.rules || []).map(formatRule).filter(Boolean);
	if (texts.length === 0) return "";
	if (texts.length === 1) return texts[0];
	return `(${texts.join(joiner)})`;
}

/**
 * Serialize a block-format condition to DSL text.
 */
export function serializeCondition(condition) {
	if (!condition) return "";
	const blocks = condition.blocks || [];
	if (blocks.length === 0) return "";

	const topJoiner = condition.logic === "any" ? " || " : " && ";
	return blocks.map(serializeBlock).filter(Boolean).join(topJoiner);
}

/**
 * Serialize an assignments array to DSL text.
 */
export function serializeAssignments(assignments) {
	if (!assignments || assignments.length === 0) return "";

	return assignments
		.map((a) => {
			const { operator, sheet, variable, value, value_type, value_sheet } = a;
			if (!sheet || !variable) return "";
			const ref = `${sheet}.${variable}`;

			if (operator === "set_true") return `${ref} = true`;
			if (operator === "set_false") return `${ref} = false`;
			if (operator === "toggle") return `toggle ${ref}`;
			if (operator === "clear") return `clear ${ref}`;

			const symbol = INSTRUCTION_SYMBOLS[operator] || "=";
			if (value_type === "variable_ref" && value_sheet && value) {
				return `${ref} ${symbol} ${value_sheet}.${value}`;
			}
			return `${ref} ${symbol} ${formatValue(value)}`;
		})
		.filter(Boolean)
		.join("\n");
}
