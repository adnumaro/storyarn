<script setup lang="ts">
import { AlertTriangle, CheckCircle2, CircleX, Download, Info, LoaderCircle } from "@lucide/vue";
import { computed, onUnmounted, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import LiveLink from "@components/navigation/LiveLink.vue";
import { SettingsRow, SettingsSection } from "@components/settings";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import { Checkbox } from "@components/ui/checkbox";
import { RadioGroup, RadioGroupItem } from "@components/ui/radio-group";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import { Switch } from "@components/ui/switch";
import { useLive } from "@shared/composables/useLive";
import { capture } from "@/js/utils/posthog";
import type {
  ExportOptions,
  FormatConfig,
  FormatOption,
  LocalizationMode,
  LocalizationPolicy,
  SectionConfig,
  ValidationFinding,
  ValidationResult,
} from "../types";

const { t } = useI18n();

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

const sectionOptions = computed(() => [
  {
    key: "sheets",
    label: t("project_settings.export.sections.sheets"),
    description: t("project_settings.export.section_descriptions.sheets"),
  },
  {
    key: "flows",
    label: t("project_settings.export.sections.flows"),
    description: t("project_settings.export.section_descriptions.flows"),
  },
  {
    key: "scenes",
    label: t("project_settings.export.sections.scenes"),
    description: t("project_settings.export.section_descriptions.scenes"),
  },
  {
    key: "localization",
    label: t("project_settings.export.sections.localization"),
    description: t("project_settings.export.section_descriptions.localization"),
  },
]);

const assetModeOptions = computed(() => [
  {
    value: "references",
    label: t("project_settings.export.asset_modes.references.title"),
    description: t("project_settings.export.asset_modes.references.description"),
  },
  {
    value: "embedded",
    label: t("project_settings.export.asset_modes.embedded.title"),
    description: t("project_settings.export.asset_modes.embedded.description"),
  },
  {
    value: "bundled",
    label: t("project_settings.export.asset_modes.bundled.title"),
    description: t("project_settings.export.asset_modes.bundled.description"),
  },
]);

const localizationPolicyOptions = computed<Array<{ value: LocalizationPolicy; label: string }>>(
  () => [
    { value: "release", label: t("project_settings.export.quality_release") },
    { value: "preview", label: t("project_settings.export.quality_preview") },
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
const localizationIncluded = computed(
  () => supportedSet.value.has("localization") && sectionsSet.value.has("localization"),
);
const prettyPrintSupported = computed(() => formatConfig.selected === "unity");
const selectedAssetMode = computed(
  () =>
    assetModeOptions.value.find((assetMode) => assetMode.value === options.assetMode) ??
    assetModeOptions.value[0],
);
const selectedPolicy = computed(
  () =>
    localizationPolicyOptions.value.find((policy) => policy.value === options.localizationPolicy) ??
    localizationPolicyOptions.value[0],
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

interface FindingGroup {
  key: "errors" | "warnings" | "info";
  label: string;
  tone: string;
  findings: ValidationFinding[];
  hidden: number;
}

const findingGroups = computed<FindingGroup[]>(() => {
  const groups: FindingGroup[] = [
    {
      key: "errors",
      label: t("project_settings.export.error_findings"),
      tone: "text-destructive",
      findings: validation?.errors?.slice(0, MAX_VISIBLE_FINDINGS) ?? [],
      hidden: hiddenFindingCount(validationCounts.value.errors),
    },
    {
      key: "warnings",
      label: t("project_settings.export.warning_findings"),
      tone: "text-amber-700 dark:text-amber-300",
      findings: validation?.warnings?.slice(0, MAX_VISIBLE_FINDINGS) ?? [],
      hidden: hiddenFindingCount(validationCounts.value.warnings),
    },
    {
      key: "info",
      label: t("project_settings.export.info_findings"),
      tone: "text-sky-700 dark:text-sky-300",
      findings: validation?.info?.slice(0, MAX_VISIBLE_FINDINGS) ?? [],
      hidden: hiddenFindingCount(validationCounts.value.info),
    },
  ];

  return groups.filter((group) => group.findings.length > 0);
});

function hiddenFindingCount(total: number) {
  return Math.max(0, total - MAX_VISIBLE_FINDINGS);
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
  if (canExport && mode !== options.assetMode) live.pushEvent("set_asset_mode", { mode });
}

function setLocalizationPolicy(policy: unknown) {
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

type BadgeVariant = "default" | "secondary" | "destructive" | "outline";

function validationBadgeVariant(status: string): BadgeVariant {
  if (validationIsStale.value) return "outline";
  if (status === "errors") return "destructive";
  if (status === "warnings") return "default";
  return "secondary";
}

const contentHint = computed(() =>
  t("project_settings.export.content_hint", {
    selected: includedSections.value.length,
    total: sectionOptions.value.length,
  }),
);

const downloadHint = computed(() => {
  if (!canExport || !hasExportableContent.value || !options.validateBeforeExport) return null;
  if (!validation || validationIsStale.value) return t("project_settings.export.validate_before");
  if (validation.status === "errors") return t("project_settings.export.download_blocked");

  return null;
});
</script>

<template>
  <div
    id="export-workspace"
    class="grid gap-8 xl:grid-cols-[minmax(0,1fr)_300px] xl:items-start"
    :data-format="formatConfig.selected"
  >
    <div class="flex min-w-0 flex-col gap-8">
      <SettingsSection
        :title="t('project_settings.export.destination')"
        :hint="t('project_settings.export.destination_hint')"
      >
        <fieldset id="export-format-options" class="min-w-0">
          <legend class="sr-only">{{ t("project_settings.export.choose_format") }}</legend>
          <RadioGroup
            :model-value="formatConfig.selected"
            :disabled="!canExport"
            class="divide-y divide-border"
            @update:model-value="setFormat"
          >
            <label
              v-for="format in visibleFormats"
              :key="format.format"
              :data-testid="`export-format-${format.format}`"
              :data-selected="formatConfig.selected === format.format ? 'true' : 'false'"
              :class="[
                'group grid grid-cols-1 items-center gap-x-6 gap-y-2 px-4 py-3 transition-colors sm:grid-cols-[minmax(0,1fr)_auto]',
                canExport ? 'cursor-pointer hover:bg-accent/40' : 'cursor-default',
                'focus-within:bg-accent/40',
              ]"
            >
              <RadioGroupItem
                :value="format.format"
                :disabled="!canExport"
                :aria-label="format.label"
                class="sr-only"
              />
              <span class="min-w-0">
                <span class="flex min-w-0 flex-wrap items-center gap-2">
                  <span class="font-medium">{{ formatName(format) }}</span>
                  <code
                    v-if="format.extension"
                    class="rounded border border-border px-1 font-mono text-[11px] leading-5 text-muted-foreground"
                  >
                    {{ extensionLabel(format.extension) }}
                  </code>
                  <Badge variant="outline" class="font-normal text-muted-foreground">
                    {{ localizationModeLabel(format.localizationMode) }}
                  </Badge>
                </span>
                <span class="block text-[13px] text-muted-foreground">
                  {{ formatDescription(format.format) }}
                </span>
              </span>
              <span class="flex items-center justify-end">
                <Badge v-if="formatConfig.selected === format.format">
                  {{ t("project_settings.export.selected") }}
                </Badge>
                <span
                  v-else
                  class="inline-flex h-8 items-center rounded-md px-2.5 text-[13px] font-medium text-muted-foreground transition-colors group-hover:text-foreground"
                >
                  {{ t("project_settings.export.use") }}
                </span>
              </span>
            </label>
          </RadioGroup>
        </fieldset>
      </SettingsSection>

      <template v-if="selectedFormatVisible">
        <SettingsSection :title="t('project_settings.export.content')" :hint="contentHint">
          <label
            v-for="section in sectionOptions"
            :key="section.key"
            :data-testid="`export-section-${section.key}`"
            :class="[
              'grid grid-cols-1 items-center gap-x-6 gap-y-2 px-4 py-3 sm:grid-cols-[minmax(0,1fr)_auto]',
              supportedSet.has(section.key)
                ? canExport
                  ? 'cursor-pointer hover:bg-accent/40'
                  : 'cursor-default'
                : 'cursor-not-allowed opacity-55',
            ]"
          >
            <span class="min-w-0">
              <span class="flex min-w-0 flex-wrap items-center gap-2">
                <span class="font-medium">{{ section.label }}</span>
                <span
                  v-if="supportedSet.has(section.key) && hasEntityCount(section.key)"
                  class="text-[13px] tabular-nums text-muted-foreground"
                >
                  {{ sectionConfig.entityCounts[section.key] }}
                </span>
                <Badge
                  v-if="!supportedSet.has(section.key)"
                  variant="outline"
                  class="font-normal text-muted-foreground"
                >
                  {{
                    t("project_settings.export.not_supported_by", {
                      format: formatName(selectedFormat),
                    })
                  }}
                </Badge>
              </span>
              <span class="block text-[13px] text-muted-foreground">{{ section.description }}</span>
            </span>
            <span class="flex items-center justify-end">
              <Checkbox
                :model-value="supportedSet.has(section.key) && sectionsSet.has(section.key)"
                :disabled="!canExport || !supportedSet.has(section.key)"
                :aria-label="section.label"
                @update:model-value="toggleSection(section.key)"
              />
            </span>
          </label>

          <template v-if="!hasExportableContent" #footer>
            <span class="inline-flex items-start gap-1.5 text-amber-700 dark:text-amber-300">
              <AlertTriangle class="mt-0.5 size-3.5 shrink-0" aria-hidden="true" />
              <span role="alert">{{ t("project_settings.export.select_content_warning") }}</span>
            </span>
          </template>
        </SettingsSection>

        <SettingsSection :title="t('project_settings.export.output')">
          <SettingsRow
            v-if="localizationIncluded"
            id="export-localization-policy-options"
            :label="t('project_settings.export.localization_policy')"
            :hint="
              options.localizationPolicy === 'release'
                ? t('project_settings.export.localization_release')
                : t('project_settings.export.localization_preview')
            "
          >
            <Select
              :model-value="options.localizationPolicy"
              :disabled="!canExport"
              @update:model-value="setLocalizationPolicy"
            >
              <SelectTrigger
                id="export-localization-policy"
                class="w-[170px]"
                :aria-label="t('project_settings.export.localization_policy')"
              >
                <SelectValue>{{ selectedPolicy.label }}</SelectValue>
              </SelectTrigger>
              <SelectContent>
                <SelectItem
                  v-for="policy in localizationPolicyOptions"
                  :key="policy.value"
                  :value="policy.value"
                  :data-testid="`export-localization-${policy.value}`"
                >
                  {{ policy.label }}
                </SelectItem>
              </SelectContent>
            </Select>
          </SettingsRow>

          <SettingsRow
            v-if="assetsSupported"
            id="export-asset-mode-options"
            :label="t('project_settings.export.assets')"
            :hint="selectedAssetMode.description"
          >
            <div
              class="flex flex-wrap items-center gap-1 rounded-lg border border-border bg-muted/40 p-1"
              role="group"
              :aria-label="t('project_settings.export.assets')"
            >
              <button
                v-for="assetMode in assetModeOptions"
                :key="assetMode.value"
                type="button"
                :data-testid="`export-assets-${assetMode.value}`"
                :aria-pressed="options.assetMode === assetMode.value"
                :disabled="!canExport"
                :class="[
                  'inline-flex h-7 items-center rounded-md px-2.5 text-xs font-medium transition-colors disabled:cursor-not-allowed',
                  options.assetMode === assetMode.value
                    ? 'bg-background text-foreground shadow-sm'
                    : 'text-muted-foreground hover:text-foreground',
                ]"
                @click="setAssetMode(assetMode.value)"
              >
                {{ assetMode.label }}
              </button>
            </div>
          </SettingsRow>

          <SettingsRow
            :label="t('project_settings.export.validate_before')"
            :hint="t('project_settings.export.validate_before_description')"
            html-for="validate-before-export"
          >
            <Switch
              id="validate-before-export"
              :model-value="options.validateBeforeExport"
              :disabled="!canExport"
              @update:model-value="toggleOption('validate_before_export')"
            />
          </SettingsRow>

          <SettingsRow
            v-if="prettyPrintSupported"
            :label="t('project_settings.export.pretty_print')"
            :hint="t('project_settings.export.pretty_print_description')"
            html-for="pretty-print-output"
          >
            <Switch
              id="pretty-print-output"
              :model-value="options.prettyPrint"
              :disabled="!canExport"
              @update:model-value="toggleOption('pretty_print')"
            />
          </SettingsRow>
        </SettingsSection>
      </template>
    </div>

    <aside
      v-if="selectedFormatVisible"
      data-testid="export-summary"
      class="flex flex-col rounded-lg border border-border bg-card xl:sticky xl:top-6"
    >
      <div class="border-b border-border px-4 py-3.5">
        <div class="text-[11px] uppercase tracking-[0.06em] text-muted-foreground">
          {{ t("project_settings.export.summary") }}
        </div>
        <div class="mt-1.5 text-base font-medium">
          {{ formatName(selectedFormat) }} · .{{ formatConfig.extension.toLowerCase() }}
        </div>
      </div>

      <dl class="flex flex-col gap-2 px-4 py-3 text-[13px]">
        <div class="flex items-center justify-between gap-3">
          <dt class="text-muted-foreground">{{ t("project_settings.export.content") }}</dt>
          <dd>{{ t("project_settings.export.area_count", includedSections.length) }}</dd>
        </div>
        <div class="flex items-center justify-between gap-3">
          <dt class="text-muted-foreground">{{ t("project_settings.export.entities") }}</dt>
          <dd class="tabular-nums">{{ includedEntityCount }}</dd>
        </div>
        <div v-if="assetsSupported" class="flex items-center justify-between gap-3">
          <dt class="text-muted-foreground">{{ t("project_settings.export.assets") }}</dt>
          <dd class="truncate">{{ selectedAssetMode.label }}</dd>
        </div>
        <div v-if="localizationIncluded" class="flex items-center justify-between gap-3">
          <dt class="text-muted-foreground">{{ t("project_settings.export.quality") }}</dt>
          <dd class="truncate">{{ selectedPolicy.label }}</dd>
        </div>
        <div class="flex items-center justify-between gap-3">
          <dt class="text-muted-foreground">{{ t("project_settings.export.preflight") }}</dt>
          <dd>
            {{
              options.validateBeforeExport
                ? t("project_settings.export.preflight_on")
                : t("project_settings.export.preflight_off")
            }}
          </dd>
        </div>
      </dl>

      <div class="flex flex-col gap-2 border-t border-border px-4 pb-4 pt-3">
        <p
          v-if="!canExport"
          data-testid="export-no-permission"
          class="flex items-start gap-2 rounded-md border border-border bg-muted px-3 py-2 text-xs text-muted-foreground"
          role="status"
        >
          <Info class="mt-0.5 size-3.5 shrink-0" aria-hidden="true" />
          <span>{{ t("project_settings.export.no_permission") }}</span>
        </p>

        <Button
          type="button"
          variant="outline"
          class="w-full"
          :disabled="!canExport || validating || !hasExportableContent"
          data-testid="validate-export"
          @click="validateExport"
        >
          <LoaderCircle v-if="validating" class="size-4 animate-spin" aria-hidden="true" />
          {{
            validating
              ? t("project_settings.export.validating")
              : t("project_settings.export.validate")
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
            <LoaderCircle v-if="downloading" class="size-4 animate-spin" aria-hidden="true" />
            <Download v-else class="size-4" aria-hidden="true" />
            {{ t("project_settings.export.download", { ext: formatConfig.extension }) }}
          </a>
        </Button>
        <Button v-else class="w-full" disabled>
          <Download class="size-4" aria-hidden="true" />
          {{ t("project_settings.export.download", { ext: formatConfig.extension }) }}
        </Button>

        <p
          v-if="downloadHint"
          :class="[
            'flex items-start gap-1.5 text-xs leading-relaxed',
            validation && !validationIsStale && validation.status === 'errors'
              ? 'text-destructive'
              : 'text-amber-700 dark:text-amber-300',
          ]"
          role="alert"
        >
          <AlertTriangle class="mt-0.5 size-3.5 shrink-0" aria-hidden="true" />
          <span>{{ downloadHint }}</span>
        </p>

        <p
          v-if="downloadError"
          id="export-download-error"
          class="flex items-start gap-1.5 text-xs leading-relaxed text-destructive"
          role="alert"
        >
          <CircleX class="mt-0.5 size-3.5 shrink-0" aria-hidden="true" />
          <span>{{ downloadError }}</span>
        </p>

        <p class="flex items-start gap-1.5 text-xs leading-relaxed text-muted-foreground">
          <Info class="mt-0.5 size-3.5 shrink-0" aria-hidden="true" />
          <span>{{ t("project_settings.export.download_note") }}</span>
        </p>
      </div>
    </aside>

    <SettingsSection
      v-if="validation && selectedFormatVisible"
      id="export-validation-results"
      class="xl:col-span-2"
      :data-status="validation.status"
      :data-stale="validationIsStale ? 'true' : 'false'"
      :title="
        validationIsStale
          ? t('project_settings.export.validate_before')
          : validationTitle(validation.status)
      "
      :hint="validationIsStale ? null : validationDescription(validation.status)"
      aria-live="polite"
    >
      <template #title-extra>
        <Badge :variant="validationBadgeVariant(validation.status)">
          {{
            validationIsStale
              ? t("project_settings.export.validate")
              : validationStatusLabel(validation.status)
          }}
        </Badge>
      </template>

      <div
        v-for="group in findingGroups"
        :key="group.key"
        :data-findings="group.key"
        class="px-4 py-3"
      >
        <div :class="['text-xs font-semibold uppercase tracking-wide', group.tone]">
          {{ group.label }}
        </div>
        <ul class="mt-2 flex flex-col gap-1.5 text-sm">
          <li v-for="(finding, index) in group.findings" :key="`${group.key}-${index}`">
            <LiveLink
              v-if="finding.href"
              :to="finding.href"
              class="font-medium underline decoration-current/30 underline-offset-4 transition hover:decoration-current"
            >
              {{ finding.message }}
            </LiveLink>
            <template v-else>{{ finding.message }}</template>
          </li>
        </ul>
        <p v-if="group.hidden" class="mt-2 text-xs text-muted-foreground">
          {{ t("project_settings.export.more_findings", { count: group.hidden }) }}
        </p>
      </div>

      <div
        v-if="!validationIsStale && validation.status === 'passed' && findingGroups.length === 0"
        class="flex items-center gap-2 px-4 py-3 text-sm text-emerald-700 dark:text-emerald-300"
      >
        <CheckCircle2 class="size-4" aria-hidden="true" />
        <span>{{ t("project_settings.export.no_issues") }}</span>
      </div>
    </SettingsSection>
  </div>
</template>
