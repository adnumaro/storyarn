export interface AnalysisEvidence {
  type: string;
  id: number;
}

export interface AnalysisFinding {
  findingId: string;
  ruleId: string;
  ruleVersion: number;
  category: string;
  severity: string;
  targetType: string;
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
