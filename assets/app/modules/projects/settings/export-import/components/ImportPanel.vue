<script setup lang="ts">
import { useLiveUpload, type UploadConfig } from "live_vue";
import { AlertTriangle, ArrowLeftRight, CheckCircle, Clock3, Eye, Lock, Upload } from "@lucide/vue";
import { computed, onMounted, onUnmounted, ref, toRef, watch } from "vue";
import { Button } from "@components/ui/button";
import { Checkbox } from "@components/ui/checkbox";
import { Label } from "@components/ui/label";
import { RadioGroup, RadioGroupItem } from "@components/ui/radio-group";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@components/ui/table";
import { useI18n } from "vue-i18n";
import { useLive } from "@shared/composables/useLive";
import type {
  ImportAttemptStatus,
  ImportPanelProps,
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

const { t } = useI18n();

interface StoredImportAttempt {
  version: 1;
  attemptId: number;
  savedAt: number;
}

type ImportStateRequestOutcome = "success" | "definitive_failure" | "transient_failure" | "stale";

interface SpeakerActionOption {
  value: string;
  action: YarnSpeakerAction;
  targetSpeaker?: string;
  labelKey: string;
  descriptionKey: string;
  accent: "primary" | "warning" | "info";
  suggested: boolean;
}

const STORAGE_VERSION = 1;
const STORAGE_TTL_MS = 7 * 24 * 60 * 60 * 1_000;
const STORAGE_CLOCK_SKEW_MS = 5 * 60 * 1_000;
const RECONCILE_INTERVAL_MS = 3_000;
const REQUEST_WATCHDOG_MS = 5_000;
const RESUME_RETRY_BASE_MS = 1_000;
const RESUME_MAX_ATTEMPTS = 4;
const REVIEW_SAVE_DEBOUNCE_MS = 500;
const PERSISTED_STATUSES = new Set<ImportAttemptStatus>([
  "ready",
  "queued",
  "running",
  "retrying",
  "completed",
  "failed",
  "expired",
]);
const PROCESSING_STATUSES = new Set<ImportAttemptStatus>(["queued", "running", "retrying"]);
const REVIEW_REASON_KEYS = new Set([
  "literal_character_name",
  "repeated_scoped_presentation_channel",
  "single_adjacent_transposition_with_dominant_frequency",
  "dynamic_speaker_expression",
  "same_nfkc_casefold",
]);
const SPEAKER_DIRECT_ACTIONS = new Set<YarnSpeakerDirectAction>([
  "create_sheet",
  "preserve_literal",
]);
const SPEAKER_CONFIDENCE_LEVELS = new Set<YarnSpeakerConfidence>(["high", "medium", "low"]);

const {
  projectId,
  canEdit,
  importState,
  uploadConfig = null,
} = defineProps<
  ImportPanelProps & {
    uploadConfig?: UploadConfig | null;
  }
>();

const live = useLive();
let reconcileTimer: ReturnType<typeof setTimeout> | null = null;
let reconcileInFlightGeneration: number | null = null;
let resumeRetryTimer: ReturnType<typeof setTimeout> | null = null;
let reviewSaveTimer: ReturnType<typeof setTimeout> | null = null;
let resumeRequestInFlight = false;
let resumeAttemptCount = 0;
let requestGeneration = 0;
let observedAttemptId = importState.attemptId;
let pendingAttemptId: number | null = null;
const dismissedAttemptIds = new Set<number>();
const activeRequestCancels = new Set<() => void>();
const reviewAcknowledged = ref(false);
const selectedReviewDecisions = ref(new Map<string, YarnReviewDecision>());

// --- Upload handling ---
const upload = uploadConfig
  ? useLiveUpload(
      toRef(() => uploadConfig),
      {
        changeEvent: "validate_upload",
        submitEvent: "parse_import",
      },
    )
  : null;

// --- Computed ---
const strategyOptions = computed(() => [
  { value: "skip", label: t("project_settings.import.strategy_skip") },
  { value: "overwrite", label: t("project_settings.import.strategy_overwrite") },
  { value: "rename", label: t("project_settings.import.strategy_rename") },
]);

const hasUploadEntries = computed(() => {
  return (upload?.entries.value?.length ?? 0) > 0;
});

const entityCountRows = computed(() => {
  if (!importState.preview?.counts) return [];
  const counts = importState.preview.counts;
  const rows = [
    { entity: t("project_settings.import.entities.sheets"), count: counts.sheets || 0 },
    { entity: t("project_settings.import.entities.flows"), count: counts.flows || 0 },
    { entity: t("project_settings.import.entities.nodes"), count: counts.nodes || 0 },
    { entity: t("project_settings.import.entities.scenes"), count: counts.scenes || 0 },
    { entity: t("project_settings.import.entities.assets"), count: counts.assets || 0 },
  ];
  return rows.filter((r) => r.count > 0);
});

const importReview = computed<YarnImportReview | null>(() => {
  const review = importState.preview?.import_review;
  return review && typeof review === "object" ? review : null;
});
const issueSummary = computed<YarnImportIssueSummary | null>(() =>
  parseIssueSummary(importState.preview?.issue_summary),
);
const issueSummaryMalformed = computed(
  () =>
    importState.preview?.issue_summary !== null &&
    importState.preview?.issue_summary !== undefined &&
    issueSummary.value === null,
);
const compatibilityIssueRows = computed(() =>
  Object.entries(issueSummary.value?.counts_by_code ?? {})
    .map(([code, count]) => ({ code, count }))
    .sort((left, right) => left.code.localeCompare(right.code)),
);
const hasCompatibilityWarnings = computed(() => (issueSummary.value?.warning_count ?? 0) > 0);
const hasCompatibilityErrors = computed(
  () => issueSummaryMalformed.value || (issueSummary.value?.error_count ?? 0) > 0,
);
const rawSpeakerDecisions = computed<unknown[]>(() => {
  const decisions = importReview.value?.speaker_decisions;
  return Array.isArray(decisions) ? decisions : [];
});
const speakerDecisions = computed<YarnSpeakerDecision[]>(() =>
  rawSpeakerDecisions.value.filter(isSpeakerDecision),
);
const rawPossibleSpeakerAliases = computed<unknown[]>(() => {
  const aliases = importReview.value?.possible_speaker_aliases;
  return Array.isArray(aliases) ? aliases : [];
});
const possibleSpeakerAliases = computed<YarnSpeakerAliasReview[]>(() =>
  rawPossibleSpeakerAliases.value.filter(isSpeakerAliasReview),
);
const importReviewDraft = computed<YarnImportReviewDraft | null>(() =>
  parseReviewSnapshot(importState.preview?.import_review_draft, 1, false),
);
const importReviewResolution = computed<YarnImportReviewResolution | null>(() =>
  parseReviewSnapshot(importState.preview?.import_review_resolution, 2, true),
);
const reviewStateFingerprint = computed(() =>
  JSON.stringify({
    attemptId: importState.attemptId,
    review: importReview.value,
    draft: importState.preview?.import_review_draft,
    resolution: importState.preview?.import_review_resolution,
    issueSummary: importState.preview?.issue_summary,
  }),
);
const reviewStructurallyComplete = computed(() => {
  const review = importReview.value;
  const summary = issueSummary.value;
  if (!review || !summary) return false;

  return (
    validReviewScalars(review) &&
    completeSpeakerReview(review, rawSpeakerDecisions.value, speakerDecisions.value) &&
    completeAliasReview(review, rawPossibleSpeakerAliases.value, possibleSpeakerAliases.value) &&
    suggestedReviewCountsMatch(review, speakerDecisions.value) &&
    compatibilityReviewMatchesSummary(review, summary) &&
    acknowledgementContractMatches(review)
  );
});
const allSpeakerDecisionsSelected = computed(
  () =>
    reviewStructurallyComplete.value &&
    selectedReviewDecisions.value.size === speakerDecisions.value.length &&
    buildReviewDecisions().length === speakerDecisions.value.length &&
    buildReviewDecisions().every(reviewDecisionIsCurrentlyValid),
);
const selectedSheetSpeakerCount = computed(() =>
  reviewStructurallyComplete.value
    ? speakerDecisions.value.filter(
        (decision) => selectedReviewAction(decision.speaker) === "create_sheet",
      ).length
    : importReview.value?.sheet_speaker_count,
);
const selectedPreservedChannelCount = computed(() =>
  reviewStructurallyComplete.value
    ? speakerDecisions.value.filter(
        (decision) => selectedReviewAction(decision.speaker) === "preserve_literal",
      ).length
    : importReview.value?.preserved_channel_count,
);
const selectedMappedAliasCount = computed(() =>
  reviewStructurallyComplete.value
    ? speakerDecisions.value.filter(
        (decision) => selectedReviewAction(decision.speaker) === "map_to_sheet",
      ).length
    : 0,
);
const reviewIsTruncated = computed(
  () =>
    importReview.value?.speaker_decisions_truncated === true ||
    importReview.value?.possible_speaker_aliases_truncated === true,
);
const reviewRequiresAcknowledgement = computed(() => {
  const review = importReview.value;
  if (!reviewStructurallyComplete.value || !review) return true;

  return (
    review.requires_acknowledgement ||
    (selectedPreservedChannelCount.value ?? 0) > 0 ||
    review.possible_speaker_alias_count > 0 ||
    hasCompatibilityWarnings.value
  );
});
const reviewMatchesResolution = computed(() => {
  const resolution = importReviewResolution.value;

  return (
    resolution !== null &&
    allSpeakerDecisionsSelected.value &&
    sameReviewDecisions(buildReviewDecisions(), resolution.decisions)
  );
});
const reviewCanValidate = computed(
  () =>
    reviewStructurallyComplete.value &&
    allSpeakerDecisionsSelected.value &&
    !hasCompatibilityErrors.value &&
    (!reviewRequiresAcknowledgement.value || reviewAcknowledged.value) &&
    !reviewMatchesResolution.value,
);
const reviewCanExecute = computed(
  () =>
    reviewStructurallyComplete.value &&
    allSpeakerDecisionsSelected.value &&
    !hasCompatibilityErrors.value &&
    reviewMatchesResolution.value &&
    nonEmptyString(importReviewResolution.value?.decision_fingerprint),
);

// --- Event handlers ---
function executeImport() {
  const resolution = importReviewResolution.value;
  if (!reviewCanExecute.value || !resolution) return;

  live.pushEvent("execute_import", {
    review_confirmation_fingerprint: resolution.decision_fingerprint,
  });
}

function validateImportReview() {
  if (!reviewCanValidate.value) return;

  clearReviewSaveTimer();
  live.pushEvent("validate_import_review", {
    review_acknowledged: reviewAcknowledged.value,
    review_decisions: buildReviewDecisions(),
  });
}

function setStrategy(strategy: string) {
  live.pushEvent("set_strategy", { strategy });
}

function resetImport() {
  const activeAttemptId = validAttemptId(importState.attemptId)
    ? importState.attemptId
    : pendingAttemptId;

  if (validAttemptId(activeAttemptId)) {
    dismissedAttemptIds.add(activeAttemptId);
  }

  invalidateRequests();
  clearReviewSaveTimer();
  pendingAttemptId = null;
  clearStoredAttempt();
  stopReconcileTimer();
  live.pushEvent("reset_import", {});
}

function handleUploadSubmit() {
  upload?.submit();
}

function setReviewAcknowledged(value: boolean | "indeterminate") {
  reviewAcknowledged.value = value === true;
}

function setReviewAction(speaker: string, action: unknown) {
  if (typeof action !== "string") return;

  const reviewEntry = speakerDecisions.value.find((decision) => decision.speaker === speaker);
  const option = reviewEntry
    ? speakerActionOptions(reviewEntry).find((candidate) => candidate.value === action)
    : undefined;

  if (!option) return;

  const nextDecision: YarnReviewDecision = {
    speaker,
    action: option.action,
    ...(option.targetSpeaker ? { target_speaker: option.targetSpeaker } : {}),
  };

  if (sameReviewDecision(selectedReviewDecisions.value.get(speaker), nextDecision)) return;

  const next = new Map(selectedReviewDecisions.value);
  next.set(speaker, nextDecision);

  if (option.action !== "create_sheet") {
    for (const [dependentSpeaker, decision] of next) {
      if (decision.action === "map_to_sheet" && decision.target_speaker === speaker) {
        next.delete(dependentSpeaker);
      }
    }
  }

  selectedReviewDecisions.value = next;
  reviewAcknowledged.value = false;
  scheduleReviewDraftSave();
}

// --- Helpers ---
function formatFileSize(bytes: number) {
  if (bytes >= 1048576) return `${(bytes / 1048576).toFixed(1)} MB`;
  if (bytes >= 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${bytes} B`;
}

function occurrencesLabel(count: number) {
  return t("project_settings.import.review_occurrences", { count }, count);
}

function nonNegativeSafeInteger(value: unknown): value is number {
  return Number.isSafeInteger(value) && Number(value) >= 0;
}

function positiveSafeInteger(value: unknown): value is number {
  return Number.isSafeInteger(value) && Number(value) > 0;
}

function nonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function validReasons(value: unknown): value is string[] {
  return Array.isArray(value) && value.length > 0 && value.every(nonEmptyString);
}

function parseIssueSummary(value: unknown): YarnImportIssueSummary | null {
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

function parseIssueCounts(value: unknown): Record<string, number> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;

  const counts = value as Record<string, unknown>;
  const entries = Object.entries(counts);
  if (!entries.every(([code]) => /^[a-z0-9_]+$/.test(code))) return null;
  if (!entries.every(([, count]) => positiveSafeInteger(count))) return null;
  return Object.fromEntries(entries) as Record<string, number>;
}

function formatIssueCode(code: string) {
  return code.replaceAll("_", " ");
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

function sameIssueCounts(left: Record<string, number>, right: Record<string, number>): boolean {
  const leftEntries = Object.entries(left).sort(([leftCode], [rightCode]) =>
    leftCode.localeCompare(rightCode),
  );
  const rightEntries = Object.entries(right).sort(([leftCode], [rightCode]) =>
    leftCode.localeCompare(rightCode),
  );

  return JSON.stringify(leftEntries) === JSON.stringify(rightEntries);
}

function completeSpeakerReview(
  review: YarnImportReview,
  rawDecisions: unknown[],
  validDecisions: YarnSpeakerDecision[],
) {
  const uniqueSpeakers = new Set(validDecisions.map((decision) => decision.speaker));

  return [
    Array.isArray(review.speaker_decisions),
    !review.speaker_decisions_truncated,
    review.speaker_decision_count === rawDecisions.length,
    validDecisions.length === rawDecisions.length,
    uniqueSpeakers.size === validDecisions.length,
  ].every(Boolean);
}

function completeAliasReview(
  review: YarnImportReview,
  rawAliases: unknown[],
  validAliases: YarnSpeakerAliasReview[],
) {
  const reviewedSpeakers = new Set(speakerDecisions.value.map((decision) => decision.speaker));
  const uniquePairs = new Set(
    validAliases.map((alias) => [alias.left, alias.right].sort().join("\u0000")),
  );

  return [
    Array.isArray(review.possible_speaker_aliases),
    !review.possible_speaker_aliases_truncated,
    review.possible_speaker_alias_count === rawAliases.length,
    validAliases.length === rawAliases.length,
    uniquePairs.size === validAliases.length,
    validAliases.every(
      (alias) => reviewedSpeakers.has(alias.left) && reviewedSpeakers.has(alias.right),
    ),
  ].every(Boolean);
}

function isSpeakerDecision(value: unknown): value is YarnSpeakerDecision {
  if (!value || typeof value !== "object") return false;

  const decision = value as Partial<YarnSpeakerDecision>;
  return [
    nonEmptyString(decision.speaker),
    positiveSafeInteger(decision.occurrences),
    SPEAKER_DIRECT_ACTIONS.has(decision.suggested_action as YarnSpeakerDirectAction),
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

function reasonLabel(reason: string) {
  const key = REVIEW_REASON_KEYS.has(reason) ? reason : "unspecified";
  return t(`project_settings.import.review_evidence.${key}`);
}

function confidenceLabel(confidence: YarnSpeakerConfidence) {
  return t(`project_settings.import.review_confidence.${confidence}`);
}

function selectedReviewAction(speaker: string) {
  return selectedReviewDecisions.value.get(speaker)?.action;
}

function selectedReviewActionValue(speaker: string) {
  const decision = selectedReviewDecisions.value.get(speaker);
  if (!decision) return undefined;

  return decision.action === "map_to_sheet" && decision.target_speaker
    ? aliasMappingValue(decision.target_speaker)
    : decision.action;
}

function buildReviewDecisions(): YarnReviewDecision[] {
  return speakerDecisions.value.flatMap((reviewEntry) => {
    const decision = selectedReviewDecisions.value.get(reviewEntry.speaker);
    return decision ? [{ ...decision }] : [];
  });
}

function aliasTargetsForSpeaker(speaker: string) {
  return [
    ...new Set(
      possibleSpeakerAliases.value
        .filter((alias) => alias.less_frequent === speaker)
        .map((alias) => alias.more_frequent),
    ),
  ];
}

function aliasMappingValue(targetSpeaker: string) {
  return `map_to_sheet:${targetSpeaker}`;
}

function preservesLiteralOnly(decision: YarnSpeakerDecision) {
  return decision.reasons.includes("dynamic_speaker_expression");
}

function speakerActionOptions(decision: YarnSpeakerDecision): SpeakerActionOption[] {
  const preserveLiteralOption: SpeakerActionOption = {
    value: "preserve_literal",
    action: "preserve_literal",
    labelKey: "project_settings.import.review_preserve_literal",
    descriptionKey: "project_settings.import.review_preserve_literal_description",
    accent: "warning",
    suggested: decision.suggested_action === "preserve_literal",
  };

  if (preservesLiteralOnly(decision)) return [preserveLiteralOption];

  const options: SpeakerActionOption[] = [
    {
      value: "create_sheet",
      action: "create_sheet",
      labelKey: "project_settings.import.review_create_sheet",
      descriptionKey: "project_settings.import.review_create_sheet_description",
      accent: "primary",
      suggested: decision.suggested_action === "create_sheet",
    },
    preserveLiteralOption,
  ];

  for (const targetSpeaker of aliasTargetsForSpeaker(decision.speaker)) {
    if (selectedReviewAction(targetSpeaker) === "create_sheet") {
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

function reviewActionOptionClasses(speaker: string, option: SpeakerActionOption) {
  const selected = selectedReviewActionValue(speaker) === option.value;
  const selectedClasses = {
    primary: "border-primary/45 bg-primary/5",
    warning: "border-amber-500/45 bg-amber-500/5",
    info: "border-sky-500/45 bg-sky-500/5",
  };

  return [
    "flex cursor-pointer items-start gap-2.5 rounded-lg border p-3 transition-colors",
    selected ? selectedClasses[option.accent] : "border-border bg-background hover:bg-muted/40",
  ];
}

function reviewActionTestId(action: YarnSpeakerAction) {
  return `yarn-import-action-${action.replaceAll("_", "-")}`;
}

function aliasCanMap(alias: YarnSpeakerAliasReview) {
  return selectedReviewAction(alias.more_frequent) === "create_sheet";
}

function reviewDecisionIsCurrentlyValid(decision: YarnReviewDecision) {
  const reviewEntry = speakerDecisions.value.find((entry) => entry.speaker === decision.speaker);
  if (!reviewEntry) return false;
  if (preservesLiteralOnly(reviewEntry)) {
    return decision.action === "preserve_literal" && decision.target_speaker === undefined;
  }

  if (SPEAKER_DIRECT_ACTIONS.has(decision.action as YarnSpeakerDirectAction)) {
    return decision.target_speaker === undefined;
  }

  return (
    decision.action === "map_to_sheet" &&
    nonEmptyString(decision.target_speaker) &&
    aliasTargetsForSpeaker(decision.speaker).includes(decision.target_speaker) &&
    selectedReviewAction(decision.target_speaker) === "create_sheet"
  );
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

function sameReviewDecisions(left: YarnReviewDecision[], right: YarnReviewDecision[]) {
  return (
    JSON.stringify(canonicalReviewDecisions(left)) ===
    JSON.stringify(canonicalReviewDecisions(right))
  );
}

function canonicalReviewDecisions(decisions: YarnReviewDecision[]) {
  return decisions
    .map((decision) => [decision.speaker, decision.action, decision.target_speaker ?? null])
    .sort(([leftSpeaker], [rightSpeaker]) =>
      String(leftSpeaker).localeCompare(String(rightSpeaker)),
    );
}

function parseReviewSnapshot(
  value: unknown,
  expectedVersion: 1,
  requireComplete: false,
): YarnImportReviewDraft | null;
function parseReviewSnapshot(
  value: unknown,
  expectedVersion: 2,
  requireComplete: true,
): YarnImportReviewResolution | null;
function parseReviewSnapshot(
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

  const decisions = parsePersistedReviewDecisions(snapshot.decisions, requireComplete);
  if (!decisions) return null;

  return {
    version: expectedVersion,
    decisions,
    decision_fingerprint: snapshot.decision_fingerprint,
  } as YarnImportReviewDraft | YarnImportReviewResolution;
}

function parsePersistedReviewDecisions(values: unknown[], requireComplete: boolean) {
  const reviewedSpeakers = new Set(speakerDecisions.value.map((decision) => decision.speaker));
  const decisions = new Map<string, YarnReviewDecision>();

  for (const value of values) {
    const decision = parsePersistedReviewDecision(value, reviewedSpeakers, decisions);
    if (!decision) return null;
    decisions.set(decision.speaker, decision);
  }

  if (requireComplete && decisions.size !== reviewedSpeakers.size) return null;
  if (!persistedMappingTargetsAreValid(decisions)) return null;

  return [...decisions.values()];
}

function parsePersistedReviewDecision(
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

  if (SPEAKER_DIRECT_ACTIONS.has(candidate.action as YarnSpeakerDirectAction)) {
    return candidate.target_speaker === undefined
      ? { speaker: candidate.speaker, action: candidate.action as YarnSpeakerDirectAction }
      : null;
  }

  return parsePersistedAliasMapping(candidate);
}

function parsePersistedAliasMapping(
  candidate: Partial<YarnReviewDecision>,
): YarnReviewDecision | null {
  const validMapping = [
    candidate.action === "map_to_sheet",
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

function persistedMappingTargetsAreValid(decisions: Map<string, YarnReviewDecision>) {
  return [...decisions.values()]
    .filter((decision) => decision.action === "map_to_sheet")
    .every((decision) => decisions.get(decision.target_speaker ?? "")?.action === "create_sheet");
}

function restoreReviewDecisions() {
  const persisted =
    importReviewResolution.value?.decisions ?? importReviewDraft.value?.decisions ?? [];

  selectedReviewDecisions.value = new Map(
    persisted.map((decision) => [decision.speaker, { ...decision }]),
  );
  reviewAcknowledged.value = false;
}

function clearReviewSaveTimer() {
  if (reviewSaveTimer !== null) {
    clearTimeout(reviewSaveTimer);
    reviewSaveTimer = null;
  }
}

function scheduleReviewDraftSave() {
  clearReviewSaveTimer();

  if (
    !canEdit ||
    !validAttemptId(importState.attemptId) ||
    !reviewStructurallyComplete.value ||
    reviewMatchesResolution.value
  ) {
    return;
  }

  reviewSaveTimer = setTimeout(() => {
    reviewSaveTimer = null;
    live.pushEvent("save_import_review", {
      review_decisions: buildReviewDecisions(),
    });
  }, REVIEW_SAVE_DEBOUNCE_MS);
}

function storageKey() {
  return `storyarn:project-import:${projectId}`;
}

function validAttemptId(value: unknown): value is number {
  return Number.isSafeInteger(value) && Number(value) > 0;
}

function clearStoredAttempt() {
  if (typeof window === "undefined") return;

  try {
    window.localStorage.removeItem(storageKey());
  } catch {
    // Storage can be disabled. Import execution must remain usable without it.
  }
}

function parseStoredAttempt(raw: string): StoredImportAttempt | null {
  const parsed: unknown = JSON.parse(raw);
  if (!parsed || typeof parsed !== "object") return null;

  const { version, attemptId, savedAt } = parsed as Partial<StoredImportAttempt>;
  const now = Date.now();

  if (
    version !== STORAGE_VERSION ||
    !validAttemptId(attemptId) ||
    typeof savedAt !== "number" ||
    !Number.isSafeInteger(savedAt) ||
    savedAt <= 0 ||
    savedAt > now + STORAGE_CLOCK_SKEW_MS ||
    now - savedAt > STORAGE_TTL_MS
  ) {
    return null;
  }

  return { version, attemptId, savedAt };
}

function readStoredAttempt(): StoredImportAttempt | null {
  if (typeof window === "undefined") return null;

  try {
    const raw = window.localStorage.getItem(storageKey());
    if (!raw) return null;

    const stored = parseStoredAttempt(raw);
    if (!stored) clearStoredAttempt();
    return stored;
  } catch {
    clearStoredAttempt();
    return null;
  }
}

function storeAttempt(attemptId: number) {
  if (typeof window === "undefined" || dismissedAttemptIds.has(attemptId)) return;

  try {
    const stored: StoredImportAttempt = {
      version: STORAGE_VERSION,
      attemptId,
      savedAt: Date.now(),
    };
    window.localStorage.setItem(storageKey(), JSON.stringify(stored));
  } catch {
    // Keep the in-page workflow functional when storage is unavailable.
  }
}

function clearStoredAttemptIfMatching(attemptId: number) {
  const stored = readStoredAttempt();
  if (stored?.attemptId === attemptId) clearStoredAttempt();
}

function reconcileReply(
  attemptId: number,
  generation: number,
  reply: Record<string, unknown>,
): ImportStateRequestOutcome {
  if (generation !== requestGeneration) return "stale";

  if (reply.ok === true) return "success";

  const currentAttemptId = importState.attemptId;
  if (validAttemptId(currentAttemptId) && currentAttemptId !== attemptId) return "stale";

  const definitiveFailure = ["invalid", "not_found", "unauthorized"].includes(String(reply.reason));

  if (definitiveFailure) {
    clearStoredAttemptIfMatching(attemptId);
    stopReconcileTimer();
    return "definitive_failure";
  }

  return "transient_failure";
}

function requestImportState(
  event: "resume_import" | "reconcile_import",
  attemptId: number,
  settled?: (generation: number, outcome: ImportStateRequestOutcome) => void,
) {
  const generation = requestGeneration;
  let finished = false;

  const cancel = () => {
    if (finished) return;

    finished = true;
    clearTimeout(watchdog);
    activeRequestCancels.delete(cancel);
  };

  const finish = (outcome: ImportStateRequestOutcome) => {
    if (finished) return;

    cancel();
    settled?.(generation, outcome);
  };

  const watchdog = setTimeout(() => finish("transient_failure"), REQUEST_WATCHDOG_MS);
  activeRequestCancels.add(cancel);

  live.pushEvent(
    event,
    { attempt_id: attemptId },
    (reply) => finish(reconcileReply(attemptId, generation, reply)),
    () => {
      // A dropped socket is transient. Keep the reference for the next mount.
      finish("transient_failure");
    },
  );
}

function cancelOutstandingRequests() {
  for (const cancel of activeRequestCancels) cancel();
}

function stopResumeRetryTimer() {
  if (resumeRetryTimer !== null) {
    clearTimeout(resumeRetryTimer);
    resumeRetryTimer = null;
  }
}

function invalidateRequests() {
  requestGeneration += 1;
  cancelOutstandingRequests();
  reconcileInFlightGeneration = null;
  resumeRequestInFlight = false;
  stopResumeRetryTimer();
  stopReconcileTimer();
}

function scheduleResumeAttempt(attemptId: number, generation: number, delayMs: number) {
  stopResumeRetryTimer();

  resumeRetryTimer = setTimeout(() => {
    resumeRetryTimer = null;

    if (
      generation === requestGeneration &&
      pendingAttemptId === attemptId &&
      !dismissedAttemptIds.has(attemptId)
    ) {
      requestResumeAttempt(attemptId, generation);
    }
  }, delayMs);
}

function requestResumeAttempt(attemptId: number, generation: number) {
  if (
    generation !== requestGeneration ||
    pendingAttemptId !== attemptId ||
    resumeRequestInFlight ||
    dismissedAttemptIds.has(attemptId)
  ) {
    return;
  }

  if (importState.attemptId === attemptId) {
    pendingAttemptId = null;
    resumeAttemptCount = 0;
    return;
  }

  resumeAttemptCount += 1;
  resumeRequestInFlight = true;

  requestImportState("resume_import", attemptId, (settledGeneration, outcome) => {
    if (settledGeneration !== requestGeneration || pendingAttemptId !== attemptId) return;

    resumeRequestInFlight = false;

    if (outcome === "definitive_failure") {
      pendingAttemptId = null;
      resumeAttemptCount = 0;
      return;
    }

    if (outcome === "stale") return;

    if (resumeAttemptCount >= RESUME_MAX_ATTEMPTS) return;

    const retryDelay =
      outcome === "success"
        ? RESUME_RETRY_BASE_MS
        : RESUME_RETRY_BASE_MS * 2 ** (resumeAttemptCount - 1);

    scheduleResumeAttempt(attemptId, settledGeneration, retryDelay);
  });
}

function startResume(attemptId: number) {
  if (
    !canEdit ||
    dismissedAttemptIds.has(attemptId) ||
    importState.attemptId === attemptId ||
    (pendingAttemptId === attemptId && (resumeRequestInFlight || resumeRetryTimer !== null))
  ) {
    return;
  }

  invalidateRequests();
  pendingAttemptId = attemptId;
  resumeAttemptCount = 0;
  requestResumeAttempt(attemptId, requestGeneration);
}

function stopReconcileTimer() {
  if (reconcileTimer !== null) {
    clearTimeout(reconcileTimer);
    reconcileTimer = null;
  }
}

function syncReconcileTimer() {
  stopReconcileTimer();

  const attemptId = importState.attemptId;
  const status = importState.status;

  if (
    canEdit &&
    validAttemptId(attemptId) &&
    status &&
    PROCESSING_STATUSES.has(status) &&
    pendingAttemptId === null &&
    reconcileInFlightGeneration === null
  ) {
    reconcileTimer = setTimeout(() => {
      reconcileTimer = null;

      if (
        importState.attemptId === attemptId &&
        importState.status &&
        PROCESSING_STATUSES.has(importState.status)
      ) {
        const generation = requestGeneration;
        reconcileInFlightGeneration = generation;

        requestImportState("reconcile_import", attemptId, (settledGeneration, outcome) => {
          if (reconcileInFlightGeneration !== settledGeneration) return;

          reconcileInFlightGeneration = null;
          if (outcome !== "definitive_failure" && outcome !== "stale") syncReconcileTimer();
        });
      }
    }, RECONCILE_INTERVAL_MS);
  }
}

watch(
  reviewStateFingerprint,
  () => {
    clearReviewSaveTimer();
    restoreReviewDecisions();
  },
  { immediate: true },
);

watch(
  () => [importState.attemptId, importState.status] as const,
  ([attemptId, status]) => {
    if (attemptId !== observedAttemptId) {
      observedAttemptId = attemptId;
      reviewAcknowledged.value = false;
      clearReviewSaveTimer();
      invalidateRequests();
      pendingAttemptId = null;
      resumeAttemptCount = 0;
    }

    if (
      validAttemptId(attemptId) &&
      status &&
      PERSISTED_STATUSES.has(status) &&
      pendingAttemptId === null
    ) {
      storeAttempt(attemptId);
    }

    syncReconcileTimer();
  },
  { immediate: true },
);

onMounted(() => {
  if (!canEdit || validAttemptId(importState.attemptId)) return;

  const stored = readStoredAttempt();
  if (stored) startResume(stored.attemptId);
});

function handleStorageChange(event: StorageEvent) {
  if (event.key !== storageKey()) return;

  if (event.newValue === null) {
    try {
      if (window.localStorage.getItem(storageKey()) !== null) return;
    } catch {
      // Treat inaccessible storage as removed and keep the in-page flow usable.
    }

    if (validAttemptId(importState.attemptId)) {
      dismissedAttemptIds.add(importState.attemptId);
    }
    if (validAttemptId(pendingAttemptId)) {
      dismissedAttemptIds.add(pendingAttemptId);
    }

    invalidateRequests();
    pendingAttemptId = null;
    stopReconcileTimer();
    return;
  }

  const stored = readStoredAttempt();
  if (stored) startResume(stored.attemptId);
}

onMounted(() => window.addEventListener("storage", handleStorageChange));

onUnmounted(() => {
  clearReviewSaveTimer();
  invalidateRequests();
  pendingAttemptId = null;
  stopReconcileTimer();
  window.removeEventListener("storage", handleStorageChange);
});
</script>

<template>
  <section class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm sm:p-6">
    <div class="mb-5 space-y-1">
      <h2 class="text-lg font-semibold">{{ $t("project_settings.import.title") }}</h2>
      <p class="text-sm text-base-content/65">
        {{ $t("project_settings.import.description") }}
      </p>
    </div>

    <template v-if="canEdit">
      <!-- Step: Upload -->
      <div v-if="importState.step === 'upload'" class="space-y-3">
        <div class="space-y-2">
          <Label>{{ $t("project_settings.import.select_file") }}</Label>
          <Button
            id="yarn-import-file-picker"
            variant="outline"
            size="sm"
            class="transition-transform hover:-translate-y-0.5"
            @click="upload?.showFilePicker()"
          >
            {{ $t("project_settings.import.choose_file") }}
          </Button>
          <p class="text-xs text-base-content/55">
            {{ $t("project_settings.import.file_help") }}
          </p>
        </div>

        <div v-for="entry in upload?.entries.value" :key="entry.ref" class="text-sm">
          <span>{{ entry.client_name }}</span>
          <span class="text-muted-foreground"> ({{ formatFileSize(entry.client_size) }}) </span>
          <div v-for="(err, ei) in entry.errors" :key="ei" class="text-sm text-destructive">
            {{ err }}
          </div>
        </div>

        <Button
          id="yarn-import-preview"
          size="sm"
          :disabled="!hasUploadEntries"
          @click="handleUploadSubmit"
        >
          <Eye class="size-4" />
          {{ $t("project_settings.import.upload_preview") }}
        </Button>
      </div>

      <!-- Step: Preview -->
      <div v-if="importState.step === 'preview'" class="space-y-4">
        <h3 class="text-base font-medium">{{ $t("project_settings.import.preview_title") }}</h3>

        <!-- Entity counts -->
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{{ $t("project_settings.import.th_entity") }}</TableHead>
              <TableHead class="text-right">{{ $t("project_settings.import.th_count") }}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow v-for="row in entityCountRows" :key="row.entity">
              <TableCell class="capitalize">{{ row.entity }}</TableCell>
              <TableCell class="text-right">{{ row.count }}</TableCell>
            </TableRow>
          </TableBody>
        </Table>

        <section
          v-if="issueSummary && issueSummary.issue_count > 0"
          data-testid="yarn-import-issue-summary"
          class="space-y-3 rounded-xl border border-amber-500/30 bg-amber-500/5 p-4"
        >
          <div class="flex items-start gap-2">
            <AlertTriangle class="mt-0.5 size-4 shrink-0 text-amber-700 dark:text-amber-300" />
            <div>
              <h4 class="text-sm font-semibold">
                {{ $t("project_settings.import.compatibility_summary_title") }}
              </h4>
              <p class="text-xs text-muted-foreground">
                {{ $t("project_settings.import.compatibility_summary_description") }}
              </p>
            </div>
          </div>

          <dl class="grid grid-cols-3 gap-2 text-center">
            <div class="rounded-lg border border-border bg-background px-2 py-2">
              <dt class="text-[11px] text-muted-foreground">
                {{ $t("project_settings.import.compatibility_warning_count") }}
              </dt>
              <dd
                data-testid="yarn-import-warning-count"
                class="text-lg font-semibold tabular-nums text-amber-700 dark:text-amber-300"
              >
                {{ issueSummary.warning_count }}
              </dd>
            </div>
            <div class="rounded-lg border border-border bg-background px-2 py-2">
              <dt class="text-[11px] text-muted-foreground">
                {{ $t("project_settings.import.compatibility_error_count") }}
              </dt>
              <dd
                data-testid="yarn-import-error-count"
                class="text-lg font-semibold tabular-nums text-destructive"
              >
                {{ issueSummary.error_count }}
              </dd>
            </div>
            <div class="rounded-lg border border-border bg-background px-2 py-2">
              <dt class="text-[11px] text-muted-foreground">
                {{ $t("project_settings.import.compatibility_total_count") }}
              </dt>
              <dd data-testid="yarn-import-issue-count" class="text-lg font-semibold tabular-nums">
                {{ issueSummary.issue_count }}
              </dd>
            </div>
          </dl>

          <ul class="flex flex-wrap gap-2" data-testid="yarn-import-issue-code-counts">
            <li
              v-for="issue in compatibilityIssueRows"
              :key="issue.code"
              class="rounded-full border border-border bg-background px-2 py-1 text-xs"
            >
              <span class="capitalize">{{ formatIssueCode(issue.code) }}</span>
              <span class="ml-1 font-semibold tabular-nums">{{ issue.count }}</span>
            </li>
          </ul>

          <p
            v-if="issueSummary.issues_truncated"
            data-testid="yarn-import-issues-truncated"
            class="text-xs text-muted-foreground"
          >
            {{ $t("project_settings.import.compatibility_counts_complete") }}
          </p>
        </section>

        <div
          v-else-if="(importState.warningCodes?.length ?? 0) > 0"
          class="alert alert-warning text-sm"
        >
          <AlertTriangle class="size-5 shrink-0" />
          <span>{{ $t("project_settings.import.compatibility_warnings") }}</span>
        </div>

        <section
          v-if="importReview"
          id="yarn-import-review"
          class="space-y-3 rounded-xl border border-border bg-muted/25 p-4"
        >
          <div class="space-y-1">
            <h4 class="text-sm font-semibold">
              {{ $t("project_settings.import.review_title") }}
            </h4>
            <p class="text-xs text-muted-foreground">
              {{ $t("project_settings.import.review_description") }}
            </p>
          </div>

          <dl class="grid grid-cols-2 gap-2 text-center lg:grid-cols-4">
            <div class="rounded-lg border border-border bg-background px-2 py-2">
              <dt class="text-[11px] text-muted-foreground">
                {{ $t("project_settings.import.review_variables") }}
              </dt>
              <dd
                data-testid="yarn-import-variable-count"
                class="text-lg font-semibold tabular-nums"
              >
                {{ importReview.variable_count }}
              </dd>
            </div>
            <div class="rounded-lg border border-border bg-background px-2 py-2">
              <dt class="text-[11px] text-muted-foreground">
                {{ $t("project_settings.import.review_sheet_speakers") }}
              </dt>
              <dd
                data-testid="yarn-import-sheet-speaker-count"
                class="text-lg font-semibold tabular-nums"
              >
                {{ selectedSheetSpeakerCount ?? "—" }}
              </dd>
            </div>
            <div class="rounded-lg border border-border bg-background px-2 py-2">
              <dt class="text-[11px] text-muted-foreground">
                {{ $t("project_settings.import.review_preserved_channels") }}
              </dt>
              <dd
                data-testid="yarn-import-preserved-channel-count"
                class="text-lg font-semibold tabular-nums"
              >
                {{ selectedPreservedChannelCount ?? "—" }}
              </dd>
            </div>
            <div class="rounded-lg border border-border bg-background px-2 py-2">
              <dt class="text-[11px] text-muted-foreground">
                {{ $t("project_settings.import.review_mapped_aliases") }}
              </dt>
              <dd
                data-testid="yarn-import-mapped-alias-count"
                class="text-lg font-semibold tabular-nums"
              >
                {{ selectedMappedAliasCount }}
              </dd>
            </div>
          </dl>

          <details
            v-if="importReview.speaker_decision_count > 0"
            open
            class="group rounded-lg border border-border"
          >
            <summary
              class="cursor-pointer select-none px-3 py-2 text-sm font-medium transition-colors hover:bg-muted/60"
            >
              {{ $t("project_settings.import.review_speaker_decisions") }}
              <span class="ml-1 text-xs font-normal text-muted-foreground">
                ({{ importReview.speaker_decision_count }})
              </span>
            </summary>
            <ul class="max-h-72 divide-y divide-border overflow-y-auto border-t border-border">
              <li
                v-for="(decision, decisionIndex) in speakerDecisions"
                :key="decision.speaker"
                :data-decision="selectedReviewAction(decision.speaker) ?? 'missing'"
                :data-suggested-action="decision.suggested_action"
                data-testid="yarn-import-speaker-decision"
                class="space-y-3 px-3 py-3"
              >
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <div class="min-w-0">
                    <p class="break-words text-sm font-semibold">{{ decision.speaker }}</p>
                    <p class="text-xs text-muted-foreground">
                      {{ occurrencesLabel(decision.occurrences) }}
                    </p>
                  </div>
                  <span
                    data-testid="yarn-import-speaker-confidence"
                    class="rounded-full border border-border bg-muted px-2 py-0.5 text-[11px] font-medium text-muted-foreground"
                  >
                    {{
                      $t("project_settings.import.review_confidence_label", {
                        confidence: confidenceLabel(decision.confidence),
                      })
                    }}
                  </span>
                </div>
                <ul class="space-y-1 text-xs text-muted-foreground">
                  <li
                    v-for="reason in decision.reasons"
                    :key="reason"
                    class="flex items-start gap-1.5"
                  >
                    <span
                      aria-hidden="true"
                      class="mt-1.5 size-1 shrink-0 rounded-full bg-current"
                    />
                    <span>{{ reasonLabel(reason) }}</span>
                  </li>
                </ul>
                <RadioGroup
                  :model-value="selectedReviewActionValue(decision.speaker)"
                  class="grid gap-2 lg:grid-cols-3"
                  @update:model-value="setReviewAction(decision.speaker, $event)"
                >
                  <label
                    v-for="(option, optionIndex) in speakerActionOptions(decision)"
                    :key="option.value"
                    :for="`yarn-speaker-${decisionIndex}-action-${optionIndex}`"
                    :class="reviewActionOptionClasses(decision.speaker, option)"
                  >
                    <RadioGroupItem
                      :id="`yarn-speaker-${decisionIndex}-action-${optionIndex}`"
                      :value="option.value"
                      :data-testid="reviewActionTestId(option.action)"
                      :data-target-speaker="option.targetSpeaker"
                      class="mt-0.5"
                    />
                    <span class="min-w-0">
                      <span class="flex flex-wrap items-center gap-1.5 text-sm font-medium">
                        {{ $t(option.labelKey, { target: option.targetSpeaker }) }}
                        <span
                          v-if="option.suggested"
                          class="rounded-full bg-primary/10 px-1.5 py-0.5 text-[10px] font-semibold text-primary"
                        >
                          {{ $t("project_settings.import.review_suggested") }}
                        </span>
                      </span>
                      <span class="mt-0.5 block text-xs text-muted-foreground">
                        {{ $t(option.descriptionKey, { target: option.targetSpeaker }) }}
                      </span>
                    </span>
                  </label>
                </RadioGroup>
              </li>
            </ul>
            <p
              v-if="importReview.speaker_decisions_truncated"
              data-testid="yarn-import-speaker-review-truncated"
              class="border-t border-border px-3 py-2 text-xs text-muted-foreground"
            >
              {{
                $t("project_settings.import.review_truncated_blocking", {
                  shown: speakerDecisions.length,
                  total: importReview.speaker_decision_count,
                })
              }}
            </p>
          </details>

          <div
            v-if="importReview.possible_speaker_alias_count > 0"
            id="yarn-import-alias-review"
            class="space-y-2 rounded-lg border border-amber-500/30 bg-amber-500/5 p-3"
          >
            <div>
              <h5 class="text-sm font-medium">
                {{ $t("project_settings.import.review_aliases_title") }}
                <span class="ml-1 text-xs font-normal text-muted-foreground">
                  ({{ importReview.possible_speaker_alias_count }})
                </span>
              </h5>
              <p class="text-xs text-muted-foreground">
                {{ $t("project_settings.import.review_aliases_description") }}
              </p>
            </div>
            <ul class="max-h-56 space-y-2 overflow-y-auto">
              <li
                v-for="alias in possibleSpeakerAliases"
                :key="`${alias.left}:${alias.right}`"
                data-testid="yarn-import-speaker-alias"
                class="rounded-md border border-border bg-background px-3 py-2"
              >
                <div class="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm">
                  <span class="font-medium">{{ alias.left }}</span>
                  <span class="text-xs text-muted-foreground">
                    {{ occurrencesLabel(alias.left_occurrences) }}
                  </span>
                  <ArrowLeftRight aria-hidden="true" class="size-3.5 text-muted-foreground" />
                  <span class="font-medium">{{ alias.right }}</span>
                  <span class="text-xs text-muted-foreground">
                    {{ occurrencesLabel(alias.right_occurrences) }}
                  </span>
                </div>
                <p class="mt-1 text-xs text-muted-foreground">
                  {{ reasonLabel(alias.evidence) }}
                </p>
                <p
                  data-testid="yarn-import-alias-mapping-status"
                  :data-mapping-enabled="aliasCanMap(alias)"
                  class="mt-2 text-xs font-medium"
                  :class="
                    aliasCanMap(alias) ? 'text-sky-700 dark:text-sky-300' : 'text-muted-foreground'
                  "
                >
                  {{
                    aliasCanMap(alias)
                      ? $t("project_settings.import.review_alias_mapping_available", {
                          alias: alias.less_frequent,
                          target: alias.more_frequent,
                        })
                      : $t("project_settings.import.review_alias_mapping_requires_target", {
                          target: alias.more_frequent,
                        })
                  }}
                </p>
              </li>
            </ul>
            <p
              v-if="importReview.possible_speaker_aliases_truncated"
              data-testid="yarn-import-alias-review-truncated"
              class="text-xs text-muted-foreground"
            >
              {{
                $t("project_settings.import.review_truncated_blocking", {
                  shown: possibleSpeakerAliases.length,
                  total: importReview.possible_speaker_alias_count,
                })
              }}
            </p>
          </div>

          <div
            v-if="!reviewStructurallyComplete"
            data-testid="yarn-import-review-incomplete"
            class="flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-sm text-destructive"
          >
            <AlertTriangle aria-hidden="true" class="mt-0.5 size-4 shrink-0" />
            <span>
              {{
                reviewIsTruncated
                  ? $t("project_settings.import.review_incomplete_truncated")
                  : $t("project_settings.import.review_incomplete")
              }}
            </span>
          </div>

          <div
            v-else-if="!allSpeakerDecisionsSelected"
            data-testid="yarn-import-review-undecided"
            class="flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-sm text-destructive"
          >
            <AlertTriangle aria-hidden="true" class="mt-0.5 size-4 shrink-0" />
            <span>{{ $t("project_settings.import.review_undecided") }}</span>
          </div>

          <div
            v-else-if="hasCompatibilityErrors"
            data-testid="yarn-import-review-compatibility-errors"
            class="flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-sm text-destructive"
          >
            <AlertTriangle aria-hidden="true" class="mt-0.5 size-4 shrink-0" />
            <span>
              {{
                issueSummaryMalformed
                  ? $t("project_settings.import.compatibility_summary_invalid")
                  : $t("project_settings.import.compatibility_errors_blocking")
              }}
            </span>
          </div>

          <div
            v-else-if="reviewMatchesResolution"
            data-testid="yarn-import-review-validated"
            class="flex items-start gap-2 rounded-lg border border-emerald-500/30 bg-emerald-500/5 p-3 text-sm text-emerald-700 dark:text-emerald-300"
          >
            <CheckCircle aria-hidden="true" class="mt-0.5 size-4 shrink-0" />
            <span>{{ $t("project_settings.import.review_validated") }}</span>
          </div>

          <div
            v-else
            data-testid="yarn-import-review-needs-validation"
            class="flex items-start gap-2 rounded-lg border border-sky-500/30 bg-sky-500/5 p-3 text-sm text-sky-700 dark:text-sky-300"
          >
            <Eye aria-hidden="true" class="mt-0.5 size-4 shrink-0" />
            <span>{{ $t("project_settings.import.review_needs_validation") }}</span>
          </div>
        </section>

        <div
          v-else
          data-testid="yarn-import-review-missing"
          class="flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-sm text-destructive"
        >
          <AlertTriangle aria-hidden="true" class="mt-0.5 size-4 shrink-0" />
          <span>{{ $t("project_settings.import.review_missing") }}</span>
        </div>

        <!-- Conflicts -->
        <div v-if="importState.preview?.has_conflicts" class="space-y-2">
          <h4 class="text-sm font-medium text-yellow-600 dark:text-yellow-500">
            {{ $t("project_settings.import.conflicts_title") }}
          </h4>
          <div
            v-for="([type, shortcuts], ci) in Object.entries(importState.preview.conflicts ?? {})"
            :key="ci"
            class="text-sm"
          >
            <span class="font-medium capitalize">{{ type }}:</span>
            <span class="text-muted-foreground">{{ shortcuts.join(", ") }}</span>
          </div>

          <div class="space-y-2">
            <Label>{{ $t("project_settings.import.conflict_strategy") }}</Label>
            <RadioGroup
              :model-value="importState.conflictStrategy"
              class="flex flex-col gap-1"
              @update:model-value="setStrategy"
            >
              <label
                v-for="opt in strategyOptions"
                :key="opt.value"
                class="flex cursor-pointer items-center gap-2 py-1"
              >
                <RadioGroupItem :value="opt.value" />
                <span class="text-sm">{{ opt.label }}</span>
              </label>
            </RadioGroup>
          </div>
        </div>

        <label
          v-if="
            reviewStructurallyComplete &&
            allSpeakerDecisionsSelected &&
            reviewRequiresAcknowledgement &&
            !reviewMatchesResolution
          "
          for="yarn-import-review-acknowledgement"
          class="flex cursor-pointer items-start gap-3 rounded-lg border border-amber-500/30 bg-amber-500/5 p-3"
        >
          <Checkbox
            id="yarn-import-review-acknowledgement"
            :model-value="reviewAcknowledged"
            required
            class="mt-0.5"
            @update:model-value="setReviewAcknowledged"
          />
          <span class="text-sm leading-5">
            <span>{{ $t("project_settings.import.review_acknowledgement") }}</span>
            <span v-if="hasCompatibilityWarnings" class="mt-1 block font-medium">
              {{ $t("project_settings.import.compatibility_acknowledgement") }}
            </span>
          </span>
        </label>

        <div class="flex items-center gap-2">
          <Button
            id="yarn-import-validate"
            variant="outline"
            size="sm"
            :disabled="!reviewCanValidate"
            @click="validateImportReview"
          >
            <Eye class="size-4" />
            {{ $t("project_settings.import.review_validate") }}
          </Button>
          <Button
            id="yarn-import-confirm"
            size="sm"
            :disabled="!reviewCanExecute"
            @click="executeImport"
          >
            <Upload class="size-4" />
            {{ $t("project_settings.import.import_button") }}
          </Button>
          <Button data-testid="yarn-import-reset" variant="ghost" size="sm" @click="resetImport">
            {{ $t("project_settings.import.cancel") }}
          </Button>
        </div>
      </div>

      <!-- Step: Queued / running -->
      <div v-if="importState.step === 'queued'" class="space-y-3">
        <div
          class="alert border-info/25 bg-info/10 text-sm text-info-content"
          data-testid="yarn-import-processing"
        >
          <Clock3 class="size-5 shrink-0 animate-pulse" />
          <div>
            <p class="font-medium">{{ $t("project_settings.import.processing") }}</p>
            <p class="text-xs opacity-75">
              {{ $t("project_settings.import.processing_description") }}
            </p>
          </div>
        </div>
      </div>

      <!-- Step: Done -->
      <div v-if="importState.step === 'done'" class="space-y-3">
        <div
          class="flex items-center gap-2 rounded-md border border-green-200 bg-green-50 p-3 text-sm text-green-800 dark:border-green-800 dark:bg-green-950 dark:text-green-200"
        >
          <CheckCircle class="size-5 shrink-0" />
          <span>{{ $t("project_settings.import.success") }}</span>
        </div>

        <Table v-if="entityCountRows.length">
          <TableHeader>
            <TableRow>
              <TableHead>{{ $t("project_settings.import.th_entity") }}</TableHead>
              <TableHead class="text-right">{{
                $t("project_settings.import.th_imported")
              }}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow v-for="row in entityCountRows" :key="row.entity">
              <TableCell class="capitalize">{{ row.entity }}</TableCell>
              <TableCell class="text-right">{{ row.count }}</TableCell>
            </TableRow>
          </TableBody>
        </Table>

        <Button data-testid="yarn-import-reset" variant="ghost" size="sm" @click="resetImport">
          {{ $t("project_settings.import.import_another") }}
        </Button>
      </div>

      <!-- Step: Error -->
      <div v-if="importState.step === 'error'" class="space-y-3">
        <div
          class="flex items-center gap-2 rounded-md border border-destructive/20 bg-destructive/10 p-3 text-sm text-destructive"
        >
          <AlertTriangle class="size-5 shrink-0" />
          <span>{{ importState.error }}</span>
        </div>

        <Button data-testid="yarn-import-reset" variant="ghost" size="sm" @click="resetImport">
          {{ $t("project_settings.import.try_again") }}
        </Button>
      </div>
    </template>

    <template v-else>
      <div
        class="flex items-center gap-2 rounded-md border bg-muted p-3 text-sm text-muted-foreground"
      >
        <Lock class="size-4 shrink-0" />
        <span>{{ $t("project_settings.import.no_permission") }}</span>
      </div>
    </template>
  </section>
</template>
