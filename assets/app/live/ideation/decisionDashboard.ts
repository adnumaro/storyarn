import { orderDecisions, primaryStatus, targetState } from "./decisionStatus";
import type { DecisionRecord, DecisionTarget, DecisionTargetType } from "./decisionTypes";

export type StatusFilter = "all" | "proposed" | "accepted" | "retired";
export type ApplicationFilter = "all" | "toApply" | "applied" | "noChange";

export interface DecisionSessionGroup {
  id: number;
  title: string;
  status: "open" | "archived";
  decisions: DecisionRecord[];
}
export interface DashboardDecision {
  decision: DecisionRecord;
  sessionId: number;
  sessionTitle: string;
}
export interface TargetGroup {
  key: string;
  type: DecisionTargetType | null;
  name: string | null;
  items: DashboardDecision[];
  toApply: number;
}

/** "3 decisions · 1 waiting for you · 1 to apply" for a session row. */
export function sessionSummary(decisions: DecisionRecord[]) {
  const kinds = decisions.map((decision) => primaryStatus(decision).kind);
  return {
    total: decisions.length,
    waiting: kinds.filter((kind) => kind === "waitingForYou").length,
    toApply: kinds.filter((kind) => kind === "toApply").length,
  };
}

function matchesStatus(decision: DecisionRecord, filter: StatusFilter) {
  if (filter === "all") return true;
  if (filter === "retired")
    return decision.status === "withdrawn" || decision.status === "superseded";
  return decision.status === filter;
}

function matchesApplication(decision: DecisionRecord, filter: ApplicationFilter) {
  if (filter === "all") return true;
  const application = decision.application;
  if (!application || decision.status !== "accepted") return false;
  const states = application.targets.map(targetState);
  if (filter === "toApply") return application.pending > 0;
  if (filter === "applied") return application.pending === 0 && states.includes("applied");
  return (
    application.decision?.state === "no_change_needed" ||
    (states.length > 0 && states.every((state) => state === "no_change_needed"))
  );
}

/**
 * The project's decisions in the order to act on them: waiting for the reader,
 * still to apply, proposals, done; retired ones apart.
 */
export function dashboardDecisions(
  groups: DecisionSessionGroup[],
  status: StatusFilter,
  application: ApplicationFilter,
) {
  const sessions = new Map<number, DecisionSessionGroup>();
  for (const group of groups)
    for (const decision of group.decisions) sessions.set(decision.id, group);
  const matching = groups
    .flatMap((group) => group.decisions)
    .filter(
      (decision) => matchesStatus(decision, status) && matchesApplication(decision, application),
    );
  const { live, retired } = orderDecisions(matching);
  const item = (decision: DecisionRecord): DashboardDecision => {
    const session = sessions.get(decision.id);
    return { decision, sessionId: session?.id ?? 0, sessionTitle: session?.title ?? "" };
  };
  return { live: live.map(item), retired: retired.map(item) };
}

function targetKey(target: DecisionTarget | null) {
  return target ? `${target.type}:${target.id ?? target.name}` : "none";
}

// Whether this content still waits for the decision in force.
function pendingHere(decision: DecisionRecord, target: DecisionTarget | null) {
  if (!target || decision.status !== "accepted") return false;
  const declared = decision.application?.targets.find((entry) => entry.key === target.key);
  return (
    declared !== undefined && ["not_applied", "partially_applied"].includes(targetState(declared))
  );
}

function emptyGroup(key: string, target: DecisionTarget | null): TargetGroup {
  return { key, type: target?.type ?? null, name: target?.name ?? null, items: [], toApply: 0 };
}

// Named content by name; decisions without affected content last.
function compareGroups(a: TargetGroup, b: TargetGroup) {
  if (a.type === null) return 1;
  if (b.type === null) return -1;
  return (a.name ?? "").localeCompare(b.name ?? "");
}

/**
 * The same decisions under each content they affect. A decision naming two
 * items appears under both; one naming nothing sits in its own group.
 */
export function groupByTarget(items: DashboardDecision[]): TargetGroup[] {
  const groups = new Map<string, TargetGroup>();
  for (const item of items) {
    const targets = (item.decision.accepted ?? item.decision.proposal).targets;
    for (const target of targets.length ? targets : [null]) {
      const key = targetKey(target);
      const group = groups.get(key) ?? emptyGroup(key, target);
      group.items.push(item);
      if (pendingHere(item.decision, target)) group.toApply += 1;
      groups.set(key, group);
    }
  }
  return [...groups.values()].sort(compareGroups);
}
