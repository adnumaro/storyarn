import type { ReferenceTarget } from "./referenceTypes";
import type { DecisionBannerState, DecisionRecord } from "./decisionTypes";

export interface ExplorationSession {
  id: number;
  title: string;
  status: "open" | "archived";
  contextStatus?: "current" | "changed" | "unavailable";
}

export interface ExplorationLauncherState {
  open: boolean;
  context: string;
  target: ReferenceTarget | null;
  linked: ExplorationSession[];
  available: ExplorationSession[];
  linkedNext: number | null;
  availableNext: number | null;
  linkedPrevious: boolean;
  availablePrevious: boolean;
  linkedCursor: number | null;
  availableCursor: number | null;
  canEdit: boolean;
  error: string | null;
  /** Decisions about this content: all of them, and those still to apply here. */
  decisions?: { total: number; toApply: number; name: string | null };
  about?: DecisionAbout[];
  banner?: DecisionBannerState | null;
}

/** A decision about the content, with the key this content has in it. */
export interface DecisionAbout {
  decision: DecisionRecord;
  targetKey: string | null;
  sessionId: number;
  sessionTitle: string;
  sessionUrl: string;
  /** Rounds of that session; the card names the round when there is more than one. */
  roundCount: number;
  toApply: boolean;
}

export type ExplorationAction =
  | "open"
  | "close"
  | "search"
  | "load_more"
  | "load_previous"
  | "create"
  | "link"
  | "resume"
  | "decision_apply"
  | "decision_declare"
  | "decision_undo"
  | "decision_dismiss";
