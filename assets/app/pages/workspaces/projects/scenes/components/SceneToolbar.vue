<script setup>
import EditableText from "@components/EditableText.vue";
import { useLive } from "@composables/useLive";

const props = defineProps({
  canEdit: { type: Boolean, default: false },
  sceneName: { type: String, default: "" },
  sceneShortcut: { type: String, default: "" },
});

const live = useLive();

function saveName(name) {
  live.pushEvent("save_name", { name });
}
</script>

<template>
  <div class="flex items-center gap-1.5 v2-surface-panel px-3 h-full">
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
