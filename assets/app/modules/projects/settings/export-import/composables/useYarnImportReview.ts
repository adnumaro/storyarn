import { computed, onUnmounted, ref, watch, type ComputedRef, type Ref } from "vue";
import { useLive } from "@shared/composables/useLive";
import type {
  ImportState,
  SpeakerActionOption,
  YarnImportIssueSummary,
  YarnImportReview,
  YarnImportReviewDraft,
  YarnImportReviewResolution,
  YarnReviewDecision,
  YarnSpeakerAction,
  YarnSpeakerAliasReview,
  YarnSpeakerConfidence,
  YarnSpeakerDecision,
  YarnSpeakerDirectAction,
} from "@modules/projects/settings/export-import/types";

/**
 * The Yarn prefix review: what the server proposed, what the user chose, and
 * whether that selection is complete enough to import.
 *
 * Everything the server sends is re-validated here before it is trusted. A
 * review that does not add up structurally blocks the import rather than
 * importing on a partial understanding of who is speaking.
 */

const REVIEW_SAVE_DEBOUNCE_MS = 500;
// Validate resolves the whole review server-side (plan-scale read-modify-write
// plus a confirmation hash), so this is deliberately looser than the
// single-row reconcile watchdog in useImportResume.
const OPERATION_WATCHDOG_MS = 10_000;

const SPEAKER_DIRECT_ACTIONS = new Set<YarnSpeakerDirectAction>([
  "create_sheet",
  "preserve_literal",
]);
const SPEAKER_ACTIONS = new Set<YarnSpeakerAction>([...SPEAKER_DIRECT_ACTIONS, "map_to_sheet"]);
const SPEAKER_CONFIDENCE_LEVELS = new Set<YarnSpeakerConfidence>(["high", "medium", "low"]);

export interface UseYarnImportReviewOptions {
  canImport: () => boolean;
  importState: () => ImportState;
}

export interface YarnReviewTransportError {
  operation: "save" | "validate" | "execute";
  reason: string;
}

export interface YarnImportReviewApi {
  review: ComputedRef<YarnImportReview | null>;
  decisions: ComputedRef<YarnSpeakerDecision[]>;
  aliases: ComputedRef<YarnSpeakerAliasReview[]>;
  acknowledged: Ref<boolean>;
  issueSummary: ComputedRef<YarnImportIssueSummary | null>;
  issueSummaryMalformed: ComputedRef<boolean>;
  hasCompatibilityWarnings: ComputedRef<boolean>;
  hasCompatibilityErrors: ComputedRef<boolean>;
  structurallyComplete: ComputedRef<boolean>;
  allDecisionsSelected: ComputedRef<boolean>;
  requiresAcknowledgement: ComputedRef<boolean>;
  matchesResolution: ComputedRef<boolean>;
  isTruncated: ComputedRef<boolean>;
  canValidate: ComputedRef<boolean>;
  canExecute: ComputedRef<boolean>;
  sheetSpeakerCount: ComputedRef<number | undefined>;
  preservedChannelCount: ComputedRef<number | undefined>;
  mappedAliasCount: ComputedRef<number>;
  pendingOperation: Ref<"validate" | "execute" | null>;
  transportError: Ref<YarnReviewTransportError | null>;
  selectedAction: (speaker: string) => YarnSpeakerAction | undefined;
  selectedActionValue: (speaker: string) => string | undefined;
  actionOptions: (decision: YarnSpeakerDecision) => SpeakerActionOption[];
  setAction: (speaker: string, action: unknown) => void;
  setAcknowledged: (value: boolean | "indeterminate") => void;
  aliasCanMap: (alias: YarnSpeakerAliasReview) => boolean;
  validate: () => void;
  execute: () => void;
  clearSaveTimer: () => void;
}

export function nonNegativeSafeInteger(value: unknown): value is number {
  return Number.isSafeInteger(value) && Number(value) >= 0;
}

export function positiveSafeInteger(value: unknown): value is number {
  return Number.isSafeInteger(value) && Number(value) > 0;
}

export function nonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

export function parseIssueCounts(value: unknown): Record<string, number> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;

  const counts = value as Record<string, unknown>;
  const entries = Object.entries(counts);
  if (!entries.every(([code]) => /^[a-z0-9_]+$/.test(code))) return null;
  if (!entries.every(([, count]) => positiveSafeInteger(count))) return null;
  return Object.fromEntries(entries) as Record<string, number>;
}

export function parseIssueSummary(value: unknown): YarnImportIssueSummary | null {
  if (!value || typeof value !== "object") return null;

  const summary = value as Partial<YarnImportIssueSummary>;
  if (!validIssueSummaryFields(summary)) return null;

  const countsByCode = parseIssueCounts(summary.counts_by_code);
  if (!countsByCode) return null;

  const countedIssues = Object.values(countsByCode).reduce((total, count) => total + count, 0);
  const countsMatch = [
    summary.warning_count + summary.error_count === summary.issue_count,
    countedIssues === summary.issue_count,
  ].every(Boolean);
  if (!countsMatch) return null;

  return {
    warning_count: summary.warning_count,
    error_count: summary.error_count,
    issue_count: summary.issue_count,
    issues_truncated: summary.issues_truncated,
    counts_by_code: countsByCode,
  };
}

function validIssueSummaryFields(
  summary: Partial<YarnImportIssueSummary>,
): summary is YarnImportIssueSummary {
  return [
    nonNegativeSafeInteger(summary.warning_count),
    nonNegativeSafeInteger(summary.error_count),
    nonNegativeSafeInteger(summary.issue_count),
    typeof summary.issues_truncated === "boolean",
    Boolean(summary.counts_by_code),
    typeof summary.counts_by_code === "object",
    !Array.isArray(summary.counts_by_code),
  ].every(Boolean);
}

function validReasons(value: unknown): value is string[] {
  return Array.isArray(value) && value.length > 0 && value.every(nonEmptyString);
}

function validAllowedActions(value: unknown): value is YarnSpeakerAction[] {
  return (
    Array.isArray(value) &&
    value.length > 0 &&
    new Set(value).size === value.length &&
    value.every((action) => SPEAKER_ACTIONS.has(action as YarnSpeakerAction))
  );
}

function isSpeakerDecision(value: unknown): value is YarnSpeakerDecision {
  if (!value || typeof value !== "object") return false;

  const decision = value as Partial<YarnSpeakerDecision>;
  return [
    nonEmptyString(decision.speaker),
    positiveSafeInteger(decision.occurrences),
    SPEAKER_DIRECT_ACTIONS.has(decision.suggested_action as YarnSpeakerDirectAction),
    validAllowedActions(decision.allowed_actions),
    Array.isArray(decision.allowed_actions) &&
      decision.allowed_actions.includes(decision.suggested_action as YarnSpeakerAction),
    SPEAKER_CONFIDENCE_LEVELS.has(decision.confidence as YarnSpeakerConfidence),
    validReasons(decision.reasons),
  ].every(Boolean);
}

function isSpeakerAliasReview(value: unknown): value is YarnSpeakerAliasReview {
  if (!value || typeof value !== "object") return false;

  const alias = value as Partial<YarnSpeakerAliasReview>;
  const fieldsAreValid = [
    nonEmptyString(alias.left),
    positiveSafeInteger(alias.left_occurrences),
    nonEmptyString(alias.right),
    positiveSafeInteger(alias.right_occurrences),
    nonEmptyString(alias.more_frequent),
    nonEmptyString(alias.less_frequent),
    nonEmptyString(alias.evidence),
    alias.decision === "review",
  ].every(Boolean);

  if (!fieldsAreValid) return false;

  const names = new Set([alias.left, alias.right]);
  return (
    names.size === 2 &&
    new Set([alias.more_frequent, alias.less_frequent]).size === 2 &&
    names.has(alias.more_frequent as string) &&
    names.has(alias.less_frequent as string)
  );
}

function sameIssueCounts(left: Record<string, number>, right: Record<string, number>): boolean {
  const leftEntries = Object.entries(left).sort(([leftCode], [rightCode]) =>
    leftCode.localeCompare(rightCode),
  );
  const rightEntries = Object.entries(right).sort(([leftCode], [rightCode]) =>
    leftCode.localeCompare(rightCode),
  );

  return JSON.stringify(leftEntries) === JSON.stringify(rightEntries);
}

function validReviewScalars(review: YarnImportReview) {
  const compatibilityCounts = parseIssueCounts(review.compatibility_warning_counts_by_code);

  return [
    nonNegativeSafeInteger(review.variable_count),
    nonNegativeSafeInteger(review.sheet_speaker_count),
    nonNegativeSafeInteger(review.preserved_channel_count),
    nonNegativeSafeInteger(review.speaker_decision_count),
    nonNegativeSafeInteger(review.possible_speaker_alias_count),
    nonNegativeSafeInteger(review.compatibility_warning_count),
    compatibilityCounts !== null,
    compatibilityCounts !== null &&
      Object.values(compatibilityCounts).reduce((total, count) => total + count, 0) ===
        review.compatibility_warning_count,
    typeof review.speaker_decisions_truncated === "boolean",
    typeof review.possible_speaker_aliases_truncated === "boolean",
    typeof review.requires_acknowledgement === "boolean",
  ].every(Boolean);
}

function suggestedReviewCountsMatch(
  review: YarnImportReview,
  decisions: YarnSpeakerDecision[],
): boolean {
  const suggestedSheetCount = decisions.filter(
    (decision) => decision.suggested_action === "create_sheet",
  ).length;
  const suggestedPreservedCount = decisions.filter(
    (decision) => decision.suggested_action === "preserve_literal",
  ).length;

  return (
    review.sheet_speaker_count + review.preserved_channel_count === review.speaker_decision_count &&
    suggestedSheetCount === review.sheet_speaker_count &&
    suggestedPreservedCount === review.preserved_channel_count
  );
}

function compatibilityReviewMatchesSummary(
  review: YarnImportReview,
  summary: YarnImportIssueSummary,
): boolean {
  return (
    review.compatibility_warning_count === summary.warning_count &&
    sameIssueCounts(review.compatibility_warning_counts_by_code, summary.counts_by_code)
  );
}

function acknowledgementContractMatches(review: YarnImportReview): boolean {
  const expected =
    review.speaker_decision_count > 0 ||
    review.possible_speaker_alias_count > 0 ||
    review.compatibility_warning_count > 0;

  return review.requires_acknowledgement === expected;
}

function sameReviewDecision(
  left: YarnReviewDecision | undefined,
  right: YarnReviewDecision | undefined,
) {
  if (!left || !right) return left === right;

  return (
    left.speaker === right.speaker &&
    left.action === right.action &&
    (left.target_speaker ?? null) === (right.target_speaker ?? null)
  );
}

function canonicalReviewDecisions(decisions: YarnReviewDecision[]) {
  return decisions
    .map((decision) => [decision.speaker, decision.action, decision.target_speaker ?? null])
    .sort(([leftSpeaker], [rightSpeaker]) =>
      String(leftSpeaker).localeCompare(String(rightSpeaker)),
    );
}

function sameReviewDecisions(left: YarnReviewDecision[], right: YarnReviewDecision[]) {
  return (
    JSON.stringify(canonicalReviewDecisions(left)) ===
    JSON.stringify(canonicalReviewDecisions(right))
  );
}

function aliasMappingValue(targetSpeaker: string) {
  return `map_to_sheet:${targetSpeaker}`;
}

export function useYarnImportReview(options: UseYarnImportReviewOptions): YarnImportReviewApi {
  const { canImport, importState } = options;
  const live = useLive();

  const acknowledged = ref(false);
  const selectedDecisions = ref(new Map<string, YarnReviewDecision>());
  let saveTimer: ReturnType<typeof setTimeout> | null = null;

  const review = computed<YarnImportReview | null>(() => {
    const value = importState().preview?.import_review;
    return value && typeof value === "object" ? value : null;
  });

  const issueSummary = computed(() => parseIssueSummary(importState().preview?.issue_summary));

  const issueSummaryMalformed = computed(() => {
    const raw = importState().preview?.issue_summary;
    return raw !== null && raw !== undefined && issueSummary.value === null;
  });

  const hasCompatibilityWarnings = computed(() => (issueSummary.value?.warning_count ?? 0) > 0);

  const hasCompatibilityErrors = computed(
    () => issueSummaryMalformed.value || (issueSummary.value?.error_count ?? 0) > 0,
  );

  const rawDecisions = computed<unknown[]>(() => {
    const value = review.value?.speaker_decisions;
    return Array.isArray(value) ? value : [];
  });

  const decisions = computed<YarnSpeakerDecision[]>(() =>
    rawDecisions.value.filter(isSpeakerDecision),
  );

  const rawAliases = computed<unknown[]>(() => {
    const value = review.value?.possible_speaker_aliases;
    return Array.isArray(value) ? value : [];
  });

  const aliases = computed<YarnSpeakerAliasReview[]>(() =>
    rawAliases.value.filter(isSpeakerAliasReview),
  );

  function aliasTargetsForSpeaker(speaker: string) {
    return [
      ...new Set(
        aliases.value
          .filter((alias) => alias.less_frequent === speaker)
          .map((alias) => alias.more_frequent),
      ),
    ];
  }

  function selectedAction(speaker: string) {
    return selectedDecisions.value.get(speaker)?.action;
  }

  function selectedActionValue(speaker: string) {
    const decision = selectedDecisions.value.get(speaker);
    if (!decision) return undefined;

    return decision.action === "map_to_sheet" && decision.target_speaker
      ? aliasMappingValue(decision.target_speaker)
      : decision.action;
  }

  function buildDecisions(): YarnReviewDecision[] {
    return decisions.value.flatMap((entry) => {
      const decision = selectedDecisions.value.get(entry.speaker);
      return decision ? [{ ...decision }] : [];
    });
  }

  function actionOptions(decision: YarnSpeakerDecision): SpeakerActionOption[] {
    const preserveLiteralOption: SpeakerActionOption = {
      value: "preserve_literal",
      action: "preserve_literal",
      labelKey: "project_settings.import.review_preserve_literal",
      descriptionKey: "project_settings.import.review_preserve_literal_description",
      accent: "warning",
      suggested: decision.suggested_action === "preserve_literal",
    };

    const options: SpeakerActionOption[] = [];

    if (decision.allowed_actions.includes("create_sheet")) {
      options.push({
        value: "create_sheet",
        action: "create_sheet",
        labelKey: "project_settings.import.review_create_sheet",
        descriptionKey: "project_settings.import.review_create_sheet_description",
        accent: "primary",
        suggested: decision.suggested_action === "create_sheet",
      });
    }

    if (decision.allowed_actions.includes("preserve_literal")) {
      options.push(preserveLiteralOption);
    }

    if (decision.allowed_actions.includes("map_to_sheet")) {
      for (const targetSpeaker of aliasTargetsForSpeaker(decision.speaker)) {
        if (selectedAction(targetSpeaker) !== "create_sheet") continue;

        options.push({
          value: aliasMappingValue(targetSpeaker),
          action: "map_to_sheet",
          targetSpeaker,
          labelKey: "project_settings.import.review_map_to_sheet",
          descriptionKey: "project_settings.import.review_map_to_sheet_description",
          accent: "info",
          suggested: false,
        });
      }
    }

    return options;
  }

  function decisionIsCurrentlyValid(decision: YarnReviewDecision) {
    const entry = decisions.value.find((candidate) => candidate.speaker === decision.speaker);
    if (!entry) return false;

    if (SPEAKER_DIRECT_ACTIONS.has(decision.action as YarnSpeakerDirectAction)) {
      return (
        entry.allowed_actions.includes(decision.action) && decision.target_speaker === undefined
      );
    }

    return (
      decision.action === "map_to_sheet" &&
      entry.allowed_actions.includes("map_to_sheet") &&
      nonEmptyString(decision.target_speaker) &&
      aliasTargetsForSpeaker(decision.speaker).includes(decision.target_speaker) &&
      selectedAction(decision.target_speaker) === "create_sheet"
    );
  }

  function completeSpeakerReview(current: YarnImportReview) {
    const uniqueSpeakers = new Set(decisions.value.map((decision) => decision.speaker));

    return [
      Array.isArray(current.speaker_decisions),
      !current.speaker_decisions_truncated,
      current.speaker_decision_count === rawDecisions.value.length,
      decisions.value.length === rawDecisions.value.length,
      uniqueSpeakers.size === decisions.value.length,
    ].every(Boolean);
  }

  function completeAliasReview(current: YarnImportReview) {
    const reviewedSpeakers = new Set(decisions.value.map((decision) => decision.speaker));
    const uniquePairs = new Set(
      // NUL separator: a printable one would let ["a b", "c"] and ["a", "b c"]
      // collapse into the same key and pass the uniqueness check.
      aliases.value.map((alias) => [alias.left, alias.right].sort().join("\u0000")),
    );

    return [
      Array.isArray(current.possible_speaker_aliases),
      !current.possible_speaker_aliases_truncated,
      current.possible_speaker_alias_count === rawAliases.value.length,
      aliases.value.length === rawAliases.value.length,
      uniquePairs.size === aliases.value.length,
      aliases.value.every(
        (alias) => reviewedSpeakers.has(alias.left) && reviewedSpeakers.has(alias.right),
      ),
    ].every(Boolean);
  }

  const structurallyComplete = computed(() => {
    const current = review.value;
    const summary = issueSummary.value;
    if (!current || !summary) return false;

    return (
      validReviewScalars(current) &&
      completeSpeakerReview(current) &&
      completeAliasReview(current) &&
      suggestedReviewCountsMatch(current, decisions.value) &&
      compatibilityReviewMatchesSummary(current, summary) &&
      acknowledgementContractMatches(current)
    );
  });

  const allDecisionsSelected = computed(
    () =>
      structurallyComplete.value &&
      selectedDecisions.value.size === decisions.value.length &&
      buildDecisions().length === decisions.value.length &&
      buildDecisions().every(decisionIsCurrentlyValid),
  );

  const sheetSpeakerCount = computed(() =>
    structurallyComplete.value
      ? decisions.value.filter((decision) => selectedAction(decision.speaker) === "create_sheet")
          .length
      : review.value?.sheet_speaker_count,
  );

  const preservedChannelCount = computed(() =>
    structurallyComplete.value
      ? decisions.value.filter(
          (decision) => selectedAction(decision.speaker) === "preserve_literal",
        ).length
      : review.value?.preserved_channel_count,
  );

  const mappedAliasCount = computed(() =>
    structurallyComplete.value
      ? decisions.value.filter((decision) => selectedAction(decision.speaker) === "map_to_sheet")
          .length
      : 0,
  );

  const isTruncated = computed(
    () =>
      review.value?.speaker_decisions_truncated === true ||
      review.value?.possible_speaker_aliases_truncated === true,
  );

  const requiresAcknowledgement = computed(() => {
    const current = review.value;
    if (!structurallyComplete.value || !current) return true;

    return (
      current.requires_acknowledgement ||
      (preservedChannelCount.value ?? 0) > 0 ||
      current.possible_speaker_alias_count > 0 ||
      hasCompatibilityWarnings.value
    );
  });

  function parsePersistedAliasMapping(
    candidate: Partial<YarnReviewDecision>,
  ): YarnReviewDecision | null {
    const entry = decisions.value.find((decision) => decision.speaker === candidate.speaker);
    const validMapping = [
      candidate.action === "map_to_sheet",
      entry?.allowed_actions.includes("map_to_sheet") === true,
      nonEmptyString(candidate.speaker),
      nonEmptyString(candidate.target_speaker),
      aliasTargetsForSpeaker(candidate.speaker ?? "").includes(candidate.target_speaker ?? ""),
    ].every(Boolean);

    return validMapping
      ? {
          speaker: candidate.speaker!,
          action: "map_to_sheet",
          target_speaker: candidate.target_speaker!,
        }
      : null;
  }

  function parsePersistedDirectDecision(
    candidate: Partial<YarnReviewDecision>,
    entry: YarnSpeakerDecision,
  ): YarnReviewDecision | null {
    const action = candidate.action as YarnSpeakerDirectAction;

    if (!entry.allowed_actions.includes(action) || candidate.target_speaker !== undefined) {
      return null;
    }

    return { speaker: candidate.speaker!, action };
  }

  function parsePersistedDecision(
    value: unknown,
    reviewedSpeakers: Set<string>,
    parsed: Map<string, YarnReviewDecision>,
  ): YarnReviewDecision | null {
    if (!value || typeof value !== "object") return null;

    const candidate = value as Partial<YarnReviewDecision>;
    const speakerIsValid = [
      nonEmptyString(candidate.speaker),
      reviewedSpeakers.has(candidate.speaker ?? ""),
      !parsed.has(candidate.speaker ?? ""),
    ].every(Boolean);
    if (!speakerIsValid || !candidate.speaker) return null;

    const entry = decisions.value.find((decision) => decision.speaker === candidate.speaker);
    if (!entry) return null;

    if (SPEAKER_DIRECT_ACTIONS.has(candidate.action as YarnSpeakerDirectAction)) {
      return parsePersistedDirectDecision(candidate, entry);
    }

    return parsePersistedAliasMapping(candidate);
  }

  function persistedMappingTargetsAreValid(parsed: Map<string, YarnReviewDecision>) {
    return [...parsed.values()]
      .filter((decision) => decision.action === "map_to_sheet")
      .every((decision) => parsed.get(decision.target_speaker ?? "")?.action === "create_sheet");
  }

  function parsePersistedDecisions(values: unknown[], requireComplete: boolean) {
    const reviewedSpeakers = new Set(decisions.value.map((decision) => decision.speaker));
    const parsed = new Map<string, YarnReviewDecision>();

    for (const value of values) {
      const decision = parsePersistedDecision(value, reviewedSpeakers, parsed);
      if (!decision) return null;
      parsed.set(decision.speaker, decision);
    }

    if (requireComplete && parsed.size !== reviewedSpeakers.size) return null;
    if (!persistedMappingTargetsAreValid(parsed)) return null;

    return [...parsed.values()];
  }

  function parseSnapshot(
    value: unknown,
    expectedVersion: 1,
    requireComplete: false,
  ): YarnImportReviewDraft | null;
  function parseSnapshot(
    value: unknown,
    expectedVersion: 2,
    requireComplete: true,
  ): YarnImportReviewResolution | null;
  function parseSnapshot(
    value: unknown,
    expectedVersion: 1 | 2,
    requireComplete: boolean,
  ): YarnImportReviewDraft | YarnImportReviewResolution | null {
    if (!value || typeof value !== "object") return null;

    const snapshot = value as {
      version?: unknown;
      decisions?: unknown;
      decision_fingerprint?: unknown;
    };

    if (
      snapshot.version !== expectedVersion ||
      !Array.isArray(snapshot.decisions) ||
      !nonEmptyString(snapshot.decision_fingerprint)
    ) {
      return null;
    }

    const parsed = parsePersistedDecisions(snapshot.decisions, requireComplete);
    if (!parsed) return null;

    return {
      version: expectedVersion,
      decisions: parsed,
      decision_fingerprint: snapshot.decision_fingerprint,
    } as YarnImportReviewDraft | YarnImportReviewResolution;
  }

  const draft = computed(() => parseSnapshot(importState().preview?.import_review_draft, 1, false));

  const resolution = computed(() =>
    parseSnapshot(importState().preview?.import_review_resolution, 2, true),
  );

  const matchesResolution = computed(() => {
    const current = resolution.value;

    return (
      current !== null &&
      allDecisionsSelected.value &&
      sameReviewDecisions(buildDecisions(), current.decisions)
    );
  });

  const canValidate = computed(
    () =>
      structurallyComplete.value &&
      allDecisionsSelected.value &&
      !hasCompatibilityErrors.value &&
      (!requiresAcknowledgement.value || acknowledged.value) &&
      !matchesResolution.value,
  );

  const canExecute = computed(
    () =>
      structurallyComplete.value &&
      allDecisionsSelected.value &&
      !hasCompatibilityErrors.value &&
      matchesResolution.value &&
      nonEmptyString(resolution.value?.decision_fingerprint),
  );

  const pendingOperation = ref<"validate" | "execute" | null>(null);
  const transportError = ref<YarnReviewTransportError | null>(null);

  // Monotone revisions correlate local edits with server acknowledgements: a
  // props echo of an older save must never clobber newer local selections,
  // and a reply for an outdated push must never surface as a fresh failure.
  let localRevision = 0;
  let syncedRevision = 0;
  let operationToken = 0;
  let operationWatchdog: ReturnType<typeof setTimeout> | null = null;
  let saveWatchdog: ReturnType<typeof setTimeout> | null = null;

  function surfaceTransportError(operation: "save" | "validate" | "execute", reason: unknown) {
    transportError.value = {
      operation,
      reason: typeof reason === "string" && reason !== "" ? reason : "unavailable",
    };
  }

  function beginOperation(operation: "validate" | "execute"): number {
    pendingOperation.value = operation;
    const token = ++operationToken;

    clearOperationWatchdog();
    operationWatchdog = setTimeout(() => {
      if (settleOperation(token)) surfaceTransportError(operation, "unavailable");
    }, OPERATION_WATCHDOG_MS);

    return token;
  }

  function settleOperation(token: number): boolean {
    if (token !== operationToken || pendingOperation.value === null) return false;

    clearOperationWatchdog();
    pendingOperation.value = null;
    return true;
  }

  function clearOperationWatchdog() {
    if (operationWatchdog !== null) {
      clearTimeout(operationWatchdog);
      operationWatchdog = null;
    }
  }

  function clearSaveWatchdog() {
    if (saveWatchdog !== null) {
      clearTimeout(saveWatchdog);
      saveWatchdog = null;
    }
  }

  function clearSaveTimer() {
    if (saveTimer !== null) {
      clearTimeout(saveTimer);
      saveTimer = null;
    }
  }

  function scheduleDraftSave() {
    clearSaveTimer();

    if (
      !canImport() ||
      !Number.isSafeInteger(importState().attemptId) ||
      !structurallyComplete.value ||
      matchesResolution.value
    ) {
      return;
    }

    saveTimer = setTimeout(() => {
      saveTimer = null;
      const sentRevision = localRevision;
      const sentAttemptId = importState().attemptId;

      // The one failure neither callback covers is a push that is accepted
      // and never answered — exactly what leaves the dirty guard blocking
      // remote adoption with no signal. The watchdog gives that case a voice;
      // a newer push re-arms it, and an attempt change disarms it.
      clearSaveWatchdog();
      saveWatchdog = setTimeout(() => {
        saveWatchdog = null;

        if (
          importState().attemptId === sentAttemptId &&
          sentRevision === localRevision &&
          syncedRevision < sentRevision
        ) {
          surfaceTransportError("save", "unavailable");
        }
      }, OPERATION_WATCHDOG_MS);

      live.pushEvent(
        "save_import_review",
        { attempt_id: sentAttemptId, review_decisions: buildDecisions() },
        (reply) => {
          // Revisions reset per attempt, so a reply is only meaningful for
          // the attempt it was sent for — a delayed reply from a previous
          // attempt must not clear the watchdog, advance the revisions or
          // surface an error into the new review.
          if (importState().attemptId !== sentAttemptId) return;

          if (sentRevision === localRevision) clearSaveWatchdog();

          if (reply.ok === true) {
            syncedRevision = Math.max(syncedRevision, sentRevision);
            if (transportError.value?.operation === "save") transportError.value = null;
            return;
          }

          // Only the newest outstanding save may complain; an older one lost
          // a race that the newer push resolves either way.
          if (sentRevision === localRevision) surfaceTransportError("save", reply.reason);
        },
        () => {
          if (importState().attemptId === sentAttemptId && sentRevision === localRevision) {
            clearSaveWatchdog();
            surfaceTransportError("save", "unavailable");
          }
        },
      );
    }, REVIEW_SAVE_DEBOUNCE_MS);
  }

  function setAction(speaker: string, action: unknown) {
    if (typeof action !== "string") return;

    const entry = decisions.value.find((decision) => decision.speaker === speaker);
    const option = entry
      ? actionOptions(entry).find((candidate) => candidate.value === action)
      : undefined;

    if (!option) return;

    const nextDecision: YarnReviewDecision = {
      speaker,
      action: option.action,
      ...(option.targetSpeaker ? { target_speaker: option.targetSpeaker } : {}),
    };

    if (sameReviewDecision(selectedDecisions.value.get(speaker), nextDecision)) return;

    const next = new Map(selectedDecisions.value);
    next.set(speaker, nextDecision);

    // Dropping a speaker's sheet invalidates every alias pointing at it.
    if (option.action !== "create_sheet") {
      for (const [dependentSpeaker, decision] of next) {
        if (decision.action === "map_to_sheet" && decision.target_speaker === speaker) {
          next.delete(dependentSpeaker);
        }
      }
    }

    selectedDecisions.value = next;
    acknowledged.value = false;
    localRevision += 1;
    transportError.value = null;
    scheduleDraftSave();
  }

  function setAcknowledged(value: boolean | "indeterminate") {
    acknowledged.value = value === true;
  }

  function aliasCanMap(alias: YarnSpeakerAliasReview) {
    return selectedAction(alias.more_frequent) === "create_sheet";
  }

  function validate() {
    if (!canValidate.value || pendingOperation.value !== null) return;

    clearSaveTimer();
    const sentRevision = localRevision;
    const sentAttemptId = importState().attemptId;
    const token = beginOperation("validate");

    live.pushEvent(
      "validate_import_review",
      {
        attempt_id: sentAttemptId,
        review_acknowledged: acknowledged.value,
        review_decisions: buildDecisions(),
      },
      (reply) => {
        const settled = settleOperation(token);

        // A success that arrives after the watchdog gave up is still a
        // success — but only while it is the LATEST operation: a newer
        // validate/execute owns the banner now, and a stale success must not
        // erase that retry's failure.
        if (reply.ok === true) {
          if (token === operationToken && importState().attemptId === sentAttemptId) {
            syncedRevision = Math.max(syncedRevision, sentRevision);
            transportError.value = null;
          }

          return;
        }

        if (settled) surfaceTransportError("validate", reply.reason);
      },
      () => {
        if (settleOperation(token)) surfaceTransportError("validate", "unavailable");
      },
    );
  }

  function execute() {
    const current = resolution.value;
    if (!canExecute.value || !current || pendingOperation.value !== null) return;

    const sentAttemptId = importState().attemptId;
    const token = beginOperation("execute");

    live.pushEvent(
      "execute_import",
      {
        attempt_id: sentAttemptId,
        review_confirmation_fingerprint: current.decision_fingerprint,
      },
      (reply) => {
        const settled = settleOperation(token);

        if (reply.ok === true) {
          if (token === operationToken && importState().attemptId === sentAttemptId) {
            transportError.value = null;
          }

          return;
        }

        if (settled) surfaceTransportError("execute", reply.reason);
      },
      () => {
        if (settleOperation(token)) surfaceTransportError("execute", "unavailable");
      },
    );
  }

  function restoreDecisions() {
    const persisted = resolution.value?.decisions ?? draft.value?.decisions ?? [];
    const echoOfCurrent = sameReviewDecisions(buildDecisions(), persisted);

    selectedDecisions.value = new Map(
      persisted.map((decision) => [decision.speaker, { ...decision }]),
    );

    // A clean echo of the very selections on screen must not cost the user
    // their acknowledgement: the checkbox appears on the same click that
    // starts the save debounce, so it is routinely ticked inside that window
    // and the save's own round-trip used to wipe it.
    if (!echoOfCurrent) acknowledged.value = false;
  }

  const stateFingerprint = computed(() =>
    JSON.stringify({
      attemptId: importState().attemptId,
      review: review.value,
      draft: importState().preview?.import_review_draft,
      resolution: importState().preview?.import_review_resolution,
      issueSummary: importState().preview?.issue_summary,
    }),
  );

  // Watcher order is load-bearing: Vue runs same-flush watchers in creation
  // order, so on an attempt change this fingerprint watcher fires FIRST while
  // the revisions still describe the previous attempt — the dirty guard bails
  // — and the attemptId watcher below then does the full reset + restore.
  // Registered the other way round, a dirty review would carry stale
  // decisions into the next file's review.
  watch(
    stateFingerprint,
    () => {
      // Local selections ahead of the last acknowledged save win over a props
      // echo of older server state — restoring here would cancel the pending
      // save and silently revert what the user just chose. The in-flight save
      // reconciles both sides when it lands.
      if (localRevision > syncedRevision) return;

      clearSaveTimer();
      restoreDecisions();
    },
    { immediate: true },
  );

  // A different attempt is a different review. Never carry an acknowledgement,
  // a pending operation, an error or an edit revision over to another file's.
  watch(
    () => importState().attemptId,
    () => {
      localRevision = 0;
      syncedRevision = 0;
      operationToken += 1;
      clearOperationWatchdog();
      clearSaveWatchdog();
      pendingOperation.value = null;
      transportError.value = null;
      acknowledged.value = false;
      clearSaveTimer();
      restoreDecisions();
    },
  );

  onUnmounted(() => {
    clearSaveTimer();
    clearSaveWatchdog();
    clearOperationWatchdog();
  });

  return {
    review,
    decisions,
    aliases,
    acknowledged,
    issueSummary,
    issueSummaryMalformed,
    hasCompatibilityWarnings,
    hasCompatibilityErrors,
    structurallyComplete,
    allDecisionsSelected,
    requiresAcknowledgement,
    matchesResolution,
    isTruncated,
    canValidate,
    canExecute,
    sheetSpeakerCount,
    preservedChannelCount,
    mappedAliasCount,
    selectedAction,
    selectedActionValue,
    actionOptions,
    setAction,
    setAcknowledged,
    aliasCanMap,
    validate,
    execute,
    clearSaveTimer,
    pendingOperation,
    transportError,
  };
}
