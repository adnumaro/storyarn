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
import type { ImportPanelProps } from "@modules/projects/settings/export-import/types";

const { t } = useI18n();

const {
  projectId,
  canImport,
  currentUserId,
  importState,
  uploadConfig = null,
} = defineProps<
  ImportPanelProps & {
    uploadConfig?: UploadConfig | null;
  }
>();

const live = useLive();

const resume = useImportResume({
  projectId,
  currentUserId,
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

function handleUploadSubmit() {
  upload?.submit();
}

function setStrategy(strategy: string) {
  live.pushEvent("set_strategy", { strategy });
}

function resetImport() {
  review.clearSaveTimer();
  resume.dismissActiveAttempt();
  live.pushEvent("reset_import", {});
}

function formatFileSize(bytes: number) {
  if (bytes >= 1048576) return `${(bytes / 1048576).toFixed(1)} MB`;
  if (bytes >= 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${bytes} B`;
}
</script>

<template>
  <section class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm sm:p-6">
    <div class="mb-5 space-y-1">
      <h2 class="text-lg font-semibold">{{ $t("project_settings.import.title") }}</h2>
      <p class="text-sm text-base-content/65">
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
            :disabled="!review.canValidate.value"
            @click="review.validate"
          >
            <Eye class="size-4" />
            {{ $t("project_settings.import.review_validate") }}
          </Button>
          <Button
            id="yarn-import-confirm"
            size="sm"
            :disabled="!review.canExecute.value"
            @click="review.execute"
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
