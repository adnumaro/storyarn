export type NotificationFilter = "all" | "unread";

export interface NotificationItem {
  id: number;
  kind:
    | "async_operation"
    | "content_created"
    | "content_deleted"
    | "comment_mention"
    | "comment_reply"
    | "comment_followed"
    | "decision_to_accept"
    | "decision_accepted"
    | "decision_next_action"
    | "decision_applied";
  entityType: string | null;
  entityName: string | null;
  status: "success" | "failure" | null;
  createdAt: string;
  readAt: string | null;
  actorName: string | null;
  projectName: string | null;
  href: string | null;
  /** Extra content a domain draws inside the notification; see attachments.ts. */
  attachment?: NotificationAttachment | null;
}

/**
 * Content a domain attaches to its notifications. The inbox knows only its
 * type and passes the data, unread, to the renderer registered for that type.
 */
export interface NotificationAttachment {
  type: string;
  data: unknown;
}

export interface NotificationCenterState {
  filter: NotificationFilter;
  items: NotificationItem[];
  unreadCount: number;
}
