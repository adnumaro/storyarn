export interface CommentMember {
  id: number | null;
  display_name: string;
  avatar_url: string | null;
}

export interface CommentSource {
  type: string;
  id: number;
  label: string;
  status: "available" | "unavailable";
}

export type CommentStatus = "open" | "resolved";
export type CommentStatusFilter = CommentStatus | "all";

export interface CommentPosition {
  x: number;
  y: number;
}

export interface CommentThread<TSource extends CommentSource = CommentSource> {
  id: number;
  status: CommentStatus;
  revision: number;
  message_count: number;
  created_at: string;
  last_activity_at: string;
  resolved_at: string | null;
  resolved_by: CommentMember | null;
  source: TSource;
  author: CommentMember;
  preview?: string;
  root_message_id?: number;
  position?: CommentPosition | null;
}

export interface CommentMessage {
  id: number;
  thread_id: number;
  parent_id: number | null;
  body: string;
  author: CommentMember;
  mentions: CommentMember[];
  inserted_at: string;
}

export interface CommentsPanelState<TSource extends CommentSource = CommentSource> {
  open: boolean;
  presentation?: "panel" | "canvas";
  placing?: boolean;
  draftPosition?: CommentPosition | null;
  draftId?: string | null;
  threads: CommentThread<TSource>[];
  nextCursor: number | null;
  thread: CommentThread<TSource> | null;
  messages: CommentMessage[];
  messageNextCursor: number | null;
  members: CommentMember[];
  canComment: boolean;
  selectedSourceId: number | null;
  selectedSourceLabel?: string | null;
  statusFilter?: CommentStatusFilter;
  error: string | null;
}

export interface CommentUiConfig {
  /** Prefix used by stable DOM ids, for example `flow` or `scene`. */
  domScope: string;
  /** Vue-i18n namespace containing the common comment labels. */
  i18nPrefix: string;
  /** Source type whose label and unavailable copy describe the whole canvas. */
  canvasSourceType: string;
  /** Translation key, relative to i18nPrefix, for an unfiltered thread list. */
  scopeThreadsKey: string;
  /** Translation key, relative to i18nPrefix, for a selected source fallback. */
  selectedSourceFallbackKey: string;
  /** Optional create-event field used by editors with entity anchors. */
  createSourceKey?: string;
}
