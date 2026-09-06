<script setup lang="ts">
import { ArrowDownToLine, BookOpen, Image, Plus, RefreshCw, Search, UserRound } from "@lucide/vue";
import { computed, onUnmounted, ref, watch } from "vue";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@components/ui/tabs";
import type { SequenceAssetEntry, SequenceEntityId } from "@modules/flows/sequence/types";
import { useLive } from "@shared/composables/useLive";
import {
  SEQUENCE_LIBRARY_IMAGE_MIME,
  type SequenceLibraryImage,
  type SequenceLibrarySheet,
} from "./sequence-library";

interface LibraryItem {
  key: string;
  label: string;
  url: string;
  image: SequenceLibraryImage | null;
  source: SequenceLibraryImage["source"];
}

interface LibraryGroup {
  key: string;
  sheet?: SequenceLibrarySheet;
  items: LibraryItem[];
}

const {
  sheets = [],
  imageAssets = [],
  speakerSheetId = null,
  selectedAssetId = null,
  canReplace = false,
  canEdit = false,
  remoteSearch = false,
} = defineProps<{
  sheets?: SequenceLibrarySheet[];
  imageAssets?: SequenceAssetEntry[];
  speakerSheetId?: SequenceEntityId | null;
  selectedAssetId?: SequenceEntityId | null;
  canReplace?: boolean;
  canEdit?: boolean;
  remoteSearch?: boolean;
}>();

const emit = defineEmits<{
  "add-image": [image: SequenceLibraryImage];
  "replace-image": [image: SequenceLibraryImage];
}>();

const tab = ref("sheets");
const query = ref("");
const pageSize = 60;
const visibleCount = ref(pageSize);
const searchText = computed(() => normalizeSearchText(query.value.trim()));
const live = useLive();
const remoteActive = computed(() => remoteSearch && tab.value === "assets");
const remoteAssets = ref<SequenceAssetEntry[] | null>(null);
const searching = ref(false);
const searchFailed = ref(false);
const hasMore = ref(false);
let latestRequestId: string | null = null;
let searchTimer: ReturnType<typeof setTimeout> | undefined;
let responseTimer: ReturnType<typeof setTimeout> | undefined;
let resultHandler: number | undefined;

function cancelSearch() {
  latestRequestId = null;
  clearTimeout(searchTimer);
  clearTimeout(responseTimer);
  searching.value = false;
}

function scheduleSearch() {
  cancelSearch();
  remoteAssets.value = null;
  hasMore.value = false;
  searchFailed.value = false;
  if (!remoteActive.value) return;

  if (resultHandler === undefined) {
    resultHandler = live.handleEvent("picker_search_results", (response) => {
      if (!latestRequestId || response.request_id !== latestRequestId) return;
      remoteAssets.value = Array.isArray(response.results)
        ? (response.results as SequenceAssetEntry[])
        : [];
      hasMore.value = response.has_more === true;
      cancelSearch();
    });
  }

  const requestId = crypto.randomUUID();
  latestRequestId = requestId;
  searching.value = true;
  searchTimer = setTimeout(() => {
    const fail = () => {
      if (latestRequestId !== requestId) return;
      cancelSearch();
      searchFailed.value = true;
    };
    responseTimer = setTimeout(fail, 10_000);
    live.pushEvent(
      "picker_search",
      {
        resource: "asset",
        kind: "image",
        query: query.value.trim(),
        limit: 100,
        request_id: requestId,
      },
      undefined,
      fail,
    );
  }, 160);
}

watch([remoteActive, query], scheduleSearch, { immediate: true, flush: "sync" });

onUnmounted(() => {
  cancelSearch();
  if (resultHandler !== undefined) live.removeHandleEvent(resultHandler);
});

const availableAssets = computed(() => {
  if (!remoteActive.value) return imageAssets.filter((asset) => matches(asset.filename));
  if (remoteAssets.value !== null) return remoteAssets.value;
  return !query.value.trim() && !searchFailed.value ? imageAssets : [];
});

function normalizeSearchText(value: string): string {
  return value
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase();
}

function sameId(left: SequenceEntityId | null | undefined, right: SequenceEntityId | null) {
  return left != null && right != null && String(left) === String(right);
}

function matches(value: string) {
  return !searchText.value || normalizeSearchText(value).includes(searchText.value);
}

function sheetItems(sheet: SequenceLibrarySheet): LibraryItem[] {
  const images = [
    ...(sheet.gallery_images ?? []).map((image) => ({
      ...image,
      label: image.label?.trim() || sheet.name,
      source: "gallery" as const,
    })),
    ...(sheet.avatars ?? []).map((image) => ({
      ...image,
      label: image.name?.trim() || sheet.name,
      source: "portrait" as const,
    })),
  ];

  return images
    .filter((image) => image.url?.trim() && matches(`${sheet.name} ${image.label}`))
    .map((image) => ({
      key: `${image.source}-${image.id}`,
      label: image.label,
      url: image.url,
      source: image.source,
      image:
        image.asset_id == null
          ? null
          : {
              asset_id: image.asset_id,
              url: image.url,
              label: image.label === sheet.name ? sheet.name : `${sheet.name} · ${image.label}`,
              sheet_id: sheet.id,
              source: image.source,
            },
    }));
}

const matchingGroups = computed<LibraryGroup[]>(() => {
  if (tab.value === "assets") {
    return [
      {
        key: "assets",
        items: availableAssets.value
          .filter((asset) => asset.url?.trim())
          .map((asset) => ({
            key: `asset-${asset.id}`,
            label: asset.filename,
            url: asset.url!,
            source: "asset",
            image: { asset_id: asset.id, url: asset.url!, label: asset.filename, source: "asset" },
          })),
      },
    ];
  }

  return [...sheets]
    .sort((left, right) => {
      const speakerOrder =
        Number(sameId(right.id, speakerSheetId)) - Number(sameId(left.id, speakerSheetId));
      return speakerOrder || left.name.localeCompare(right.name);
    })
    .map((sheet) => ({ key: `sheet-${sheet.id}`, sheet, items: sheetItems(sheet) }))
    .filter((group) => group.items.length > 0);
});

const totalItems = computed(() =>
  matchingGroups.value.reduce((total, group) => total + group.items.length, 0),
);
const visibleGroups = computed(() => {
  let remaining = visibleCount.value;
  return matchingGroups.value.flatMap((group) => {
    const items = group.items.slice(0, remaining);
    remaining -= items.length;
    return items.length ? [{ ...group, items }] : [];
  });
});

watch([tab, query], () => {
  visibleCount.value = pageSize;
});

function addImage(item: LibraryItem) {
  if (canEdit && item.image) emit("add-image", item.image);
}

function replaceImage(item: LibraryItem) {
  if (canEdit && canReplace && item.image && !sameId(item.image.asset_id, selectedAssetId)) {
    emit("replace-image", item.image);
  }
}

function dragImage(event: DragEvent, item: LibraryItem) {
  if (!canEdit || !item.image || !event.dataTransfer) {
    event.preventDefault();
    return;
  }
  event.dataTransfer.effectAllowed = "copy";
  event.dataTransfer.setData(SEQUENCE_LIBRARY_IMAGE_MIME, JSON.stringify(item.image));
}
</script>

<template>
  <aside class="flex h-full min-h-0 min-w-0 flex-col bg-card" data-sequence-library>
    <header class="flex items-center gap-2 border-b border-border px-3 py-2.5">
      <BookOpen class="size-4 text-muted-foreground" />
      <h3 class="text-xs font-semibold">{{ $t("flows.sequence_library.title") }}</h3>
    </header>

    <Tabs v-model="tab" class="flex min-h-0 flex-1 flex-col gap-0">
      <div class="space-y-2 border-b border-border p-3">
        <TabsList class="grid h-8 w-full grid-cols-2">
          <TabsTrigger value="sheets" class="gap-1.5 text-xs" data-library-tab-sheets>
            <UserRound class="size-3.5" />
            {{ $t("flows.sequence_library.sheets") }}
          </TabsTrigger>
          <TabsTrigger value="assets" class="gap-1.5 text-xs" data-library-tab-assets>
            <Image class="size-3.5" />
            {{ $t("flows.sequence_library.assets") }}
          </TabsTrigger>
        </TabsList>
        <div class="relative">
          <Search
            class="pointer-events-none absolute left-2.5 top-2 size-3.5 text-muted-foreground"
          />
          <Input
            v-model="query"
            type="search"
            class="h-8 pl-8 text-xs"
            :aria-label="$t('flows.sequence_library.search')"
            :placeholder="$t('flows.sequence_library.search')"
            data-library-search
          />
        </div>
      </div>

      <TabsContent :value="tab" class="m-0 min-h-0 flex-1 overflow-y-auto p-3">
        <p
          v-if="searching"
          class="mb-3 text-xs text-muted-foreground"
          role="status"
          data-library-searching
        >
          {{ $t("common.searching") }}
        </p>
        <div
          v-if="searchFailed"
          class="mb-3 space-y-2 text-xs"
          role="status"
          data-library-search-failed
        >
          <p class="text-muted-foreground">{{ $t("flows.sequence_library.search_failed") }}</p>
          <Button variant="outline" size="sm" data-library-retry @click="scheduleSearch">
            {{ $t("common.dashboard.retry") }}
          </Button>
        </div>
        <div v-if="visibleGroups.length" class="space-y-5">
          <section v-for="group in visibleGroups" :key="group.key" :data-library-group="group.key">
            <div v-if="group.sheet" class="mb-2 flex items-center gap-2">
              <img
                v-if="group.sheet.avatar_url"
                :src="group.sheet.avatar_url"
                alt=""
                class="size-6 shrink-0 rounded object-cover"
              />
              <UserRound v-else class="size-4 shrink-0 text-muted-foreground" />
              <h4 class="min-w-0 flex-1 truncate text-xs font-medium">{{ group.sheet.name }}</h4>
              <span
                v-if="sameId(group.sheet.id, speakerSheetId)"
                class="rounded bg-primary/10 px-1.5 py-0.5 text-[9px] text-primary"
              >
                {{ $t("flows.sequence_library.current_speaker") }}
              </span>
            </div>
            <div class="grid grid-cols-2 gap-2">
              <div
                v-for="item in group.items"
                :key="item.key"
                class="group min-w-0 overflow-hidden rounded-lg border bg-background transition-colors"
                :class="
                  sameId(item.image?.asset_id, selectedAssetId)
                    ? 'border-primary'
                    : 'border-border hover:border-primary/50'
                "
                :data-library-item="item.key"
              >
                <button
                  type="button"
                  class="relative block aspect-square w-full cursor-grab overflow-hidden bg-muted/30 focus-visible:outline-2 focus-visible:outline-primary disabled:cursor-default disabled:opacity-50 active:cursor-grabbing"
                  :disabled="!canEdit || !item.image"
                  :draggable="canEdit && !!item.image"
                  :aria-label="
                    $t('flows.sequence_library.add', { name: item.image?.label ?? item.label })
                  "
                  data-library-add
                  @click="addImage(item)"
                  @dragstart="dragImage($event, item)"
                >
                  <img
                    :src="item.url"
                    :alt="item.label"
                    class="size-full object-contain p-1"
                    loading="lazy"
                    decoding="async"
                    draggable="false"
                  />
                  <span
                    class="pointer-events-none absolute bottom-1 right-1 rounded bg-background/90 p-1 opacity-0 transition-opacity group-hover:opacity-100 group-focus-within:opacity-100"
                  >
                    <Plus class="size-3" />
                  </span>
                </button>
                <div class="space-y-1 px-2 py-1.5">
                  <p class="truncate text-[11px] font-medium" :title="item.label">
                    {{ item.label }}
                  </p>
                  <p v-if="item.source !== 'asset'" class="text-[9px] text-muted-foreground">
                    {{ $t(`flows.sequence_library.${item.source}`) }}
                  </p>
                  <p
                    v-if="!item.image"
                    class="text-[9px] text-muted-foreground"
                    data-library-unavailable
                  >
                    {{ $t("flows.sequence_library.unavailable") }}
                  </p>
                  <Button
                    v-if="canReplace"
                    variant="ghost"
                    size="xs"
                    class="h-6 w-full justify-start gap-1 px-0 text-[10px]"
                    :disabled="
                      !canEdit || !item.image || sameId(item.image.asset_id, selectedAssetId)
                    "
                    :aria-label="
                      $t('flows.sequence_library.replace', {
                        name: item.image?.label ?? item.label,
                      })
                    "
                    data-library-replace
                    @click="replaceImage(item)"
                  >
                    <RefreshCw class="size-3 shrink-0" />
                    <span class="truncate">{{
                      $t("flows.sequence_library.replace_selected")
                    }}</span>
                  </Button>
                </div>
              </div>
            </div>
          </section>
        </div>
        <div
          v-else-if="!searching && !searchFailed"
          class="grid justify-items-center gap-2 px-2 py-8 text-center text-xs text-muted-foreground"
          data-library-empty
        >
          <Image class="size-7 opacity-40" />
          <p>{{ $t(searchText ? "common.no_results" : `flows.sequence_library.empty_${tab}`) }}</p>
        </div>
        <Button
          v-if="totalItems > visibleCount"
          variant="ghost"
          size="sm"
          class="mt-3 w-full gap-1.5 text-xs"
          data-library-show-more
          @click="visibleCount += pageSize"
        >
          <ArrowDownToLine class="size-3.5" />
          {{ $t("flows.sequence_library.show_more") }}
        </Button>
        <p
          v-if="remoteActive && hasMore && !searching"
          class="mt-3 text-xs text-muted-foreground"
          role="status"
          data-library-limited
        >
          {{ $t("common.limited_matches", { shown: Math.min(totalItems, visibleCount) }) }}.
          {{ $t("flows.sequence_library.refine_search") }}
        </p>
      </TabsContent>
    </Tabs>
    <p class="border-t border-border px-3 py-2 text-[10px] leading-relaxed text-muted-foreground">
      {{ $t("flows.sequence_library.hint") }}
    </p>
  </aside>
</template>
