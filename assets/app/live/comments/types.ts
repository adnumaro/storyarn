import type { CommentsPanelState, CommentThread } from "@components/comments/types";

export interface HubThread extends CommentThread {
  project_id: number;
  project_name: string;
  project_slug: string;
  workspace_id: number;
  workspace_name: string;
  workspace_slug: string;
}

export type HubToggle = "" | "1";

export interface HubFilters {
  workspace_id: string;
  project_id: string;
  tool: string;
  status: "all" | "open" | "resolved";
  personal: "all" | "participated" | "mentioned";
  unread: HubToggle;
  following: HubToggle;
  search: string;
}

/** Facet counts for the current scope and search: what each chip would show if selected. */
export interface HubCounts {
  all: number;
  open: number;
  resolved: number;
  tools: Record<string, number>;
  unread: number;
  mentioned: number;
  participated: number;
  following: number;
}

export interface HubWorkspaceOption {
  id: number;
  name: string;
}

export interface HubProjectOption extends HubWorkspaceOption {
  workspace_id: number;
}

export interface HubState {
  threads: HubThread[];
  counts?: HubCounts;
  nextCursor: { prio?: number; at: string; id: number } | null;
  filters: HubFilters;
  workspaces: HubWorkspaceOption[];
  projects: HubProjectOption[];
  conversation: CommentsPanelState;
  selectedProjectId: number | null;
  selectedThreadId: number | null;
  contextUrl: string | null;
  error: string | null;
}
