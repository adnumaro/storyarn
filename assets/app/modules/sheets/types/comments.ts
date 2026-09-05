import type {
  CommentMessage,
  CommentPosition,
  CommentSource,
  CommentsPanelState,
  CommentThread,
} from "@components/comments/types";

export interface SheetCommentSource extends CommentSource {
  type: "sheet_block";
  sheet_id: number;
}

export type SheetCommentPosition = CommentPosition;
export type SheetCommentThread = CommentThread<SheetCommentSource>;
export type SheetCommentMessage = CommentMessage;

export interface SheetCommentsPanelState extends Omit<
  CommentsPanelState<SheetCommentSource>,
  "selectedSourceId" | "selectedSourceLabel"
> {
  selectedBlockId: number | null;
  selectedBlockLabel?: string | null;
}
