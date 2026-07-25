import type { AIDestination } from "./aiCommands";

/**
 * Canonical AI destinations.
 *
 * A destination is registered by the surface that OWNS it (one instance per
 * LiveView), while commands that point at it may be registered from anywhere:
 * `registerAIDestination` deliberately throws when a second owner claims the
 * same id.
 */
export const FLOW_ANALYSIS_DESTINATION = {
  type: "panel",
  id: "flow_analysis",
} as const satisfies AIDestination;
