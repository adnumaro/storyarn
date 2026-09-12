/** Page keys avoid the AltGr/Option required for brackets on some keyboard layouts. */
export function commentContextCycleDirection(event: KeyboardEvent): 1 | -1 | null {
  if (event.altKey || event.ctrlKey || event.metaKey) return null;
  if (event.key === "PageDown" || event.key === "]") return 1;
  if (event.key === "PageUp" || event.key === "[") return -1;
  return null;
}
