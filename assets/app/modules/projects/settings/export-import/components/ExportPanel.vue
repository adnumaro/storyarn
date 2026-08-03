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
  ShieldCheck,
  Table2,
} from "@lucide/vue";
import { computed, onUnmounted, ref, watch, type Component } from "vue";
import { Button } from "@components/ui/button";
import { Checkbox } from "@components/ui/checkbox";
import LiveLink from "@components/navigation/LiveLink.vue";
import { RadioGroup, RadioGroupItem } from "@components/ui/radio-group";
import { Switch } from "@components/ui/switch";
import { useI18n } from "vue-i18n";
import { useLive } from "@shared/composables/useLive";
import { capture } from "@/js/utils/posthog";
import type {
  ExportOptions,
  FormatConfig,
  FormatOption,
  LocalizationMode,
  LocalizationPolicy,
  SectionConfig,
  ValidationResult,
} from "../types";

const { t } = useI18n();

interface FormatVisual {
  icon: Component;
}

const {
  canExport,
  formatConfig,
  sectionConfig,
  options,
  validation = null,
  exportDownloadUrl,
} = defineProps<{
  canExport: boolean;
  formatConfig: FormatConfig;
  sectionConfig: SectionConfig;
  options: ExportOptions;
  validation?: ValidationResult | null;
  exportDownloadUrl: string;
}>();

const live = useLive();
const validating = ref(false);
const downloading = ref(false);
const downloadError = ref<string | null>(null);
const VALIDATION_TIMEOUT_MS = 15_000;
let validationTimer: ReturnType<typeof setTimeout> | null = null;
let validationEpoch = 0;

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

const localizationPolicyOptions = computed<Array<{ value: LocalizationPolicy; label: string }>>(
  () => [
    { value: "release", label: t("project_settings.export.localization_release") },
    { value: "preview", label: t("project_settings.export.localization_preview") },
  ],
);

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
const hasExportableContent = computed(() => includedSections.value.length > 0);
const validationIsStale = computed(() => validation?.stale === true);
const canDownload = computed(
  () =>
    canExport &&
    hasExportableContent.value &&
    (!options.validateBeforeExport ||
      (validation != null && !validationIsStale.value && validation.status !== "errors")),
);
const validationCounts = computed(() => ({
  errors: validation?.errors?.length ?? 0,
  warnings: validation?.warnings?.length ?? 0,
  info: validation?.info?.length ?? 0,
}));
const MAX_VISIBLE_FINDINGS = 50;
const visibleErrors = computed(() => validation?.errors?.slice(0, MAX_VISIBLE_FINDINGS) ?? []);
const visibleWarnings = computed(() => validation?.warnings?.slice(0, MAX_VISIBLE_FINDINGS) ?? []);
const visibleInfo = computed(() => validation?.info?.slice(0, MAX_VISIBLE_FINDINGS) ?? []);

function hiddenFindingCount(total: number) {
  return Math.max(0, total - MAX_VISIBLE_FINDINGS);
}

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
  if (canExport && format !== formatConfig.selected) live.pushEvent("set_format", { format });
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

watch(
  () => exportDownloadUrl,
  () => {
    downloadError.value = null;
  },
);

function toggleSection(section: string) {
  if (canExport && supportedSet.value.has(section)) {
    live.pushEvent("toggle_section", { section });
  }
}

function setAssetMode(mode: string) {
  if (canExport) live.pushEvent("set_asset_mode", { mode });
}

function setLocalizationPolicy(policy: string) {
  if (canExport && (policy === "release" || policy === "preview")) {
    live.pushEvent("set_localization_policy", { policy });
  }
}

function localizationModeLabel(mode: LocalizationMode) {
  return t(`project_settings.export.localization_modes.${mode}`);
}

function toggleOption(option: string) {
  if (canExport) live.pushEvent("toggle_option", { option });
}

function validateExport() {
  if (!canExport || validating.value || !hasExportableContent.value) return;

  validating.value = true;
  const epoch = ++validationEpoch;
  const finish = () => {
    if (epoch !== validationEpoch) return;

    if (validationTimer) {
      clearTimeout(validationTimer);
      validationTimer = null;
    }
    validating.value = false;
  };

  validationTimer = setTimeout(finish, VALIDATION_TIMEOUT_MS);
  live.pushEvent("validate_export", {}, finish, finish);
}

function downloadFilename(response: Response) {
  const disposition = response.headers.get("content-disposition") ?? "";
  const quoted = /filename="([^"]+)"/i.exec(disposition);
  const unquoted = /filename=([^;]+)/i.exec(disposition);

  return (
    quoted?.[1] ??
    unquoted?.[1]?.trim() ??
    `storyarn-export.${formatConfig.extension.toLowerCase()}`
  );
}

function isDownloadResponse(response: Response) {
  const disposition = response.headers.get("content-disposition") ?? "";
  const contentType = response.headers.get("content-type") ?? "";

  return (
    !response.redirected &&
    /^\s*attachment(?:\s*;|$)/i.test(disposition) &&
    !/^(?:text\/html|application\/xhtml\+xml)\b/i.test(contentType)
  );
}

async function downloadExport() {
  if (!canDownload.value || downloading.value) return;

  downloading.value = true;
  downloadError.value = null;

  try {
    const response = await fetch(exportDownloadUrl);

    if (!response.ok) {
      const errorKind = response.headers.get("x-storyarn-export-error");
      downloadError.value =
        response.status === 422 && errorKind === "validation"
          ? t("project_settings.export.download_failed_validation")
          : t("project_settings.export.download_failed");
      return;
    }

    if (!isDownloadResponse(response)) {
      downloadError.value = t("project_settings.export.download_failed");
      return;
    }

    const objectUrl = URL.createObjectURL(await response.blob());
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = downloadFilename(response);
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(objectUrl);
    trackExport();
  } catch {
    downloadError.value = t("project_settings.export.download_failed");
  } finally {
    downloading.value = false;
  }
}

onUnmounted(() => {
  validationEpoch += 1;
  if (validationTimer) {
    clearTimeout(validationTimer);
    validationTimer = null;
  }
});

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
  if (validationIsStale.value) return "border-amber-500/30 bg-amber-500/5";
  if (status === "passed") return "border-emerald-500/30 bg-emerald-500/5";
  if (status === "warnings") return "border-amber-500/30 bg-amber-500/5";
  if (status === "errors") return "border-destructive/30 bg-destructive/5";
  return "border-border bg-card";
}

function validationIconClass(status: string) {
  if (validationIsStale.value) return "bg-amber-500/15 text-amber-700 dark:text-amber-300";
  if (status === "passed") return "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300";
  if (status === "warnings") return "bg-amber-500/15 text-amber-700 dark:text-amber-300";
  if (status === "errors") return "bg-destructive/15 text-destructive";
  return "bg-sky-500/15 text-sky-700 dark:text-sky-300";
}
</script>

<template>
  <section id="export-workspace" class="space-y-5">
    <div class="overflow-hidden rounded-xl border border-border bg-card shadow-sm">
      <header
        class="flex flex-col gap-3 border-b border-border bg-muted/40 px-5 py-4 sm:flex-row sm:items-center"
      >
        <div class="flex size-11 items-center justify-center rounded-xl bg-primary/10 text-primary">
          <Download class="size-5" />
        </div>
        <div class="min-w-0 flex-1">
          <h2 class="font-semibold">{{ $t("project_settings.export.workspace_title") }}</h2>
          <p class="mt-1 text-sm text-muted-foreground">
            {{ $t("project_settings.export.workspace_description") }}
          </p>
        </div>
        <span
          class="inline-flex items-center whitespace-nowrap rounded-full border border-border px-2 py-0.5 text-xs font-medium text-muted-foreground"
        >
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
        <p class="mt-1 text-xs text-muted-foreground">
          {{ $t("project_settings.export.choose_format_description") }}
        </p>

        <RadioGroup
          :model-value="formatConfig.selected"
          :disabled="!canExport"
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
                : 'border-border bg-background hover:-translate-y-0.5 hover:border-foreground/25 hover:shadow-sm',
            ]"
          >
            <RadioGroupItem
              :value="format.format"
              :disabled="!canExport"
              :aria-label="format.label"
              class="absolute size-px opacity-0"
            />
            <span
              :class="[
                'flex size-9 shrink-0 items-center justify-center rounded-lg transition-colors',
                formatConfig.selected === format.format
                  ? 'bg-primary text-primary-foreground'
                  : 'bg-muted text-muted-foreground group-hover:bg-accent',
              ]"
            >
              <component :is="formatVisual(format.format).icon" class="size-4" />
            </span>
            <span class="min-w-0 flex-1">
              <span class="flex items-center gap-2">
                <span class="truncate text-sm font-medium">{{ formatName(format) }}</span>
                <span
                  v-if="format.extension"
                  class="inline-flex rounded-full bg-muted px-1.5 py-0.5 text-[10px] font-medium uppercase text-muted-foreground"
                >
                  {{ extensionLabel(format.extension) }}
                </span>
              </span>
              <span class="mt-1 block text-xs leading-relaxed text-muted-foreground">
                {{ formatDescription(format.format) }}
              </span>
              <span
                class="mt-2 inline-flex rounded-full bg-muted px-2 py-0.5 text-xs font-medium text-muted-foreground"
              >
                {{ localizationModeLabel(format.localizationMode) }}
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
          <section class="rounded-xl border border-border bg-card p-5 shadow-sm">
            <div class="flex items-start justify-between gap-4">
              <div>
                <h3 class="font-semibold">{{ $t("project_settings.export.content") }}</h3>
                <p class="mt-1 text-xs text-muted-foreground">
                  {{ $t("project_settings.export.content_description") }}
                </p>
              </div>
              <span
                class="inline-flex items-center whitespace-nowrap rounded-full border border-primary/30 px-2 py-0.5 text-xs font-medium text-primary"
              >
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
                    ? 'cursor-pointer border-border hover:bg-muted/45'
                    : 'cursor-not-allowed border-border/60 bg-muted/30 opacity-55',
                ]"
              >
                <Checkbox
                  :model-value="supportedSet.has(section.key) && sectionsSet.has(section.key)"
                  :disabled="!canExport || !supportedSet.has(section.key)"
                  :aria-label="section.label"
                  class="mt-0.5"
                  @update:model-value="toggleSection(section.key)"
                />
                <component
                  :is="section.icon"
                  class="mt-0.5 size-4 shrink-0 text-muted-foreground"
                />
                <span class="min-w-0 flex-1">
                  <span class="flex items-center justify-between gap-2">
                    <span class="text-sm font-medium">{{ section.label }}</span>
                    <span
                      v-if="supportedSet.has(section.key)"
                      class="inline-flex rounded-full bg-muted px-1.5 py-0.5 text-[10px] font-medium tabular-nums text-muted-foreground"
                    >
                      {{
                        hasEntityCount(section.key) ? sectionConfig.entityCounts[section.key] : "—"
                      }}
                    </span>
                    <span
                      v-else
                      class="inline-flex rounded-full bg-muted px-1.5 py-0.5 text-[10px] font-medium text-muted-foreground"
                    >
                      {{ $t("project_settings.export.not_supported") }}
                    </span>
                  </span>
                  <span class="mt-0.5 block text-xs leading-relaxed text-muted-foreground">
                    {{ section.description }}
                  </span>
                </span>
              </label>
            </div>

            <div
              v-if="!hasExportableContent"
              class="mt-4 flex items-start gap-2 rounded-lg border border-amber-500/30 bg-amber-500/10 p-3 text-sm text-foreground"
              role="alert"
            >
              <AlertTriangle class="size-4" />
              <span>{{ $t("project_settings.export.select_content_warning") }}</span>
            </div>
          </section>

          <section class="overflow-hidden rounded-xl border border-border bg-card shadow-sm">
            <div class="border-b border-border px-5 py-4">
              <h3 class="font-semibold">{{ $t("project_settings.export.output_settings") }}</h3>
              <p class="mt-1 text-xs text-muted-foreground">
                {{ $t("project_settings.export.output_settings_description") }}
              </p>
            </div>

            <fieldset
              v-if="supportedSet.has('localization') && sectionsSet.has('localization')"
              id="export-localization-policy-options"
              class="border-b border-border p-5"
            >
              <legend class="text-sm font-medium">
                {{ $t("project_settings.export.localization_policy") }}
              </legend>
              <RadioGroup
                :model-value="options.localizationPolicy"
                :disabled="!canExport"
                class="mt-3 grid gap-2 sm:grid-cols-2"
                @update:model-value="setLocalizationPolicy"
              >
                <label
                  v-for="policy in localizationPolicyOptions"
                  :key="policy.value"
                  :data-testid="`export-localization-${policy.value}`"
                  :class="[
                    'relative flex cursor-pointer items-start gap-3 rounded-lg border p-3 transition-colors focus-within:ring-2 focus-within:ring-primary/30',
                    options.localizationPolicy === policy.value
                      ? 'border-primary/45 bg-primary/5'
                      : 'border-border hover:bg-muted/40',
                  ]"
                >
                  <RadioGroupItem
                    :value="policy.value"
                    :disabled="!canExport"
                    :aria-label="policy.label"
                    class="absolute size-px opacity-0"
                  />
                  <span class="text-sm leading-relaxed">{{ policy.label }}</span>
                  <Check
                    v-if="options.localizationPolicy === policy.value"
                    class="ml-auto mt-0.5 size-3.5 shrink-0 text-primary"
                  />
                </label>
              </RadioGroup>
            </fieldset>

            <fieldset
              v-if="assetsSupported"
              id="export-asset-mode-options"
              class="border-b border-border p-5"
            >
              <legend class="text-sm font-medium">
                {{ $t("project_settings.export.assets") }}
              </legend>
              <p class="mt-1 text-xs text-muted-foreground">
                {{ $t("project_settings.export.assets_description") }}
              </p>
              <RadioGroup
                :model-value="options.assetMode"
                :disabled="!canExport"
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
                      : 'border-border hover:bg-muted/40',
                  ]"
                >
                  <RadioGroupItem
                    :value="assetMode.value"
                    :disabled="!canExport"
                    :aria-label="assetMode.label"
                    class="absolute size-px opacity-0"
                  />
                  <span class="flex items-center gap-2">
                    <component :is="assetMode.icon" class="size-4 text-muted-foreground" />
                    <span class="text-sm font-medium">{{ assetMode.label }}</span>
                    <Check
                      v-if="options.assetMode === assetMode.value"
                      class="ml-auto size-3.5 text-primary"
                    />
                  </span>
                  <span class="text-xs leading-relaxed text-muted-foreground">
                    {{ assetMode.description }}
                  </span>
                </label>
              </RadioGroup>
            </fieldset>

            <div class="divide-y divide-border px-5">
              <div class="flex items-center gap-3 py-4">
                <div
                  class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-sky-500/10 text-sky-700 dark:text-sky-300"
                >
                  <ShieldCheck class="size-4" />
                </div>
                <label for="validate-before-export" class="min-w-0 flex-1 cursor-pointer">
                  <span class="block text-sm font-medium">
                    {{ $t("project_settings.export.validate_before") }}
                  </span>
                  <span class="mt-0.5 block text-xs text-muted-foreground">
                    {{ $t("project_settings.export.validate_before_description") }}
                  </span>
                </label>
                <Switch
                  id="validate-before-export"
                  :model-value="options.validateBeforeExport"
                  :disabled="!canExport"
                  @update:model-value="toggleOption('validate_before_export')"
                />
              </div>

              <div v-if="prettyPrintSupported" class="flex items-center gap-3 py-4">
                <div
                  class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-secondary text-secondary-foreground"
                >
                  <Braces class="size-4" />
                </div>
                <label for="pretty-print-output" class="min-w-0 flex-1 cursor-pointer">
                  <span class="block text-sm font-medium">
                    {{ $t("project_settings.export.pretty_print") }}
                  </span>
                  <span class="mt-0.5 block text-xs text-muted-foreground">
                    {{ $t("project_settings.export.pretty_print_description") }}
                  </span>
                </label>
                <Switch
                  id="pretty-print-output"
                  :model-value="options.prettyPrint"
                  :disabled="!canExport"
                  @update:model-value="toggleOption('pretty_print')"
                />
              </div>
            </div>
          </section>
        </div>

        <aside
          data-testid="export-summary"
          class="rounded-xl border border-border bg-card shadow-sm xl:sticky xl:top-5"
        >
          <div class="border-b border-border px-4 py-3.5">
            <p class="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              {{ $t("project_settings.export.summary") }}
            </p>
          </div>

          <div class="space-y-4 p-4">
            <div class="flex items-center gap-3">
              <div
                class="flex size-10 items-center justify-center rounded-lg bg-primary text-primary-foreground"
              >
                <component :is="formatVisual(formatConfig.selected).icon" class="size-4" />
              </div>
              <div class="min-w-0 flex-1">
                <p class="truncate text-sm font-semibold">{{ formatName(selectedFormat) }}</p>
                <p class="text-xs text-muted-foreground">
                  {{ $t("project_settings.export.download_file") }}
                  <span class="font-medium uppercase">.{{ formatConfig.extension }}</span>
                </p>
              </div>
            </div>

            <dl class="space-y-2.5 border-y border-border py-3 text-xs">
              <div class="flex items-center justify-between gap-3">
                <dt class="text-muted-foreground">{{ $t("project_settings.export.content") }}</dt>
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
                <dt class="text-muted-foreground">{{ $t("project_settings.export.entities") }}</dt>
                <dd class="font-medium tabular-nums">{{ includedEntityCount }}</dd>
              </div>
              <div v-if="assetsSupported" class="flex items-center justify-between gap-3">
                <dt class="text-muted-foreground">{{ $t("project_settings.export.assets") }}</dt>
                <dd class="truncate font-medium">{{ selectedAssetMode.label }}</dd>
              </div>
              <div
                v-if="supportedSet.has('localization') && sectionsSet.has('localization')"
                class="flex items-center justify-between gap-3"
              >
                <dt class="text-muted-foreground">
                  {{ $t("project_settings.export.localization_policy") }}
                </dt>
                <dd class="truncate font-medium">
                  {{
                    localizationPolicyOptions.find(
                      (policy) => policy.value === options.localizationPolicy,
                    )?.label
                  }}
                </dd>
              </div>
              <div class="flex items-center justify-between gap-3">
                <dt class="text-muted-foreground">{{ $t("project_settings.export.preflight") }}</dt>
                <dd class="flex items-center gap-1.5 font-medium">
                  <CheckCircle2
                    v-if="options.validateBeforeExport"
                    class="size-3.5 text-emerald-600 dark:text-emerald-400"
                  />
                  <CircleX v-else class="size-3.5 text-muted-foreground" />
                  {{
                    options.validateBeforeExport
                      ? $t("project_settings.export.enabled")
                      : $t("project_settings.export.disabled")
                  }}
                </dd>
              </div>
            </dl>

            <div class="space-y-2">
              <p
                v-if="!canExport"
                data-testid="export-no-permission"
                class="flex items-start gap-2 rounded-lg border border-border bg-muted p-3 text-xs text-muted-foreground"
                role="status"
              >
                <ShieldCheck class="mt-0.5 size-3.5 shrink-0" />
                <span>{{ $t("project_settings.export.no_permission") }}</span>
              </p>
              <Button
                type="button"
                variant="outline"
                class="w-full"
                :disabled="!canExport || validating || !hasExportableContent"
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

              <Button v-if="canDownload" class="w-full" as-child>
                <a
                  :href="exportDownloadUrl"
                  :aria-busy="downloading"
                  data-live-link-exempt="download"
                  data-testid="download-export"
                  @click.prevent="downloadExport"
                >
                  <LoaderCircle v-if="downloading" class="size-4 animate-spin" />
                  <Download v-else class="size-4" />
                  {{ $t("project_settings.export.download", { ext: formatConfig.extension }) }}
                </a>
              </Button>
              <Button v-else class="w-full" disabled>
                <Download class="size-4" />
                {{ $t("project_settings.export.download", { ext: formatConfig.extension }) }}
              </Button>
            </div>

            <p
              v-if="
                canExport &&
                hasExportableContent &&
                options.validateBeforeExport &&
                (!validation || validationIsStale || validation.status === 'errors')
              "
              :class="[
                'flex items-start gap-2 text-xs leading-relaxed',
                !validation || validationIsStale
                  ? 'text-amber-700 dark:text-amber-300'
                  : 'text-destructive',
              ]"
              role="alert"
            >
              <AlertTriangle
                v-if="!validation || validationIsStale"
                class="mt-0.5 size-3.5 shrink-0"
              />
              <CircleX v-else class="mt-0.5 size-3.5 shrink-0" />
              <span>
                {{
                  !validation || validationIsStale
                    ? $t("project_settings.export.validate_before")
                    : $t("project_settings.export.download_blocked")
                }}
              </span>
            </p>

            <p
              v-if="downloadError"
              id="export-download-error"
              class="flex items-start gap-2 text-xs leading-relaxed text-destructive"
              role="alert"
            >
              <CircleX class="mt-0.5 size-3.5 shrink-0" />
              <span>{{ downloadError }}</span>
            </p>

            <p class="flex items-start gap-2 text-xs leading-relaxed text-muted-foreground">
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
        :data-stale="validationIsStale ? 'true' : 'false'"
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
            <AlertTriangle v-if="validationIsStale" class="size-5" />
            <CheckCircle2 v-else-if="validation.status === 'passed'" class="size-5" />
            <AlertTriangle v-else-if="validation.status === 'warnings'" class="size-5" />
            <CircleX v-else class="size-5" />
          </div>
          <div class="min-w-0 flex-1">
            <div class="flex flex-wrap items-center gap-2">
              <h3 class="font-semibold">
                {{
                  validationIsStale
                    ? $t("project_settings.export.validate_before")
                    : validationTitle(validation.status)
                }}
              </h3>
              <span
                :class="[
                  'inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-medium',
                  validationIsStale && 'border-amber-500/30 text-amber-700 dark:text-amber-300',
                  !validationIsStale &&
                    validation.status === 'passed' &&
                    'border-emerald-500/30 text-emerald-700 dark:text-emerald-300',
                  !validationIsStale &&
                    validation.status === 'warnings' &&
                    'border-amber-500/30 text-amber-700 dark:text-amber-300',
                  !validationIsStale &&
                    validation.status === 'errors' &&
                    'border-destructive/30 text-destructive',
                ]"
              >
                {{
                  validationIsStale
                    ? $t("project_settings.export.validate")
                    : validationStatusLabel(validation.status)
                }}
              </span>
            </div>
            <p v-if="!validationIsStale" class="mt-1 text-sm text-muted-foreground">
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
              class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-destructive"
            >
              <CircleX class="size-3.5" />
              {{ $t("project_settings.export.error_findings") }}
            </h4>
            <div
              v-for="(finding, index) in visibleErrors"
              :key="`error-${index}`"
              class="rounded-lg border border-destructive/20 bg-card/65 px-3 py-2.5 text-sm"
            >
              <LiveLink
                v-if="finding.href"
                :to="finding.href"
                class="font-medium underline decoration-current/30 underline-offset-4 transition hover:decoration-current"
              >
                {{ finding.message }}
              </LiveLink>
              <template v-else>{{ finding.message }}</template>
            </div>
            <p
              v-if="hiddenFindingCount(validationCounts.errors)"
              class="text-xs text-muted-foreground"
            >
              {{
                $t("project_settings.export.more_findings", {
                  count: hiddenFindingCount(validationCounts.errors),
                })
              }}
            </p>
          </div>

          <div v-if="validation.warnings?.length" class="space-y-2">
            <h4
              class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-amber-700 dark:text-amber-300"
            >
              <AlertTriangle class="size-3.5" />
              {{ $t("project_settings.export.warning_findings") }}
            </h4>
            <div
              v-for="(finding, index) in visibleWarnings"
              :key="`warning-${index}`"
              class="rounded-lg border border-amber-500/20 bg-card/65 px-3 py-2.5 text-sm"
            >
              <LiveLink
                v-if="finding.href"
                :to="finding.href"
                class="font-medium underline decoration-current/30 underline-offset-4 transition hover:decoration-current"
              >
                {{ finding.message }}
              </LiveLink>
              <template v-else>{{ finding.message }}</template>
            </div>
            <p
              v-if="hiddenFindingCount(validationCounts.warnings)"
              class="text-xs text-muted-foreground"
            >
              {{
                $t("project_settings.export.more_findings", {
                  count: hiddenFindingCount(validationCounts.warnings),
                })
              }}
            </p>
          </div>

          <div v-if="validation.info?.length" class="space-y-2">
            <h4
              class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-sky-700 dark:text-sky-300"
            >
              <Info class="size-3.5" />
              {{ $t("project_settings.export.info_findings") }}
            </h4>
            <div
              v-for="(finding, index) in visibleInfo"
              :key="`info-${index}`"
              class="rounded-lg border border-sky-500/20 bg-card/65 px-3 py-2.5 text-sm"
            >
              <LiveLink
                v-if="finding.href"
                :to="finding.href"
                class="font-medium underline decoration-current/30 underline-offset-4 transition hover:decoration-current"
              >
                {{ finding.message }}
              </LiveLink>
              <template v-else>{{ finding.message }}</template>
            </div>
            <p
              v-if="hiddenFindingCount(validationCounts.info)"
              class="text-xs text-muted-foreground"
            >
              {{
                $t("project_settings.export.more_findings", {
                  count: hiddenFindingCount(validationCounts.info),
                })
              }}
            </p>
          </div>
        </div>

        <div
          v-if="!validationIsStale && validation.status === 'passed' && !validation.info?.length"
          class="flex items-center gap-2 border-t border-emerald-500/15 px-5 py-3 text-sm text-emerald-700 dark:text-emerald-300"
        >
          <CheckCircle2 class="size-4" />
          <span>{{ $t("project_settings.export.no_issues") }}</span>
        </div>
      </section>
    </template>
  </section>
</template>
