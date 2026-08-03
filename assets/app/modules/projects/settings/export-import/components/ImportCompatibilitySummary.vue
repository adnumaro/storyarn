<script setup lang="ts">
import { computed } from "vue";
import { AlertTriangle } from "@lucide/vue";
import { useI18n } from "vue-i18n";
import type { YarnImportIssueSummary } from "@modules/projects/settings/export-import/types";

/**
 * Aggregate counts of the conversions Yarn cannot express exactly.
 *
 * Counts only: no imported text or examples cross this boundary.
 */
const { summary = null, warningCodes = [] } = defineProps<{
  summary?: YarnImportIssueSummary | null;
  warningCodes?: string[];
}>();

const { t, te } = useI18n();

// Issue codes render through the catalog, never raw — a Spanish user must not
// read "dynamic text preserved" in English. Unknown codes fall back to a
// generic, still-localized label rather than leaking the identifier.
function issueLabel(code: string) {
  const key = `project_settings.import.issue_codes.${code}`;
  return te(key) ? t(key) : t("project_settings.import.issue_codes.unknown");
}

const issueRows = computed(() =>
  Object.entries(summary?.counts_by_code ?? {})
    .map(([code, count]) => ({ code, count, label: issueLabel(code) }))
    .sort((left, right) => left.label.localeCompare(right.label)),
);
</script>

<template>
  <section
    v-if="summary && summary.issue_count > 0"
    data-testid="yarn-import-issue-summary"
    class="space-y-3 rounded-xl border border-amber-500/30 bg-amber-500/5 p-4"
  >
    <div class="flex items-start gap-2">
      <AlertTriangle class="mt-0.5 size-4 shrink-0 text-amber-700 dark:text-amber-300" />
      <div>
        <h4 class="text-sm font-semibold">
          {{ $t("project_settings.import.compatibility_summary_title") }}
        </h4>
        <p class="text-xs text-muted-foreground">
          {{ $t("project_settings.import.compatibility_summary_description") }}
        </p>
      </div>
    </div>

    <dl class="grid grid-cols-3 gap-2 text-center">
      <div class="rounded-lg border border-border bg-background px-2 py-2">
        <dt class="text-[11px] text-muted-foreground">
          {{ $t("project_settings.import.compatibility_warning_count") }}
        </dt>
        <dd
          data-testid="yarn-import-warning-count"
          class="text-lg font-semibold tabular-nums text-amber-700 dark:text-amber-300"
        >
          {{ summary.warning_count }}
        </dd>
      </div>
      <div class="rounded-lg border border-border bg-background px-2 py-2">
        <dt class="text-[11px] text-muted-foreground">
          {{ $t("project_settings.import.compatibility_error_count") }}
        </dt>
        <dd
          data-testid="yarn-import-error-count"
          class="text-lg font-semibold tabular-nums text-destructive"
        >
          {{ summary.error_count }}
        </dd>
      </div>
      <div class="rounded-lg border border-border bg-background px-2 py-2">
        <dt class="text-[11px] text-muted-foreground">
          {{ $t("project_settings.import.compatibility_total_count") }}
        </dt>
        <dd data-testid="yarn-import-issue-count" class="text-lg font-semibold tabular-nums">
          {{ summary.issue_count }}
        </dd>
      </div>
    </dl>

    <ul class="flex flex-wrap gap-2" data-testid="yarn-import-issue-code-counts">
      <li
        v-for="issue in issueRows"
        :key="issue.code"
        class="rounded-full border border-border bg-background px-2 py-1 text-xs"
      >
        <span>{{ issue.label }}</span>
        <span class="ml-1 font-semibold tabular-nums">{{ issue.count }}</span>
      </li>
    </ul>

    <p
      v-if="summary.issues_truncated"
      data-testid="yarn-import-issues-truncated"
      class="text-xs text-muted-foreground"
    >
      {{ $t("project_settings.import.compatibility_counts_complete") }}
    </p>
  </section>

  <div
    v-else-if="warningCodes.length > 0"
    class="flex items-start gap-2 rounded-lg border border-amber-500/30 bg-amber-500/10 p-3 text-sm text-foreground"
  >
    <AlertTriangle class="size-5 shrink-0" />
    <span>{{ $t("project_settings.import.compatibility_warnings") }}</span>
  </div>
</template>
