import type { ReferenceTarget } from "./referenceTypes";

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
  canEdit: boolean;
  error: string | null;
}

export type ExplorationAction =
  | "open"
  | "close"
  | "search"
  | "load_more"
  | "create"
  | "link"
  | "resume";
