import type {
  ApplicationState,
  DecisionRecord,
  DecisionRevision,
  DecisionRound,
  DecisionSource,
  DecisionTarget,
} from "./decisionTypes";

export type PrimaryStatus =
  | { kind: "toApply"; pending: number; total: number }
  | { kind: "accepted" }
  | { kind: "waitingForYou" }
  | { kind: "proposal"; waitingFor: string | null }
  | { kind: "withdrawn"; by: string | null }
  | { kind: "superseded" };

/** An agreement in force stays the face of a decision while a revision waits. */
export function shownRevision(decision: DecisionRecord): DecisionRevision {
  return decision.accepted && decision.status !== "withdrawn"
    ? decision.accepted
    : decision.proposal;
}

export function revisionPending(decision: DecisionRecord) {
  return decision.status === "proposed" && decision.accepted !== null;
}

export function retired(decision: DecisionRecord) {
  return decision.status === "withdrawn" || decision.status === "superseded";
}

/** Exactly one primary status; "to apply" already means accepted. */
export function primaryStatus(decision: DecisionRecord): PrimaryStatus {
  if (decision.status === "withdrawn") return { kind: "withdrawn", by: decision.withdrawnByName };
  if (decision.status === "superseded") return { kind: "superseded" };
  if (decision.accepted) {
    const application = decision.application;
    return application && application.pending > 0
      ? { kind: "toApply", pending: application.pending, total: application.total }
      : { kind: "accepted" };
  }
  if (decision.canAccept) return { kind: "waitingForYou" };
  return { kind: "proposal", waitingFor: decision.proposal.responsibleName };
}

export function hasUnavailableSource(decision: DecisionRecord) {
  return (
    decision.status === "proposed" && decision.proposal.sources.some((source) => !source.available)
  );
}

const rank = { waitingForYou: 0, toApply: 1, proposal: 2, accepted: 3 } as const;

/** Waiting for you, then still to apply, then proposals, then done; retired folds away. */
export function orderDecisions(items: DecisionRecord[]) {
  const live = items
    .filter((item) => !retired(item))
    .map((item, index) => ({ item, index, kind: primaryStatus(item).kind }))
    .sort(
      (a, b) =>
        rank[a.kind as keyof typeof rank] - rank[b.kind as keyof typeof rank] || a.index - b.index,
    )
    .map(({ item }) => item);
  return { live, retired: items.filter(retired) };
}

/** Decisions whose agreement is still in force can be replaced. */
export function replaceable(items: DecisionRecord[], except: number | null) {
  return items.filter(
    (item) =>
      item.id !== except &&
      item.accepted !== null &&
      (item.status === "accepted" || item.status === "proposed"),
  );
}

export function roundTag(round: DecisionRound | null, roundCount: number) {
  return round && roundCount > 1 ? `R${round.number}` : null;
}

export function excerpt(text: string, max = 60) {
  const clean = text.replace(/\s+/g, " ").trim();
  return clean.length > max ? `${clean.slice(0, max).trimEnd()}…` : clean;
}

export function sourceLabel(source: DecisionSource) {
  return source.title.trim() || excerpt(source.preview);
}

/** The longest title a decision record accepts. */
const TITLE_MAX = 160;

/**
 * The first sentence of the conclusion names the decision until someone edits
 * it. The title is stored whole and never carries an ellipsis: screens cut a
 * long title, the record does not. A first sentence longer than any title
 * allows keeps its whole words up to that limit.
 */
export function deriveTitle(conclusion: string) {
  const first = (conclusion.trim().split(/(?<=[.!?])\s|\n/)[0] ?? "")
    .replace(/[.!?]+$/, "")
    .replace(/\s+/g, " ")
    .trim();
  if (first.length <= TITLE_MAX) return first;
  const words = first.slice(0, TITLE_MAX + 1).split(" ");
  return words.length > 1 ? words.slice(0, -1).join(" ") : first.slice(0, TITLE_MAX);
}

export function targetState(target: DecisionTarget): ApplicationState {
  return target.application?.state ?? "not_applied";
}

const stateRank: Record<ApplicationState, number> = {
  not_applied: 0,
  partially_applied: 1,
  applied: 2,
  no_change_needed: 2,
};

/** On an accepted decision what is still to apply comes first. */
export function orderTargets(targets: DecisionTarget[], accepted: boolean) {
  if (!accepted) return targets;
  return targets
    .map((target, index) => ({ target, index }))
    .sort(
      (a, b) =>
        stateRank[targetState(a.target)] - stateRank[targetState(b.target)] || a.index - b.index,
    )
    .map(({ target }) => target);
}

/** Three chips fit; beyond that two show and the rest fold into "+n more". */
export function splitTargets(targets: DecisionTarget[]) {
  const cut = targets.length > 3 ? 2 : targets.length;
  return { visible: targets.slice(0, cut), hidden: targets.slice(cut) };
}
