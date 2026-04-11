<script setup lang="ts">
import { AlertTriangle, CircleX, Download, Info, ShieldCheck } from "lucide-vue-next";
import { computed } from "vue";
import { Badge } from "@components/ui/badge/index.ts";
import { Button } from "@components/ui/button/index.ts";
import { Checkbox } from "@components/ui/checkbox/index.ts";
import { Label } from "@components/ui/label/index.ts";
import { RadioGroup, RadioGroupItem } from "@components/ui/radio-group/index.ts";
import { useLive } from "@composables/useLive";

interface FormatOption {
  format: string;
  label: string;
}

interface FormatConfig {
  selected: string;
  formats: FormatOption[];
  extension: string;
}

interface SectionConfig {
  selected: string[];
  supported: string[];
  entityCounts: Record<string, number>;
}

interface ExportOptions {
  assetMode: string;
  validateBeforeExport: boolean;
  prettyPrint: boolean;
}

interface ValidationFinding {
  message: string;
}

interface ValidationResult {
  status: string;
  errors?: ValidationFinding[];
  warnings?: ValidationFinding[];
  info?: ValidationFinding[];
}

const {
  formatConfig,
  sectionConfig,
  options,
  validation = null,
  exportDownloadUrl,
} = defineProps<{
  formatConfig: FormatConfig;
  sectionConfig: SectionConfig;
  options: ExportOptions;
  validation?: ValidationResult | null;
  exportDownloadUrl: string;
}>();

const live = useLive();

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

const sectionsSet = computed(() => new Set(sectionConfig.selected));
const supportedSet = computed(() => new Set(sectionConfig.supported));

function setFormat(format: string) {
  live.pushEvent("set_format", { format });
}

function toggleSection(section: string) {
  live.pushEvent("toggle_section", { section });
}

function setAssetMode(mode: string) {
  live.pushEvent("set_asset_mode", { mode });
}

function toggleOption(option: string) {
  live.pushEvent("toggle_option", { option });
}

function validateExport() {
  live.pushEvent("validate_export", {});
}

function validationStatusLabel(status: string) {
  const labels: Record<string, string> = {
    passed: "Passed",
    warnings: "Warnings",
    errors: "Errors",
  };
  return labels[status] || status;
}

function validationBadgeVariant(status: string) {
  if (status === "passed") return "default";
  if (status === "warnings") return "secondary";
  if (status === "errors") return "destructive";
  return "outline";
}
</script>

<template>
  <section class="space-y-5">
    <h2 class="text-lg font-semibold">Export</h2>

    <!-- Format selector -->
    <div class="space-y-2">
      <Label class="text-sm font-medium">Format</Label>
      <RadioGroup
        :model-value="formatConfig.selected"
        class="flex flex-col gap-1"
        @update:model-value="setFormat"
      >
        <label
          v-for="fmt in formatConfig.formats"
          :key="fmt.format"
          class="flex cursor-pointer items-center gap-3 rounded-lg px-3 py-2"
          :class="formatConfig.selected === fmt.format ? 'bg-muted' : ''"
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
          <span class="text-sm" :class="!supportedSet.has(sec.key) ? 'opacity-40' : ''">
            {{ sec.label }}
            <span v-if="sectionConfig.entityCounts[sec.key]" class="text-muted-foreground">
              ({{ sectionConfig.entityCounts[sec.key] }})
            </span>
          </span>
        </label>
      </div>
    </div>

    <!-- Asset mode -->
    <div class="space-y-2">
      <Label class="text-sm font-medium">Assets</Label>
      <RadioGroup
        :model-value="options.assetMode"
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
            :model-value="options.validateBeforeExport"
            @update:model-value="toggleOption('validate_before_export')"
          />
          <span class="text-sm">Validate before export</span>
        </label>
        <label class="flex cursor-pointer items-center gap-3 py-1">
          <Checkbox
            :model-value="options.prettyPrint"
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
          Download .{{ formatConfig.extension }}
        </a>
      </Button>
    </div>

    <!-- Validation results -->
    <div v-if="validation" class="space-y-2">
      <Badge :variant="validationBadgeVariant(validation.status)">
        {{ validationStatusLabel(validation.status) }}
      </Badge>

      <div v-if="validation.errors?.length" class="space-y-1">
        <div
          v-for="(finding, i) in validation.errors"
          :key="'err-' + i"
          class="flex items-start gap-2 text-sm text-destructive"
        >
          <CircleX class="mt-0.5 size-4 shrink-0" />
          <span>{{ finding.message }}</span>
        </div>
      </div>

      <div v-if="validation.warnings?.length" class="space-y-1">
        <div
          v-for="(finding, i) in validation.warnings"
          :key="'warn-' + i"
          class="flex items-start gap-2 text-sm text-yellow-600 dark:text-yellow-500"
        >
          <AlertTriangle class="mt-0.5 size-4 shrink-0" />
          <span>{{ finding.message }}</span>
        </div>
      </div>

      <div v-if="validation.info?.length" class="space-y-1">
        <div
          v-for="(finding, i) in validation.info"
          :key="'info-' + i"
          class="flex items-start gap-2 text-sm text-blue-600 dark:text-blue-400"
        >
          <Info class="mt-0.5 size-4 shrink-0" />
          <span>{{ finding.message }}</span>
        </div>
      </div>

      <p
        v-if="validation.status === 'passed' && !validation.info?.length"
        class="text-sm text-green-600 dark:text-green-400"
      >
        No issues found. Project is ready for export.
      </p>
    </div>
  </section>
</template>
