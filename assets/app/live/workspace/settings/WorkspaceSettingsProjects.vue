<script setup lang="ts">
import { useLiveUpload, type UploadConfig } from "live_vue";
import { FolderOpen, LoaderCircle, Package, RotateCw } from "@lucide/vue";
import { computed, ref, toRef, watch } from "vue";
import { useI18n } from "vue-i18n";
import LiveLink from "@components/navigation/LiveLink.vue";
import {
  SettingsEmptyState,
  SettingsPage,
  SettingsRow,
  SettingsSection,
} from "@components/settings";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import { Progress } from "@components/ui/progress";
import { useLive } from "@shared/composables/useLive";
import WorkspaceDeletedProjectsList, {
  type DeletedProject,
} from "./WorkspaceDeletedProjectsList.vue";
import { formatBytes, type ByteCount } from "@shared/utils/storage-accounting";

type ImportStatus = "uploading" | "queued" | "running" | "retrying" | "completed" | "failed";

interface WorkspaceSnapshotImport {
  id: number;
  fileName: string | null;
  projectName: string | null;
  status: ImportStatus;
  phase: string | null;
  progressBytes: ByteCount;
  progressTotalBytes: ByteCount | null;
  attempt: number;
  maxAttempts: number | null;
  insertedAt: string | null;
  completedAt: string | null;
  failureCode: string | null;
  projectPath: string | null;
}

interface QuotaRejection {
  requiredBytes: ByteCount;
  availableBytes: ByteCount;
  limitBytes: ByteCount;
}

const {
  imports,
  quotaRejection,
  requestErrorCode,
  uploadErrorCode,
  uploadConfig,
  deletedProjects = [],
} = defineProps<{
  imports: WorkspaceSnapshotImport[];
  quotaRejection: QuotaRejection | null;
  requestErrorCode: string | null;
  uploadErrorCode: string | null;
  uploadConfig: UploadConfig;
  deletedProjects?: DeletedProject[];
}>();

const { locale, t } = useI18n();
const live = useLive();
const quotaOpen = ref(quotaRejection !== null);
const submitted = ref(false);

const upload = useLiveUpload(
  toRef(() => uploadConfig),
  {
    changeEvent: "validate_snapshot_zip",
    submitEvent: "import_snapshot",
  },
);

const selectedEntry = computed(() => upload.entries.value[0] ?? null);
const hasActiveImport = computed(() => imports.some(activeImport));
const canSubmit = computed(
  () =>
    selectedEntry.value?.valid === true &&
    !submitted.value &&
    !hasActiveImport.value &&
    uploadErrorCode === null,
);

const visibleError = computed(() => {
  const code = uploadErrorCode ?? requestErrorCode;
  if (!code) return null;

  if (code === "file_too_large") return t("settings.workspace.imports.errors.file_too_large");
  if (code === "unauthorized") return t("settings.workspace.imports.errors.unauthorized");
  if (code === "invalid_file") return t("settings.workspace.imports.errors.invalid_file");
  if (code === "in_progress") return t("settings.workspace.imports.errors.in_progress");
  if (code === "rate_limited") return t("settings.workspace.imports.errors.rate_limited");
  return t("settings.workspace.imports.errors.unavailable");
});

watch(
  () => quotaRejection,
  (rejection) => {
    if (rejection) quotaOpen.value = true;
  },
);

watch(
  () => uploadConfig.entries.length,
  (entryCount) => {
    if (entryCount === 0) submitted.value = false;
  },
);

function submitImport(): void {
  if (!canSubmit.value) return;
  submitted.value = true;
  upload.submit();
}

function statusLabel(status: ImportStatus): string {
  return t(`settings.workspace.imports.status.${status}`);
}

function statusVariant(status: ImportStatus): "default" | "secondary" | "destructive" | "outline" {
  if (status === "failed") return "destructive";
  if (status === "completed") return "outline";
  if (status === "retrying") return "secondary";
  return "default";
}

function activeImport(item: WorkspaceSnapshotImport): boolean {
  return ["uploading", "queued", "running", "retrying"].includes(item.status);
}

function phaseLabel(item: WorkspaceSnapshotImport): string {
  const knownPhases = new Set(["uploading", "queued", "verifying", "materializing", "retrying"]);

  if (item.phase && knownPhases.has(item.phase)) {
    return t(`settings.workspace.imports.phase.${item.phase}`);
  }

  return statusLabel(item.status);
}

function progressPercent(item: WorkspaceSnapshotImport): number | null {
  if (!item.progressTotalBytes || !/^\d+$/.test(item.progressTotalBytes)) return null;
  if (!/^\d+$/.test(item.progressBytes)) return null;

  const total = BigInt(item.progressTotalBytes);
  if (total <= 0n) return null;

  const completed = BigInt(item.progressBytes);
  const basisPoints = (completed * 10_000n) / total;
  return Math.min(Number(basisPoints) / 100, 100);
}

function formatDate(value: string | null): string {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";

  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function importTitle(item: WorkspaceSnapshotImport): string {
  return item.projectName || item.fileName || t("settings.workspace.imports.upload.title");
}

function importMeta(item: WorkspaceSnapshotImport): string {
  const parts = [formatDate(item.insertedAt)];
  if (item.fileName && item.fileName !== item.projectName) parts.push(item.fileName);
  if (item.progressTotalBytes) parts.push(formatBytes(item.progressTotalBytes, locale.value));
  return parts.filter((part) => part.length > 0).join(" · ");
}

function failureMessage(item: WorkspaceSnapshotImport): string {
  if (
    item.failureCode &&
    ["invalid_archive", "invalid_snapshot_archive", "invalid_snapshot_manifest"].includes(
      item.failureCode,
    )
  ) {
    return t("settings.workspace.imports.errors.invalid_file");
  }

  return t("settings.workspace.imports.errors.failed");
}

function cancelStoredUpload(id: number): void {
  window.dispatchEvent(
    new CustomEvent("storyarn:workspace-snapshot-upload-cancel", { detail: { import_id: id } }),
  );
  live.pushEvent("cancel_snapshot_upload", { id });
}

function cancelSelectedUpload(): void {
  if (!selectedEntry.value) return;
  window.dispatchEvent(
    new CustomEvent("storyarn:workspace-snapshot-upload-cancel", {
      detail: { ref: selectedEntry.value.ref },
    }),
  );
  upload.cancel(selectedEntry.value.ref);
}
</script>

<template>
  <SettingsPage :title="t('settings.workspace.projects.title')">
    <SettingsSection :title="t('settings.workspace.projects.import_section')">
      <SettingsRow
        :label="t('settings.workspace.imports.upload.title')"
        :hint="t('settings.workspace.imports.upload.description')"
      >
        <Button
          id="workspace-snapshot-import-picker"
          type="button"
          variant="outline"
          size="sm"
          :disabled="submitted || hasActiveImport"
          @click="upload.showFilePicker()"
        >
          {{ t("settings.workspace.imports.upload.choose_file") }}
        </Button>
        <Button
          id="workspace-snapshot-import-submit"
          type="button"
          size="sm"
          :disabled="!canSubmit"
          @click="submitImport"
        >
          <LoaderCircle v-if="submitted" class="size-4 animate-spin" aria-hidden="true" />
          {{
            submitted
              ? t("settings.workspace.imports.upload.validating")
              : t("settings.workspace.imports.upload.submit")
          }}
        </Button>
      </SettingsRow>

      <div
        v-if="selectedEntry"
        data-testid="workspace-snapshot-import-file"
        class="flex flex-col gap-2 px-4 py-3.5"
      >
        <div class="flex items-center justify-between gap-3 text-sm">
          <span class="min-w-0 truncate font-medium">{{ selectedEntry.client_name }}</span>
          <span class="shrink-0 tabular-nums text-muted-foreground">
            {{ formatBytes(String(selectedEntry.client_size), locale) }}
          </span>
        </div>
        <Progress
          v-if="submitted && selectedEntry.progress < 100"
          :model-value="selectedEntry.progress"
          class="h-1.5"
          :aria-label="
            t('settings.workspace.imports.progress', { percent: selectedEntry.progress })
          "
        />
        <div v-if="submitted" class="flex justify-end">
          <Button type="button" variant="ghost" size="sm" @click="cancelSelectedUpload">
            {{ t("settings.workspace.imports.cancel") }}
          </Button>
        </div>
      </div>

      <div
        v-if="hasActiveImport && !visibleError"
        class="px-4 py-3 text-[13px] text-muted-foreground"
      >
        {{ t("settings.workspace.imports.errors.in_progress") }}
      </div>

      <p
        v-if="visibleError"
        data-testid="workspace-snapshot-import-error"
        role="alert"
        class="px-4 py-3 text-[13px] text-destructive"
      >
        {{ visibleError }}
      </p>

      <template #footer>{{ t("settings.workspace.imports.upload.file_help") }}</template>
    </SettingsSection>

    <SettingsSection :title="t('settings.workspace.imports.history.title')">
      <SettingsEmptyState
        v-if="imports.length === 0"
        :icon="FolderOpen"
        :title="t('settings.workspace.imports.history.empty_title')"
        :text="t('settings.workspace.imports.history.empty_description')"
      />

      <div
        v-for="item in imports"
        :key="item.id"
        :data-testid="`workspace-snapshot-import-${item.id}`"
        class="flex flex-col gap-2.5 px-4 py-3.5"
      >
        <div
          class="grid grid-cols-1 items-center gap-x-6 gap-y-2 sm:grid-cols-[minmax(0,1fr)_auto]"
        >
          <div class="flex min-w-0 items-center gap-3">
            <Package class="size-[18px] shrink-0 text-muted-foreground" aria-hidden="true" />
            <div class="min-w-0">
              <div class="truncate font-medium">{{ importTitle(item) }}</div>
              <div class="text-[13px] text-muted-foreground">
                <template v-if="item.status === 'failed'">{{ failureMessage(item) }}</template>
                <template v-else>{{ importMeta(item) }}</template>
              </div>
            </div>
          </div>
          <div class="flex items-center justify-end gap-2">
            <Badge :variant="statusVariant(item.status)" aria-live="polite" aria-atomic="true">
              {{ statusLabel(item.status) }}
            </Badge>
            <Button
              v-if="item.status === 'uploading'"
              type="button"
              variant="ghost"
              size="sm"
              @click="cancelStoredUpload(item.id)"
            >
              {{ t("settings.workspace.imports.cancel") }}
            </Button>
            <Button
              v-else-if="item.status === 'completed' && item.projectPath"
              as-child
              variant="ghost"
              size="sm"
            >
              <LiveLink :to="item.projectPath">
                {{ t("settings.workspace.imports.open_project") }}
              </LiveLink>
            </Button>
          </div>
        </div>

        <template v-if="activeImport(item)">
          <div class="flex items-center justify-between gap-3 text-xs">
            <span class="inline-flex items-center gap-1.5 font-medium text-primary">
              <RotateCw
                v-if="item.status === 'retrying'"
                class="size-3.5 animate-spin"
                aria-hidden="true"
              />
              <LoaderCircle v-else class="size-3.5 animate-spin" aria-hidden="true" />
              {{ phaseLabel(item) }}
            </span>
            <span
              v-if="item.progressTotalBytes"
              class="shrink-0 tabular-nums text-muted-foreground"
            >
              {{ formatBytes(item.progressBytes, locale) }} /
              {{ formatBytes(item.progressTotalBytes, locale) }}
            </span>
          </div>
          <Progress
            v-if="progressPercent(item) !== null"
            :model-value="progressPercent(item) ?? 0"
            class="h-1.5"
            :aria-label="
              t('settings.workspace.imports.progress', { percent: progressPercent(item) })
            "
          />
          <p
            v-if="item.status === 'retrying' && item.maxAttempts"
            class="text-xs text-muted-foreground"
          >
            {{
              t("settings.workspace.imports.attempt", {
                attempt: item.attempt,
                max: item.maxAttempts,
              })
            }}
          </p>
        </template>
      </div>
    </SettingsSection>

    <WorkspaceDeletedProjectsList :deleted-projects="deletedProjects" />

    <Dialog :open="quotaOpen" @update:open="quotaOpen = $event">
      <DialogContent class="sm:max-w-md" data-testid="workspace-snapshot-quota-modal">
        <DialogHeader>
          <DialogTitle>{{ t("settings.workspace.imports.quota.title") }}</DialogTitle>
          <DialogDescription>
            {{ t("settings.workspace.imports.quota.description") }}
          </DialogDescription>
        </DialogHeader>

        <div v-if="quotaRejection" class="grid gap-2 sm:grid-cols-3">
          <div class="rounded-lg border border-border bg-muted/25 p-3">
            <div class="text-xs text-muted-foreground">
              {{ t("settings.workspace.imports.quota.required") }}
            </div>
            <div class="mt-1 font-semibold tabular-nums">
              {{ formatBytes(quotaRejection.requiredBytes, locale) }}
            </div>
          </div>
          <div class="rounded-lg border border-border bg-muted/25 p-3">
            <div class="text-xs text-muted-foreground">
              {{ t("settings.workspace.imports.quota.available") }}
            </div>
            <div class="mt-1 font-semibold tabular-nums">
              {{ formatBytes(quotaRejection.availableBytes, locale) }}
            </div>
          </div>
          <div class="rounded-lg border border-border bg-muted/25 p-3">
            <div class="text-xs text-muted-foreground">
              {{ t("settings.workspace.imports.quota.limit") }}
            </div>
            <div class="mt-1 font-semibold tabular-nums">
              {{ formatBytes(quotaRejection.limitBytes, locale) }}
            </div>
          </div>
        </div>

        <p class="text-sm text-muted-foreground">
          {{ t("settings.workspace.imports.quota.action") }}
        </p>

        <DialogFooter>
          <Button type="button" @click="quotaOpen = false">
            {{ t("settings.workspace.imports.quota.close") }}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </SettingsPage>
</template>
