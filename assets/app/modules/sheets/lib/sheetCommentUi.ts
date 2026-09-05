import type { CommentsPanelState, CommentUiConfig } from "@components/comments/types";
import type { SheetCommentsPanelState } from "../types/comments";

export const sheetCommentUi: CommentUiConfig = {
  domScope: "sheet",
  i18nPrefix: "sheets.comments",
  // Sheets only expose block anchors. Keeping the canvas discriminator distinct
  // makes the shared conversation render each block's persisted label.
  canvasSourceType: "sheet_canvas",
  scopeThreadsKey: "sheet_threads",
  selectedSourceFallbackKey: "block_label",
  createSourceKey: "block_id",
};

export function adaptSheetCommentsState(state: SheetCommentsPanelState): CommentsPanelState {
  return {
    ...state,
    selectedSourceId: state.selectedBlockId,
    selectedSourceLabel: state.selectedBlockLabel,
  };
}
