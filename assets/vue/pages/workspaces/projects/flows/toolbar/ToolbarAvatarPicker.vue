<script setup>
import { Image, X } from "lucide-vue-next";
import { ref } from "vue";
import {
	Popover,
	PopoverContent,
	PopoverTrigger,
} from "@/vue/components/ui/popover/index.js";

const props = defineProps({
	avatars: { type: Array, default: () => [] },
	hasOverride: { type: Boolean, default: false },
	disabled: { type: Boolean, default: false },
});

const emit = defineEmits(["select"]);
const open = ref(false);

function selectAvatar(id) {
	emit("select", id);
	open.value = false;
}

function clearAvatar() {
	emit("select", null);
	open.value = false;
}
</script>

<template>
  <Popover v-model:open="open">
    <PopoverTrigger as-child>
      <button
        type="button"
        class="v2-toolbar-btn text-xs"
        :class="{ 'text-primary': hasOverride }"
        :disabled="disabled"
        title="Select avatar"
      >
        <Image class="size-3.5" />
      </button>
    </PopoverTrigger>
    <PopoverContent class="w-64 p-2" :side-offset="8" side="top">
      <div class="text-xs font-medium text-muted-foreground mb-2">
        Select avatar
      </div>
      <div class="grid grid-cols-3 gap-1.5">
        <button
          v-for="avatar in avatars"
          :key="avatar.id"
          type="button"
          class="aspect-square rounded-md overflow-hidden border border-border hover:border-primary transition-colors cursor-pointer"
          @click="selectAvatar(avatar.id)"
        >
          <img
            :src="avatar.url"
            :alt="avatar.name || ''"
            class="w-full h-full object-cover"
          />
        </button>
      </div>
      <button
        v-if="hasOverride"
        type="button"
        class="flex items-center gap-1.5 w-full mt-2 px-2 py-1.5 rounded text-xs text-muted-foreground hover:bg-accent transition-colors"
        @click="clearAvatar"
      >
        <X class="size-3" />
        Use default
      </button>
    </PopoverContent>
  </Popover>
</template>
