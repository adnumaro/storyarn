/**
 * Variable utilities for condition and instruction builders.
 */

/**
 * Groups a flat variable list into sheets with their variables.
 *
 * @param {Array} variables - Flat list of { sheet_shortcut, sheet_name, variable_name, block_type, options }
 * @returns {Array} Sorted array of { shortcut, name, vars: [{ variable_name, block_type, options }] }
 */
export function groupVariablesBySheet(variables) {
	const sheetMap = new Map();

	for (const v of variables) {
		const key = v.sheet_shortcut;
		if (!sheetMap.has(key)) {
			sheetMap.set(key, {
				shortcut: v.sheet_shortcut,
				name: v.sheet_name || v.sheet_shortcut,
				vars: [],
			});
		}
		sheetMap.get(key).vars.push({
			variable_name: v.variable_name,
			block_type: v.block_type,
			options: v.options,
		});
	}

	return Array.from(sheetMap.values()).sort((a, b) =>
		a.name.localeCompare(b.name),
	);
}

/**
 * Finds a variable by sheet shortcut and variable name.
 *
 * @param {Array} variables - Flat variable list
 * @param {string} sheetShortcut
 * @param {string} variableName
 * @returns {Object|null}
 */
export function findVariable(variables, sheetShortcut, variableName) {
	if (!sheetShortcut || !variableName) return null;
	return variables.find(
		(v) =>
			v.sheet_shortcut === sheetShortcut && v.variable_name === variableName,
	);
}

/**
 * Generates a unique ID with the given prefix.
 *
 * @param {string} [prefix="block"] - Prefix for the ID ("block", "group", "rule")
 * @returns {string}
 */
export function generateId(prefix = "block") {
	return `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
}
