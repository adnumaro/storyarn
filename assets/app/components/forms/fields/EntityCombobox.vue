<script setup lang="ts">
import { Check, ChevronsUpDown } from "lucide-vue-next";
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

interface EntityOption {
  id: number | string;
  name: string;
}

const MAX_RENDERED_OPTIONS = 100;

const {
  options = [],
  selectedId = null,
  label = "",
  placeholder = "Select...",
  disabled = false,
  variant = "default",
  selectedOption = null,
  searchEvent,
  searchResultsEvent,
  searchPayload,
} = defineProps<{
  options?: EntityOption[];
  selectedId?: number | string | null;
  label?: string;
  placeholder?: string;
  disabled?: boolean;
  variant?: "default" | "ghost";
  selectedOption?: EntityOption | null;
  searchEvent?: string;
  searchResultsEvent?: string;
  searchPayload?: Record<string, unknown>;
}>();

const triggerClass = computed(() => {
  if (variant === "ghost") {
    return "w-full flex items-center justify-between text-left text-[13px] font-medium bg-transparent border-none text-inherit cursor-pointer p-0 outline-none disabled:opacity-50 disabled:cursor-not-allowed";
  }
  return "w-full flex items-center justify-between text-left text-sm px-2 py-1.5 rounded-md border border-input bg-background dark:bg-card shadow-xs hover:dark:bg-card/80 transition-colors disabled:opacity-50 disabled:cursor-not-allowed";
});

const emit = defineEmits<{
  "update:selectedId": [id: number | string | null];
}>();
const open = ref(false);

const selectedName = computed(() => {
  if (selectedId == null) return null;
  const id = String(selectedId);
  const opt = options.find((o) => String(o.id) === id);
  if (opt?.name) return opt.name;
  return selectedOption && String(selectedOption.id) === id ? selectedOption.name : null;
});

const selectedKey = computed(() => (selectedId == null ? null : String(selectedId)));

const optionSearch = useBoundedSearch({
  get items() {
    return options;
  },
  limit: MAX_RENDERED_OPTIONS,
  getText: (option) => option.name,
  getKey: (option) => String(option.id),
  selectedKey,
});

const remoteEnabled = computed(() => !!searchEvent);
const remoteSearch = useRemotePickerSearch<EntityOption>({
  enabled: computed(() => remoteEnabled.value && open.value),
  event: computed(() => searchEvent),
  resultsEvent: computed(() => searchResultsEvent),
  payload: computed(() => searchPayload),
  selectedId: computed(() => selectedId),
  limit: MAX_RENDERED_OPTIONS,
});

const searchQuery = computed({
  get: () => (remoteEnabled.value ? remoteSearch.query.value : optionSearch.query.value),
  set: (value: string) => {
    if (remoteEnabled.value) {
      remoteSearch.query.value = value;
    } else {
      optionSearch.query.value = value;
    }
  },
});

const visibleOptions = computed(() => {
  if (!remoteEnabled.value) return optionSearch.visibleItems.value;
  if (!remoteSearch.hasResponse.value) return optionSearch.visibleItems.value;
  return remoteSearch.results.value;
});

const isSearching = computed(() =>
  remoteEnabled.value ? remoteSearch.isSearching.value : optionSearch.isSearching.value,
);

const isLimited = computed(() =>
  remoteEnabled.value ? remoteSearch.hasMore.value : optionSearch.isLimited.value,
);

const totalOptions = computed(() =>
  remoteEnabled.value ? visibleOptions.value.length : options.length,
);

watch(open, (isOpen) => {
  if (!isOpen) searchQuery.value = "";
});

function select(id: number | string | null) {
  emit("update:selectedId", id);
  open.value = false;
}
</script>

<template>
  <div>
    <label v-if="label" class="block text-xs font-medium text-foreground/70 mb-1">
      {{ label }}
    </label>
    <Popover v-model:open="open">
      <PopoverTrigger as-child>
        <button type="button" :class="triggerClass" :disabled="disabled">
          <span
            class="overflow-hidden text-ellipsis whitespace-nowrap"
            :class="
              selectedName ? '' : variant === 'ghost' ? 'opacity-60' : 'text-muted-foreground'
            "
          >
            {{ selectedName || placeholder }}
          </span>
          <ChevronsUpDown
            class="size-3 shrink-0 ml-1"
            :class="variant === 'ghost' ? 'opacity-60' : 'text-muted-foreground'"
          />
        </button>
      </PopoverTrigger>
      <PopoverContent class="p-0" :side-offset="4" align="start">
        <Command :disable-filter="remoteEnabled">
          <CommandInput v-model="searchQuery" :placeholder="$t('common.search')" />
          <CommandList>
            <CommandEmpty v-if="!isSearching && searchQuery.trim()">{{
              $t("common.no_results")
            }}</CommandEmpty>
            <div
              v-if="isSearching && visibleOptions.length === 0"
              class="py-6 text-center text-sm text-muted-foreground"
            >
              {{ $t("common.searching") }}
            </div>
            <CommandGroup>
              <CommandItem value="__none__" @select="select(null)">
                <span class="text-muted-foreground">{{ $t("common.none") }}</span>
                <Check v-if="selectedId == null" class="size-3 ml-auto" />
              </CommandItem>
              <CommandItem
                v-for="opt in visibleOptions"
                :key="opt.id"
                :value="opt.name"
                @select="select(opt.id)"
              >
                {{ opt.name }}
                <Check v-if="String(opt.id) === String(selectedId)" class="size-3 ml-auto" />
              </CommandItem>
            </CommandGroup>
            <div
              v-if="isLimited"
              class="border-t border-border px-3 py-2 text-xs text-muted-foreground"
            >
              <template v-if="remoteEnabled || searchQuery.trim()">
                {{ $t("common.limited_matches", { shown: visibleOptions.length }) }}
              </template>
              <template v-else>
                {{
                  $t("common.limited_results", {
                    shown: visibleOptions.length,
                    total: totalOptions,
                  })
                }}
              </template>
            </div>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  </div>
</template>
