export interface AnalysisEvidence {
  type: string;
  id: number;
}

export type AnalysisCategory = "structure" | "reference_integrity";
export type AnalysisSeverity = "error" | "warning";
export type AnalysisTargetType = "flow" | "node";

export interface AnalysisFinding {
  findingId: string;
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
  evidence: AnalysisEvidence[];
  // Present only on dismissed findings
  dismissalId?: number;
  reasonCode?: string;
  note?: string | null;
  dismissedBy?: string | null;
  dismissedAt?: string | null;
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
