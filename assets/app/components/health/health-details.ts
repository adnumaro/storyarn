import type { HealthStatusDetails } from "@shared/types/health";

/** What `t()` may safely receive as named params. */
export type InterpolatableDetails = Record<string, string | number | boolean | null>;

/**
 * Prepares a finding's `details` for `t()`.
 *
 * vue-i18n renders an array passed as a named param as pretty-printed JSON —
 * `pins: ["true", "false"]` comes out as `[\n  "true",\n  "false"\n]` inside
 * the sentence. Every list detail is therefore joined into a readable string
 * first. Scalars pass through untouched, `null` included: vue-i18n renders it
 * as an empty placeholder, which is what an absent value should look like.
 */
export function interpolatableDetails(details?: HealthStatusDetails): InterpolatableDetails {
  if (!details) return {};

  const prepared: InterpolatableDetails = {};

  for (const [key, value] of Object.entries(details)) {
    prepared[key] = Array.isArray(value) ? value.join(", ") : value;
  }

  return prepared;
}
