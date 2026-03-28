<script setup>
import { useLiveUpload } from "live_vue";
import {
	AlertTriangle,
	CheckCircle,
	CircleX,
	Download,
	Eye,
	Info,
	Lock,
	ShieldCheck,
	Upload,
} from "lucide-vue-next";
import { computed, toRef } from "vue";
import { Badge } from "@/vue/components/ui/badge";
import { Button } from "@/vue/components/ui/button";
import { Checkbox } from "@/vue/components/ui/checkbox";
import { Label } from "@/vue/components/ui/label";
import { RadioGroup, RadioGroupItem } from "@/vue/components/ui/radio-group";
import { Separator } from "@/vue/components/ui/separator";
import {
	Table,
	TableBody,
	TableCell,
	TableHead,
	TableHeader,
	TableRow,
} from "@/vue/components/ui/table";
import { useLive } from "@/vue/composables/useLive";

const props = defineProps({
	// Export props
	formats: { type: Array, required: true },
	selectedFormat: { type: String, required: true },
	selectedExtension: { type: String, required: true },
	supportedSections: { type: Array, required: true },
	sections: { type: Array, required: true },
	entityCounts: { type: Object, default: () => ({}) },
	assetMode: { type: String, required: true },
	validateBeforeExport: { type: Boolean, required: true },
	prettyPrint: { type: Boolean, required: true },
	validationResult: { type: Object, default: null },
	exportDownloadUrl: { type: String, required: true },

	// Import props
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
const upload = props.uploadConfig
	? useLiveUpload(toRef(props, "uploadConfig"), {
			changeEvent: "validate_upload",
			submitEvent: "parse_import",
		})
	: null;

// --- Computed ---
const sectionLabels = [
	{ key: "sheets", label: "Sheets" },
	{ key: "flows", label: "Flows" },
	{ key: "scenes", label: "Scenes" },
	{ key: "screenplays", label: "Screenplays" },
	{ key: "localization", label: "Localization" },
];

const assetModeOptions = [
	{ value: "references", label: "References only (URLs in output)" },
	{ value: "embedded", label: "Embedded (Base64 — larger file)" },
	{ value: "bundled", label: "Bundled (ZIP with assets folder)" },
];

const strategyOptions = [
	{ value: "skip", label: "Skip — keep existing, ignore conflicts" },
	{ value: "overwrite", label: "Overwrite — replace existing entities" },
	{ value: "rename", label: "Rename — import with a new shortcut" },
];

const sectionsSet = computed(() => new Set(props.sections));
const supportedSet = computed(() => new Set(props.supportedSections));

const hasUploadEntries = computed(() => {
	return upload?.entries.value?.length > 0;
});

const previewCountRows = computed(() => {
	if (!props.importPreview?.counts) return [];
	const counts = props.importPreview.counts;
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
	if (!props.importResult) return [];
	const result = props.importResult;
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
function setFormat(format) {
	live.pushEvent("set_format", { format });
}

function toggleSection(section) {
	live.pushEvent("toggle_section", { section });
}

function setAssetMode(mode) {
	live.pushEvent("set_asset_mode", { mode });
}

function toggleOption(option) {
	live.pushEvent("toggle_option", { option });
}

function validateExport() {
	live.pushEvent("validate_export", {});
}

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

function validationStatusLabel(status) {
	const labels = { passed: "Passed", warnings: "Warnings", errors: "Errors" };
	return labels[status] || status;
}

function validationBadgeVariant(status) {
	if (status === "passed") return "default";
	if (status === "warnings") return "secondary";
	if (status === "errors") return "destructive";
	return "outline";
}
</script>

<template>
  <div class="space-y-8">
    <!-- ===== Export section ===== -->
    <section class="space-y-5">
      <h2 class="text-lg font-semibold">Export</h2>

      <!-- Format selector -->
      <div class="space-y-2">
        <Label class="text-sm font-medium">Format</Label>
        <RadioGroup
          :model-value="selectedFormat"
          class="flex flex-col gap-1"
          @update:model-value="setFormat"
        >
          <label
            v-for="fmt in formats"
            :key="fmt.format"
            class="flex cursor-pointer items-center gap-3 rounded-lg px-3 py-2"
            :class="selectedFormat === fmt.format ? 'bg-muted' : ''"
          >
            <RadioGroupItem :value="fmt.format" />
            <span class="text-sm">{{ fmt.label }}</span>
          </label>
        </RadioGroup>
      </div>

      <!-- Content section checkboxes -->
      <div class="space-y-2">
        <Label class="text-sm font-medium">Content</Label>
        <div class="flex flex-col gap-1">
          <label
            v-for="sec in sectionLabels"
            :key="sec.key"
            class="flex cursor-pointer items-center gap-3 py-1"
          >
            <Checkbox
              :model-value="sectionsSet.has(sec.key)"
              :disabled="!supportedSet.has(sec.key)"
              @update:model-value="toggleSection(sec.key)"
            />
            <span
              class="text-sm"
              :class="!supportedSet.has(sec.key) ? 'opacity-40' : ''"
            >
              {{ sec.label }}
              <span v-if="entityCounts[sec.key]" class="text-muted-foreground">
                ({{ entityCounts[sec.key] }})
              </span>
            </span>
          </label>
        </div>
      </div>

      <!-- Asset mode -->
      <div class="space-y-2">
        <Label class="text-sm font-medium">Assets</Label>
        <RadioGroup
          :model-value="assetMode"
          class="flex flex-col gap-1"
          @update:model-value="setAssetMode"
        >
          <label
            v-for="opt in assetModeOptions"
            :key="opt.value"
            class="flex cursor-pointer items-center gap-3 py-1"
          >
            <RadioGroupItem :value="opt.value" />
            <span class="text-sm">{{ opt.label }}</span>
          </label>
        </RadioGroup>
      </div>

      <!-- Options -->
      <div class="space-y-2">
        <Label class="text-sm font-medium">Options</Label>
        <div class="flex flex-col gap-1">
          <label class="flex cursor-pointer items-center gap-3 py-1">
            <Checkbox
              :model-value="validateBeforeExport"
              @update:model-value="toggleOption('validate_before_export')"
            />
            <span class="text-sm">Validate before export</span>
          </label>
          <label class="flex cursor-pointer items-center gap-3 py-1">
            <Checkbox
              :model-value="prettyPrint"
              @update:model-value="toggleOption('pretty_print')"
            />
            <span class="text-sm">Pretty print output</span>
          </label>
        </div>
      </div>

      <!-- Actions -->
      <div class="flex items-center gap-3 pt-2">
        <Button variant="outline" size="sm" @click="validateExport">
          <ShieldCheck class="size-4" />
          Validate
        </Button>

        <Button size="sm" as-child>
          <a :href="exportDownloadUrl">
            <Download class="size-4" />
            Download .{{ selectedExtension }}
          </a>
        </Button>
      </div>

      <!-- Validation results -->
      <div v-if="validationResult" class="space-y-2">
        <Badge :variant="validationBadgeVariant(validationResult.status)">
          {{ validationStatusLabel(validationResult.status) }}
        </Badge>

        <div v-if="validationResult.errors?.length" class="space-y-1">
          <div
            v-for="(finding, i) in validationResult.errors"
            :key="'err-' + i"
            class="flex items-start gap-2 text-sm text-destructive"
          >
            <CircleX class="mt-0.5 size-4 shrink-0" />
            <span>{{ finding.message }}</span>
          </div>
        </div>

        <div v-if="validationResult.warnings?.length" class="space-y-1">
          <div
            v-for="(finding, i) in validationResult.warnings"
            :key="'warn-' + i"
            class="flex items-start gap-2 text-sm text-yellow-600 dark:text-yellow-500"
          >
            <AlertTriangle class="mt-0.5 size-4 shrink-0" />
            <span>{{ finding.message }}</span>
          </div>
        </div>

        <div v-if="validationResult.info?.length" class="space-y-1">
          <div
            v-for="(finding, i) in validationResult.info"
            :key="'info-' + i"
            class="flex items-start gap-2 text-sm text-blue-600 dark:text-blue-400"
          >
            <Info class="mt-0.5 size-4 shrink-0" />
            <span>{{ finding.message }}</span>
          </div>
        </div>

        <p
          v-if="validationResult.status === 'passed' && !validationResult.info?.length"
          class="text-sm text-green-600 dark:text-green-400"
        >
          No issues found. Project is ready for export.
        </p>
      </div>
    </section>

    <Separator />

    <!-- ===== Import section ===== -->
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
            <span class="text-muted-foreground">
              ({{ formatFileSize(entry.client_size) }})
            </span>
            <div
              v-for="(err, ei) in entry.errors"
              :key="ei"
              class="text-sm text-destructive"
            >
              {{ err }}
            </div>
          </div>

          <Button
            size="sm"
            :disabled="!hasUploadEntries"
            @click="handleUploadSubmit"
          >
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
              <span class="text-muted-foreground">{{ shortcuts.join(', ') }}</span>
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
            <Button variant="ghost" size="sm" @click="resetImport">
              Cancel
            </Button>
          </div>
        </div>

        <!-- Step: Done -->
        <div v-if="importStep === 'done'" class="space-y-3">
          <div class="flex items-center gap-2 rounded-md border border-green-200 bg-green-50 p-3 text-sm text-green-800 dark:border-green-800 dark:bg-green-950 dark:text-green-200">
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

          <Button variant="ghost" size="sm" @click="resetImport">
            Import another
          </Button>
        </div>

        <!-- Step: Error -->
        <div v-if="importStep === 'error'" class="space-y-3">
          <div class="flex items-center gap-2 rounded-md border border-destructive/20 bg-destructive/10 p-3 text-sm text-destructive">
            <AlertTriangle class="size-5 shrink-0" />
            <span>{{ importError }}</span>
          </div>

          <Button variant="ghost" size="sm" @click="resetImport">
            Try again
          </Button>
        </div>
      </template>

      <template v-else>
        <div class="flex items-center gap-2 rounded-md border bg-muted p-3 text-sm text-muted-foreground">
          <Lock class="size-4 shrink-0" />
          <span>You need edit permissions to import data.</span>
        </div>
      </template>
    </section>
  </div>
</template>
