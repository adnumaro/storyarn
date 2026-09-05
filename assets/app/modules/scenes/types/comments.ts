import type {
  CommentMessage,
  CommentPosition,
  CommentSource,
  CommentsPanelState,
  CommentThread,
} from "@components/comments/types";

export interface SceneCommentSource extends CommentSource {
  type: "scene_canvas";
  scene_id: number;
}

export type SceneCommentPosition = CommentPosition;
export type SceneCommentThread = CommentThread<SceneCommentSource>;
export type SceneCommentMessage = CommentMessage;

export interface SceneCommentsPanelState extends Omit<
  CommentsPanelState<SceneCommentSource>,
  "selectedSourceId" | "selectedSourceLabel"
> {}
