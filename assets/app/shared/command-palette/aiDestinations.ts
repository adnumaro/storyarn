import type { AIDestination } from "./aiCommands";

/**
 * Canonical AI destinations.
 *
 * A destination should be registered by the surface that OWNS it — one instance
 * per LiveView — while commands that point at it may be registered from
 * anywhere. That ownership is a convention, NOT enforced: registration is
 * last-one-wins, because a LiveVue remount runs the incoming component's setup
 * before the outgoing one's onUnmounted and refusing the duplicate crashed the
 * surface on every remount. Two different surfaces claiming one id will
 * therefore hijack each other silently.
 */
export const FLOW_ANALYSIS_DESTINATION = {
  type: "panel",
  id: "flow_analysis",
} as const satisfies AIDestination;
