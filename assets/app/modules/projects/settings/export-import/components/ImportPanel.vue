<script setup lang="ts">
import { useLiveUpload, type UploadConfig } from "live_vue";
import {
  AlertTriangle,
  Check,
  CheckCircle,
  Clock3,
  FileText,
  Lock,
  ShieldCheck,
  Upload,
} from "@lucide/vue";
import { computed, ref, toRef, watch } from "vue";
import ConfirmDialog from "@components/ConfirmDialog.vue";
import LiveLink from "@components/navigation/LiveLink.vue";
import { SettingsRow, SettingsSection } from "@components/settings";
import { Button } from "@components/ui/button";
import { Checkbox } from "@components/ui/checkbox";
import { Label } from "@components/ui/label";
import { RadioGroup, RadioGroupItem } from "@components/ui/radio-group";
import { useI18n } from "vue-i18n";
import { useLive } from "@shared/composables/useLive";
import ImportCompatibilitySummary from "@modules/projects/settings/export-import/components/ImportCompatibilitySummary.vue";
import YarnSpeakerReview from "@modules/projects/settings/export-import/components/YarnSpeakerReview.vue";
import { useImportResume } from "@modules/projects/settings/export-import/composables/useImportResume";
import { useYarnImportReview } from "@modules/projects/settings/export-import/composables/useYarnImportReview";
import type {
  ImportConflictStrategy,
  ImportMode,
  ImportPanelProps,
  MainFlowImportOutcome,
} from "../types";

const { t } = useI18n();

const {
  canImport,
  resumeStorageKey,
  importState,
  uploadConfig = null,
} = defineProps<
  ImportPanelProps & {
    uploadConfig?: UploadConfig | null;
  }
>();

const live = useLive();

const resume = useImportResume({
  resumeStorageKey,
  canImport: () => canImport,
  importState: () => importState,
});

const review = useYarnImportReview({
  canImport: () => canImport,
  importState: () => importState,
});

interface ReplacementConfirmationIdentity {
  attemptId: number;
  decisionFingerprint: string;
}

const replaceDialogOpen = ref(false);
const replacementConfirmationIdentity = ref<ReplacementConfirmationIdentity | null>(null);

// Import state is server-authoritative. Unknown values fail closed to the
// additive presentation and are still rejected by the event contract.
const currentImportMode = computed<ImportMode>(() =>
  importState.importMode === "replace_project" ? "replace_project" : "additive",
);
const replacementSelected = computed(() => currentImportMode.value === "replace_project");
const currentConflictStrategy = computed<ImportConflictStrategy>(() => {
  if (importState.conflictStrategy === "skip" || importState.conflictStrategy === "overwrite") {
    return importState.conflictStrategy;
  }

  return "rename";
});
const skipUnavailable = computed(
  () =>
    importState.errorCode === "skip_conflict_ambiguous" ||
    importState.errorCode === "skip_variable_contract_mismatch",
);
const overwriteUnavailable = computed(
  () =>
    importState.preview?.has_conflicts === true ||
    importState.errorCode === "overwrite_conflict_requires_rename" ||
    skipUnavailable.value,
);
const strategyCorrectionRequired = computed(
  () => importState.errorCode === "overwrite_conflict_requires_rename" || skipUnavailable.value,
);
const showConflictStrategies = computed(
  () =>
    !replacementSelected.value &&
    (importState.preview?.has_conflicts === true || strategyCorrectionRequired.value),
);
const unsafeOverwriteSelected = computed(
  () =>
    !replacementSelected.value &&
    overwriteUnavailable.value &&
    currentConflictStrategy.value === "overwrite",
);
const unsafeSkipSelected = computed(
  () =>
    !replacementSelected.value && currentConflictStrategy.value === "skip" && skipUnavailable.value,
);
const invalidConflictStrategySelected = computed(
  () => unsafeOverwriteSelected.value || unsafeSkipSelected.value,
);
const mainFlowOutcome = computed<MainFlowImportOutcome | null>(() => {
  const preview = importState.preview?.main_flow;
  if (!preview || invalidConflictStrategySelected.value) return null;

  return replacementSelected.value
    ? preview.replace_project
    : preview.additive[currentConflictStrategy.value];
});
const mainFlowOutcomeKey = computed(() =>
  mainFlowOutcome.value ? `project_settings.import.main_flow_${mainFlowOutcome.value}` : null,
);
const recoverySnapshotUrl = computed(() =>
  replacementSelected.value && typeof importState.recoverySnapshotUrl === "string"
    ? importState.recoverySnapshotUrl
    : null,
);
const replacementEligible = computed(() => importState.replaceEligible);
const awaitingSnapshot = computed(() => importState.stage === "awaiting_snapshot");

function currentReplacementConfirmationIdentity(): ReplacementConfirmationIdentity | null {
  const attemptId = importState.attemptId;
  const decisionFingerprint = importState.preview?.import_review_resolution?.decision_fingerprint;

  if (
    typeof attemptId !== "number" ||
    !Number.isSafeInteger(attemptId) ||
    attemptId <= 0 ||
    typeof decisionFingerprint !== "string" ||
    decisionFingerprint.length === 0
  ) {
    return null;
  }

  return { attemptId, decisionFingerprint };
}

function sameReplacementConfirmationIdentity(
  left: ReplacementConfirmationIdentity | null,
  right: ReplacementConfirmationIdentity | null,
) {
  return (
    left !== null &&
    right !== null &&
    left.attemptId === right.attemptId &&
    left.decisionFingerprint === right.decisionFingerprint
  );
}

function closeReplacementDialog() {
  replaceDialogOpen.value = false;
  replacementConfirmationIdentity.value = null;
}

const upload = uploadConfig
  ? useLiveUpload(
      toRef(() => uploadConfig),
      {
        changeEvent: "validate_upload",
        submitEvent: "parse_import",
      },
    )
  : null;

const dragging = ref(false);

function onDrop(event: DragEvent) {
  dragging.value = false;
  if (event.dataTransfer && upload) upload.addFiles(event.dataTransfer);
}

const strategyOptions = computed(() => [
  {
    value: "skip",
    label: t("project_settings.import.strategy_skip"),
    disabled: skipUnavailable.value,
    description: null,
  },
  {
    value: "overwrite",
    label: t("project_settings.import.strategy_overwrite"),
    disabled: overwriteUnavailable.value,
    description: overwriteUnavailable.value
      ? t("project_settings.import.strategy_overwrite_unavailable")
      : null,
  },
  {
    value: "rename",
    label: t("project_settings.import.strategy_rename"),
    disabled: false,
    description: null,
  },
]);

const hasUploadEntries = computed(() => (upload?.entries.value?.length ?? 0) > 0);

const entityCountRows = computed(() => {
  const counts = importState.preview?.counts;
  if (!counts) return [];

  return [
    { entity: t("project_settings.import.entities.sheets"), count: counts.sheets || 0 },
    { entity: t("project_settings.import.entities.flows"), count: counts.flows || 0 },
    { entity: t("project_settings.import.entities.nodes"), count: counts.nodes || 0 },
    { entity: t("project_settings.import.entities.scenes"), count: counts.scenes || 0 },
    { entity: t("project_settings.import.entities.assets"), count: counts.assets || 0 },
  ].filter((row) => row.count > 0);
});

// A running import is materializing into the project. The server refuses to
// cancel it, so the panel does not offer a button that cannot work.
const canReset = computed(
  () => !importState.status || !["running", "retrying"].includes(importState.status),
);

const showAcknowledgement = computed(
  () =>
    review.structurallyComplete.value &&
    review.allDecisionsSelected.value &&
    review.requiresAcknowledgement.value &&
    !review.matchesResolution.value,
);

const RECOVERABLE_PREFLIGHT_ERROR_KEYS_BY_CODE: Readonly<Record<string, string>> = {
  import_replace_not_eligible: "project_settings.import.errors.preflight_not_eligible",
  invalid_import_snapshot_request: "project_settings.import.errors.preflight_snapshot_request",
  overwrite_conflict_requires_rename: "project_settings.import.errors.preflight_overwrite_conflict",
  replace_import_confirmation_required: "project_settings.import.errors.preflight_reconfirm",
  skip_conflict_ambiguous: "project_settings.import.errors.preflight_skip_conflict_ambiguous",
  skip_variable_contract_mismatch:
    "project_settings.import.errors.preflight_skip_variable_contract_mismatch",
  stale_import_mode: "project_settings.import.errors.preflight_mode_changed",
};

const preflightErrorMessage = computed(() => {
  if (importState.step !== "preview" || !importState.errorCode) return null;

  const key = RECOVERABLE_PREFLIGHT_ERROR_KEYS_BY_CODE[importState.errorCode];
  return key ? t(key) : null;
});

// Server rejections carry coarse reason codes; each maps to catalog copy so
// raw codes never render as UI text. Recoverable preflight failures are
// projected by the server on the preview itself, so avoid a second generic
// transport banner for the same failure.
const reviewErrorMessage = computed(() => {
  if (preflightErrorMessage.value) return null;

  const failure = review.transportError.value;
  if (!failure) return null;

  switch (failure.reason) {
    case "stale":
      return t("project_settings.import.review_error_stale");
    case "unauthorized":
      return t("project_settings.import.review_error_unauthorized");
    case "ownership_invariant_violation":
      return t("project_settings.import.review_error_ownership_invariant");
    default:
      return failure.operation === "save"
        ? t("project_settings.import.review_error_save")
        : t("project_settings.import.review_error_failed");
  }
});

const INVALID_FILE_ERROR_CODES = new Set([
  "archive_entry_too_large",
  "archive_expansion_ratio_exceeded",
  "archive_missing_yarn_files",
  "archive_too_large",
  "archive_too_many_entries",
  "duplicate_archive_entry",
  "empty_yarn_project",
  "entity_limits_exceeded",
  "file_too_large",
  "import_plan_too_large",
  "import_reference_contract_mismatch",
  "import_review_too_large",
  "invalid_archive",
  "invalid_archive_entry",
  "invalid_archive_path",
  "invalid_json",
  "invalid_json_structure",
  "invalid_text_encoding",
  "invalid_yarn_command",
  "missing_yarn_body_end",
  "missing_yarn_body_start",
  "missing_yarn_endif",
  "nested_archive_not_allowed",
  "unsupported_archive_entry",
  "unsupported_import_format",
  "unsupported_yarn_character_markup",
  "yarn_document_limit_exceeded",
  "yarn_node_description_too_long",
  "yarn_node_title_too_long",
  "yarn_statement_limit_exceeded",
]);

const TERMINAL_ERROR_KEYS_BY_CODE: Readonly<Record<string, string>> = {
  import_cancelled: "project_settings.import.errors.cancelled",
  import_expired: "project_settings.import.errors.expired",
  invalid_import_snapshot_identity: "project_settings.import.errors.snapshot_failed",
  pre_import_snapshot_capacity_unavailable: "project_settings.import.errors.snapshot_failed",
  pre_import_snapshot_request_failed: "project_settings.import.errors.snapshot_failed",
  pre_import_snapshot_unavailable: "project_settings.import.errors.snapshot_failed",
  pre_import_snapshot_verification_failed: "project_settings.import.errors.snapshot_failed",
  import_project_replacement_failed: "project_settings.import.errors.replacement_failed",
  overwrite_conflict_requires_rename: "project_settings.import.errors.overwrite_conflict",
  project_changed_since_import_snapshot: "project_settings.import.errors.project_changed",
  project_already_has_main_flow: "project_settings.import.errors.project_has_main_flow",
  skip_conflict_ambiguous: "project_settings.import.errors.skip_conflict_ambiguous",
  skip_variable_contract_mismatch: "project_settings.import.errors.skip_variable_contract_mismatch",
  duplicate_yarn_node_title: "project_settings.import.errors.unsupported_narrative",
  import_plan_has_errors: "project_settings.import.errors.unsupported_narrative",
  ownership_invariant_violation: "project_settings.import.errors.ownership_invariant",
  unauthorized: "project_settings.import.errors.unauthorized",
};

const terminalErrorMessage = computed(() => {
  const code = importState.errorCode;
  const directKey = code ? TERMINAL_ERROR_KEYS_BY_CODE[code] : undefined;

  if (directKey) return t(directKey);
  if (importState.status === "expired" && code) {
    return t("project_settings.import.errors.discarded");
  }
  if (importState.status === "expired") return t("project_settings.import.errors.preview_expired");
  if (code && INVALID_FILE_ERROR_CODES.has(code)) {
    return t("project_settings.import.errors.invalid_file");
  }

  return t("project_settings.import.errors.generic");
});

function handleUploadSubmit() {
  upload?.submit();
}

function setStrategy(strategy: string) {
  const attemptId = importState.attemptId;
  if (typeof attemptId !== "number" || !Number.isSafeInteger(attemptId)) return;
  if (strategy === "overwrite" && overwriteUnavailable.value) return;
  if (strategy === "skip" && skipUnavailable.value) return;

  live.pushEvent("set_strategy", { attempt_id: attemptId, strategy });
}

function setImportMode(importMode: unknown) {
  const attemptId = importState.attemptId;
  if (typeof attemptId !== "number" || !Number.isSafeInteger(attemptId)) return;
  if (importMode !== "additive" && importMode !== "replace_project") return;
  if (importMode === "replace_project" && !replacementEligible.value) return;

  live.pushEvent("set_import_mode", { attempt_id: attemptId, import_mode: importMode });
}

function startImport() {
  if (
    !review.canExecute.value ||
    review.pendingOperation.value !== null ||
    invalidConflictStrategySelected.value
  )
    return;

  if (replacementSelected.value) {
    if (!replacementEligible.value) return;

    const identity = currentReplacementConfirmationIdentity();
    if (!identity) return;

    replacementConfirmationIdentity.value = identity;
    replaceDialogOpen.value = true;
    return;
  }

  review.execute(false);
}

function confirmReplacement() {
  // Confirmation authorizes exactly the attempt and validated review that
  // opened the dialog. Cross-tab recovery or a new review resolution must
  // never inherit an already-open destructive confirmation.
  const openedFor = replacementConfirmationIdentity.value;
  const current = currentReplacementConfirmationIdentity();

  if (
    !replacementSelected.value ||
    !replacementEligible.value ||
    !sameReplacementConfirmationIdentity(openedFor, current)
  ) {
    closeReplacementDialog();
    return;
  }

  review.execute(true);
}

function resetImport() {
  // The durable browser reference is dropped only once the server confirms
  // the reset. A refused reset (the import is already running) keeps both the
  // reference and the reconcile backstop; the server explains it via flash.
  const attemptId = importState.attemptId;

  review.clearSaveTimer();

  if (attemptId === null) {
    // Pre-attempt validation/upload errors have no durable row to tombstone.
    // The explicit null still lets the server reject this reset as stale if a
    // cross-tab resume became authoritative before the event was processed.
    live.pushEvent("reset_import", { attempt_id: null });
    return;
  }

  if (typeof attemptId !== "number" || !Number.isSafeInteger(attemptId)) return;

  live.pushEvent("reset_import", { attempt_id: attemptId }, (reply) => {
    const resetAttemptId = reply.attempt_id;
    if (reply.ok === true && resetAttemptId === attemptId) {
      resume.dismissAttempt(attemptId);
    }
  });
}

function formatFileSize(bytes: number) {
  if (bytes >= 1048576) return `${(bytes / 1048576).toFixed(1)} MB`;
  if (bytes >= 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${bytes} B`;
}

// ---------------------------------------------------------------------------
// Step header: Upload → Review → Import
// ---------------------------------------------------------------------------
type StepKey = "upload" | "review" | "import";

const STEPS: StepKey[] = ["upload", "review", "import"];

const currentStepIndex = computed(() => {
  switch (importState.step) {
    case "upload":
      return 0;
    case "preview":
      return 1;
    default:
      return 2;
  }
});

function stepState(index: number): "done" | "current" | "todo" {
  if (importState.step === "done" && index === 2) return "done";
  if (index < currentStepIndex.value) return "done";
  if (index === currentStepIndex.value) return "current";
  return "todo";
}

watch(
  () =>
    [
      importState.attemptId,
      importState.preview?.import_review_resolution?.decision_fingerprint,
      importState.step,
      importState.importMode,
      importState.replaceEligible,
    ] as const,
  () => {
    const identityStillMatches = sameReplacementConfirmationIdentity(
      replacementConfirmationIdentity.value,
      currentReplacementConfirmationIdentity(),
    );

    if (
      importState.step !== "preview" ||
      !replacementSelected.value ||
      !replacementEligible.value ||
      (replaceDialogOpen.value && !identityStillMatches)
    ) {
      closeReplacementDialog();
    }
  },
);

watch(replaceDialogOpen, (open) => {
  if (!open) replacementConfirmationIdentity.value = null;
});
</script>

<template>
  <div id="import-workspace" class="flex flex-col gap-8" :data-step="importState.step">
    <ol class="flex items-center gap-2 text-[13px]" data-testid="import-steps">
      <template v-for="(step, index) in STEPS" :key="step">
        <li
          class="flex items-center gap-2"
          :class="stepState(index) === 'todo' ? 'text-muted-foreground' : ''"
          :data-step-state="stepState(index)"
          :aria-current="stepState(index) === 'current' ? 'step' : undefined"
        >
          <span
            :class="[
              'inline-flex size-[22px] items-center justify-center rounded-full text-xs',
              stepState(index) === 'todo'
                ? 'border border-border'
                : 'bg-primary font-semibold text-primary-foreground',
            ]"
          >
            <Check v-if="stepState(index) === 'done'" class="size-3" aria-hidden="true" />
            <template v-else>{{ index + 1 }}</template>
          </span>
          <span :class="stepState(index) === 'current' ? 'font-medium' : ''">
            {{ t(`project_settings.import.steps.${step}`) }}
          </span>
        </li>
        <li v-if="index < STEPS.length - 1" class="h-px flex-1 bg-border" aria-hidden="true" />
      </template>
    </ol>

    <template v-if="canImport">
      <!-- Step: Upload -->
      <SettingsSection
        v-if="importState.step === 'upload'"
        :title="t('project_settings.import.source_section')"
      >
        <div
          :class="[
            'm-4 flex flex-col items-center gap-1.5 rounded-md border border-dashed px-4 py-8 text-center transition-colors',
            dragging ? 'border-primary bg-primary/5' : 'border-input',
          ]"
          data-testid="yarn-import-dropzone"
          @dragover.prevent="dragging = true"
          @dragleave="dragging = false"
          @drop.prevent="onDrop"
        >
          <Upload class="size-[22px] text-muted-foreground" aria-hidden="true" />
          <div class="mt-1.5 font-medium">{{ t("project_settings.import.dropzone_title") }}</div>
          <div class="text-[13px] text-muted-foreground">
            {{ t("project_settings.import.dropzone_hint") }}
          </div>
          <div class="mt-2.5">
            <Button
              id="yarn-import-file-picker"
              type="button"
              variant="outline"
              size="sm"
              @click="upload?.showFilePicker()"
            >
              {{ t("project_settings.import.choose_file") }}
            </Button>
          </div>
        </div>

        <div
          v-for="entry in upload?.entries.value"
          :key="entry.ref"
          class="grid grid-cols-1 items-center gap-x-6 gap-y-2 px-4 py-3 sm:grid-cols-[minmax(0,1fr)_auto]"
          data-testid="yarn-import-selected-file"
        >
          <div class="flex min-w-0 items-center gap-3">
            <FileText class="size-4 shrink-0 text-muted-foreground" aria-hidden="true" />
            <div class="min-w-0">
              <span class="block truncate font-medium">{{ entry.client_name }}</span>
              <span class="text-[13px] text-muted-foreground">
                {{ formatFileSize(entry.client_size) }}
              </span>
            </div>
          </div>
          <div v-if="entry.errors.length" class="text-[13px] text-destructive">
            <div v-for="(err, ei) in entry.errors" :key="ei">{{ err }}</div>
          </div>
        </div>

        <SettingsRow :label="t('project_settings.import.upload_footer')" class="text-[13px]">
          <Button
            id="yarn-import-preview"
            type="button"
            size="sm"
            :disabled="!hasUploadEntries"
            @click="handleUploadSubmit"
          >
            {{ t("project_settings.import.upload_preview") }}
          </Button>
        </SettingsRow>
      </SettingsSection>

      <!-- Step: Review -->
      <template v-if="importState.step === 'preview'">
        <SettingsSection
          :title="t('project_settings.import.review_section')"
          :hint="t('project_settings.import.review_section_hint')"
        >
          <SettingsRow v-for="row in entityCountRows" :key="row.entity" :label="row.entity">
            <span class="tabular-nums">{{ row.count }}</span>
          </SettingsRow>

          <div class="px-4 py-3">
            <ImportCompatibilitySummary
              :summary="review.issueSummary.value"
              :warning-codes="importState.warningCodes ?? []"
            />
          </div>
        </SettingsSection>

        <SettingsSection
          v-if="importState.replaceEligible || mainFlowOutcomeKey || showConflictStrategies"
          :title="t('project_settings.import.options_section')"
        >
          <div
            v-if="importState.replaceEligible"
            data-testid="yarn-import-mode-selector"
            class="flex flex-col gap-3 px-4 py-3.5"
          >
            <div class="flex flex-col gap-0.5">
              <Label id="yarn-import-mode-label" class="font-medium">
                {{ t("project_settings.import.mode_title") }}
              </Label>
              <p class="text-[13px] text-muted-foreground">
                {{ t("project_settings.import.mode_description") }}
              </p>
            </div>

            <RadioGroup
              :model-value="currentImportMode"
              aria-labelledby="yarn-import-mode-label"
              class="grid gap-2"
              @update:model-value="setImportMode"
            >
              <label
                data-testid="yarn-import-mode-additive"
                class="flex cursor-pointer items-start gap-3 rounded-md border border-border bg-background p-3 transition-colors hover:border-primary/40"
              >
                <RadioGroupItem value="additive" class="mt-0.5" />
                <span class="space-y-1">
                  <span class="block text-sm font-medium">
                    {{ t("project_settings.import.mode_additive") }}
                  </span>
                  <span class="block text-[13px] leading-5 text-muted-foreground">
                    {{ t("project_settings.import.mode_additive_description") }}
                  </span>
                </span>
              </label>

              <label
                data-testid="yarn-import-mode-replace"
                class="flex items-start gap-3 rounded-md border bg-background p-3 transition-colors"
                :class="[
                  replacementEligible
                    ? 'cursor-pointer hover:border-destructive/50'
                    : 'cursor-not-allowed opacity-60',
                  replacementSelected && replacementEligible
                    ? 'border-destructive/50 bg-destructive/5'
                    : 'border-border',
                ]"
              >
                <RadioGroupItem
                  value="replace_project"
                  class="mt-0.5"
                  :disabled="!replacementEligible"
                  aria-describedby="yarn-import-mode-replace-description"
                />
                <span class="space-y-1">
                  <span class="flex items-center gap-1.5 text-sm font-medium">
                    <ShieldCheck class="size-4 text-destructive" aria-hidden="true" />
                    {{ t("project_settings.import.mode_replace") }}
                  </span>
                  <span
                    id="yarn-import-mode-replace-description"
                    class="block text-[13px] leading-5 text-muted-foreground"
                  >
                    {{ t("project_settings.import.mode_replace_description") }}
                  </span>
                </span>
              </label>
            </RadioGroup>
          </div>

          <div
            v-if="mainFlowOutcomeKey"
            data-testid="yarn-import-main-flow-outcome"
            role="status"
            aria-live="polite"
            aria-atomic="true"
            class="px-4 py-3.5"
          >
            <p class="font-medium">{{ t("project_settings.import.main_flow_title") }}</p>
            <p class="mt-1 text-[13px] leading-5 text-muted-foreground">
              {{ t(mainFlowOutcomeKey) }}
            </p>
            <p class="mt-1 text-[13px] leading-5 text-muted-foreground">
              {{ t("project_settings.import.main_flow_rechecked") }}
            </p>
          </div>

          <div v-if="showConflictStrategies" class="flex flex-col gap-3 px-4 py-3.5">
            <template v-if="importState.preview?.has_conflicts">
              <p class="font-medium text-amber-700 dark:text-amber-300">
                {{ t("project_settings.import.conflicts_title") }}
              </p>
              <div
                v-for="([type, shortcuts], ci) in Object.entries(
                  importState.preview.conflicts ?? {},
                )"
                :key="ci"
                class="text-[13px]"
              >
                <span class="font-medium capitalize">{{ type }}:</span>
                <span class="text-muted-foreground">{{ shortcuts.join(", ") }}</span>
              </div>
            </template>

            <div class="flex flex-col gap-2">
              <Label id="yarn-import-conflict-strategy-label" class="font-medium">
                {{ t("project_settings.import.conflict_strategy") }}
              </Label>
              <RadioGroup
                :model-value="importState.conflictStrategy"
                aria-labelledby="yarn-import-conflict-strategy-label"
                class="flex flex-col gap-1"
                @update:model-value="setStrategy"
              >
                <label
                  v-for="opt in strategyOptions"
                  :key="opt.value"
                  :data-testid="`yarn-import-strategy-${opt.value}`"
                  class="flex items-start gap-2 py-1"
                  :class="opt.disabled ? 'cursor-not-allowed opacity-60' : 'cursor-pointer'"
                >
                  <RadioGroupItem
                    :value="opt.value"
                    class="mt-0.5"
                    :disabled="opt.disabled"
                    :aria-describedby="
                      opt.description ? `yarn-import-strategy-${opt.value}-description` : undefined
                    "
                  />
                  <span class="space-y-0.5 text-sm">
                    <span class="block">{{ opt.label }}</span>
                    <span
                      v-if="opt.description"
                      :id="`yarn-import-strategy-${opt.value}-description`"
                      data-testid="yarn-import-strategy-overwrite-unavailable"
                      class="block text-[13px] leading-5 text-muted-foreground"
                    >
                      {{ opt.description }}
                    </span>
                  </span>
                </label>
              </RadioGroup>
            </div>
          </div>
        </SettingsSection>

        <YarnSpeakerReview :review="review" />

        <label
          v-if="showAcknowledgement"
          for="yarn-import-review-acknowledgement"
          class="flex cursor-pointer items-start gap-3 rounded-lg border border-amber-500/30 bg-amber-500/5 p-3"
        >
          <Checkbox
            id="yarn-import-review-acknowledgement"
            :model-value="review.acknowledged.value"
            required
            class="mt-0.5"
            @update:model-value="review.setAcknowledged"
          />
          <span class="text-sm leading-5">
            <span>{{ t("project_settings.import.review_acknowledgement") }}</span>
            <span v-if="review.hasCompatibilityWarnings.value" class="mt-1 block font-medium">
              {{ t("project_settings.import.compatibility_acknowledgement") }}
            </span>
          </span>
        </label>

        <div class="flex flex-wrap items-center gap-2">
          <Button
            id="yarn-import-validate"
            type="button"
            variant="outline"
            size="sm"
            :disabled="!review.canValidate.value || review.pendingOperation.value !== null"
            @click="review.validate"
          >
            {{ t("project_settings.import.review_validate") }}
          </Button>
          <Button
            id="yarn-import-confirm"
            type="button"
            size="sm"
            :disabled="
              !review.canExecute.value ||
              review.pendingOperation.value !== null ||
              invalidConflictStrategySelected
            "
            @click="startImport"
          >
            <Upload class="size-4" aria-hidden="true" />
            {{
              t(
                replacementSelected
                  ? "project_settings.import.replace_button"
                  : "project_settings.import.import_button",
              )
            }}
          </Button>
          <Button
            data-testid="yarn-import-reset"
            type="button"
            variant="ghost"
            size="sm"
            @click="resetImport"
          >
            {{ t("project_settings.import.cancel") }}
          </Button>
        </div>

        <div
          v-if="preflightErrorMessage"
          data-testid="yarn-import-preflight-error"
          role="alert"
          class="flex items-start gap-2 rounded-lg border border-amber-500/30 bg-amber-500/10 p-3 text-sm text-foreground"
        >
          <AlertTriangle
            class="mt-0.5 size-4 shrink-0 text-amber-600 dark:text-amber-400"
            aria-hidden="true"
          />
          <span>{{ preflightErrorMessage }}</span>
        </div>

        <div
          v-if="reviewErrorMessage"
          data-testid="yarn-import-review-error"
          role="alert"
          class="flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-sm text-destructive"
        >
          <AlertTriangle class="mt-0.5 size-4 shrink-0" aria-hidden="true" />
          <span>{{ reviewErrorMessage }}</span>
        </div>
      </template>

      <!-- Step: Queued / running -->
      <SettingsSection
        v-if="importState.step === 'queued'"
        :title="t('project_settings.import.status_section')"
      >
        <div
          v-if="awaitingSnapshot"
          class="flex items-start gap-3 px-4 py-3.5"
          data-testid="yarn-import-awaiting-snapshot"
        >
          <ShieldCheck
            class="mt-0.5 size-4 shrink-0 text-amber-600 dark:text-amber-400"
            aria-hidden="true"
          />
          <div>
            <p class="font-medium">{{ t("project_settings.import.snapshot_preparing") }}</p>
            <p class="text-[13px] leading-5 text-muted-foreground">
              {{ t("project_settings.import.snapshot_preparing_description") }}
            </p>
          </div>
        </div>

        <div v-else class="flex items-start gap-3 px-4 py-3.5" data-testid="yarn-import-processing">
          <Clock3 class="mt-0.5 size-4 shrink-0 animate-pulse text-primary" aria-hidden="true" />
          <div>
            <p class="font-medium">{{ t("project_settings.import.processing") }}</p>
            <p class="text-[13px] leading-5 text-muted-foreground">
              {{ t("project_settings.import.processing_description") }}
            </p>
          </div>
        </div>

        <template v-if="canReset" #footer>
          <Button
            data-testid="yarn-import-reset"
            type="button"
            variant="ghost"
            size="sm"
            class="h-auto p-0 text-xs"
            @click="resetImport"
          >
            {{ t("project_settings.import.cancel") }}
          </Button>
        </template>
      </SettingsSection>

      <!-- Step: Done -->
      <SettingsSection
        v-if="importState.step === 'done'"
        :title="t('project_settings.import.result_section')"
      >
        <div class="flex items-start gap-3 px-4 py-3.5 text-emerald-700 dark:text-emerald-300">
          <CheckCircle class="mt-0.5 size-4 shrink-0" aria-hidden="true" />
          <span class="text-sm">
            {{
              t(
                replacementSelected
                  ? "project_settings.import.replace_success"
                  : "project_settings.import.success",
              )
            }}
          </span>
        </div>

        <SettingsRow v-for="row in entityCountRows" :key="row.entity" :label="row.entity">
          <span class="tabular-nums">{{ row.count }}</span>
        </SettingsRow>

        <template #footer>
          <span class="flex flex-wrap items-center gap-3">
            <LiveLink
              v-if="recoverySnapshotUrl"
              :to="recoverySnapshotUrl"
              data-testid="yarn-import-recovery-snapshot-link"
              class="inline-flex items-center gap-1.5 font-medium text-primary transition-colors hover:text-primary/80"
            >
              <ShieldCheck class="size-3.5" aria-hidden="true" />
              {{ t("project_settings.import.recovery_snapshot_link") }}
            </LiveLink>
            <Button
              data-testid="yarn-import-reset"
              type="button"
              variant="ghost"
              size="sm"
              class="h-auto p-0 text-xs"
              @click="resetImport"
            >
              {{ t("project_settings.import.import_another") }}
            </Button>
          </span>
        </template>
      </SettingsSection>

      <!-- Step: Error -->
      <SettingsSection
        v-if="importState.step === 'error'"
        :title="t('project_settings.import.result_section')"
      >
        <div
          data-testid="yarn-import-terminal-error"
          class="flex items-start gap-3 px-4 py-3.5 text-sm text-destructive"
        >
          <AlertTriangle class="mt-0.5 size-4 shrink-0" aria-hidden="true" />
          <span>{{ terminalErrorMessage }}</span>
        </div>

        <template #footer>
          <span class="flex flex-wrap items-center gap-3">
            <LiveLink
              v-if="recoverySnapshotUrl"
              :to="recoverySnapshotUrl"
              data-testid="yarn-import-recovery-snapshot-link"
              class="inline-flex items-center gap-1.5 font-medium text-primary transition-colors hover:text-primary/80"
            >
              <ShieldCheck class="size-3.5" aria-hidden="true" />
              {{ t("project_settings.import.recovery_snapshot_link") }}
            </LiveLink>
            <Button
              data-testid="yarn-import-reset"
              type="button"
              variant="ghost"
              size="sm"
              class="h-auto p-0 text-xs"
              @click="resetImport"
            >
              {{ t("project_settings.import.try_again") }}
            </Button>
          </span>
        </template>
      </SettingsSection>
    </template>

    <SettingsSection v-else :title="t('project_settings.import.locked_section')" locked>
      <div class="flex items-start gap-3 px-4 py-3.5 text-sm text-muted-foreground">
        <Lock class="mt-0.5 size-4 shrink-0" aria-hidden="true" />
        <span>{{ t("project_settings.import.no_permission") }}</span>
      </div>
    </SettingsSection>

    <ConfirmDialog
      v-model:open="replaceDialogOpen"
      :title="t('project_settings.import.replace_confirm_title')"
      :description="t('project_settings.import.replace_confirm_description')"
      :confirm-text="t('project_settings.import.replace_confirm_action')"
      :cancel-text="t('project_settings.import.replace_confirm_cancel')"
      variant="destructive"
      :icon="AlertTriangle"
      @confirm="confirmReplacement"
    />
  </div>
</template>
