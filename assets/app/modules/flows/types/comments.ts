import type {
  CommentMember,
  CommentMessage,
  CommentPosition,
  CommentSource,
  CommentStatus,
  CommentStatusFilter,
  CommentsPanelState,
  CommentThread,
} from "@components/comments/types";

export type { CommentMember, CommentStatus, CommentStatusFilter };

export interface FlowCommentSource extends CommentSource {
  type: "flow_node" | "flow_canvas";
  flow_id: number;
}

export type FlowCommentPosition = CommentPosition;
export type FlowCommentThread = CommentThread<FlowCommentSource>;
export type FlowCommentMessage = CommentMessage;

export interface FlowCommentsPanelState extends Omit<
  CommentsPanelState<FlowCommentSource>,
  "selectedSourceId" | "selectedSourceLabel"
> {
  selectedNodeId: number | null;
  selectedNodeLabel?: string | null;
}
