import type {
  DecisionRecord,
  DecisionSource,
  DecisionsPanelState,
} from "@app/live/ideation/decisionTypes";

export function source(overrides: Partial<DecisionSource> = {}): DecisionSource {
  return {
    type: "idea",
    id: 10,
    identity: "idea-identity",
    version: 2,
    title: "The old road",
    preview: "The road is guarded.",
    available: true,
    ...overrides,
  };
}
export function decision(overrides: Partial<DecisionRecord> = {}): DecisionRecord {
  return {
    id: 4,
    revision: 1,
    title: "Take the forest path",
    conclusion: "The party avoids the road.",
    reason: "It creates a difficult choice.",
    ownerId: 1,
    ownerName: "Alex",
    acceptedAt: null,
    sources: [source()],
    status: "proposed",
    canAccept: true,
    canRevise: true,
    canAssign: true,
    ...overrides,
  };
}
export function decisions(overrides: Partial<DecisionsPanelState> = {}): DecisionsPanelState {
  return {
    open: true,
    context: "decisions-1",
    mode: "list",
    items: [],
    nextCursor: null,
    selected: null,
    history: [],
    sources: [],
    sourceResults: [],
    sourceNextCursor: null,
    searched: false,
    members: [{ id: 1, display_name: "Alex", avatar_url: null }],
    defaultOwnerId: 1,
    canPropose: true,
    error: null,
    ...overrides,
  };
}
