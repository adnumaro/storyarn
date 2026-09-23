import type {
  CommentsPanelState,
  CommentThread,
  CommentPosition,
} from "@components/comments/types";

export interface BrainstormingCommentsState extends CommentsPanelState {
  pins: CommentThread[];
  ideaId: number | null;
  groupId?: number | null;
  /** Set while the decision panel holds the conversation (presentation "workspace"). */
  decisionId?: number | null;
  /** Messages in each decision's open discussions, keyed by decision id. */
  decisionCounts?: Record<string, number>;
  context: string;
}

export interface BrainstormingCommentTarget {
  ideaId: number | null;
  groupId: number | null;
  position: CommentPosition;
}
