<script setup>
import { ImagePlus, RefreshCw, Trash2 } from "lucide-vue-next";
import { useLive } from "@composables/useLive";

const { backgroundUrl, canEdit } = defineProps({
  backgroundUrl: { type: String, default: null },
  canEdit: { type: Boolean, default: false },
});

const live = useLive();

function triggerUpload() {
  const input = document.querySelector("#bg-upload-form input[type=file]");
  if (input) input.click();
}

function removeBackground() {
  live.pushEvent("remove_background", {});
}
</script>

<template>
  <div>
    <label class="text-xs font-medium text-foreground"> Background Image </label>
    <div v-if="backgroundUrl" class="space-y-2 mt-1.5">
      <div class="rounded border border-border overflow-hidden">
        <img :src="backgroundUrl" alt="Scene background" class="w-full h-32 object-cover" />
      </div>
      <div v-if="canEdit" class="flex gap-2">
        <button
          type="button"
          class="flex-1 inline-flex items-center justify-center gap-1.5 h-7 px-2 text-xs rounded-md bg-transparent hover:bg-accent text-foreground transition-colors"
          @click="triggerUpload"
        >
          <RefreshCw class="size-3" />
          Change
        </button>
        <button
          type="button"
          class="flex-1 inline-flex items-center justify-center gap-1.5 h-7 px-2 text-xs rounded-md border border-destructive/30 text-destructive hover:bg-destructive/10 transition-colors"
          @click="removeBackground"
        >
          <Trash2 class="size-3" />
          Remove
        </button>
      </div>
    </div>
    <button
      v-else-if="canEdit"
      type="button"
      class="mt-1.5 w-full inline-flex items-center justify-center gap-1.5 h-8 px-3 text-xs rounded-md border border-dashed border-border hover:bg-accent text-muted-foreground transition-colors"
      @click="triggerUpload"
    >
      <ImagePlus class="size-4" />
      Upload Background
    </button>
  </div>
</template>
