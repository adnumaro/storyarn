<script setup lang="ts">
import { Layers, SlidersHorizontal } from "lucide-vue-next";
import { computed } from "vue";
import { useLive } from "@shared/composables/useLive.ts";
import SceneLayerList from "./SceneLayerList.vue";

interface LayerItem {
  id: number | string;
  name: string;
  visible: boolean;
  fogEnabled: boolean;
}

const {
  layers = [],
  activeLayerId = null,
  canEdit = false,
  editMode = true,
  popoverOpen = false,
} = defineProps<{
  layers: LayerItem[];
  activeLayerId: number | string | null;
  canEdit: boolean;
  editMode: boolean;
  popoverOpen: boolean;
}>();

const live = useLive();
const layerListKey = computed(() => layers.map((layer) => layer.id).join(":"));

function togglePopover(): void {
  live.pushEvent("toggle_layers_popover", {});
}

function openFogSettings(): void {
  live.pushEvent("open_scene_settings", {});
  live.pushEvent("toggle_layers_popover", {});
}
</script>

<template>
  <div class="relative">
    <button
      type="button"
      class="inline-flex items-center gap-1.5 h-8 px-3 text-sm bg-surface border border-border rounded-lg shadow-md hover:bg-accent transition-colors"
      :title="popoverOpen ? $t('scenes.layers.hide_layers') : $t('scenes.layers.show_layers')"
      :aria-label="popoverOpen ? $t('scenes.layers.hide_layers') : $t('scenes.layers.show_layers')"
      @click="togglePopover"
    >
      <Layers class="size-4" />
      {{ $t("scenes.layers.layers") }}
    </button>

    <div
      v-if="popoverOpen"
      class="absolute bottom-full right-0 mb-2 bg-surface rounded-lg border border-border shadow-md w-max min-w-44 max-w-64 overflow-hidden flex flex-col"
    >
      <div class="overflow-y-auto p-2">
        <SceneLayerList
          :key="layerListKey"
          :layers="layers"
          :active-layer-id="activeLayerId"
          :can-edit="canEdit"
          :edit-mode="editMode"
        />
      </div>
      <div v-if="canEdit && editMode" class="border-t border-border p-2">
        <button
          type="button"
          class="w-full inline-flex items-center justify-center gap-2 h-7 px-2 rounded-md text-xs text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
          @click="openFogSettings"
        >
          <SlidersHorizontal class="size-3.5" />
          {{ $t("scenes.layers.adjust_fog_design") }}
        </button>
      </div>
    </div>
  </div>
</template>
