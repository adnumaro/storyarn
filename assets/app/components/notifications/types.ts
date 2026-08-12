export type NotificationFilter = "all" | "unread";

export interface NotificationItem {
  id: number;
  kind: "async_operation" | "content_created" | "content_deleted";
  entityType: string | null;
  entityName: string | null;
  status: "success" | "failure" | null;
  createdAt: string;
  readAt: string | null;
  actorName: string | null;
  projectName: string | null;
}

export interface NotificationCenterState {
  filter: NotificationFilter;
  items: NotificationItem[];
  unreadCount: number;
}
