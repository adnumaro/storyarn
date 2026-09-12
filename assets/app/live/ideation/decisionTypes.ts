import type { Board } from "@modules/ideation";

export type DecisionMember = Board["members"][number];

export type DecisionSourceType = "idea" | "group";
export interface DecisionSourceIdentity {
  type: DecisionSourceType;
  id: number | null;
  identity: string;
}
export interface DecisionSource extends DecisionSourceIdentity {
  version: number;
  title: string;
  preview: string;
  available: boolean;
  changed?: boolean;
  currentVersion?: number | null;
}
export interface DecisionDraftInput {
  title: string;
  conclusion: string;
  reason: string;
  owner_id: number;
  revision?: number;
}
export interface DecisionAgreement {
  revision: number;
  title: string;
  conclusion: string;
  reason: string;
  ownerId: number | null;
  ownerName: string | null;
  acceptedAt: string | null;
  sources: DecisionSource[];
}
export interface DecisionRecord extends DecisionAgreement {
  id: number;
  status: "proposed" | "accepted";
  canAccept: boolean;
  canRevise: boolean;
  canAssign: boolean;
  previousAgreement?: DecisionAgreement | null;
}
export interface DecisionHistoryEntry extends DecisionAgreement {
  operation: "proposed" | "revised" | "accepted" | "assigned";
  actorName: string | null;
  recordedAt: string;
}
export interface DecisionsPanelState {
  open: boolean;
  context: string;
  mode: "list" | "create" | "detail" | "revise";
  items: DecisionRecord[];
  nextCursor: number | null;
  selected: DecisionRecord | null;
  history: DecisionHistoryEntry[];
  historyNextCursor?: number | null;
  sources: DecisionSource[];
  sourceResults: DecisionSource[];
  sourceNextCursor: number | null;
  searched: boolean;
  members: DecisionMember[];
  defaultOwnerId: number | null;
  canPropose: boolean;
  error: string | null;
}
