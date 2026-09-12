import type { CommentsPanelState, CommentThread } from "@components/comments/types";

export interface HubThread extends CommentThread {
  project_id: number;
  project_name: string;
  project_slug: string;
  workspace_id: number;
  workspace_name: string;
  workspace_slug: string;
}

export interface HubFilters {
  workspace_id: string;
  project_id: string;
  tool: string;
  status: "all" | "open" | "resolved";
  personal: "all" | "participated" | "mentioned";
  search: string;
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
  counts?: { all: number; open: number; resolved: number };
  nextCursor: { at: string; id: number } | null;
  filters: HubFilters;
  workspaces: HubWorkspaceOption[];
  projects: HubProjectOption[];
  conversation: CommentsPanelState;
  selectedProjectId: number | null;
  selectedThreadId: number | null;
  contextUrl: string | null;
  error: string | null;
}
