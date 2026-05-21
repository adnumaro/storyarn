<script setup lang="ts">
import { LayoutGrid, Plus, X } from "lucide-vue-next";
import { computed } from "vue";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import type { Sheet, SheetAvatar } from "../../../types";
import { generateId } from "@shared/domain/variables.ts";

const { sheet, canEdit = false } = defineProps<{
  sheet: Sheet;
  canEdit?: boolean;
}>();

const emit = defineEmits<{
  "trigger-upload": [];
  "set-default": [id: number | string];
  remove: [id: number | string];
  "open-gallery": [];
}>();

const defaultAvatar = computed<SheetAvatar | null>(
  () => sheet.avatars?.find((a) => a.is_default) || sheet.avatars?.[0] || null,
);
</script>

<template>
  <Popover>
    <PopoverTrigger as-child>
      <button
        :id="`avatar-trigger-${generateId()}`"
        class="shrink-0 group/avatar relative"
        :disabled="!canEdit"
      >
        <img
          v-if="defaultAvatar?.url"
          :src="defaultAvatar.url"
          :alt="sheet.name"
          class="size-20 rounded-lg object-cover"
        />
        <div v-else class="size-20 rounded-lg bg-muted flex items-center justify-center">
          <span class="text-2xl font-bold text-muted-foreground/40">
            {{ sheet.name?.[0]?.toUpperCase() || "?" }}
          </span>
        </div>
      </button>
    </PopoverTrigger>
    <PopoverContent v-if="canEdit" align="start" :side-offset="8" class="w-auto p-3">
      <!-- Film strip -->
      <div class="grid grid-cols-3 gap-2" style="width: 16.5rem">
        <div v-for="avatar in sheet.avatars" :key="avatar.id" class="flex flex-col items-center">
          <div
            :class="[
              'relative group/thumb size-20 rounded-lg overflow-hidden border-2 transition-colors',
              avatar.is_default ? 'border-primary' : 'border-border hover:border-foreground/30',
            ]"
          >
            <button
              v-if="avatar.url"
              type="button"
              class="w-full h-full"
              @click="$emit('set-default', avatar.id)"
            >
              <img :src="avatar.url" :alt="avatar.name || ''" class="w-full h-full object-cover" />
            </button>
            <button
              type="button"
              class="absolute top-0 right-0 size-4 bg-black/70 rounded-bl flex items-center justify-center opacity-0 group-hover/thumb:opacity-100 transition-opacity z-10"
              @click.stop="$emit('remove', avatar.id)"
            >
              <X class="size-2.5 text-white" />
            </button>
          </div>
          <span class="text-[10px] text-muted-foreground truncate max-w-full mt-0.5">
            {{ avatar.name || "" }}
          </span>
        </div>

        <!-- Upload slot -->
        <div class="flex flex-col items-center">
          <button
            class="size-20 rounded-lg border-2 border-dashed border-muted-foreground/20 hover:border-muted-foreground/40 flex items-center justify-center transition-colors"
            @click="$emit('trigger-upload')"
          >
            <Plus class="size-5 text-muted-foreground/40" />
          </button>
        </div>
      </div>

      <!-- Gallery link -->
      <button
        v-if="(sheet.avatars?.length ?? 0) > 0"
        class="flex items-center justify-center gap-1.5 w-full mt-2 pt-2 border-t border-border text-xs text-muted-foreground hover:text-foreground transition-colors"
        @click="$emit('open-gallery')"
      >
        <LayoutGrid class="size-3.5" />
        {{ $t("sheets.avatar_gallery.gallery") }}
      </button>
    </PopoverContent>
  </Popover>
</template>
