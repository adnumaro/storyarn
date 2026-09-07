export type IdeaState = "active" | "parked" | "discarded";
export type Visibility = "private" | "shared";
export type PublicationPolicy = "author_only" | "facilitator_assisted";

export interface IdeaContent {
  title: string | null;
  body: string;
  state: IdeaState;
}
export interface CanvasPlacement {
  links?: number[];
  x?: number;
  y?: number;
  width?: number;
  color?: string;
  version?: number;
}
export interface Idea extends IdeaContent {
  deleted_at?: string | null;
  canvas?: CanvasPlacement;
  id: number;
  session_id: number;
  author_id: number | null;
  author_kind: string;
  revision: number;
  visibility: Visibility;
  published_revision: number | null;
  current_revision?: number;
  publication_consent?: PublicationPolicy;
  configuration_version?: number;
  has_unpublished_changes?: boolean;
  source_idea_id: number | null;
  source_revision: number | null;
  inserted_at: string;
  preview: string;
}
export interface IdeaRevision extends IdeaContent {
  id: number;
  number: number;
  actor_id: number | null;
  inserted_at: string;
}
export interface EditReceipt {
  id: number;
  idea_id: number;
  base_revision: number;
  attempted: IdeaContent;
  inserted_at: string;
}
export interface HistoryPage<T> {
  entries: T[];
  next: number | null;
}

export interface Inspection {
  idea: Idea;
  history: IdeaRevision[];
  history_next: number | null;
  conflicts: EditReceipt[];
  conflicts_next: number | null;
}
export interface SessionConfiguration {
  private_mode: boolean;
  default_visibility: Visibility;
  publication_policy: PublicationPolicy;
}
export interface Session {
  id: number;
  title: string;
  objective: string | null;
  context: string | null;
  status: "open" | "archived";
  revision: number;
  configuration_version: number;
  facilitator_id: number | null;
  decision_owner_id: number | null;
  deleted_at: string | null;
  inserted_at: string;
  configuration: SessionConfiguration;
  can_manage: boolean;
}
export interface SessionRevision {
  id: number;
  number: number;
  actor_id: number | null;
  action: string;
  snapshot: Omit<Session, "id" | "revision" | "inserted_at" | "can_manage" | "deleted_at">;
  inserted_at: string;
}
export interface Member {
  id: number;
  display_name: string;
  avatar_url: string | null;
}
export interface Board {
  epoch: string;
  loading: boolean;
  error: string | null;
  sessions: Session[];
  sessions_next: number | null;
  session_before: number | null;
  session_status: "open" | "archived" | "replaced";
  session: Session | null;
  session_missing: boolean;
  ideas: Idea[];
  ideas_next: number | null;
  idea_before: number | null;
  counts: { active: number; parked: number; discarded: number };
  can_edit: boolean;
  can_manage: boolean;
  is_owner: boolean;
  current_user_id: number | null;
  members: Member[];
}
export interface BoardContext {
  epoch: string;
  session_id: number | null;
}
export interface Reveal {
  id: number;
  count: number;
  status: string;
}
export interface Conflict {
  current: Idea;
  receipt: EditReceipt;
}
export type Reply<T> =
  | { status: "ok"; value: T }
  | { status: "error"; code: string; fields?: string[] }
  | { status: "conflict"; value: Conflict };
export type Request = <T>(
  event: string,
  payload: Record<string, unknown>,
  context?: BoardContext,
) => Promise<Reply<T>>;
