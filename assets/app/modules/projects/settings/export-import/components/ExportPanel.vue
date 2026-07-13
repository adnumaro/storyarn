<script setup lang="ts">
import {
  AlertTriangle,
  Boxes,
  Braces,
  Check,
  CheckCircle2,
  CircleX,
  Download,
  Feather,
  FileText,
  Gamepad2,
  GitBranch,
  Info,
  Layers3,
  Link2,
  LoaderCircle,
  Map,
  MessageSquareText,
  Network,
  Package,
  ScrollText,
  ShieldCheck,
  Table2,
} from "lucide-vue-next";
import { computed, ref, watch, type Component } from "vue";
import { Button } from "@components/ui/button";
import { Checkbox } from "@components/ui/checkbox";
import { RadioGroup, RadioGroupItem } from "@components/ui/radio-group";
import { Switch } from "@components/ui/switch";
import { useI18n } from "vue-i18n";
import { useLive } from "@shared/composables/useLive";
import { capture } from "@/js/utils/posthog";

const { t } = useI18n();

interface FormatOption {
  format: string;
  label: string;
  extension?: string;
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

interface FormatVisual {
  icon: Component;
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
const validating = ref(false);

const formatVisuals: Record<string, FormatVisual> = {
  ink: { icon: Feather },
  yarn: { icon: MessageSquareText },
  unity: { icon: Boxes },
  godot: { icon: Gamepad2 },
  unreal: { icon: Braces },
  articy: { icon: GitBranch },
};

const fallbackFormatVisual: FormatVisual = { icon: FileText };

const sectionOptions = computed(() => [
  {
    key: "sheets",
    label: t("project_settings.export.sections.sheets"),
    description: t("project_settings.export.section_descriptions.sheets"),
    icon: Table2,
  },
  {
    key: "flows",
    label: t("project_settings.export.sections.flows"),
    description: t("project_settings.export.section_descriptions.flows"),
    icon: Network,
  },
  {
    key: "scenes",
    label: t("project_settings.export.sections.scenes"),
    description: t("project_settings.export.section_descriptions.scenes"),
    icon: Map,
  },
  {
    key: "screenplays",
    label: t("project_settings.export.sections.screenplays"),
    description: t("project_settings.export.section_descriptions.screenplays"),
    icon: ScrollText,
  },
  {
    key: "localization",
    label: t("project_settings.export.sections.localization"),
    description: t("project_settings.export.section_descriptions.localization"),
    icon: MessageSquareText,
  },
]);

const assetModeOptions = computed(() => [
  {
    value: "references",
    label: t("project_settings.export.asset_modes.references.title"),
    description: t("project_settings.export.asset_modes.references.description"),
    icon: Link2,
  },
  {
    value: "embedded",
    label: t("project_settings.export.asset_modes.embedded.title"),
    description: t("project_settings.export.asset_modes.embedded.description"),
    icon: Layers3,
  },
  {
    value: "bundled",
    label: t("project_settings.export.asset_modes.bundled.title"),
    description: t("project_settings.export.asset_modes.bundled.description"),
    icon: Package,
  },
]);

const sectionsSet = computed(() => new Set(sectionConfig.selected));
const supportedSet = computed(() => new Set(sectionConfig.supported));
const visibleFormats = computed(() =>
  formatConfig.formats.filter((format) => format.format !== "storyarn"),
);
const selectedFormatVisible = computed(() =>
  visibleFormats.value.some((format) => format.format === formatConfig.selected),
);
const selectedFormat = computed(
  () =>
    visibleFormats.value.find((format) => format.format === formatConfig.selected) ??
    visibleFormats.value[0] ??
    null,
);
const includedSections = computed(() =>
  sectionOptions.value.filter(
    (section) => supportedSet.value.has(section.key) && sectionsSet.value.has(section.key),
  ),
);
const includedEntityCount = computed(() =>
  includedSections.value.reduce(
    (total, section) => total + (sectionConfig.entityCounts[section.key] ?? 0),
    0,
  ),
);
const assetsSupported = computed(() => supportedSet.value.has("assets"));
const prettyPrintSupported = computed(() => formatConfig.selected === "unity");
const selectedAssetMode = computed(
  () =>
    assetModeOptions.value.find((assetMode) => assetMode.value === options.assetMode) ??
    assetModeOptions.value[0],
);
const canExport = computed(() => includedSections.value.length > 0);
const validationCounts = computed(() => ({
  errors: validation?.errors?.length ?? 0,
  warnings: validation?.warnings?.length ?? 0,
  info: validation?.info?.length ?? 0,
}));

function formatVisual(format: string) {
  return formatVisuals[format] ?? fallbackFormatVisual;
}

function formatName(format: FormatOption | null) {
  return format?.label.replace(/\s+\([^)]*\)$/, "") ?? "";
}

function formatDescription(format: string) {
  return t(`project_settings.export.format_descriptions.${format}`);
}

function extensionLabel(extension?: string) {
  return extension ? `.${extension.toLowerCase()}` : "";
}

function hasEntityCount(section: string) {
  return Object.prototype.hasOwnProperty.call(sectionConfig.entityCounts, section);
}

function setFormat(format: string) {
  if (format !== formatConfig.selected) live.pushEvent("set_format", { format });
}

watch(
  () => [formatConfig.selected, visibleFormats.value.map((format) => format.format).join("|")],
  () => {
    if (!selectedFormatVisible.value && visibleFormats.value[0]) {
      setFormat(visibleFormats.value[0].format);
    }
  },
  { immediate: true },
);

function toggleSection(section: string) {
  if (supportedSet.value.has(section)) live.pushEvent("toggle_section", { section });
}

function setAssetMode(mode: string) {
  live.pushEvent("set_asset_mode", { mode });
}

function toggleOption(option: string) {
  live.pushEvent("toggle_option", { option });
}

function validateExport() {
  if (validating.value || !canExport.value) return;

  validating.value = true;
  const finish = () => {
    validating.value = false;
  };

  live.pushEvent("validate_export", {}, finish, finish);
}

function trackExport() {
  capture("project exported", {
    format: formatConfig.selected,
    asset_mode: assetsSupported.value ? options.assetMode : "unsupported",
    section_count: includedSections.value.length,
  });
}

function validationStatusLabel(status: string) {
  const labels: Record<string, string> = {
    passed: t("project_settings.export.passed"),
    warnings: t("project_settings.export.warnings"),
    errors: t("project_settings.export.errors"),
  };
  return labels[status] || status;
}

function validationTitle(status: string) {
  return t(`project_settings.export.validation_titles.${status}`);
}

function validationDescription(status: string) {
  return t(`project_settings.export.validation_descriptions.${status}`, {
    errors: validationCounts.value.errors,
    warnings: validationCounts.value.warnings,
  });
}

function validationPanelClass(status: string) {
  if (status === "passed") return "border-success/30 bg-success/5";
  if (status === "warnings") return "border-warning/30 bg-warning/5";
  if (status === "errors") return "border-error/30 bg-error/5";
  return "border-base-300 bg-base-100";
}

function validationIconClass(status: string) {
  if (status === "passed") return "bg-success/15 text-success";
  if (status === "warnings") return "bg-warning/15 text-warning";
  if (status === "errors") return "bg-error/15 text-error";
  return "bg-info/15 text-info";
}
</script>

<template>
  <section id="export-workspace" class="space-y-5">
    <div class="overflow-hidden rounded-xl border border-base-300 bg-base-100 shadow-sm">
      <header
        class="flex flex-col gap-3 border-b border-base-300 bg-base-200/40 px-5 py-4 sm:flex-row sm:items-center"
      >
        <div class="flex size-11 items-center justify-center rounded-xl bg-primary/10 text-primary">
          <Download class="size-5" />
        </div>
        <div class="min-w-0 flex-1">
          <h2 class="font-semibold">{{ $t("project_settings.export.workspace_title") }}</h2>
          <p class="mt-1 text-sm text-base-content/55">
            {{ $t("project_settings.export.workspace_description") }}
          </p>
        </div>
        <span class="badge badge-outline badge-sm whitespace-nowrap">
          {{
            $t(
              "project_settings.export.format_count",
              { count: visibleFormats.length },
              visibleFormats.length,
            )
          }}
        </span>
      </header>

      <fieldset id="export-format-options" class="p-5">
        <legend class="text-sm font-semibold">
          {{ $t("project_settings.export.choose_format") }}
        </legend>
        <p class="mt-1 text-xs text-base-content/50">
          {{ $t("project_settings.export.choose_format_description") }}
        </p>

        <RadioGroup
          :model-value="formatConfig.selected"
          class="mt-3 grid gap-2 sm:grid-cols-2"
          @update:model-value="setFormat"
        >
          <label
            v-for="format in visibleFormats"
            :key="format.format"
            :data-testid="`export-format-${format.format}`"
            :class="[
              'group relative flex cursor-pointer items-start gap-3 rounded-xl border p-3.5 transition-all duration-200 focus-within:ring-2 focus-within:ring-primary/30',
              formatConfig.selected === format.format
                ? 'border-primary/45 bg-primary/5 shadow-sm'
                : 'border-base-300 bg-base-100 hover:-translate-y-0.5 hover:border-base-content/25 hover:shadow-sm',
            ]"
          >
            <RadioGroupItem
              :value="format.format"
              :aria-label="format.label"
              class="absolute size-px opacity-0"
            />
            <span
              :class="[
                'flex size-9 shrink-0 items-center justify-center rounded-lg transition-colors',
                formatConfig.selected === format.format
                  ? 'bg-primary text-primary-content'
                  : 'bg-base-200 text-base-content/65 group-hover:bg-base-300',
              ]"
            >
              <component :is="formatVisual(format.format).icon" class="size-4" />
            </span>
            <span class="min-w-0 flex-1">
              <span class="flex items-center gap-2">
                <span class="truncate text-sm font-medium">{{ formatName(format) }}</span>
                <span v-if="format.extension" class="badge badge-ghost badge-xs uppercase">
                  {{ extensionLabel(format.extension) }}
                </span>
              </span>
              <span class="mt-1 block text-xs leading-relaxed text-base-content/50">
                {{ formatDescription(format.format) }}
              </span>
            </span>
            <Check
              v-if="formatConfig.selected === format.format"
              class="mt-0.5 size-4 shrink-0 text-primary"
            />
          </label>
        </RadioGroup>
      </fieldset>
    </div>

    <template v-if="selectedFormatVisible">
      <div class="grid gap-5 xl:grid-cols-[minmax(0,1fr)_18rem] xl:items-start">
        <div class="space-y-5">
          <section class="rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm">
            <div class="flex items-start justify-between gap-4">
              <div>
                <h3 class="font-semibold">{{ $t("project_settings.export.content") }}</h3>
                <p class="mt-1 text-xs text-base-content/50">
                  {{ $t("project_settings.export.content_description") }}
                </p>
              </div>
              <span class="badge badge-primary badge-outline badge-sm whitespace-nowrap">
                {{
                  $t(
                    "project_settings.export.selected_count",
                    { count: includedSections.length },
                    includedSections.length,
                  )
                }}
              </span>
            </div>

            <div class="mt-4 grid gap-2 sm:grid-cols-2">
              <label
                v-for="section in sectionOptions"
                :key="section.key"
                :data-testid="`export-section-${section.key}`"
                :class="[
                  'flex items-start gap-3 rounded-lg border p-3 transition-colors',
                  supportedSet.has(section.key)
                    ? 'cursor-pointer border-base-300 hover:bg-base-200/45'
                    : 'cursor-not-allowed border-base-300/60 bg-base-200/30 opacity-55',
                ]"
              >
                <Checkbox
                  :model-value="supportedSet.has(section.key) && sectionsSet.has(section.key)"
                  :disabled="!supportedSet.has(section.key)"
                  :aria-label="section.label"
                  class="mt-0.5"
                  @update:model-value="toggleSection(section.key)"
                />
                <component :is="section.icon" class="mt-0.5 size-4 shrink-0 text-base-content/55" />
                <span class="min-w-0 flex-1">
                  <span class="flex items-center justify-between gap-2">
                    <span class="text-sm font-medium">{{ section.label }}</span>
                    <span
                      v-if="supportedSet.has(section.key)"
                      class="badge badge-ghost badge-xs tabular-nums"
                    >
                      {{
                        hasEntityCount(section.key) ? sectionConfig.entityCounts[section.key] : "—"
                      }}
                    </span>
                    <span v-else class="badge badge-ghost badge-xs">
                      {{ $t("project_settings.export.not_supported") }}
                    </span>
                  </span>
                  <span class="mt-0.5 block text-xs leading-relaxed text-base-content/45">
                    {{ section.description }}
                  </span>
                </span>
              </label>
            </div>

            <div v-if="!canExport" class="alert alert-warning mt-4 py-2.5 text-sm" role="alert">
              <AlertTriangle class="size-4" />
              <span>{{ $t("project_settings.export.select_content_warning") }}</span>
            </div>
          </section>

          <section class="overflow-hidden rounded-xl border border-base-300 bg-base-100 shadow-sm">
            <div class="border-b border-base-300 px-5 py-4">
              <h3 class="font-semibold">{{ $t("project_settings.export.output_settings") }}</h3>
              <p class="mt-1 text-xs text-base-content/50">
                {{ $t("project_settings.export.output_settings_description") }}
              </p>
            </div>

            <fieldset
              v-if="assetsSupported"
              id="export-asset-mode-options"
              class="border-b border-base-300 p-5"
            >
              <legend class="text-sm font-medium">
                {{ $t("project_settings.export.assets") }}
              </legend>
              <p class="mt-1 text-xs text-base-content/50">
                {{ $t("project_settings.export.assets_description") }}
              </p>
              <RadioGroup
                :model-value="options.assetMode"
                class="mt-3 grid gap-2 sm:grid-cols-3"
                @update:model-value="setAssetMode"
              >
                <label
                  v-for="assetMode in assetModeOptions"
                  :key="assetMode.value"
                  :data-testid="`export-assets-${assetMode.value}`"
                  :class="[
                    'relative flex cursor-pointer flex-col gap-2 rounded-lg border p-3 transition-colors focus-within:ring-2 focus-within:ring-primary/30',
                    options.assetMode === assetMode.value
                      ? 'border-primary/45 bg-primary/5'
                      : 'border-base-300 hover:bg-base-200/40',
                  ]"
                >
                  <RadioGroupItem
                    :value="assetMode.value"
                    :aria-label="assetMode.label"
                    class="absolute size-px opacity-0"
                  />
                  <span class="flex items-center gap-2">
                    <component :is="assetMode.icon" class="size-4 text-base-content/60" />
                    <span class="text-sm font-medium">{{ assetMode.label }}</span>
                    <Check
                      v-if="options.assetMode === assetMode.value"
                      class="ml-auto size-3.5 text-primary"
                    />
                  </span>
                  <span class="text-xs leading-relaxed text-base-content/45">
                    {{ assetMode.description }}
                  </span>
                </label>
              </RadioGroup>
            </fieldset>

            <div class="divide-y divide-base-300 px-5">
              <div class="flex items-center gap-3 py-4">
                <div
                  class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-info/10 text-info"
                >
                  <ShieldCheck class="size-4" />
                </div>
                <label for="validate-before-export" class="min-w-0 flex-1 cursor-pointer">
                  <span class="block text-sm font-medium">
                    {{ $t("project_settings.export.validate_before") }}
                  </span>
                  <span class="mt-0.5 block text-xs text-base-content/50">
                    {{ $t("project_settings.export.validate_before_description") }}
                  </span>
                </label>
                <Switch
                  id="validate-before-export"
                  :model-value="options.validateBeforeExport"
                  @update:model-value="toggleOption('validate_before_export')"
                />
              </div>

              <div v-if="prettyPrintSupported" class="flex items-center gap-3 py-4">
                <div
                  class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-secondary/10 text-secondary"
                >
                  <Braces class="size-4" />
                </div>
                <label for="pretty-print-output" class="min-w-0 flex-1 cursor-pointer">
                  <span class="block text-sm font-medium">
                    {{ $t("project_settings.export.pretty_print") }}
                  </span>
                  <span class="mt-0.5 block text-xs text-base-content/50">
                    {{ $t("project_settings.export.pretty_print_description") }}
                  </span>
                </label>
                <Switch
                  id="pretty-print-output"
                  :model-value="options.prettyPrint"
                  @update:model-value="toggleOption('pretty_print')"
                />
              </div>
            </div>
          </section>
        </div>

        <aside
          data-testid="export-summary"
          class="rounded-xl border border-base-300 bg-base-100 shadow-sm xl:sticky xl:top-5"
        >
          <div class="border-b border-base-300 px-4 py-3.5">
            <p class="text-xs font-semibold uppercase tracking-wider text-base-content/45">
              {{ $t("project_settings.export.summary") }}
            </p>
          </div>

          <div class="space-y-4 p-4">
            <div class="flex items-center gap-3">
              <div
                class="flex size-10 items-center justify-center rounded-lg bg-primary text-primary-content"
              >
                <component :is="formatVisual(formatConfig.selected).icon" class="size-4" />
              </div>
              <div class="min-w-0 flex-1">
                <p class="truncate text-sm font-semibold">{{ formatName(selectedFormat) }}</p>
                <p class="text-xs text-base-content/50">
                  {{ $t("project_settings.export.download_file") }}
                  <span class="font-medium uppercase">.{{ formatConfig.extension }}</span>
                </p>
              </div>
            </div>

            <dl class="space-y-2.5 border-y border-base-300 py-3 text-xs">
              <div class="flex items-center justify-between gap-3">
                <dt class="text-base-content/50">{{ $t("project_settings.export.content") }}</dt>
                <dd class="font-medium">
                  {{
                    $t(
                      "project_settings.export.section_count",
                      { count: includedSections.length },
                      includedSections.length,
                    )
                  }}
                </dd>
              </div>
              <div class="flex items-center justify-between gap-3">
                <dt class="text-base-content/50">{{ $t("project_settings.export.entities") }}</dt>
                <dd class="font-medium tabular-nums">{{ includedEntityCount }}</dd>
              </div>
              <div v-if="assetsSupported" class="flex items-center justify-between gap-3">
                <dt class="text-base-content/50">{{ $t("project_settings.export.assets") }}</dt>
                <dd class="truncate font-medium">{{ selectedAssetMode.label }}</dd>
              </div>
              <div class="flex items-center justify-between gap-3">
                <dt class="text-base-content/50">{{ $t("project_settings.export.preflight") }}</dt>
                <dd class="flex items-center gap-1.5 font-medium">
                  <CheckCircle2 v-if="options.validateBeforeExport" class="size-3.5 text-success" />
                  <CircleX v-else class="size-3.5 text-base-content/35" />
                  {{
                    options.validateBeforeExport
                      ? $t("project_settings.export.enabled")
                      : $t("project_settings.export.disabled")
                  }}
                </dd>
              </div>
            </dl>

            <div class="space-y-2">
              <Button
                type="button"
                variant="outline"
                class="w-full"
                :disabled="validating || !canExport"
                data-testid="validate-export"
                @click="validateExport"
              >
                <LoaderCircle v-if="validating" class="size-4 animate-spin" />
                <ShieldCheck v-else class="size-4" />
                {{
                  validating
                    ? $t("project_settings.export.validating")
                    : $t("project_settings.export.validate")
                }}
              </Button>

              <Button v-if="canExport" class="w-full" as-child>
                <a
                  :href="exportDownloadUrl"
                  data-live-link-exempt="download"
                  data-testid="download-export"
                  @click="trackExport"
                >
                  <Download class="size-4" />
                  {{ $t("project_settings.export.download", { ext: formatConfig.extension }) }}
                </a>
              </Button>
              <Button v-else class="w-full" disabled>
                <Download class="size-4" />
                {{ $t("project_settings.export.download", { ext: formatConfig.extension }) }}
              </Button>
            </div>

            <p class="flex items-start gap-2 text-xs leading-relaxed text-base-content/45">
              <Info class="mt-0.5 size-3.5 shrink-0" />
              <span>{{ $t("project_settings.export.download_note") }}</span>
            </p>
          </div>
        </aside>
      </div>

      <section
        v-if="validation"
        id="export-validation-results"
        :data-status="validation.status"
        :class="[
          'overflow-hidden rounded-xl border shadow-sm',
          validationPanelClass(validation.status),
        ]"
        aria-live="polite"
      >
        <div class="flex flex-col gap-3 p-5 sm:flex-row sm:items-start">
          <div
            :class="[
              'flex size-10 shrink-0 items-center justify-center rounded-xl',
              validationIconClass(validation.status),
            ]"
          >
            <CheckCircle2 v-if="validation.status === 'passed'" class="size-5" />
            <AlertTriangle v-else-if="validation.status === 'warnings'" class="size-5" />
            <CircleX v-else class="size-5" />
          </div>
          <div class="min-w-0 flex-1">
            <div class="flex flex-wrap items-center gap-2">
              <h3 class="font-semibold">{{ validationTitle(validation.status) }}</h3>
              <span
                :class="[
                  'badge badge-sm badge-outline',
                  validation.status === 'passed' && 'badge-success',
                  validation.status === 'warnings' && 'badge-warning',
                  validation.status === 'errors' && 'badge-error',
                ]"
              >
                {{ validationStatusLabel(validation.status) }}
              </span>
            </div>
            <p class="mt-1 text-sm text-base-content/55">
              {{ validationDescription(validation.status) }}
            </p>
          </div>
        </div>

        <div
          v-if="validation.errors?.length || validation.warnings?.length || validation.info?.length"
          class="grid gap-3 border-t border-current/10 p-5 lg:grid-cols-2"
        >
          <div v-if="validation.errors?.length" class="space-y-2 lg:col-span-2">
            <h4
              class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-error"
            >
              <CircleX class="size-3.5" />
              {{ $t("project_settings.export.error_findings") }}
            </h4>
            <div
              v-for="(finding, index) in validation.errors"
              :key="`error-${index}`"
              class="rounded-lg border border-error/20 bg-base-100/65 px-3 py-2.5 text-sm"
            >
              {{ finding.message }}
            </div>
          </div>

          <div v-if="validation.warnings?.length" class="space-y-2">
            <h4
              class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-warning"
            >
              <AlertTriangle class="size-3.5" />
              {{ $t("project_settings.export.warning_findings") }}
            </h4>
            <div
              v-for="(finding, index) in validation.warnings"
              :key="`warning-${index}`"
              class="rounded-lg border border-warning/20 bg-base-100/65 px-3 py-2.5 text-sm"
            >
              {{ finding.message }}
            </div>
          </div>

          <div v-if="validation.info?.length" class="space-y-2">
            <h4
              class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-info"
            >
              <Info class="size-3.5" />
              {{ $t("project_settings.export.info_findings") }}
            </h4>
            <div
              v-for="(finding, index) in validation.info"
              :key="`info-${index}`"
              class="rounded-lg border border-info/20 bg-base-100/65 px-3 py-2.5 text-sm"
            >
              {{ finding.message }}
            </div>
          </div>
        </div>

        <div
          v-if="validation.status === 'passed' && !validation.info?.length"
          class="flex items-center gap-2 border-t border-success/15 px-5 py-3 text-sm text-success"
        >
          <CheckCircle2 class="size-4" />
          <span>{{ $t("project_settings.export.no_issues") }}</span>
        </div>
      </section>
    </template>
  </section>
</template>
