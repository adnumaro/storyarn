<script setup lang="ts">
import { BookOpenText, Download, Languages, LoaderCircle, Upload, X } from "lucide-vue-next";
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
const importResult = ref<{ ok: boolean; updated?: number; error?: string } | null>(null);
const active = computed(() => activeRun && ["queued", "running"].includes(activeRun.status));
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
  const content = await file.text();
  live.pushEvent(
    "import_csv",
    { content },
    (response: { ok?: boolean; updated?: number; error?: string }) => {
      importing.value = false;
      input.value = "";
      importResult.value = response?.ok
        ? { ok: true, updated: response.updated || 0 }
        : { ok: false, error: response?.error || "import_failed" };
    },
  );
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
    <span
      v-if="importResult"
      :class="['hidden text-xs lg:inline', importResult.ok ? 'text-success' : 'text-error']"
      role="status"
    >
      {{
        importResult.ok
          ? $t("localization.toolbar.imported_count", { count: importResult.updated })
          : $t("localization.toolbar.import_failed")
      }}
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
