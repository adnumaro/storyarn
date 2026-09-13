import type {
  CommentsPanelState,
  CommentThread,
  CommentPosition,
} from "@components/comments/types";

export interface BrainstormingCommentsState extends CommentsPanelState {
  pins: CommentThread[];
  ideaId: number | null;
  groupId?: number | null;
  context: string;
}

export interface BrainstormingCommentTarget {
  ideaId: number | null;
  groupId: number | null;
  position: CommentPosition;
}
