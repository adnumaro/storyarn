<script setup lang="ts">
import { useLiveUpload, type UploadConfig } from "live_vue";
import { AlertTriangle, CheckCircle, Eye, Lock, Upload } from "lucide-vue-next";
import { computed, toRef } from "vue";
import { Button } from "@components/ui/button";
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

const { t } = useI18n();

interface ImportPreview {
  counts?: Record<string, number>;
  has_conflicts?: boolean;
  conflicts?: Record<string, string[]>;
}

interface ImportResult {
  assets?: unknown[];
  sheets?: unknown[];
  flows?: unknown[];
  scenes?: unknown[];
  screenplays?: unknown[];
  localization?: unknown[];
}

interface ImportState {
  step: string;
  preview?: ImportPreview;
  result?: ImportResult;
  error?: string;
  conflictStrategy?: string;
}

const {
  canEdit,
  importState,
  uploadConfig = null,
} = defineProps<{
  canEdit: boolean;
  importState: ImportState;
  uploadConfig?: UploadConfig | null;
}>();

const live = useLive();

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

const previewCountRows = computed(() => {
  if (!importState.preview?.counts) return [];
  const counts = importState.preview.counts;
  const rows = [
    { entity: t("project_settings.import.entities.sheets"), count: counts.sheets || 0 },
    { entity: t("project_settings.import.entities.flows"), count: counts.flows || 0 },
    { entity: t("project_settings.import.entities.nodes"), count: counts.nodes || 0 },
    { entity: t("project_settings.import.entities.scenes"), count: counts.scenes || 0 },
    { entity: t("project_settings.import.entities.screenplays"), count: counts.screenplays || 0 },
    { entity: t("project_settings.import.entities.assets"), count: counts.assets || 0 },
  ];
  return rows.filter((r) => r.count > 0);
});

const importResultRows = computed(() => {
  if (!importState.result) return [];
  const result = importState.result;
  const rows = [
    { entity: t("project_settings.import.entities.assets"), items: result.assets },
    { entity: t("project_settings.import.entities.sheets"), items: result.sheets },
    { entity: t("project_settings.import.entities.flows"), items: result.flows },
    { entity: t("project_settings.import.entities.scenes"), items: result.scenes },
    { entity: t("project_settings.import.entities.screenplays"), items: result.screenplays },
    { entity: t("project_settings.import.entities.localization"), items: result.localization },
  ];
  return rows.filter(
    (r) =>
      r.items != null &&
      !(Array.isArray(r.items) && r.items.length === 0) &&
      !(typeof r.items === "object" && Object.keys(r.items).length === 0),
  );
});

// --- Event handlers ---
function executeImport() {
  live.pushEvent("execute_import", {});
}

function setStrategy(strategy: string) {
  live.pushEvent("set_strategy", { strategy });
}

function resetImport() {
  live.pushEvent("reset_import", {});
}

function handleUploadSubmit() {
  upload?.submit();
}

// --- Helpers ---
function formatFileSize(bytes: number) {
  if (bytes >= 1048576) return `${(bytes / 1048576).toFixed(1)} MB`;
  if (bytes >= 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${bytes} B`;
}

function formatImportCount(items: unknown[] | Record<string, string | number> | string | number) {
  if (Array.isArray(items)) return items.length;
  if (typeof items === "object") return JSON.stringify(items);
  return String(items);
}
</script>

<template>
  <section class="space-y-4">
    <h2 class="text-lg font-semibold">{{ $t("project_settings.import.title") }}</h2>

    <template v-if="canEdit">
      <!-- Step: Upload -->
      <div v-if="importState.step === 'upload'" class="space-y-3">
        <div class="space-y-2">
          <Label>{{ $t("project_settings.import.select_file") }}</Label>
          <Button variant="outline" size="sm" @click="upload?.showFilePicker()">
            {{ $t("project_settings.import.choose_file") }}
          </Button>
        </div>

        <div v-for="entry in upload?.entries.value" :key="entry.ref" class="text-sm">
          <span>{{ entry.client_name }}</span>
          <span class="text-muted-foreground"> ({{ formatFileSize(entry.client_size) }}) </span>
          <div v-for="(err, ei) in entry.errors" :key="ei" class="text-sm text-destructive">
            {{ err }}
          </div>
        </div>

        <Button size="sm" :disabled="!hasUploadEntries" @click="handleUploadSubmit">
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
            <TableRow v-for="row in previewCountRows" :key="row.entity">
              <TableCell class="capitalize">{{ row.entity }}</TableCell>
              <TableCell class="text-right">{{ row.count }}</TableCell>
            </TableRow>
          </TableBody>
        </Table>

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

        <div class="flex items-center gap-2">
          <Button size="sm" @click="executeImport">
            <Upload class="size-4" />
            {{ $t("project_settings.import.import_button") }}
          </Button>
          <Button variant="ghost" size="sm" @click="resetImport">
            {{ $t("project_settings.import.cancel") }}
          </Button>
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

        <Table v-if="importResultRows.length">
          <TableHeader>
            <TableRow>
              <TableHead>{{ $t("project_settings.import.th_entity") }}</TableHead>
              <TableHead class="text-right">{{
                $t("project_settings.import.th_imported")
              }}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow v-for="row in importResultRows" :key="row.entity">
              <TableCell class="capitalize">{{ row.entity }}</TableCell>
              <TableCell class="text-right">{{ formatImportCount(row.items ?? []) }}</TableCell>
            </TableRow>
          </TableBody>
        </Table>

        <Button variant="ghost" size="sm" @click="resetImport">
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

        <Button variant="ghost" size="sm" @click="resetImport">
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
