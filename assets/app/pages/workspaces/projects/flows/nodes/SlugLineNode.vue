<script setup>
import { Clapperboard } from "lucide-vue-next";
import { computed } from "vue";
import NodeHeader from "../components/NodeHeader.vue";
import NodeShell from "../components/NodeShell.vue";
import NodeSockets from "../components/NodeSockets.vue";

const { data, emit, config, color, sheetsMap } = defineProps({
  data: { type: Object, required: true },
  emit: { type: Function, required: true },
  config: { type: Object, required: true },
  color: { type: String, required: true },
  sheetsMap: { type: Object, default: () => ({}) },
});

const nodeData = computed(() => data.nodeData || {});

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
  const parts = [];
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
        title="No location set"
      >
        !
      </div>
    </NodeHeader>

    <!-- Visual strip: override avatar or banner -->
    <img
      v-if="overrideAvatarUrl"
      :src="overrideAvatarUrl"
      alt=""
      class="block w-[calc(100%-24px)] max-h-[200px] object-contain rounded-lg mx-3 mt-3"
    />
    <img
      v-else-if="bannerUrl"
      :src="bannerUrl"
      alt=""
      class="block w-[calc(100%-24px)] max-h-[200px] object-contain rounded-lg mx-3 mt-3"
    />

    <!-- Slug line -->
    <div
      v-if="slugLine"
      class="text-[11px] text-muted-foreground px-3 py-2 max-w-[200px] border-b border-border/10 break-words"
    >
      <div class="line-clamp-4 leading-[1.4] font-bold text-xs tracking-wide">
        {{ slugLine }}
      </div>
    </div>

    <!-- Description -->
    <div
      v-if="description"
      class="text-[11px] text-muted-foreground px-3 py-2 max-w-[200px] border-b border-border/10 break-words"
    >
      <div class="line-clamp-4 leading-[1.4]">{{ description }}</div>
    </div>

    <NodeSockets :data="data" :emit="emit" />
  </NodeShell>
</template>
