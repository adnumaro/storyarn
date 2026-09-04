export interface CommentMember {
  id: number | null;
  display_name: string;
  avatar_url: string | null;
}

export interface FlowCommentSource {
  type: "flow_node" | "flow_canvas";
  id: number;
  flow_id: number;
  label: string;
  status: "available" | "unavailable";
}

export type CommentStatus = "open" | "resolved";
export type CommentStatusFilter = CommentStatus | "all";

export interface FlowCommentPosition {
  x: number;
  y: number;
}

export interface FlowCommentThread {
  id: number;
  status: CommentStatus;
  revision: number;
  message_count: number;
  created_at: string;
  last_activity_at: string;
  resolved_at: string | null;
  resolved_by: CommentMember | null;
  source: FlowCommentSource;
  author: CommentMember;
  preview?: string;
  root_message_id?: number;
  position?: FlowCommentPosition | null;
}

export interface FlowCommentMessage {
  id: number;
  thread_id: number;
  parent_id: number | null;
  body: string;
  author: CommentMember;
  mentions: CommentMember[];
  inserted_at: string;
}

export interface FlowCommentsPanelState {
  open: boolean;
  presentation?: "panel" | "canvas";
  placing?: boolean;
  draftPosition?: FlowCommentPosition | null;
  draftId?: string | null;
  threads: FlowCommentThread[];
  nextCursor: number | null;
  thread: FlowCommentThread | null;
  messages: FlowCommentMessage[];
  messageNextCursor: number | null;
  members: CommentMember[];
  canComment: boolean;
  selectedNodeId: number | null;
  selectedNodeLabel?: string | null;
  statusFilter?: CommentStatusFilter;
  error: string | null;
}
