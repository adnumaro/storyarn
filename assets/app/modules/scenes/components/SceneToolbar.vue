<script setup lang="ts">
import EditableText from "@components/EditableText.vue";
import { useLive } from "@composables/useLive";

const {
  canEdit = false,
  sceneName = "",
  sceneShortcut = "",
} = defineProps<{
  canEdit: boolean;
  sceneName: string;
  sceneShortcut: string;
}>();

const live = useLive();

function saveName(name: string): void {
  live.pushEvent("save_name", { name });
}
</script>

<template>
  <div class="flex items-center gap-1.5 surface-panel px-3 h-full">
    <EditableText
      :model-value="sceneName"
      placeholder="Scene name"
      tag="span"
      class="text-sm font-medium max-w-[200px] truncate"
      :disabled="!canEdit"
      @save="saveName"
    />
    <span v-if="sceneShortcut" class="text-xs text-muted-foreground"> #{{ sceneShortcut }} </span>
  </div>
</template>
