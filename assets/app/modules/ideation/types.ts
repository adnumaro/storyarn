import type { DecisionSessionGroup } from "@app/live/ideation/decisionDashboard";
export type IdeaState = "active" | "parked" | "discarded";
export type Visibility = "private" | "shared";
export type PublicationPolicy = "author_only" | "facilitator_assisted";
export type NoteShape = "plain" | "rectangle" | "ellipse" | "diamond";
export type LinkDirection = "none" | "forward" | "backward" | "both";

export interface IdeaContent {
  title: string | null;
  body: string;
  state: IdeaState;
}
export interface CanvasPlacement {
  links?: number[];
  link_directions?: { [target: number]: LinkDirection };
  links_version?: number;
  x?: number;
  y?: number;
  width?: number;
  color?: string;
  shape?: NoteShape;
  version?: number;
}
export interface ConnectionChange {
  source_id: number;
  target_id: number;
  connected: boolean;
  direction?: LinkDirection;
}
export interface ConnectionAcknowledgement extends Omit<ConnectionChange, "direction"> {
  direction?: LinkDirection | null;
  previous_connected?: boolean;
  previous_direction?: LinkDirection | null;
}
export interface ConnectionVersion {
  id: number;
  version: number;
}
export interface ConnectionResult {
  changes: ConnectionAcknowledgement[];
  versions: ConnectionVersion[];
}
export interface NoteConnection {
  source_ids: number[];
}
export interface CreatedConnection extends ConnectionVersion {
  before_version: number;
}
/** A deep link from the session tree, applied once per `seq`. */
export interface BoardLink {
  round_id: number | null;
  view: "later" | null;
  seq: number;
}
export interface CreatedIdea extends Idea {
  connected_from?: CreatedConnection[];
}
export interface Idea extends IdeaContent {
  round_id: number | null;
  late_contribution: boolean;
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
export interface IdeaGroup {
  id: number;
  session_id: number;
  /** The round whose band holds the group; its frame and members are stored relative to that header. */
  round_id?: number | null;
  title: string | null;
  synthesis: string | null;
  author_id: number | null;
  version: number;
  canvas: { x: number; y: number; width: number; height: number };
  idea_ids: number[];
  members: Array<{
    idea_id: number;
    source_revision: number;
    round_id?: number | null;
    canvas: CanvasPlacement;
  }>;
  deleted_at: string | null;
  inserted_at: string;
}
export interface GroupVersions {
  version: number;
  member_versions: Array<{ id: number; version: number }>;
}

export interface GroupText {
  title?: string;
  synthesis?: string;
}
export interface CanvasIdea extends Idea {
  round_number?: number;
  /** Stable render key across the local-to-server id swap of a new note. */
  key?: string;
}
export interface EditReceipt {
  id: number;
  idea_id: number;
  base_revision: number;
  attempted: IdeaContent;
  inserted_at: string;
}
export interface SessionConfiguration {
  default_visibility: Visibility;
  publication_policy: PublicationPolicy;
}
export interface HistoryPage<T> {
  entries: T[];
  next: number | null;
}
export interface Session {
  id: number;
  title: string;
  objective: string | null;
  context: string | null;
  status: "open" | "archived";
  revision: number;
  configuration_version: number;
  contributions_open: boolean;
  facilitator_id: number | null;
  decision_owner_id: number | null;
  deleted_at: string | null;
  inserted_at: string;
  configuration: SessionConfiguration;
  can_manage: boolean;
  /** Session tree only: rounds in band order and the parked notes the viewer may see. */
  rounds?: Round[];
  parked_count?: number;
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
/** What the facilitator sets on the round in progress. */
export interface RoundPrivacy {
  private: boolean;
  reveal_on_expiry: boolean;
}
/** Another person's note in a private round: where it is and how wide, nothing more. */
export interface MaskedIdea {
  id: number;
  round_id: number;
  canvas: { x?: number; y?: number; width?: number };
}
export interface Round {
  id: number;
  session_id: number;
  number: number;
  prompt: string | null;
  status: "active" | "closed";
  private: boolean;
  reveal_on_expiry: boolean;
  revealed_at: string | null;
  /** Canvas y of the round header; note positions in the band are relative to it. */
  started_at: string | null;
  closed_at: string | null;
  inserted_at: string;
  updated_at: string;
}
/** Width tiers of a round header, measured on the header itself. */
export type HeaderTier = "xl" | "l" | "m" | "s" | "xs";
/** The session timer as the round in progress shows it on its header. */
export interface RoundTimerContext {
  session: Session;
  epoch: string;
  timer: SessionTimer | null;
  canEdit: boolean;
}
export interface SessionTimer {
  id: number;
  version: number;
  status: "running" | "paused" | "elapsed" | "cancelled";
  deadline_at: string | null;
  remaining_seconds: number;
  duration_seconds: number;
  close_contributions_on_expiry: boolean;
  outcome:
    | "completed"
    | "skipped_authorization"
    | "skipped_configuration"
    | "skipped_session"
    | null;
  server_now: string;
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
  timer: SessionTimer | null;
  rounds: Round[];
  active_round: Round | null;
  ideas: Idea[];
  masked_ideas: MaskedIdea[];
  groups: IdeaGroup[];
  ideas_next: number | null;
  idea_before: number | null;
  counts: { active: number; parked: number; discarded: number };
  can_edit: boolean;
  can_manage: boolean;
  is_owner: boolean;
  current_user_id: number | null;
  members: Member[];
  /** The dashboard's decisions, grouped by session. */
  decision_sessions?: DecisionSessionGroup[];
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
