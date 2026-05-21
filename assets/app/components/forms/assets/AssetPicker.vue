<script setup lang="ts">
import { Check, Music } from "lucide-vue-next";
import { computed, ref } from "vue";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@components/ui/command";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";

interface AssetItem {
  id: number | string;
  filename: string;
  url?: string | null;
}

const {
  assets = [],
  kind,
  selectedId = null,
  searchPlaceholder,
  emptyText,
  popoverWidth = "w-72",
  align = "start",
} = defineProps<{
  assets?: AssetItem[];
  kind: "image" | "audio";
  selectedId?: number | string | null;
  searchPlaceholder?: string;
  emptyText?: string;
  popoverWidth?: string;
  align?: "start" | "center" | "end";
}>();

const emit = defineEmits<{
  select: [asset: AssetItem];
}>();

const open = ref(false);

const selectedKey = computed(() => (selectedId == null ? null : String(selectedId)));

function isSelected(asset: AssetItem): boolean {
  return selectedKey.value !== null && String(asset.id) === selectedKey.value;
}

function pick(asset: AssetItem) {
  emit("select", asset);
  open.value = false;
}
</script>

<template>
  <Popover v-model:open="open">
    <PopoverTrigger as-child>
      <slot name="trigger" />
    </PopoverTrigger>
    <PopoverContent :class="[popoverWidth, 'p-0']" :align="align">
      <Command>
        <CommandInput
          :placeholder="
            searchPlaceholder ||
            (kind === 'image'
              ? $t('common.assets.picker.search_image')
              : $t('common.assets.picker.search_audio'))
          "
        />
        <CommandList class="max-h-64">
          <div v-if="assets.length === 0" class="py-6 text-center text-sm text-muted-foreground">
            {{
              emptyText ||
              (kind === "image"
                ? $t("common.assets.picker.empty_image")
                : $t("common.assets.picker.empty_audio"))
            }}
          </div>
          <CommandEmpty>{{ $t("common.no_results") }}</CommandEmpty>
          <CommandGroup>
            <CommandItem
              v-for="asset in assets"
              :key="asset.id"
              :value="asset.filename"
              class="hover:bg-accent hover:text-accent-foreground transition-colors"
              @select="pick(asset)"
            >
              <div class="flex items-center gap-2 min-w-0 flex-1">
                <img
                  v-if="kind === 'image' && asset.url"
                  :src="asset.url"
                  class="size-8 rounded object-cover border border-border shrink-0"
                  :alt="asset.filename"
                />
                <Music
                  v-else-if="kind === 'audio'"
                  class="size-3.5 shrink-0 text-muted-foreground"
                />
                <span class="truncate text-xs">{{ asset.filename }}</span>
              </div>
              <Check v-if="isSelected(asset)" class="size-3.5 shrink-0 text-primary" />
            </CommandItem>
          </CommandGroup>
        </CommandList>
      </Command>
    </PopoverContent>
  </Popover>
</template>
