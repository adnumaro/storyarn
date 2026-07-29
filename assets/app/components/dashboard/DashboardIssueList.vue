<script setup lang="ts" generic="TIssue extends DashboardIssueListItem">
import { AlertTriangle, CircleX, Info } from "@lucide/vue";
import { useI18n } from "vue-i18n";
import DashboardPagination from "./DashboardPagination.vue";
import type {
  DashboardIssueListItem,
  DashboardPagination as DashboardPaginationModel,
} from "./types";

const { issues, pagination } = defineProps<{
  issues: TIssue[];
  pagination: DashboardPaginationModel;
}>();

const emit = defineEmits<{
  page: [page: number];
}>();

defineSlots<{
  description(props: { issue: TIssue }): unknown;
}>();

const { t } = useI18n();
</script>

<template>
  <div
    v-if="issues.length > 0"
    data-testid="dashboard-issue-list"
    class="divide-y divide-border rounded-lg border border-border"
  >
    <a
      v-for="issue in issues"
      :key="issue.id"
      :href="issue.href"
      :data-severity="issue.severity"
      data-phx-link="redirect"
      data-phx-link-state="push"
      class="flex items-start gap-2 px-3 py-2 text-sm transition-colors hover:bg-muted/30"
    >
      <CircleX
        v-if="issue.severity === 'error'"
        data-testid="dashboard-issue-error-icon"
        class="mt-0.5 size-4 shrink-0 text-red-500"
        aria-hidden="true"
      />
      <AlertTriangle
        v-else-if="issue.severity === 'warning'"
        data-testid="dashboard-issue-warning-icon"
        class="mt-0.5 size-4 shrink-0 text-yellow-500"
        aria-hidden="true"
      />
      <Info
        v-else
        data-testid="dashboard-issue-info-icon"
        class="mt-0.5 size-4 shrink-0 text-blue-400"
        aria-hidden="true"
      />
      <span class="sr-only"> {{ t(`common.dashboard.issue_severity.${issue.severity}`) }}: </span>
      <span class="text-muted-foreground">
        <span class="text-foreground">{{ issue.label }}</span>
        · <slot name="description" :issue="issue" />
      </span>
    </a>
  </div>

  <p
    v-else
    data-testid="dashboard-issues-empty-filter"
    class="rounded-lg border border-dashed border-border px-4 py-8 text-center text-sm text-muted-foreground"
  >
    {{ t("common.dashboard.no_matching_issues") }}
  </p>

  <DashboardPagination
    v-if="pagination.total > 0"
    :pagination="pagination"
    :total-label="t('common.dashboard.total_issues', { count: pagination.total })"
    :previous-label="t('common.dashboard.previous_page')"
    :next-label="t('common.dashboard.next_page')"
    @page="emit('page', $event)"
  />
</template>
