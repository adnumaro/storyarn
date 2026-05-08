/**
 * JS port of `Storyarn.Flows.Evaluator.Helpers.format_value/1` and
 * `strip_html/2`. Used across the debug panel (console, variables, history,
 * path) and the start-node select.
 */

export function formatDebugValue(value: unknown): string {
  if (value === null || value === undefined) return "nil";
  if (value === true) return "true";
  if (value === false) return "false";
  if (Array.isArray(value)) return value.join(", ");
  if (typeof value === "string") {
    return value.length > 30 ? `${value.slice(0, 30)}...` : value;
  }
  return String(value);
}

export function stripHtml(text: unknown, maxLength = 40): string | null {
  if (typeof text !== "string") return null;
  const stripped = text.replace(/<[^>]*>/g, "").trim();
  if (stripped === "") return null;
  return stripped.length > maxLength ? `${stripped.slice(0, maxLength)}…` : stripped;
}

export function formatDebugTs(ms: unknown): string {
  if (typeof ms !== "number" || !Number.isFinite(ms)) return "0.000s";
  const s = Math.floor(ms / 1000);
  const rem = Math.floor(ms % 1000);
  return `${s}.${String(rem).padStart(3, "0")}s`;
}
