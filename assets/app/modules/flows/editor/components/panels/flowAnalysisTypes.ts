export interface AnalysisEvidence {
  type: string;
  id: number;
}

export type AnalysisCategory = "structure" | "reference_integrity";
export type AnalysisSeverity = "error" | "warning";
export type AnalysisTargetType = "flow" | "node";

export interface AnalysisFinding {
  findingId: string;
  /** Stable for rule+target across evidence changes; anchors the AI surface. */
  findingKey: string;
  ruleId: string;
  ruleVersion: number;
  category: AnalysisCategory;
  severity: AnalysisSeverity;
  targetType: AnalysisTargetType;
  targetId: number;
  nodeType?: string | null;
  pins: string[];
  count?: number | null;
  hubId?: string | null;
  limitationsKey?: string | null;
  previousDismissal?: {
    reasonCode: string;
    dismissedBy: string | null;
    dismissedAt: string | null;
  } | null;
  evidence: AnalysisEvidence[];
  // Present only on dismissed findings
  dismissalId?: number;
  reasonCode?: string;
  note?: string | null;
  dismissedBy?: string | null;
  dismissedAt?: string | null;
}

/** Optional AI explanation of ONE finding (Slice 7.2a). */
export type ExplanationStatus =
  | "idle"
  | "preflight"
  | "blocked"
  | "running"
  | "succeeded"
  | "failed"
  | "expired";

export interface ExplanationRoute {
  routeRef: string;
  lane: string;
  provider: string;
  model: string;
  payer: string;
  priceUnits: number;
}

export interface ExplanationBlockedLane {
  lane: string;
  reason: string;
}

export interface ExplanationDisclosure {
  version: string;
  context_version: string;
  scope: string;
  serialized_bytes: number;
  token_count: number | null;
  included_count: number;
  excluded_count: number;
  truncated: boolean;
  warnings: string[];
}

/** Bounded narrative. Never carries ids, severities, or actions. */
export interface ExplanationResult {
  summary: string;
  whyItTriggers: string;
  implications: string[];
  suggestedChecks: string[];
}

export interface FlowExplanationState {
  available: boolean;
  findingId: string | null;
  findingKey: string | null;
  status: ExplanationStatus;
  error: string | null;
  stale: boolean;
  routes: ExplanationRoute[];
  blockedLanes: ExplanationBlockedLane[];
  disclosure: ExplanationDisclosure | null;
  result: ExplanationResult | null;
}

export interface FlowAnalysisPanelState {
  open: boolean;
  canEdit: boolean;
  stale: boolean;
  computedAt: string | null;
  reasonCodes: string[];
  maxNoteLength: number;
  active: AnalysisFinding[];
  dismissed: AnalysisFinding[];
}
