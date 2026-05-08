<script setup lang="ts">
import { Image, X } from "lucide-vue-next";
import { ref } from "vue";
import { Popover, PopoverAnchor, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";

interface AvatarOption {
  id: number;
  url: string;
  name: string;
}

const {
  avatars = [],
  hasOverride = false,
  disabled = false,
} = defineProps<{
  avatars?: AvatarOption[];
  hasOverride?: boolean;
  disabled?: boolean;
}>();

const emit = defineEmits<{
  select: [id: number | null];
}>();
const open = ref(false);

function selectAvatar(id: number) {
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
    <PopoverAnchor as-child>
      <ToolbarTooltip :label="$t('flows.avatar_picker.select_avatar')">
        <PopoverTrigger
          class="toolbar-btn text-xs"
          :class="{ 'text-primary': hasOverride }"
          :disabled="disabled"
        >
          <Image class="size-3.5" />
        </PopoverTrigger>
      </ToolbarTooltip>
    </PopoverAnchor>
    <PopoverContent class="w-64 p-2" :side-offset="8" side="top">
      <div class="text-xs font-medium text-muted-foreground mb-2">
        {{ $t("flows.avatar_picker.select_avatar") }}
      </div>
      <div class="grid grid-cols-3 gap-1.5">
        <button
          v-for="avatar in avatars"
          :key="avatar.id"
          type="button"
          class="aspect-square rounded-md overflow-hidden border border-border hover:border-primary transition-colors cursor-pointer"
          @click="selectAvatar(avatar.id)"
        >
          <img :src="avatar.url" :alt="avatar.name || ''" class="w-full h-full object-cover" />
        </button>
      </div>
      <button
        v-if="hasOverride"
        type="button"
        class="flex items-center gap-1.5 w-full mt-2 px-2 py-1.5 rounded text-xs text-muted-foreground hover:bg-accent transition-colors"
        @click="clearAvatar"
      >
        <X class="size-3" />
        {{ $t("flows.avatar_picker.use_default") }}
      </button>
    </PopoverContent>
  </Popover>
</template>
