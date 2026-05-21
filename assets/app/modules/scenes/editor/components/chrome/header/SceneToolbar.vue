<script setup lang="ts">
import EditableText from "@components/forms/EditableText.vue";
import { useLive } from "@shared/composables/useLive.ts";

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
  <div class="flex items-center gap-1.5 px-3 h-8">
    <EditableText
      :model-value="sceneName"
      :placeholder="$t('scenes.toolbar.scene_name')"
      tag="span"
      class="text-sm font-medium max-w-50 truncate"
      :disabled="!canEdit"
      @save="saveName"
    />
    <span v-if="sceneShortcut" class="text-xs text-muted-foreground"> #{{ sceneShortcut }} </span>
  </div>
</template>
