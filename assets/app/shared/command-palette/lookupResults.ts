export type PaletteLookupResultIcon = "sheet" | "flow" | "scene" | "reference";

export type PaletteLookupResultAction =
  | { kind: "navigate"; url: string }
  | { kind: "complete"; value: string };

/**
 * One authorized result returned by a deterministic palette lookup.
 *
 * `id` is presentation identity only. Callers must never forward it to
 * analytics. An explicit action keeps completion candidates separate from
 * server-validated navigation destinations.
 */
export interface PaletteLookupResult {
  id: string;
  label: string;
  context?: string;
  detail?: string;
  group?: string;
  icon?: PaletteLookupResultIcon;
  action: PaletteLookupResultAction;
}

export function lookupResultSearchText(result: PaletteLookupResult): string {
  return [result.label, result.context, result.detail].filter(Boolean).join(" ");
}

export function lookupResultAccessibleLabel(result: PaletteLookupResult): string {
  return [result.label, result.detail, result.context].filter(Boolean).join(", ");
}
