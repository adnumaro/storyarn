/**
 * Deep equality comparison for plain JSON-like objects (conditions, assignments, etc.).
 */
export function deepEqual(a, b) {
  if (a === b) return true;
  if (a == null || b == null) return a == b;
  if (Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length) return false;
    return a.every((item, i) => deepEqual(item, b[i]));
  }
  if (typeof a === "object" && typeof b === "object") {
    const keysA = Object.keys(a).sort();
    const keysB = Object.keys(b).sort();
    if (keysA.length !== keysB.length) return false;
    return keysA.every(
      (key, i) => keysB[i] === key && deepEqual(a[key], b[key]),
    );
  }
  return false;
}
