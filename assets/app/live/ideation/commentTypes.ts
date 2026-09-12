import type { CommentsPanelState } from "@components/comments/types";

export interface BrainstormingCommentsState extends CommentsPanelState {
  ideaId: number | null;
  groupId?: number | null;
  context: string;
}
