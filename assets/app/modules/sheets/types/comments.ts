import type {
  CommentMessage,
  CommentPosition,
  CommentSource,
  CommentsPanelState,
  CommentThread,
} from "@components/comments/types";

export interface SheetCommentSource extends CommentSource {
  type: "sheet_canvas";
  sheet_id: number;
}

export type SheetCommentPosition = CommentPosition;
export type SheetCommentThread = CommentThread<SheetCommentSource>;
export type SheetCommentMessage = CommentMessage;

export type SheetCommentsPanelState = Omit<
  CommentsPanelState<SheetCommentSource>,
  "selectedSourceId" | "selectedSourceLabel"
>;
