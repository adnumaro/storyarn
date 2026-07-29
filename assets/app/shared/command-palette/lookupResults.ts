export type PaletteLookupResultIcon = "sheet" | "flow" | "scene" | "reference";

/**
 * One authorized, navigable result returned by a deterministic palette lookup.
 *
 * `id` is presentation identity only. Callers must never forward it to
 * analytics; lookup telemetry uses closed operation ids without result data.
 */
export interface PaletteLookupResult {
  id: string;
  url: string;
  label: string;
  context?: string;
  detail?: string;
  icon?: PaletteLookupResultIcon;
}

export function lookupResultSearchText(result: PaletteLookupResult): string {
  return [result.label, result.context, result.detail].filter(Boolean).join(" ");
}

export function lookupResultAccessibleLabel(result: PaletteLookupResult): string {
  return [result.label, result.detail, result.context].filter(Boolean).join(", ");
}
