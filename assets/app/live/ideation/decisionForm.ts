import { deriveTitle } from "./decisionStatus";
import type {
  DecisionDraftInput,
  DecisionLink,
  DecisionMember,
  DecisionNextAction,
  DecisionPrefill,
  DecisionRevision,
  DecisionRound,
  DecisionSource,
  DecisionTarget,
  DecisionTargetInput,
  DecisionTargetOption,
  DecisionVerb,
} from "./decisionTypes";

export interface AffectedChip extends DecisionTargetInput {
  name: string;
  available: boolean;
}

/** Everything the form offers besides the proposal being written. */
export interface DecisionFormOptions {
  members: DecisionMember[];
  defaultOwnerId: number | null;
  viewerId: number | null;
  prefill: DecisionPrefill | null;
  rounds: DecisionRound[];
  suggestions: DecisionTargetOption[];
  results: DecisionTargetOption[];
  replaceable: DecisionLink[];
}

export interface DecisionFormFields {
  conclusion: string;
  verb: DecisionVerb | null;
  affected: AffectedChip[];
  reason: string;
  owner: string;
  nextOpen: boolean;
  nextText: string;
  nextOwner: string;
  replacesOpen: boolean;
  replaces: string;
  title: string;
  titleTouched: boolean;
}

function nextActionFields(next: DecisionNextAction | null) {
  if (!next) return { nextOpen: false, nextText: "", nextOwner: "none" };
  return { nextOpen: true, nextText: next.text, nextOwner: String(next.ownerId ?? "none") };
}

function replacesFields(id: number | null) {
  return id === null
    ? { replacesOpen: false, replaces: "none" }
    : { replacesOpen: true, replaces: String(id) };
}

function chip(target: DecisionTarget): AffectedChip {
  return target.isNew
    ? { type: target.type, id: null, label: target.name, name: target.name, available: true }
    : { type: target.type, id: target.id, name: target.name, available: target.available };
}

/** A revision starts from the proposal or agreement it revises. */
export function draftFields(draft: DecisionRevision): DecisionFormFields {
  return {
    conclusion: draft.conclusion,
    verb: draft.verb,
    affected: draft.targets.map(chip),
    reason: draft.reason ?? "",
    owner: String(draft.responsibleId ?? ""),
    ...nextActionFields(draft.nextAction),
    ...replacesFields(draft.replacesId),
    title: draft.title,
    titleTouched: draft.title !== deriveTitle(draft.conclusion),
  };
}

/** A new proposal starts empty, or from a group's own words. */
export function newFields(prefill: DecisionPrefill | null, owner: string): DecisionFormFields {
  const conclusion = prefill?.conclusion ?? "";
  const title = prefill?.title ?? deriveTitle(conclusion);
  return {
    conclusion,
    verb: null,
    affected: [],
    reason: "",
    owner,
    ...nextActionFields(null),
    ...replacesFields(null),
    title,
    titleTouched: title !== deriveTitle(conclusion),
  };
}

/** The proposer is responsible most of the time, so registering is the default. */
export function defaultOwner(options: DecisionFormOptions) {
  const proposer = options.members.some((person) => person.id === options.viewerId)
    ? options.viewerId
    : null;
  return String(proposer ?? options.defaultOwnerId ?? "");
}

/** The newest round among the sources gives the proposal its context line. */
export function sourceRound(sources: DecisionSource[], rounds: DecisionRound[]) {
  const numbers = sources
    .map((source) => source.roundNumber)
    .filter((value): value is number => typeof value === "number");
  if (!numbers.length) return null;
  const number = Math.max(...numbers);
  return { number, prompt: rounds.find((item) => item.number === number)?.prompt ?? null };
}

export function sourcesReady(sources: DecisionSource[]) {
  return sources.length > 0 && sources.length <= 20 && sources.every((source) => source.available);
}

export function fieldsReady(form: DecisionFormFields) {
  return (
    !!form.conclusion.trim() &&
    !!form.title.trim() &&
    form.verb !== null &&
    Number(form.owner) > 0 &&
    form.affected.every((item) => item.available)
  );
}

function targetInput(item: AffectedChip): DecisionTargetInput {
  return item.id === null
    ? { type: item.type, id: null, label: item.label ?? item.name }
    : { type: item.type, id: item.id };
}

function nextActionInput(form: DecisionFormFields) {
  const text = form.nextOpen ? form.nextText.trim() : "";
  if (!text) return { next_action: null, next_action_owner_id: null };
  return {
    next_action: text,
    next_action_owner_id: form.nextOwner === "none" ? null : Number(form.nextOwner),
  };
}

export function draftInput(
  form: DecisionFormFields & { verb: DecisionVerb },
  register: boolean,
  revision: number | null,
): DecisionDraftInput {
  return {
    title: form.title.trim(),
    conclusion: form.conclusion.trim(),
    reason: form.reason.trim() || null,
    verb: form.verb,
    targets: form.affected.map(targetInput),
    ...nextActionInput(form),
    replaces_id: form.replacesOpen && form.replaces !== "none" ? Number(form.replaces) : null,
    owner_id: Number(form.owner),
    register,
    ...(revision !== null ? { revision } : {}),
  };
}
