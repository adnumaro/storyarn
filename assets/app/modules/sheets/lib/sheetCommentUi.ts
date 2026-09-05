import type { CommentsPanelState, CommentUiConfig } from "@components/comments/types";
import type { SheetCommentsPanelState } from "../types/comments";

export const sheetCommentUi: CommentUiConfig = {
  domScope: "sheet",
  i18nPrefix: "sheets.comments",
  canvasSourceType: "sheet_canvas",
  scopeThreadsKey: "sheet_threads",
  selectedSourceFallbackKey: "sheet_label",
};

export function adaptSheetCommentsState(state: SheetCommentsPanelState): CommentsPanelState {
  return { ...state, selectedSourceId: null, selectedSourceLabel: null };
}
