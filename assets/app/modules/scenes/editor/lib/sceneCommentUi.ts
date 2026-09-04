import type { CommentsPanelState, CommentUiConfig } from "@components/comments/types";
import type { SceneCommentsPanelState } from "../../types/comments";

export const sceneCommentUi: CommentUiConfig = {
  domScope: "scene",
  i18nPrefix: "scenes.comments",
  canvasSourceType: "scene_canvas",
  scopeThreadsKey: "scene_threads",
  selectedSourceFallbackKey: "scene_label",
};

export function adaptSceneCommentsState(state: SceneCommentsPanelState): CommentsPanelState {
  return {
    ...state,
    selectedSourceId: null,
    selectedSourceLabel: null,
  };
}
