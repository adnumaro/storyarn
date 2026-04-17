<script setup lang="ts">
import { AlertCircle, FileText, GitBranch, Link, X, ChevronDown } from "lucide-vue-next";
import type { ComponentPublicInstance, FunctionalComponent } from "vue";
import { computed, nextTick, onBeforeUpdate, ref, watch } from "vue";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@components/ui/command/index.ts";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover/index.ts";
import { useServerSearch } from "@composables/useServerSearch";
import { useBlockActions } from "../../composables/useBlockActions";
import type { Block, ReferenceSearchResult } from "../../types";
import BlockLabel from "../BlockLabel.vue";
import BlockToolbar from "../BlockToolbar.vue";
import { generateId } from "@modules/shared/variables.ts";

const {
  block,
  canEdit = false,
  inherited = false,
} = defineProps<{
  block: Block;
  canEdit?: boolean;
  inherited?: boolean;
}>();

const { live, label, isSelected, onBlockClick } = useBlockActions({
  get block() {
    return block;
  },
  get canEdit() {
    return canEdit;
  },
});

const targetType = computed(() => block.value?.target_type);
const targetId = computed(() => block.value?.target_id);
const referenceTarget = computed(() => block.reference_target);
const hasReference = computed(() => targetType.value && targetId.value);
const isDeleted = computed(() => hasReference.value && !referenceTarget.value);

function saveLabel(val: string): void {
  live.pushEvent("update_block_config", {
    id: block.id,
    field: "label",
    value: val,
  });
}

// ── Search ──
const open = ref(false);
const pendingLoad = ref(false);
const listRef = ref<ComponentPublicInstance | null>(null);
const searchResults = ref<ReferenceSearchResult[]>([]);
let savedScrollTop = 0;

const { query, loading, search, reset } = useServerSearch({
  searchEvent: "search_references",
  debounceMs: 300,
});

// Listen for results from server
interface ReferenceResultsPayload {
  block_id: number | string;
  results: ReferenceSearchResult[];
}

live.handleEvent("reference_results", (payload) => {
  const data = payload as unknown as ReferenceResultsPayload;
  if (data.block_id === block.id) {
    searchResults.value = data.results || [];
    pendingLoad.value = false;
  }
});

watch(open, (v) => {
  if (v) {
    searchResults.value = [];
    pendingLoad.value = false;
    savedScrollTop = 0;
    reset();
    // Push search with block_id so server knows allowed_types
    live.pushEvent("search_references", {
      query: "",
      "block-id": block.id,
    });
  }
});

function onSearchInput(q: string): void {
  pendingLoad.value = false;
  savedScrollTop = 0;
  live.pushEvent("search_references", {
    query: q,
    "block-id": block.id,
  });
}

function selectReference(result: ReferenceSearchResult): void {
  live.pushEvent("select_reference", {
    "block-id": block.id,
    type: result.type,
    id: String(result.id),
  });
  open.value = false;
}

function clearReference(): void {
  live.pushEvent("clear_reference", { "block-id": block.id });
  open.value = false;
}

function typeIcon(type: string | undefined): FunctionalComponent {
  return type === "flow" ? GitBranch : FileText;
}

function typeColor(type: string | undefined): string {
  return type === "flow" ? "text-violet-500 bg-violet-500/10" : "text-primary bg-primary/10";
}

// ── Infinite scroll ──
function getListEl(): HTMLElement | null {
  return (listRef.value?.$el ?? listRef.value) as HTMLElement | null;
}

function onScroll(): void {
  // Reference search returns all results (no pagination needed for now)
}

onBeforeUpdate(() => {
  const el = getListEl();
  if (el) savedScrollTop = el.scrollTop;
});

watch(searchResults, () => {
  nextTick(() => {
    const el = getListEl();
    if (el && savedScrollTop > 0) {
      el.scrollTop = savedScrollTop;
    }
    pendingLoad.value = false;
  });
});
</script>

<template>
  <div
    class="group relative rounded-lg border p-4 pt-5 transition-colors"
    :class="
      isSelected
        ? 'border-primary ring-1 ring-primary/30'
        : 'border-border hover:border-foreground/20'
    "
    @click="onBlockClick"
  >
    <BlockToolbar
      v-if="canEdit"
      :block-id="block.id"
      :show-constant="false"
      :show-config="false"
      :show-scope="!inherited"
      :scope="block.scope || 'self'"
      :required="block.required"
      @change-scope="(s) => live.pushEvent('change_block_scope', { id: block.id, scope: s })"
      @toggle-required="live.pushEvent('toggle_required', { id: block.id })"
    />

    <BlockLabel
      :icon="Link"
      :label="label"
      :can-edit="canEdit"
      :required="block.required"
      :detached="block.detached"
      @save="saveLabel"
    >
      <slot name="menu" />
    </BlockLabel>

    <!-- Editable: searchable select -->
    <Popover v-if="canEdit" v-model:open="open">
      <PopoverTrigger as-child>
        <button
          :id="`reference-trigger-${block.id}-${generateId()}`"
          type="button"
          class="flex items-center gap-2 w-full min-h-9 rounded-md border border-input bg-card px-3 py-2 text-sm transition-colors"
        >
          <!-- Selected reference -->
          <template v-if="hasReference && referenceTarget">
            <span class="flex items-center gap-2 flex-1">
              <span
                :class="[
                  'size-5 rounded flex items-center justify-center shrink-0',
                  typeColor(targetType),
                ]"
              >
                <component :is="typeIcon(targetType)" class="size-3" />
              </span>
              <span class="flex-1 text-left truncate">{{ referenceTarget.name }}</span>
            </span>
            <span class="flex items-center gap-2">
              <span v-if="referenceTarget.shortcut" class="text-xs text-muted-foreground">{{
                referenceTarget.shortcut
              }}</span>
              <ChevronDown class="h-4 w-4 opacity-50" />
            </span>
          </template>
          <!-- Deleted reference -->
          <template v-else-if="isDeleted">
            <AlertCircle class="size-4 text-destructive shrink-0" />
            <span class="flex-1 text-left text-destructive text-xs">{{
              $t("sheets.reference_block.not_found")
            }}</span>
          </template>
          <!-- Empty -->
          <template v-else>
            <span class="text-muted-foreground">{{ $t("sheets.reference_block.select") }}</span>
          </template>
        </button>
      </PopoverTrigger>
      <PopoverContent class="w-(--reka-popover-trigger-width) p-0" align="start" :side-offset="4">
        <Command :should-filter="false">
          <CommandInput
            :placeholder="$t('sheets.reference_block.search')"
            class="h-8 text-xs"
            :model-value="query"
            @update:model-value="onSearchInput"
          />
          <CommandList ref="listRef">
            <CommandEmpty class="py-3 text-xs text-center">
              <span v-if="loading">{{ $t("sheets.reference_block.searching") }}</span>
              <span v-else>{{ $t("sheets.reference_block.no_results") }}</span>
            </CommandEmpty>

            <CommandGroup>
              <!-- Clear option -->
              <CommandItem
                v-if="hasReference"
                value="__clear__"
                class="gap-2 text-xs text-muted-foreground data-highlighted:bg-transparent"
                @select="clearReference"
              >
                <X class="size-3.5" />
                {{ $t("sheets.reference_block.clear") }}
              </CommandItem>

              <!-- Results -->
              <CommandItem
                v-for="result in searchResults"
                :key="`${result.type}-${result.id}`"
                :value="`${result.type}-${result.id}-${result.name}`"
                class="gap-2"
                @select="selectReference(result)"
              >
                <span
                  :class="[
                    'size-5 rounded flex items-center justify-center shrink-0',
                    typeColor(result.type),
                  ]"
                >
                  <component :is="typeIcon(result.type)" class="size-3" />
                </span>
                <span class="flex-1 truncate">{{ result.name }}</span>
                <span v-if="result.shortcut" class="text-xs text-muted-foreground">{{
                  result.shortcut
                }}</span>
              </CommandItem>
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>

    <!-- Read-only display -->
    <div v-else>
      <div v-if="hasReference && referenceTarget" class="flex items-center gap-2 text-sm">
        <span
          :class="[
            'size-5 rounded flex items-center justify-center shrink-0',
            typeColor(targetType),
          ]"
        >
          <component :is="typeIcon(targetType)" class="size-3" />
        </span>
        <span>{{ referenceTarget.name }}</span>
        <span v-if="referenceTarget.shortcut" class="text-xs text-muted-foreground">{{
          referenceTarget.shortcut
        }}</span>
      </div>
      <div v-else-if="isDeleted" class="flex items-center gap-1.5 text-xs text-destructive">
        <AlertCircle class="size-3.5" />
        {{ $t("sheets.reference_block.not_found") }}
      </div>
      <span v-else class="text-sm text-muted-foreground">\u2014</span>
    </div>
  </div>
</template>
