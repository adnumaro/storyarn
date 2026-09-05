<script setup lang="ts">
import { MessageSquare, Square, UserRound } from "@lucide/vue";
import { computed, type Component } from "vue";
import LiveLink from "@components/navigation/LiveLink.vue";
import { SOURCE_TYPE_I18N, SOURCE_TYPE_KEYS, type SourceType } from "../../domain/status";
import { workbenchUrl } from "../../navigation/workbenchUrl";

/** What the language is made of; each row opens the workbench filtered by type. */
const { typeCounts, workbenchBase } = defineProps<{
  typeCounts: Record<string, number>;
  workbenchBase: string;
}>();

const icons: Record<SourceType, Component> = {
  flow_node: MessageSquare,
  block: Square,
  sheet: UserRound,
};

const hintKeys: Record<SourceType, string> = {
  flow_node: "localization.overview.content.flow_node_hint",
  block: "localization.overview.content.block_hint",
  sheet: "localization.overview.content.sheet_hint",
};

const rows = computed(() =>
  SOURCE_TYPE_KEYS.map((type) => ({
    type,
    icon: icons[type],
    labelKey: SOURCE_TYPE_I18N[type],
    hintKey: hintKeys[type],
    count: typeCounts[type] ?? 0,
    href: workbenchUrl(workbenchBase, { sourceType: type }),
  })),
);

const empty = computed(() => rows.value.every((row) => row.count === 0));
</script>

<template>
  <div class="flex flex-col gap-2 rounded-lg border border-border bg-card px-4 py-3.5">
    <div class="text-[13px] font-medium">{{ $t("localization.overview.content.title") }}</div>
    <p v-if="empty" class="py-2 text-sm text-muted-foreground">
      {{ $t("localization.overview.content.empty") }}
    </p>
    <div v-else class="flex flex-col">
      <LiveLink
        v-for="row in rows"
        :key="row.type"
        :to="row.href"
        class="flex items-center gap-2.5 py-1.5 text-[13px] text-foreground transition-colors hover:text-primary"
      >
        <component :is="row.icon" class="size-3.5 shrink-0 text-muted-foreground" />
        <span class="min-w-0 flex-1 truncate">
          {{ $t(row.labelKey) }}
          <span class="text-muted-foreground"> · {{ $t(row.hintKey) }}</span>
        </span>
        <span class="tabular-nums text-muted-foreground">{{ row.count }}</span>
      </LiveLink>
    </div>
  </div>
</template>
