import type {
  DecisionRecord,
  DecisionRevision,
  DecisionSource,
  DecisionTarget,
  DecisionsPanelState,
} from "@app/live/ideation/decisionTypes";

export function source(overrides: Partial<DecisionSource> = {}): DecisionSource {
  return {
    type: "idea",
    id: 10,
    identity: "idea-identity",
    version: 2,
    title: "",
    preview: "The road is guarded.",
    authorName: "Alex",
    roundNumber: 1,
    available: true,
    ...overrides,
  };
}
export function target(overrides: Partial<DecisionTarget> = {}): DecisionTarget {
  return {
    key: "target-mara",
    type: "sheet",
    id: 7,
    name: "Mara",
    isNew: false,
    available: true,
    application: null,
    ...overrides,
  };
}
export function revision(overrides: Partial<DecisionRevision> = {}): DecisionRevision {
  return {
    revision: 1,
    operation: "propose",
    verb: "change",
    title: "Take the forest path",
    conclusion: "The party avoids the road.",
    reason: "It creates a difficult choice.",
    responsibleId: 1,
    responsibleName: "Alex",
    actorName: "Alex",
    nextAction: null,
    round: { number: 1, prompt: "Where do they go?" },
    replacesId: null,
    recordedAt: "2026-09-13T12:00:00Z",
    sources: [source()],
    targets: [target()],
    ...overrides,
  };
}
export function decision(overrides: Partial<DecisionRecord> = {}): DecisionRecord {
  return {
    id: 4,
    version: 1,
    status: "proposed",
    proposal: revision(),
    accepted: null,
    application: null,
    proposerName: "Alex",
    withdrawnByName: null,
    replaces: null,
    supersedes: null,
    supersededBy: null,
    canAccept: true,
    canRevise: true,
    canAssign: true,
    canWithdraw: true,
    canDeclare: false,
    tasks: [],
    canLinkTasks: false,
    updatedAt: "2026-09-13T12:00:00Z",
    ...overrides,
  };
}
/** An accepted decision: its agreement is revision 2 and every target starts not applied. */
export function accepted(overrides: Partial<DecisionRecord> = {}): DecisionRecord {
  const agreement = revision({ revision: 2, operation: "accept" });
  return decision({
    version: 2,
    status: "accepted",
    proposal: agreement,
    accepted: agreement,
    application: { targets: agreement.targets, decision: null, pending: 1, total: 1 },
    proposerName: null,
    canAccept: false,
    canWithdraw: false,
    canDeclare: true,
    ...overrides,
  });
}
export function decisions(overrides: Partial<DecisionsPanelState> = {}): DecisionsPanelState {
  return {
    open: true,
    context: "decisions-1",
    mode: "list",
    items: [],
    selected: null,
    history: [],
    sources: [],
    sourceResults: [],
    sourceNextCursor: null,
    searched: false,
    targetSuggestions: [],
    targetResults: [],
    prefill: null,
    members: [
      { id: 1, display_name: "Alex", avatar_url: null },
      { id: 2, display_name: "Noor", avatar_url: null },
    ],
    defaultOwnerId: null,
    viewerId: 1,
    rounds: [{ number: 1, prompt: "Where do they go?" }],
    canPropose: true,
    error: null,
    ...overrides,
  };
}
