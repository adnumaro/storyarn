<script setup lang="ts" generic="TIssue extends DashboardIssueListItem">
import { LoaderCircle } from "lucide-vue-next";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import DashboardIssueFilters from "./DashboardIssueFilters.vue";
import DashboardIssueList from "./DashboardIssueList.vue";
import type {
  DashboardIssueFilter,
  DashboardIssueFilterOptions,
  DashboardIssueFilterValues,
  DashboardIssueListItem,
  DashboardIssuePagination,
  DashboardLoadStatus,
} from "./types";

const {
  title,
  testIdPrefix,
  status,
  issues,
  pagination,
  filters,
  filterOptions,
  allResourcesLabel,
  codeLabel,
} = defineProps<{
  title: string;
  testIdPrefix: string;
  status: DashboardLoadStatus;
  issues: TIssue[];
  pagination: DashboardIssuePagination;
  filters: DashboardIssueFilterValues;
  filterOptions: DashboardIssueFilterOptions;
  allResourcesLabel: string;
  codeLabel?: (code: string) => string;
}>();

const emit = defineEmits<{
  retry: [];
  filter: [payload: { filter: DashboardIssueFilter; value: string }];
  page: [page: number];
}>();

defineSlots<{
  description(props: { issue: TIssue }): unknown;
}>();

const { t } = useI18n();
const visible = computed(
  () =>
    status === "loading" ||
    status === "error" ||
    status === "stale" ||
    pagination.unfilteredTotal > 0,
);
</script>

<template>
  <section
    v-if="visible"
    :data-testid="`${testIdPrefix}-dashboard-issues`"
    class="space-y-3"
    :aria-busy="status === 'loading' || status === 'refreshing'"
  >
    <div class="flex min-h-6 items-center justify-between gap-3">
      <h2 class="text-sm font-medium">{{ title }}</h2>
      <div
        v-if="status === 'refreshing'"
        :data-testid="`${testIdPrefix}-issues-refreshing`"
        class="inline-flex items-center gap-1.5 text-xs text-muted-foreground"
        role="status"
        aria-live="polite"
      >
        <LoaderCircle class="size-3.5 animate-spin" aria-hidden="true" />
        <span>{{ t("common.dashboard.refreshing_issues") }}</span>
      </div>
    </div>

    <div
      v-if="status === 'loading'"
      :data-testid="`${testIdPrefix}-issues-loading`"
      class="flex items-center justify-center rounded-lg border border-border py-8"
      role="status"
      aria-live="polite"
    >
      <LoaderCircle class="size-5 animate-spin text-muted-foreground" aria-hidden="true" />
      <span class="sr-only">{{ t("common.dashboard.loading_issues") }}</span>
    </div>

    <div
      v-else-if="status === 'error'"
      :data-testid="`${testIdPrefix}-issues-error`"
      class="flex flex-col items-center justify-center gap-3 rounded-lg border border-destructive/30 bg-destructive/5 px-4 py-8 text-center"
      role="alert"
    >
      <p class="text-sm text-destructive">
        {{ t("common.dashboard.issues_load_failed") }}
      </p>
      <Button
        variant="outline"
        size="sm"
        :data-testid="`${testIdPrefix}-issues-retry`"
        @click="emit('retry')"
      >
        {{ t("common.dashboard.retry") }}
      </Button>
    </div>

    <template v-else>
      <div
        v-if="status === 'stale'"
        :data-testid="`${testIdPrefix}-issues-stale`"
        class="flex items-center justify-between gap-3 rounded-lg border border-amber-500/30 bg-amber-500/5 px-4 py-3"
        role="status"
        aria-live="polite"
      >
        <p class="text-sm text-amber-700 dark:text-amber-300">
          {{ t("common.dashboard.issues_stale") }}
        </p>
        <Button
          variant="outline"
          size="sm"
          class="shrink-0"
          :data-testid="`${testIdPrefix}-issues-retry`"
          @click="emit('retry')"
        >
          {{ t("common.dashboard.retry") }}
        </Button>
      </div>

      <template v-if="pagination.unfilteredTotal > 0">
        <DashboardIssueFilters
          :filters="filters"
          :options="filterOptions"
          :all-resources-label="allResourcesLabel"
          :code-label="codeLabel"
          :busy="status === 'refreshing'"
          @change="emit('filter', $event)"
        />

        <DashboardIssueList :issues="issues" :pagination="pagination" @page="emit('page', $event)">
          <template #description="{ issue }">
            <slot name="description" :issue="issue" />
          </template>
        </DashboardIssueList>
      </template>
    </template>
  </section>
</template>
