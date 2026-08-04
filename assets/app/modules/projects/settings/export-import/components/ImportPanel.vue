<script setup lang="ts">
import { useLiveUpload, type UploadConfig } from "live_vue";
import { AlertTriangle, CheckCircle, Clock3, Eye, Lock, Upload } from "@lucide/vue";
import { computed, toRef } from "vue";
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
import ImportCompatibilitySummary from "@modules/projects/settings/export-import/components/ImportCompatibilitySummary.vue";
import YarnSpeakerReview from "@modules/projects/settings/export-import/components/YarnSpeakerReview.vue";
import { useImportResume } from "@modules/projects/settings/export-import/composables/useImportResume";
import { useYarnImportReview } from "@modules/projects/settings/export-import/composables/useYarnImportReview";
import type { ImportPanelProps } from "../types";

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

const upload = uploadConfig
  ? useLiveUpload(
      toRef(() => uploadConfig),
      {
        changeEvent: "validate_upload",
        submitEvent: "parse_import",
      },
    )
  : null;

const strategyOptions = computed(() => [
  { value: "skip", label: t("project_settings.import.strategy_skip") },
  { value: "overwrite", label: t("project_settings.import.strategy_overwrite") },
  { value: "rename", label: t("project_settings.import.strategy_rename") },
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

// Server rejections carry coarse reason codes; each maps to catalog copy so
// raw codes never render as UI text.
const reviewErrorMessage = computed(() => {
  const failure = review.transportError.value;
  if (!failure) return null;

  if (failure.operation === "save") return t("project_settings.import.review_error_save");

  switch (failure.reason) {
    case "stale":
      return t("project_settings.import.review_error_stale");
    case "unauthorized":
      return t("project_settings.import.review_error_unauthorized");
    default:
      return t("project_settings.import.review_error_failed");
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
  project_already_has_main_flow: "project_settings.import.errors.project_has_main_flow",
  duplicate_yarn_node_title: "project_settings.import.errors.unsupported_narrative",
  import_plan_has_errors: "project_settings.import.errors.unsupported_narrative",
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

  live.pushEvent("set_strategy", { attempt_id: attemptId, strategy });
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
</script>

<template>
  <section class="rounded-2xl border border-border bg-card p-5 shadow-sm sm:p-6">
    <div class="mb-5 space-y-1">
      <h2 class="text-lg font-semibold">{{ $t("project_settings.import.title") }}</h2>
      <p class="text-sm text-muted-foreground">
        {{ $t("project_settings.import.description") }}
      </p>
    </div>

    <template v-if="canImport">
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
          <p class="text-xs text-muted-foreground">
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

        <ImportCompatibilitySummary
          :summary="review.issueSummary.value"
          :warning-codes="importState.warningCodes ?? []"
        />

        <YarnSpeakerReview :review="review" />

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
            <Label id="yarn-import-conflict-strategy-label">
              {{ $t("project_settings.import.conflict_strategy") }}
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
                class="flex cursor-pointer items-center gap-2 py-1"
              >
                <RadioGroupItem :value="opt.value" />
                <span class="text-sm">{{ opt.label }}</span>
              </label>
            </RadioGroup>
          </div>
        </div>

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
            <span>{{ $t("project_settings.import.review_acknowledgement") }}</span>
            <span v-if="review.hasCompatibilityWarnings.value" class="mt-1 block font-medium">
              {{ $t("project_settings.import.compatibility_acknowledgement") }}
            </span>
          </span>
        </label>

        <div class="flex items-center gap-2">
          <Button
            id="yarn-import-validate"
            variant="outline"
            size="sm"
            :disabled="!review.canValidate.value || review.pendingOperation.value !== null"
            @click="review.validate"
          >
            <Eye class="size-4" />
            {{ $t("project_settings.import.review_validate") }}
          </Button>
          <Button
            id="yarn-import-confirm"
            size="sm"
            :disabled="!review.canExecute.value || review.pendingOperation.value !== null"
            @click="review.execute"
          >
            <Upload class="size-4" />
            {{ $t("project_settings.import.import_button") }}
          </Button>
          <Button data-testid="yarn-import-reset" variant="ghost" size="sm" @click="resetImport">
            {{ $t("project_settings.import.cancel") }}
          </Button>
        </div>

        <div
          v-if="reviewErrorMessage"
          data-testid="yarn-import-review-error"
          role="alert"
          class="flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-sm text-destructive"
        >
          <AlertTriangle class="mt-0.5 size-4 shrink-0" />
          <span>{{ reviewErrorMessage }}</span>
        </div>
      </div>

      <!-- Step: Queued / running -->
      <div v-if="importState.step === 'queued'" class="space-y-3">
        <div
          class="flex items-start gap-3 rounded-lg border border-sky-500/25 bg-sky-500/10 p-3 text-sm text-foreground"
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

        <Button
          v-if="canReset"
          data-testid="yarn-import-reset"
          variant="ghost"
          size="sm"
          @click="resetImport"
        >
          {{ $t("project_settings.import.cancel") }}
        </Button>
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
              <TableHead class="text-right">
                {{ $t("project_settings.import.th_imported") }}
              </TableHead>
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
          data-testid="yarn-import-terminal-error"
          class="flex items-center gap-2 rounded-md border border-destructive/20 bg-destructive/10 p-3 text-sm text-destructive"
        >
          <AlertTriangle class="size-5 shrink-0" />
          <span>{{ terminalErrorMessage }}</span>
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
