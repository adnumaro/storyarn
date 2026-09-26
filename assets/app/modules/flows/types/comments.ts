import type { CommentSource, CommentsPanelState, CommentThread } from "@components/comments/types";

export interface FlowCommentSource extends CommentSource {
  type: "flow_node" | "flow_canvas";
  flow_id: number;
}

export type FlowCommentThread = CommentThread<FlowCommentSource>;

export interface FlowCommentsPanelState extends Omit<
  CommentsPanelState<FlowCommentSource>,
  "selectedSourceId" | "selectedSourceLabel"
> {
  selectedNodeId: number | null;
  selectedNodeLabel?: string | null;
}
