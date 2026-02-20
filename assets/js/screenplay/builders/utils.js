/**
 * Shared utilities for screenplay builders (condition, instruction, response).
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

  return Array.from(sheetMap.values()).sort((a, b) => a.name.localeCompare(b.name));
}
