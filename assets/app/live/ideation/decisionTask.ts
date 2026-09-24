import type { DecisionRecord, DecisionRevision, DecisionTarget } from "./decisionTypes";

export type TaskPart = "conclusion" | "reason" | "targets" | "nextAction" | "sources";
type Translate = (key: string, values?: Record<string, unknown>) => string;
interface SummaryContext {
  t: Translate;
  /** Where the reader is, so links to Storyarn work once pasted elsewhere. */
  origin: string;
  decisionUrl: string;
}

const blank = (char: string) => /\s/u.test(char) || char < " " || char === "\u007f";

/** The rule the server applies: a web address without credentials. */
export function validTaskUrl(value: string): boolean {
  const url = value.trim();
  if (!url || url.length > 2048 || [...url].some(blank)) return false;
  try {
    const parsed = new URL(url);
    return (
      (parsed.protocol === "http:" || parsed.protocol === "https:") &&
      parsed.hostname !== "" &&
      !parsed.username &&
      !parsed.password
    );
  } catch {
    return false;
  }
}

export function taskHost(url: string): string {
  try {
    return new URL(url).host;
  } catch {
    return url;
  }
}

/** A task is prepared from the agreement in force, or the proposal before one exists. */
export function taskBasis(decision: DecisionRecord): DecisionRevision {
  return decision.accepted ?? decision.proposal;
}

/** The parts this decision has something to say about, in reading order. */
export function taskParts(basis: DecisionRevision): TaskPart[] {
  const present: Record<TaskPart, boolean> = {
    conclusion: true,
    reason: !!basis.reason,
    targets: basis.targets.length > 0,
    nextAction: !!basis.nextAction,
    sources: basis.sources.some((source) => source.available),
  };
  return (Object.keys(present) as TaskPart[]).filter((part) => present[part]);
}

function targetLine(target: DecisionTarget, { t, origin }: SummaryContext) {
  const type = t(`brainstormingDecisions.targetTypes.${target.type}`);
  const label = target.isNew
    ? `${target.name} (${type}, ${t("brainstormingDecisions.targetNew")})`
    : `${target.name} (${type})`;
  return target.href ? `- ${label}: ${new URL(target.href, origin).toString()}` : `- ${label}`;
}

const sections: Record<TaskPart, (basis: DecisionRevision, context: SummaryContext) => string> = {
  conclusion: (basis, { t }) => `${t("brainstormingDecisions.conclusion")}\n${basis.conclusion}`,
  reason: (basis, { t }) => `${t("brainstormingDecisions.reason")}\n${basis.reason ?? ""}`,
  targets: (basis, context) =>
    [
      context.t("brainstormingDecisions.tasks.summary.affected"),
      ...basis.targets.map((target) => targetLine(target, context)),
    ].join("\n"),
  nextAction: (basis, { t }) => {
    const action = basis.nextAction;
    const owner = action?.ownerName ? ` (${action.ownerName})` : "";
    return `${t("brainstormingDecisions.nextAction")}\n${action?.text ?? ""}${owner}`;
  },
  sources: (basis, { t }) =>
    [
      t("brainstormingDecisions.tasks.summary.sources"),
      ...basis.sources
        .filter((source) => source.available)
        .map((source) => `- ${source.title || source.preview}`),
    ].join("\n"),
};

/**
 * The text a person pastes into their tracker. Only the chosen parts of what
 * the reader already sees go in: never the discussion, drafts or hidden sources.
 */
export function taskSummary(
  decision: DecisionRecord,
  chosen: TaskPart[],
  context: SummaryContext,
): string {
  const basis = taskBasis(decision);
  const status = decision.accepted
    ? context.t("brainstormingDecisions.tasks.summary.agreed")
    : context.t("brainstormingDecisions.tasks.summary.proposed");
  const heading = `${basis.title}\n${context.t(`brainstormingDecisions.verbs.${basis.verb}`)} · ${status}`;
  const body = taskParts(basis)
    .filter((part) => chosen.includes(part))
    .map((part) => sections[part](basis, context));
  const link = `${context.t("brainstormingDecisions.tasks.summary.link")}: ${context.decisionUrl}`;
  return [heading, ...body, link].join("\n\n");
}
