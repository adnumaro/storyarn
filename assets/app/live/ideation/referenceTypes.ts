export type ReferenceTargetType = "sheet" | "flow" | "scene" | "asset" | "localization";
export type ReferenceRelation = "origin" | "reference" | "affects" | "result" | "work";

export interface ReferenceField {
  key: string;
  value: string;
  truncated: boolean;
}

export interface ReferenceOverview {
  name: string;
  fields: ReferenceField[];
  capturedAt?: string | null;
}

export interface ReferenceTarget extends ReferenceOverview {
  id: number;
  type: ReferenceTargetType;
  href: string | null;
}

export interface BrainstormingReference {
  id: number;
  version: number;
  relation: ReferenceRelation;
  targetType: ReferenceTargetType;
  targetId: number | null;
  status: "current" | "changed" | "unavailable";
  base: ReferenceOverview | null;
  current: ReferenceTarget | null;
  capturedAt: string | null;
}

export interface ReferenceHistoryEntry {
  number: number;
  operation: "add" | "refresh" | "remove";
  insertedAt: string;
  context: ReferenceOverview | null;
}

export interface ReferencesPanelState {
  open: boolean;
  context: string;
  ideaId: number | null;
  items: BrainstormingReference[];
  nextCursor: number | null;
  results: ReferenceTarget[];
  searched: boolean;
  historyReferenceId: number | null;
  history: ReferenceHistoryEntry[];
  canEdit: boolean;
  error: string | null;
}
