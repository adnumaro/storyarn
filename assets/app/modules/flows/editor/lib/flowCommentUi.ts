import type { CommentsPanelState, CommentUiConfig } from "@components/comments/types";
import type { FlowCommentsPanelState } from "../../types/comments";

export const flowCommentUi: CommentUiConfig = {
  domScope: "flow",
  i18nPrefix: "flows.comments",
  canvasSourceType: "flow_canvas",
  scopeThreadsKey: "flow_threads",
  selectedSourceFallbackKey: "node_label",
  createSourceKey: "node_id",
};

export function adaptFlowCommentsState(state: FlowCommentsPanelState): CommentsPanelState {
  return {
    ...state,
    selectedSourceId: state.selectedNodeId,
    selectedSourceLabel: state.selectedNodeLabel,
  };
}
