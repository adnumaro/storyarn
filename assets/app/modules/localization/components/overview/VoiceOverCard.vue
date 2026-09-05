<script setup lang="ts">
import { Mic } from "@lucide/vue";
import { computed } from "vue";
import LiveLink from "@components/navigation/LiveLink.vue";
import { TONES, VO_I18N, VO_STATUS_KEYS, voTone } from "../../domain/status";
import type { VoProgress } from "../../domain/types";
import { workbenchUrl } from "../../navigation/workbenchUrl";

/** Voice-over state of the eligible lines; every tile opens the workbench filtered. */
const { voProgress, workbenchBase } = defineProps<{
  voProgress: VoProgress;
  workbenchBase: string;
}>();

const eligible = computed(
  () => voProgress.none + voProgress.needed + voProgress.recorded + voProgress.approved,
);

const tiles = computed(() =>
  VO_STATUS_KEYS.map((status) => ({
    status,
    labelKey: VO_I18N[status],
    count: voProgress[status],
    dot: TONES[voTone(status)].dot,
    href: workbenchUrl(workbenchBase, { voStatus: status }),
  })),
);
</script>

<template>
  <div class="flex flex-col gap-3 rounded-lg border border-border bg-card px-4 py-3.5">
    <div class="flex items-center gap-2 text-[13px] font-medium">
      <Mic class="size-3.5 text-muted-foreground" />
      {{ $t("localization.overview.voice_over.title") }}
      <span class="ml-auto text-xs font-normal text-muted-foreground">
        {{ $t("localization.overview.voice_over.eligible", eligible) }}
      </span>
    </div>
    <div class="grid grid-cols-2 gap-2 sm:grid-cols-4">
      <LiveLink
        v-for="tile in tiles"
        :key="tile.status"
        :to="tile.href"
        class="flex flex-col gap-1 rounded-md border border-border bg-background px-3 py-2.5 text-foreground transition-colors hover:bg-accent/60"
      >
        <span class="flex items-center gap-1.5 text-[11px] text-muted-foreground">
          <span :class="['size-[7px] rounded-full', tile.dot]" aria-hidden="true" />
          {{ $t(tile.labelKey) }}
        </span>
        <span class="text-xl font-semibold tracking-tight tabular-nums">{{ tile.count }}</span>
      </LiveLink>
    </div>
  </div>
</template>
