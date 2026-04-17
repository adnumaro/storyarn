<script setup lang="ts">
import { Clapperboard } from "lucide-vue-next";
import { computed } from "vue";
import NodeHeader from "../components/NodeHeader.vue";
import NodeShell from "../components/NodeShell.vue";
import NodeSockets from "../components/NodeSockets.vue";
import type { NodeConfig } from "../lib/node-configs";
import type { ReteEmitFn, ReteNodeData, SheetMapEntry } from "../types";

interface SlugLineNodeData {
  location_sheet_id?: number | string | null;
  avatar_id?: number | string | null;
  int_ext?: string;
  sub_location?: string;
  time_of_day?: string;
  description?: string;
}

const {
  data,
  emit,
  config,
  color,
  sheetsMap = {},
} = defineProps<{
  data: ReteNodeData;
  emit: ReteEmitFn;
  config: NodeConfig;
  color: string;
  sheetsMap?: Record<string, SheetMapEntry>;
}>();

const nodeData = computed<SlugLineNodeData>(() => (data.nodeData as SlugLineNodeData) || {});

const locSheet = computed(() => {
  const sheetId = nodeData.value.location_sheet_id;
  if (!sheetId) return null;
  return sheetsMap[String(sheetId)] || null;
});

const headerLabel = computed(() => locSheet.value?.name || config.label);
const hasError = computed(() => !nodeData.value.location_sheet_id);

// Visual: override avatar > banner > nothing
const overrideAvatarUrl = computed(() => {
  const avatarId = nodeData.value.avatar_id;
  if (!avatarId) return null;
  const avatars = locSheet.value?.avatars || [];
  const found = avatars.find((a) => a.id === avatarId);
  return found?.url || null;
});
const bannerUrl = computed(() => locSheet.value?.banner_url || null);
const hasVisual = computed(() => overrideAvatarUrl.value || bannerUrl.value);

// Slug line: "INT./EXT. SUB_LOCATION - TIME_OF_DAY"
const slugLine = computed(() => {
  const d = nodeData.value;
  const parts: string[] = [];
  const intExt = (d.int_ext || "").toUpperCase().replace("_", "./");
  if (intExt) parts.push(`${intExt}.`);
  if (d.sub_location) parts.push(d.sub_location.toUpperCase());
  if (d.time_of_day) {
    if (parts.length > 0) parts.push("-");
    parts.push(d.time_of_day.toUpperCase());
  }
  return parts.join(" ") || null;
});

const description = computed(() => nodeData.value.description || "");
const hasContent = computed(() => slugLine.value || description.value || hasVisual.value);
</script>

<template>
  <NodeShell
    :color="color"
    :selected="data.selected"
    :extra-class="hasContent ? 'slug-line min-w-[200px] max-w-[280px]' : ''"
  >
    <NodeHeader :color="color" :icon="Clapperboard" :label="headerLabel">
      <div
        v-if="hasError"
        class="ml-auto inline-flex items-center justify-center size-3.5 text-[10px] font-bold rounded-full bg-destructive text-destructive-foreground"
        :title="$t('flows.nodes.slug_line.no_location')"
      >
        !
      </div>
    </NodeHeader>

    <!-- Visual strip: override avatar or banner -->
    <img
      v-if="overrideAvatarUrl"
      :src="overrideAvatarUrl"
      alt=""
      class="block w-[calc(100%-24px)] max-h-50 object-contain rounded-lg mx-3 mt-3"
    />
    <img
      v-else-if="bannerUrl"
      :src="bannerUrl"
      alt=""
      class="block w-[calc(100%-24px)] max-h-50 object-contain rounded-lg mx-3 mt-3"
    />

    <!-- Slug line -->
    <div
      v-if="slugLine"
      class="text-[11px] text-muted-foreground px-3 py-2 max-w-50 border-b border-border/10 wrap-break-word"
    >
      <div class="line-clamp-4 leading-[1.4] font-bold text-xs tracking-wide">
        {{ slugLine }}
      </div>
    </div>

    <!-- Description -->
    <div
      v-if="description"
      class="text-[11px] text-muted-foreground px-3 py-2 max-w-50 border-b border-border/10 wrap-break-word"
    >
      <div class="line-clamp-4 leading-[1.4]">{{ description }}</div>
    </div>

    <NodeSockets :data="data" :emit="emit" />
  </NodeShell>
</template>
