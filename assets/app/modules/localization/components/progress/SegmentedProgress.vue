<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { STATUS_I18N, TONES, statusSegments, type StatusCounts } from "../../domain/status";

/**
 * A progress bar segmented by translation status. Final is the only "done";
 * the other statuses show how far the remaining strings have travelled.
 */
const {
  counts,
  total,
  size = "md",
} = defineProps<{
  counts: StatusCounts;
  total: number;
  size?: "sm" | "md";
}>();

const { t } = useI18n();

const segments = computed(() =>
  statusSegments(counts)
    .filter((segment) => segment.value > 0)
    .map((segment) => ({
      key: segment.key,
      fill: TONES[segment.key].dot,
      // Segments grow in proportion to their count from a zero basis, so the
      // gaps between them come out of the track instead of clipping the last one.
      style: { flexGrow: segment.value, flexBasis: "0%" },
      title: `${t(STATUS_I18N[segment.key])}: ${segment.value}`,
    })),
);

const summary = computed(() => {
  const titles = segments.value.map((segment) => segment.title);
  return titles.length > 0
    ? titles.join(" · ")
    : t("localization.overview.final_of_total", { final: 0, total });
});
</script>

<template>
  <div
    :class="[
      'flex w-full overflow-hidden rounded-full bg-muted',
      size === 'sm' ? 'h-[3px]' : 'h-2',
      segments.length > 1 && 'gap-px',
    ]"
    role="img"
    :aria-label="summary"
  >
    <span
      v-for="segment in segments"
      :key="segment.key"
      :class="['h-full min-w-0', segment.fill]"
      :style="segment.style"
      :title="segment.title"
    />
  </div>
</template>
