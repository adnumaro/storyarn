/**
 * Variable utilities for condition and instruction builders.
 */

export interface VariableOption {
  key: string;
  value: string;
}

export interface Variable {
  sheet_shortcut: string;
  sheet_name?: string;
  variable_name: string;
  block_type: string;
  options?: VariableOption[];
}

export interface SheetGroup {
  shortcut: string;
  name: string;
  vars: Pick<Variable, "variable_name" | "block_type" | "options">[];
}

/**
 * Groups a flat variable list into sheets with their variables.
 */
export function groupVariablesBySheet(variables: Variable[]): SheetGroup[] {
  const sheetMap = new Map<string, SheetGroup>();

  for (const v of variables) {
    const key = v.sheet_shortcut;
    if (!sheetMap.has(key)) {
      sheetMap.set(key, {
        shortcut: v.sheet_shortcut,
        name: v.sheet_name || v.sheet_shortcut,
        vars: [],
      });
    }
    sheetMap.get(key)!.vars.push({
      variable_name: v.variable_name,
      block_type: v.block_type,
      options: v.options,
    });
  }

  return Array.from(sheetMap.values()).sort((a, b) => a.name.localeCompare(b.name));
}

/**
 * Finds a variable by sheet shortcut and variable name.
 */
export function findVariable(
  variables: Variable[],
  sheetShortcut: string | null | undefined,
  variableName: string | null | undefined,
): Variable | null | undefined {
  if (!sheetShortcut || !variableName) return null;
  return variables.find(
    (v) => v.sheet_shortcut === sheetShortcut && v.variable_name === variableName,
  );
}

/**
 * Generates a unique ID with the given prefix.
 */
export function generateId(prefix: string = "block"): string {
  return `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
}
