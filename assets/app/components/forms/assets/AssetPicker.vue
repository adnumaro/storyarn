<script setup lang="ts">
import { Check, Music } from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@components/ui/command";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import { useBoundedSearch } from "@shared/composables/useBoundedSearch";
import { useRemotePickerSearch } from "@shared/composables/useRemotePickerSearch";

interface AssetItem {
  id: number | string;
  filename: string;
  url?: string | null;
}

const MAX_RENDERED_ASSETS = 80;

const {
  assets = [],
  kind,
  selectedId = null,
  searchPlaceholder,
  emptyText,
  popoverWidth = "w-72",
  align = "start",
  searchEvent,
  searchResultsEvent,
  searchPayload,
} = defineProps<{
  assets?: AssetItem[];
  kind: "image" | "audio";
  selectedId?: number | string | null;
  searchPlaceholder?: string;
  emptyText?: string;
  popoverWidth?: string;
  align?: "start" | "center" | "end";
  searchEvent?: string;
  searchResultsEvent?: string;
  searchPayload?: Record<string, unknown>;
}>();

const emit = defineEmits<{
  select: [asset: AssetItem];
}>();

const open = ref(false);

const selectedKey = computed(() => (selectedId == null ? null : String(selectedId)));

const assetSearch = useBoundedSearch({
  get items() {
    return assets;
  },
  limit: MAX_RENDERED_ASSETS,
  getText: (asset) => asset.filename,
  getKey: (asset) => String(asset.id),
  selectedKey,
});

const remoteEnabled = computed(() => !!searchEvent);
const remoteSearch = useRemotePickerSearch<AssetItem>({
  enabled: computed(() => remoteEnabled.value && open.value),
  event: computed(() => searchEvent),
  resultsEvent: computed(() => searchResultsEvent),
  payload: computed(() => searchPayload),
  selectedId: computed(() => selectedId),
  limit: MAX_RENDERED_ASSETS,
});

const searchQuery = computed({
  get: () => (remoteEnabled.value ? remoteSearch.query.value : assetSearch.query.value),
  set: (value: string) => {
    if (remoteEnabled.value) {
      remoteSearch.query.value = value;
    } else {
      assetSearch.query.value = value;
    }
  },
});

const visibleAssets = computed(() => {
  if (!remoteEnabled.value) return assetSearch.visibleItems.value;
  if (!remoteSearch.hasResponse.value) return assetSearch.visibleItems.value;
  return remoteSearch.results.value;
});

const isSearching = computed(() =>
  remoteEnabled.value ? remoteSearch.isSearching.value : assetSearch.isSearching.value,
);

const isLimited = computed(() =>
  remoteEnabled.value ? remoteSearch.hasMore.value : assetSearch.isLimited.value,
);

const totalAssets = computed(() =>
  remoteEnabled.value ? visibleAssets.value.length : assets.length,
);

watch(open, (isOpen) => {
  if (!isOpen) searchQuery.value = "";
});

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
    <PopoverContent :class="[popoverWidth, 'min-w-0 overflow-hidden p-0']" :align="align">
      <Command :disable-filter="remoteEnabled">
        <CommandInput
          v-model="searchQuery"
          :placeholder="
            searchPlaceholder ||
            (kind === 'image'
              ? $t('common.assets.picker.search_image')
              : $t('common.assets.picker.search_audio'))
          "
        />
        <CommandList class="max-h-64">
          <div
            v-if="visibleAssets.length === 0 && !isSearching && !searchQuery.trim()"
            class="py-6 text-center text-sm text-muted-foreground"
          >
            {{
              emptyText ||
              (kind === "image"
                ? $t("common.assets.picker.empty_image")
                : $t("common.assets.picker.empty_audio"))
            }}
          </div>
          <CommandEmpty v-if="!isSearching && searchQuery.trim()">{{
            $t("common.no_results")
          }}</CommandEmpty>
          <div
            v-if="isSearching && visibleAssets.length === 0"
            class="py-6 text-center text-sm text-muted-foreground"
          >
            {{ $t("common.searching") }}
          </div>
          <CommandGroup>
            <CommandItem
              v-for="asset in visibleAssets"
              :key="asset.id"
              :value="asset.filename"
              class="min-w-0 hover:bg-accent hover:text-accent-foreground transition-colors"
              @select="pick(asset)"
            >
              <div class="flex items-center gap-2 min-w-0 flex-1">
                <img
                  v-if="kind === 'image' && asset.url"
                  :src="asset.url"
                  class="size-8 rounded object-cover border border-border shrink-0"
                  :alt="asset.filename"
                  loading="lazy"
                  decoding="async"
                />
                <Music
                  v-else-if="kind === 'audio'"
                  class="size-3.5 shrink-0 text-muted-foreground"
                />
                <span class="min-w-0 flex-1 truncate text-xs">{{ asset.filename }}</span>
              </div>
              <Check v-if="isSelected(asset)" class="size-3.5 shrink-0 text-primary" />
            </CommandItem>
          </CommandGroup>
          <div
            v-if="isLimited"
            class="border-t border-border px-3 py-2 text-xs text-muted-foreground"
          >
            <template v-if="remoteEnabled || searchQuery.trim()">
              {{ $t("common.limited_matches", { shown: visibleAssets.length }) }}
            </template>
            <template v-else>
              {{
                $t("common.limited_results", {
                  shown: visibleAssets.length,
                  total: totalAssets,
                })
              }}
            </template>
          </div>
        </CommandList>
      </Command>
    </PopoverContent>
  </Popover>
</template>
