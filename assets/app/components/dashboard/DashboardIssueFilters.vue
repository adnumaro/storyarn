<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import DashboardFilterPopover from "./DashboardFilterPopover.vue";
import type {
  DashboardFilterPopoverOption,
  DashboardIssueFilter,
  DashboardIssueFilterOptions,
  DashboardIssueFilterValues,
} from "./types";

const {
  filters,
  options,
  allResourcesLabel,
  codeLabel,
  disabled = false,
} = defineProps<{
  filters: DashboardIssueFilterValues;
  options: DashboardIssueFilterOptions;
  allResourcesLabel: string;
  codeLabel?: (code: string) => string;
  disabled?: boolean;
}>();

const emit = defineEmits<{
  change: [payload: { filter: DashboardIssueFilter; value: string }];
}>();

const { t } = useI18n();

const severityOptions = computed<DashboardFilterPopoverOption[]>(() => [
  {
    value: "all",
    label: t("common.dashboard.issue_filters.all_severities"),
    count: options.totals.severity,
  },
  ...options.severities.map((option) => ({
    ...option,
    label: t(`common.dashboard.issue_filters.severities.${option.value}`),
  })),
]);

const codeOptions = computed<DashboardFilterPopoverOption[]>(() => [
  {
    value: "all",
    label: t("common.dashboard.issue_filters.all_codes"),
    count: options.totals.code,
  },
  ...options.codes.map((option) => ({
    ...option,
    label: issueCodeLabel(option.value),
    searchText: option.value,
  })),
]);

const resourceOptions = computed<DashboardFilterPopoverOption[]>(() => [
  {
    value: "all",
    label: allResourcesLabel,
    count: options.totals.resource,
  },
  ...options.resources.map((option) => ({
    ...option,
    searchText: option.value,
  })),
]);

function changeFilter(filter: DashboardIssueFilter, value: string) {
  if (!value || value === filters[filter]) return;

  emit("change", { filter, value });
}

function issueCodeLabel(code: string) {
  return codeLabel?.(code) ?? code;
}
</script>

<template>
  <div
    data-testid="dashboard-issue-filters"
    class="flex flex-wrap items-center gap-2"
    :aria-busy="disabled"
  >
    <DashboardFilterPopover
      id="dashboard-issue-severity-filter"
      :model-value="filters.severity"
      :options="severityOptions"
      :label="t('common.dashboard.issue_filters.severity_label')"
      :search-placeholder="t('common.search')"
      :empty-label="t('common.no_results')"
      :disabled="disabled"
      trigger-class="sm:max-w-52"
      @update:model-value="changeFilter('severity', $event)"
    />

    <DashboardFilterPopover
      id="dashboard-issue-code-filter"
      :model-value="filters.code"
      :options="codeOptions"
      :label="t('common.dashboard.issue_filters.code_label')"
      :search-placeholder="t('common.search')"
      :empty-label="t('common.no_results')"
      searchable
      :disabled="disabled"
      trigger-class="sm:max-w-72"
      @update:model-value="changeFilter('code', $event)"
    />

    <DashboardFilterPopover
      id="dashboard-issue-resource-filter"
      :model-value="filters.resource"
      :options="resourceOptions"
      :label="t('common.dashboard.issue_filters.resource_label')"
      :search-placeholder="t('common.search')"
      :empty-label="t('common.no_results')"
      searchable
      :disabled="disabled"
      trigger-class="sm:max-w-64"
      @update:model-value="changeFilter('resource', $event)"
    />
  </div>
</template>
