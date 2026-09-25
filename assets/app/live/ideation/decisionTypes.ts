import type { BrainstormingCommentsState } from "@modules/ideation/commentTypes";
/** An editor who can be made responsible; the board's canvas reads decisions too. */
export interface DecisionMember {
  id: number;
  display_name: string;
  avatar_url: string | null;
}
export type DecisionSourceType = "idea" | "group";
export type DecisionStatus = "proposed" | "accepted" | "withdrawn" | "superseded";
export type DecisionVerb = "create" | "change" | "test" | "keep" | "discard";
export type DecisionTargetType = "sheet" | "flow" | "scene";
export type ApplicationState = "not_applied" | "partially_applied" | "applied" | "no_change_needed";
export type DecisionOperation =
  | "propose"
  | "revise"
  | "accept"
  | "register"
  | "withdraw"
  | "supersede";

export interface DecisionSourceIdentity {
  type: DecisionSourceType;
  id: number | null;
  identity: string;
}
export interface DecisionSource extends DecisionSourceIdentity {
  version: number;
  title: string;
  preview: string;
  authorName?: string | null;
  roundNumber?: number | null;
  state?: string | null;
  available: boolean;
  changed?: boolean;
  currentVersion?: number | null;
}
export interface DecisionDeclaration {
  state: ApplicationState;
  note: string | null;
  actorName: string | null;
  at: string;
}
export interface DecisionTarget {
  key: string;
  type: DecisionTargetType;
  id: number | null;
  name: string;
  isNew: boolean;
  available: boolean;
  /** Its editor, when the reader can open it. */
  href?: string | null;
  application: DecisionDeclaration | null;
}
export interface DecisionNextAction {
  text: string;
  ownerId: number | null;
  ownerName: string | null;
}
export interface DecisionRound {
  number: number;
  prompt: string | null;
}
export interface DecisionLink {
  id: number;
  title: string;
}
export interface DecisionRevision {
  revision: number;
  operation: DecisionOperation;
  verb: DecisionVerb;
  title: string;
  conclusion: string;
  reason: string | null;
  responsibleId: number | null;
  responsibleName: string | null;
  actorName: string | null;
  nextAction: DecisionNextAction | null;
  round: DecisionRound | null;
  replacesId: number | null;
  recordedAt: string;
  sources: DecisionSource[];
  targets: DecisionTarget[];
}
export interface DecisionApplication {
  targets: DecisionTarget[];
  decision: DecisionDeclaration | null;
  pending: number;
  total: number;
}
export interface DecisionRecord {
  id: number;
  sessionId?: number;
  version: number;
  status: DecisionStatus;
  proposal: DecisionRevision;
  accepted: DecisionRevision | null;
  application: DecisionApplication | null;
  proposerName: string | null;
  withdrawnByName: string | null;
  replaces: DecisionLink | null;
  supersedes: DecisionLink | null;
  supersededBy: DecisionLink | null;
  canAccept: boolean;
  canRevise: boolean;
  canAssign: boolean;
  canWithdraw: boolean;
  canDeclare: boolean;
  tasks: DecisionTask[];
  canLinkTasks: boolean;
  canEditTasks: boolean;
  canUnlinkTasks: boolean;
  updatedAt: string;
}
/** A task in an external tracker, linked by hand. Storyarn never reads it. */
export interface DecisionTask {
  key: string;
  kind: "manual";
  url: string;
  title: string | null;
  linkedByName: string | null;
  linkedAt: string;
}
export type TaskOperation = "link" | "edit" | "unlink";
/** What a decision notification attaches: the decision as its reader sees it now. */
export interface DecisionNoticeData {
  decision: DecisionRecord;
  /** The content to apply, or the one the actor marked applied. */
  target: string | null;
  action: { kind: "open" | "apply"; href: string };
  sessionName: string | null;
}
export interface DecisionHistoryEntry {
  kind: "record" | "application" | "task";
  id: string;
  operation: DecisionOperation | "registered" | ApplicationState | TaskOperation;
  actorName: string | null;
  responsibleName?: string | null;
  title?: string;
  targetName?: string | null;
  targetType?: DecisionTargetType | null;
  url?: string | null;
  text: string | null;
  at: string;
}
export interface DecisionTargetOption {
  type: DecisionTargetType;
  id: number;
  name: string;
  relation?: string;
}
export interface DecisionTargetInput {
  type: DecisionTargetType;
  id: number | null;
  label?: string;
}
export interface DecisionPrefill {
  title: string;
  conclusion: string;
  fromGroup: string;
}
export interface DecisionDraftInput {
  title: string;
  conclusion: string;
  reason: string | null;
  verb: DecisionVerb;
  targets: DecisionTargetInput[];
  next_action: string | null;
  next_action_owner_id: number | null;
  replaces_id: number | null;
  owner_id: number;
  register: boolean;
  revision?: number;
}
/**
 * The board's comment state while it holds the shown decision's conversation,
 * and the messages of every decision's open discussions, keyed by decision id.
 */
export interface DecisionDiscussionState {
  state: BrainstormingCommentsState | null;
  counts: Record<string, number>;
}
/** A decision brought to the content it affects, under the editor header. */
export interface DecisionBannerState {
  decision: DecisionRecord;
  targetKey: string;
  sessionTitle: string;
  sessionUrl: string;
  marked: { state: Exclude<ApplicationState, "not_applied"> } | null;
  error: string | null;
}
export interface DecisionsPanelState {
  open: boolean;
  context: string;
  mode: "list" | "create" | "detail" | "revise";
  items: DecisionRecord[];
  selected: DecisionRecord | null;
  history: DecisionHistoryEntry[];
  sources: DecisionSource[];
  sourceResults: DecisionSource[];
  sourceNextCursor: number | null;
  searched: boolean;
  targetSuggestions: DecisionTargetOption[];
  targetResults: DecisionTargetOption[];
  prefill: DecisionPrefill | null;
  members: DecisionMember[];
  defaultOwnerId: number | null;
  viewerId: number | null;
  rounds: DecisionRound[];
  canPropose: boolean;
  error: string | null;
}
