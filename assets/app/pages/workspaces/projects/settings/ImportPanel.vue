<script setup>
import { useLiveUpload } from "live_vue";
import { AlertTriangle, CheckCircle, Eye, Lock, Upload } from "lucide-vue-next";
import { computed, toRef } from "vue";
import { Button } from "@components/ui/button/index.js";
import { Label } from "@components/ui/label/index.js";
import { RadioGroup, RadioGroupItem } from "@components/ui/radio-group/index.js";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@components/ui/table/index.js";
import { useLive } from "@composables/useLive.js";

const { canEdit, importStep, importPreview, importResult, importError, conflictStrategy, uploadConfig } = defineProps({
  canEdit: { type: Boolean, required: true },
  importStep: { type: String, required: true },
  importPreview: { type: Object, default: null },
  importResult: { type: Object, default: null },
  importError: { type: String, default: null },
  conflictStrategy: { type: String, required: true },
  uploadConfig: { type: Object, default: null },
});

const live = useLive();

// --- Upload handling ---
const upload = uploadConfig
  ? useLiveUpload(toRef(() => uploadConfig), {
      changeEvent: "validate_upload",
      submitEvent: "parse_import",
    })
  : null;

// --- Computed ---
const strategyOptions = [
  { value: "skip", label: "Skip — keep existing, ignore conflicts" },
  { value: "overwrite", label: "Overwrite — replace existing entities" },
  { value: "rename", label: "Rename — import with a new shortcut" },
];

const hasUploadEntries = computed(() => {
  return upload?.entries.value?.length > 0;
});

const previewCountRows = computed(() => {
  if (!importPreview?.counts) return [];
  const counts = importPreview.counts;
  const rows = [
    { entity: "Sheets", count: counts.sheets || 0 },
    { entity: "Flows", count: counts.flows || 0 },
    { entity: "Nodes", count: counts.nodes || 0 },
    { entity: "Scenes", count: counts.scenes || 0 },
    { entity: "Screenplays", count: counts.screenplays || 0 },
    { entity: "Assets", count: counts.assets || 0 },
  ];
  return rows.filter((r) => r.count > 0);
});

const importResultRows = computed(() => {
  if (!importResult) return [];
  const result = importResult;
  const rows = [
    { entity: "Assets", items: result.assets },
    { entity: "Sheets", items: result.sheets },
    { entity: "Flows", items: result.flows },
    { entity: "Scenes", items: result.scenes },
    { entity: "Screenplays", items: result.screenplays },
    { entity: "Localization", items: result.localization },
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

function setStrategy(strategy) {
  live.pushEvent("set_strategy", { strategy });
}

function resetImport() {
  live.pushEvent("reset_import", {});
}

function handleUploadSubmit() {
  upload?.submit();
}

// --- Helpers ---
function formatFileSize(bytes) {
  if (bytes >= 1048576) return `${(bytes / 1048576).toFixed(1)} MB`;
  if (bytes >= 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${bytes} B`;
}

function formatImportCount(items) {
  if (Array.isArray(items)) return items.length;
  if (typeof items === "object") return JSON.stringify(items);
  return String(items);
}
</script>

<template>
  <section class="space-y-4">
    <h2 class="text-lg font-semibold">Import</h2>

    <template v-if="canEdit">
      <!-- Step: Upload -->
      <div v-if="importStep === 'upload'" class="space-y-3">
        <div class="space-y-2">
          <Label>Select a .storyarn.json file</Label>
          <Button variant="outline" size="sm" @click="upload?.showFilePicker()">
            Choose file...
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
          Upload &amp; Preview
        </Button>
      </div>

      <!-- Step: Preview -->
      <div v-if="importStep === 'preview'" class="space-y-4">
        <h3 class="text-base font-medium">Import preview</h3>

        <!-- Entity counts -->
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Entity</TableHead>
              <TableHead class="text-right">Count</TableHead>
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
        <div v-if="importPreview?.has_conflicts" class="space-y-2">
          <h4 class="text-sm font-medium text-yellow-600 dark:text-yellow-500">
            Shortcut conflicts detected
          </h4>
          <div
            v-for="([type, shortcuts], ci) in Object.entries(importPreview.conflicts)"
            :key="ci"
            class="text-sm"
          >
            <span class="font-medium capitalize">{{ type }}:</span>
            <span class="text-muted-foreground">{{ shortcuts.join(", ") }}</span>
          </div>

          <div class="space-y-2">
            <Label>Conflict resolution strategy</Label>
            <RadioGroup
              :model-value="conflictStrategy"
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
            Import
          </Button>
          <Button variant="ghost" size="sm" @click="resetImport"> Cancel </Button>
        </div>
      </div>

      <!-- Step: Done -->
      <div v-if="importStep === 'done'" class="space-y-3">
        <div
          class="flex items-center gap-2 rounded-md border border-green-200 bg-green-50 p-3 text-sm text-green-800 dark:border-green-800 dark:bg-green-950 dark:text-green-200"
        >
          <CheckCircle class="size-5 shrink-0" />
          <span>Import completed successfully!</span>
        </div>

        <Table v-if="importResultRows.length">
          <TableHeader>
            <TableRow>
              <TableHead>Entity</TableHead>
              <TableHead class="text-right">Imported</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow v-for="row in importResultRows" :key="row.entity">
              <TableCell class="capitalize">{{ row.entity }}</TableCell>
              <TableCell class="text-right">{{ formatImportCount(row.items) }}</TableCell>
            </TableRow>
          </TableBody>
        </Table>

        <Button variant="ghost" size="sm" @click="resetImport"> Import another </Button>
      </div>

      <!-- Step: Error -->
      <div v-if="importStep === 'error'" class="space-y-3">
        <div
          class="flex items-center gap-2 rounded-md border border-destructive/20 bg-destructive/10 p-3 text-sm text-destructive"
        >
          <AlertTriangle class="size-5 shrink-0" />
          <span>{{ importError }}</span>
        </div>

        <Button variant="ghost" size="sm" @click="resetImport"> Try again </Button>
      </div>
    </template>

    <template v-else>
      <div
        class="flex items-center gap-2 rounded-md border bg-muted p-3 text-sm text-muted-foreground"
      >
        <Lock class="size-4 shrink-0" />
        <span>You need edit permissions to import data.</span>
      </div>
    </template>
  </section>
</template>
