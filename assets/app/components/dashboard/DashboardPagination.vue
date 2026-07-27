<script setup lang="ts">
import { ChevronLeft, ChevronRight } from "lucide-vue-next";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import type { DashboardPagination } from "./types";

type PageToken = number | "start-ellipsis" | "end-ellipsis";

const { pagination, totalLabel, previousLabel, nextLabel } = defineProps<{
  pagination: DashboardPagination;
  totalLabel: string;
  previousLabel: string;
  nextLabel: string;
}>();

const emit = defineEmits<{
  page: [page: number];
}>();

const { t } = useI18n();

const totalPages = computed(() => {
  const value = Math.trunc(pagination.totalPages);
  return Number.isFinite(value) ? Math.max(1, value) : 1;
});

const currentPage = computed(() => {
  const value = Math.trunc(pagination.page);
  const page = Number.isFinite(value) ? value : 1;
  return Math.min(totalPages.value, Math.max(1, page));
});

const pageTokens = computed<PageToken[]>(() => {
  const total = totalPages.value;
  const current = currentPage.value;

  if (total <= 7) {
    return Array.from({ length: total }, (_, index) => index + 1);
  }

  if (current <= 4) {
    return [1, 2, 3, 4, 5, "end-ellipsis", total];
  }

  if (current >= total - 3) {
    return [1, "start-ellipsis", total - 4, total - 3, total - 2, total - 1, total];
  }

  return [1, "start-ellipsis", current - 1, current, current + 1, "end-ellipsis", total];
});

function goToPage(page: number) {
  if (
    !Number.isInteger(page) ||
    page < 1 ||
    page > totalPages.value ||
    page === currentPage.value
  ) {
    return;
  }

  emit("page", page);
}
</script>

<template>
  <div
    data-testid="dashboard-pagination"
    class="flex flex-col gap-3 border-t border-border/60 pt-4 sm:flex-row sm:items-center sm:justify-between"
  >
    <span data-testid="dashboard-pagination-total" class="text-sm text-muted-foreground">
      {{ totalLabel }}
    </span>

    <nav
      v-if="totalPages > 1"
      class="flex flex-wrap items-center gap-1"
      :aria-label="t('common.dashboard.pagination_label')"
      data-testid="dashboard-pagination-pages"
    >
      <Button
        type="button"
        variant="ghost"
        size="icon-sm"
        :aria-label="previousLabel"
        :title="previousLabel"
        :disabled="currentPage <= 1"
        data-testid="dashboard-pagination-previous"
        @click="goToPage(currentPage - 1)"
      >
        <ChevronLeft class="size-4" aria-hidden="true" />
      </Button>

      <template v-for="token in pageTokens" :key="token">
        <span
          v-if="typeof token === 'string'"
          :data-testid="`dashboard-pagination-${token}`"
          class="flex size-8 items-center justify-center text-sm text-muted-foreground"
          aria-hidden="true"
        >
          …
        </span>
        <Button
          v-else
          type="button"
          :variant="token === currentPage ? 'secondary' : 'ghost'"
          size="icon-sm"
          :aria-label="t('common.dashboard.page_label', { page: token })"
          :aria-current="token === currentPage ? 'page' : undefined"
          :data-testid="`dashboard-pagination-page-${token}`"
          @click="goToPage(token)"
        >
          {{ token }}
        </Button>
      </template>

      <Button
        type="button"
        variant="ghost"
        size="icon-sm"
        :aria-label="nextLabel"
        :title="nextLabel"
        :disabled="currentPage >= totalPages"
        data-testid="dashboard-pagination-next"
        @click="goToPage(currentPage + 1)"
      >
        <ChevronRight class="size-4" aria-hidden="true" />
      </Button>
    </nav>
  </div>
</template>
