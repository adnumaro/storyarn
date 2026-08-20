<script setup lang="ts">
import { useLiveUpload, type UploadConfig } from "live_vue";
import {
  CheckCircle2,
  FileArchive,
  FileUp,
  FolderOpen,
  LoaderCircle,
  RotateCw,
  XCircle,
} from "@lucide/vue";
import { computed, ref, toRef, watch } from "vue";
import { useI18n } from "vue-i18n";
import LiveLink from "@components/navigation/LiveLink.vue";
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
import { formatBytes, type ByteCount } from "@shared/utils/storage-accounting";

type ImportStatus = "queued" | "running" | "retrying" | "completed" | "failed";

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

const { imports, quotaRejection, requestErrorCode, uploadErrorCode, uploadConfig } = defineProps<{
  imports: WorkspaceSnapshotImport[];
  quotaRejection: QuotaRejection | null;
  requestErrorCode: string | null;
  uploadErrorCode: string | null;
  uploadConfig: UploadConfig;
}>();

const { locale, t } = useI18n();
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
const canSubmit = computed(
  () => selectedEntry.value?.valid === true && !submitted.value && uploadErrorCode === null,
);

const visibleError = computed(() => {
  const code = uploadErrorCode ?? requestErrorCode;
  if (!code) return null;

  if (code === "file_too_large") return t("settings.workspace.imports.errors.file_too_large");
  if (code === "unauthorized") return t("settings.workspace.imports.errors.unauthorized");
  if (code === "invalid_file") return t("settings.workspace.imports.errors.invalid_file");
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
  return ["queued", "running", "retrying"].includes(item.status);
}

function phaseLabel(item: WorkspaceSnapshotImport): string {
  const knownPhases = new Set(["queued", "verifying", "materializing", "retrying"]);

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
</script>

<template>
  <div class="space-y-8">
    <header class="space-y-1.5">
      <h1 class="text-2xl font-bold tracking-tight text-foreground">
        {{ t("settings.workspace.imports.title") }}
      </h1>
      <p class="text-base text-muted-foreground">
        {{ t("settings.workspace.imports.subtitle") }}
      </p>
    </header>

    <section class="rounded-2xl border border-border bg-card p-5 shadow-sm sm:p-6">
      <div class="flex items-start gap-3">
        <span
          class="grid size-10 shrink-0 place-items-center rounded-lg bg-primary/10 text-primary"
        >
          <FileUp class="size-5" aria-hidden="true" />
        </span>
        <div class="min-w-0">
          <h2 class="text-lg font-semibold">
            {{ t("settings.workspace.imports.upload.title") }}
          </h2>
          <p class="mt-1 text-sm leading-relaxed text-muted-foreground">
            {{ t("settings.workspace.imports.upload.description") }}
          </p>
        </div>
      </div>

      <div class="mt-5 space-y-3">
        <div class="flex flex-wrap items-center gap-3">
          <Button
            id="workspace-snapshot-import-picker"
            type="button"
            variant="outline"
            size="sm"
            :disabled="submitted"
            @click="upload.showFilePicker()"
          >
            <FileArchive class="size-4" aria-hidden="true" />
            {{ t("settings.workspace.imports.upload.choose_file") }}
          </Button>
          <p class="text-xs text-muted-foreground">
            {{ t("settings.workspace.imports.upload.file_help") }}
          </p>
        </div>

        <div
          v-if="selectedEntry"
          data-testid="workspace-snapshot-import-file"
          class="rounded-lg border border-border bg-muted/25 p-3"
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
            class="mt-2 h-1.5"
            :aria-label="
              t('settings.workspace.imports.progress', { percent: selectedEntry.progress })
            "
          />
        </div>

        <p
          v-if="visibleError"
          data-testid="workspace-snapshot-import-error"
          role="alert"
          class="rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive"
        >
          {{ visibleError }}
        </p>

        <Button
          id="workspace-snapshot-import-submit"
          type="button"
          size="sm"
          :disabled="!canSubmit"
          @click="submitImport"
        >
          <LoaderCircle v-if="submitted" class="size-4 animate-spin" aria-hidden="true" />
          <FileUp v-else class="size-4" aria-hidden="true" />
          {{
            submitted
              ? t("settings.workspace.imports.upload.validating")
              : t("settings.workspace.imports.upload.submit")
          }}
        </Button>
      </div>
    </section>

    <section aria-labelledby="workspace-project-imports-heading">
      <h2 id="workspace-project-imports-heading" class="text-lg font-semibold">
        {{ t("settings.workspace.imports.history.title") }}
      </h2>

      <div v-if="imports.length === 0" class="py-12 text-center">
        <FolderOpen class="mx-auto mb-4 size-12 text-muted-foreground/30" aria-hidden="true" />
        <h3 class="mb-1 text-base font-semibold">
          {{ t("settings.workspace.imports.history.empty_title") }}
        </h3>
        <p class="text-sm text-muted-foreground">
          {{ t("settings.workspace.imports.history.empty_description") }}
        </p>
      </div>

      <ul v-else class="mt-4 space-y-3">
        <li
          v-for="item in imports"
          :key="item.id"
          :data-testid="`workspace-snapshot-import-${item.id}`"
          class="rounded-xl border border-border bg-card p-4 shadow-sm"
        >
          <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
            <div class="min-w-0 flex-1">
              <div class="flex flex-wrap items-center gap-2">
                <h3 class="min-w-0 truncate font-semibold text-foreground">
                  {{ importTitle(item) }}
                </h3>
                <Badge :variant="statusVariant(item.status)">
                  {{ statusLabel(item.status) }}
                </Badge>
              </div>
              <p
                v-if="item.fileName && item.fileName !== item.projectName"
                class="mt-1 truncate text-sm text-muted-foreground"
              >
                {{ item.fileName }}
              </p>
              <time
                v-if="item.insertedAt"
                :datetime="item.insertedAt"
                class="mt-1 block text-xs text-muted-foreground"
              >
                {{ formatDate(item.insertedAt) }}
              </time>

              <div
                v-if="activeImport(item)"
                class="mt-3 rounded-lg border border-primary/20 bg-primary/5 p-3"
              >
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
                  class="mt-2 h-1.5"
                  :aria-label="
                    t('settings.workspace.imports.progress', {
                      percent: progressPercent(item),
                    })
                  "
                />
                <p
                  v-if="item.status === 'retrying' && item.maxAttempts"
                  class="mt-2 text-xs text-muted-foreground"
                >
                  {{
                    t("settings.workspace.imports.attempt", {
                      attempt: item.attempt,
                      max: item.maxAttempts,
                    })
                  }}
                </p>
              </div>

              <p
                v-if="item.status === 'failed'"
                role="alert"
                class="mt-3 flex items-start gap-2 text-sm text-destructive"
              >
                <XCircle class="mt-0.5 size-4 shrink-0" aria-hidden="true" />
                {{ failureMessage(item) }}
              </p>
              <p
                v-else-if="item.status === 'completed'"
                class="mt-3 flex items-center gap-2 text-sm text-emerald-700 dark:text-emerald-400"
              >
                <CheckCircle2 class="size-4 shrink-0" aria-hidden="true" />
                {{ statusLabel(item.status) }}
              </p>
            </div>

            <Button v-if="item.status === 'completed' && item.projectPath" as-child size="sm">
              <LiveLink :to="item.projectPath">
                {{ t("settings.workspace.imports.open_project") }}
              </LiveLink>
            </Button>
          </div>
        </li>
      </ul>
    </section>

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
  </div>
</template>
