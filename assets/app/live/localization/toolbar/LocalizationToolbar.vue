<script setup lang="ts">
import {
  BookOpenText,
  CircleCheck,
  CircleX,
  Download,
  Languages,
  LoaderCircle,
  TriangleAlert,
  Upload,
  X,
} from "lucide-vue-next";
import { computed, ref } from "vue";
import { Button } from "@components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu";
import { useLive } from "@shared/composables/useLive.ts";

const {
  exportCsvUrl = null,
  exportXlsxUrl = null,
  glossaryUrl = null,
  hasProvider = false,
  canEdit = false,
  activeRun = null,
} = defineProps<{
  exportCsvUrl?: string | null;
  exportXlsxUrl?: string | null;
  glossaryUrl?: string | null;
  hasProvider?: boolean;
  canEdit?: boolean;
  activeRun?: {
    id: number;
    status: string;
    total: number;
    processed: number;
    translated: number;
    failed: number;
    error?: string | null;
  } | null;
}>();

const live = useLive();
const translating = ref(false);
const importing = ref(false);
const importInput = ref<HTMLInputElement | null>(null);

type ImportRowError = { line: number; error: string };
type ImportResult = {
  ok: boolean;
  updated?: number;
  skipped?: number;
  errors?: ImportRowError[];
  error?: string;
};

const maxVisibleImportErrors = 20;
const importResult = ref<ImportResult | null>(null);
const active = computed(() => activeRun && ["queued", "running"].includes(activeRun.status));
const importErrors = computed(() => importResult.value?.errors || []);
const importIssueCount = computed(
  () => (importResult.value?.skipped || 0) + importErrors.value.length,
);
const visibleImportErrors = computed(() => importErrors.value.slice(0, maxVisibleImportErrors));
const hiddenImportErrorCount = computed(() =>
  Math.max(0, importErrors.value.length - maxVisibleImportErrors),
);
const progress = computed(() => {
  if (!activeRun || activeRun.total === 0) return 0;
  return Math.min(100, Math.round((activeRun.processed / activeRun.total) * 100));
});

function translateBatch(): void {
  translating.value = true;
  live.pushEvent("translate_batch", {}, () => {
    translating.value = false;
  });
}

function cancelRun(): void {
  if (!activeRun) return;
  live.pushEvent("cancel_translation_run", { id: activeRun.id });
}

async function importCsv(event: Event): Promise<void> {
  const input = event.target as HTMLInputElement;
  const file = input.files?.[0];
  if (!file) return;

  importing.value = true;
  importResult.value = null;
  let content: string;

  try {
    content = await file.text();
  } catch {
    importing.value = false;
    input.value = "";
    importResult.value = { ok: false, error: "import_failed" };
    return;
  }

  live.pushEvent(
    "import_csv",
    { content },
    (response: Record<string, unknown>) => {
      const result = response as ImportResult;
      importing.value = false;
      input.value = "";
      importResult.value = result.ok
        ? {
            ok: true,
            updated: result.updated || 0,
            skipped: result.skipped || 0,
            errors: result.errors || [],
          }
        : { ok: false, error: result.error || "import_failed" };
    },
    () => {
      importing.value = false;
      input.value = "";
      importResult.value = { ok: false, error: "import_failed" };
    },
  );
}

function importRowErrorKey(error: string): string {
  const code = error.replace(/^:/, "");

  if (["stale_source", "invalid_id", "text_not_found"].includes(code)) {
    return `localization.toolbar.import_error_${code}`;
  }

  return "localization.toolbar.import_error_unknown";
}

function importFailureKey(error?: string): string {
  if (error === "file_too_large" || error === "unauthorized") {
    return `localization.toolbar.import_${error}`;
  }

  return "localization.toolbar.import_failed";
}
</script>

<template>
  <div class="flex items-center gap-1 px-1.5 py-1 surface-panel">
    <div
      v-if="activeRun"
      class="hidden min-w-48 items-center gap-2 rounded-lg border border-base-300 bg-base-100 px-2.5 py-1.5 lg:flex"
      role="status"
      aria-live="polite"
    >
      <LoaderCircle v-if="active" class="size-3.5 animate-spin text-primary" />
      <div class="min-w-0 flex-1">
        <div class="flex items-center justify-between gap-3 text-xs font-medium">
          <span>{{ $t(`localization.toolbar.run_${activeRun.status}`) }}</span>
          <span class="tabular-nums text-base-content/60">{{ progress }}%</span>
        </div>
        <progress class="progress progress-primary h-1 w-full" :value="progress" max="100" />
      </div>
      <button
        v-if="active && canEdit"
        type="button"
        class="btn btn-ghost btn-xs btn-square"
        :aria-label="$t('localization.toolbar.cancel')"
        @click="cancelRun"
      >
        <X class="size-3.5" />
      </button>
    </div>

    <DropdownMenu v-if="exportCsvUrl || exportXlsxUrl">
      <DropdownMenuTrigger as-child>
        <Button variant="ghost" size="sm" class="gap-1.5">
          <Download class="size-4" />
          <span class="hidden xl:inline">{{ $t("localization.toolbar.export") }}</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem v-if="exportXlsxUrl" as-child>
          <a :href="exportXlsxUrl" data-live-link-exempt="download">{{
            $t("localization.toolbar.excel")
          }}</a>
        </DropdownMenuItem>
        <DropdownMenuItem v-if="exportCsvUrl" as-child>
          <a :href="exportCsvUrl" data-live-link-exempt="download">{{
            $t("localization.toolbar.csv")
          }}</a>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>

    <Button v-if="glossaryUrl" variant="ghost" size="sm" class="gap-1.5" as-child>
      <a :href="glossaryUrl" data-phx-link="redirect" data-phx-link-state="push">
        <BookOpenText class="size-4" />
        <span class="hidden xl:inline">{{ $t("localization.toolbar.glossary") }}</span>
      </a>
    </Button>

    <input
      ref="importInput"
      type="file"
      accept=".csv,text/csv"
      class="hidden"
      @change="importCsv"
    />
    <Button
      v-if="canEdit"
      variant="ghost"
      size="sm"
      class="gap-1.5"
      :disabled="importing"
      @click="importInput?.click()"
    >
      <LoaderCircle v-if="importing" class="size-4 animate-spin" />
      <Upload v-else class="size-4" />
      <span class="hidden xl:inline">{{ $t("localization.toolbar.import_csv") }}</span>
    </Button>
    <details
      v-if="importResult?.ok && importIssueCount > 0"
      class="dropdown dropdown-end"
      data-testid="localization-import-result"
    >
      <summary class="btn btn-ghost btn-sm gap-1.5 text-warning">
        <TriangleAlert class="size-4 shrink-0" />
        <span class="hidden lg:inline">
          {{
            $t("localization.toolbar.imported_with_issues", {
              count: importResult.updated,
              issues: importIssueCount,
            })
          }}
        </span>
        <span class="sr-only lg:hidden">
          {{
            $t("localization.toolbar.imported_with_issues", {
              count: importResult.updated,
              issues: importIssueCount,
            })
          }}
        </span>
      </summary>
      <span class="sr-only" role="status" aria-live="polite">
        {{
          $t("localization.toolbar.imported_with_issues", {
            count: importResult.updated,
            issues: importIssueCount,
          })
        }}
      </span>

      <div
        class="dropdown-content z-50 mt-2 w-80 rounded-box border border-base-300 bg-base-100 p-3 shadow-xl"
      >
        <p class="font-semibold text-base-content">
          {{ $t("localization.toolbar.import_summary_title") }}
        </p>
        <dl class="mt-3 grid grid-cols-3 gap-2 text-center text-xs">
          <div class="rounded-lg bg-success/10 px-2 py-2">
            <dt class="text-base-content/60">
              {{ $t("localization.toolbar.import_summary_updated") }}
            </dt>
            <dd class="mt-0.5 font-semibold tabular-nums text-success">
              {{ importResult.updated || 0 }}
            </dd>
          </div>
          <div class="rounded-lg bg-base-200 px-2 py-2">
            <dt class="text-base-content/60">
              {{ $t("localization.toolbar.import_summary_skipped") }}
            </dt>
            <dd class="mt-0.5 font-semibold tabular-nums">
              {{ importResult.skipped || 0 }}
            </dd>
          </div>
          <div class="rounded-lg bg-error/10 px-2 py-2">
            <dt class="text-base-content/60">
              {{ $t("localization.toolbar.import_summary_errors") }}
            </dt>
            <dd class="mt-0.5 font-semibold tabular-nums text-error">
              {{ importErrors.length }}
            </dd>
          </div>
        </dl>

        <p v-if="(importResult.skipped || 0) > 0" class="mt-3 text-xs text-base-content/60">
          {{ $t("localization.toolbar.import_skipped_help") }}
        </p>

        <div v-if="importErrors.length > 0" class="mt-3 border-t border-base-300 pt-2">
          <p class="mb-1.5 text-xs font-medium text-base-content/70">
            {{ $t("localization.toolbar.import_error_details") }}
          </p>
          <div class="max-h-52 space-y-1 overflow-y-auto pr-1">
            <div
              v-for="rowError in visibleImportErrors"
              :key="`${rowError.line}-${rowError.error}`"
              class="flex gap-2 rounded-md bg-error/5 px-2 py-1.5 text-xs"
            >
              <span class="shrink-0 font-medium tabular-nums text-error">
                {{ $t("localization.toolbar.import_error_line", { line: rowError.line }) }}
              </span>
              <span class="text-base-content/70">
                {{ $t(importRowErrorKey(rowError.error)) }}
              </span>
            </div>
          </div>
          <p v-if="hiddenImportErrorCount > 0" class="mt-2 text-xs text-base-content/50">
            {{
              $t("localization.toolbar.import_more_errors", {
                count: hiddenImportErrorCount,
              })
            }}
          </p>
        </div>
      </div>
    </details>

    <span
      v-else-if="importResult?.ok"
      class="flex items-center gap-1 text-xs text-success"
      role="status"
      aria-live="polite"
      data-testid="localization-import-result"
    >
      <CircleCheck class="size-4 shrink-0" />
      <span class="hidden lg:inline">
        {{ $t("localization.toolbar.imported_count", { count: importResult.updated }) }}
      </span>
      <span class="sr-only lg:hidden">
        {{ $t("localization.toolbar.imported_count", { count: importResult.updated }) }}
      </span>
    </span>

    <span
      v-else-if="importResult"
      class="flex items-center gap-1 text-xs text-error"
      role="status"
      aria-live="polite"
      data-testid="localization-import-result"
    >
      <CircleX class="size-4 shrink-0" />
      <span class="hidden lg:inline">{{ $t(importFailureKey(importResult.error)) }}</span>
      <span class="sr-only lg:hidden">{{ $t(importFailureKey(importResult.error)) }}</span>
    </span>

    <Button
      v-if="hasProvider"
      size="sm"
      :disabled="translating || !!active || !canEdit"
      class="gap-1.5"
      @click="translateBatch"
    >
      <Languages class="size-4" />
      <span class="hidden xl:inline">{{
        translating
          ? $t("localization.toolbar.translating")
          : $t("localization.toolbar.translate_all")
      }}</span>
    </Button>
  </div>
</template>
