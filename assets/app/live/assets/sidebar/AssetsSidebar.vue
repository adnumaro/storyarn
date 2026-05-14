<script setup lang="ts">
import { File, Image, Music, Search } from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import SidebarFrame from "@shell/SidebarFrame.vue";
import { Input } from "@components/ui/input";
import { useLive } from "@shared/composables/useLive.ts";

type AssetFilter = "all" | "image" | "audio" | "file";

const {
  mainSidebarOpen = false,
  activeTool = "assets",
  dashboardUrl = null,
  onDashboard = false,
  sidebarProps = {},
} = defineProps<{
  mainSidebarOpen?: boolean;
  activeTool?: string;
  dashboardUrl?: string | null;
  onDashboard?: boolean;
  sidebarProps?: {
    filter?: AssetFilter;
    search?: string;
    typeCounts?: Record<string, number>;
  };
}>();

const live = useLive();
const searchValue = ref(sidebarProps.search ?? "");

watch(
  () => sidebarProps.search,
  (nextSearch) => {
    searchValue.value = nextSearch ?? "";
  },
);

const totalCount = computed(() =>
  Object.values(sidebarProps.typeCounts ?? {}).reduce((total, count) => total + count, 0),
);

const imageCount = computed(() => sidebarProps.typeCounts?.image ?? 0);
const audioCount = computed(() => sidebarProps.typeCounts?.audio ?? 0);
const fileCount = computed(() =>
  Math.max(totalCount.value - imageCount.value - audioCount.value, 0),
);

const filters = computed(() => [
  { key: "all" as const, label: "common.assets.filter_all", icon: File, count: totalCount.value },
  {
    key: "image" as const,
    label: "common.assets.filter_images",
    icon: Image,
    count: imageCount.value,
  },
  {
    key: "audio" as const,
    label: "common.assets.filter_audio",
    icon: Music,
    count: audioCount.value,
  },
  { key: "file" as const, label: "common.assets.filter_files", icon: File, count: fileCount.value },
]);

function filterAssets(type: AssetFilter): void {
  live.pushEvent("filter_assets", { type });
}

function searchAssets(event: Event): void {
  const target = event.target as HTMLInputElement;
  searchValue.value = target.value;
  live.pushEvent("search_assets", { search: target.value });
}
</script>

<template>
  <SidebarFrame
    :main-sidebar-open="mainSidebarOpen"
    :active-tool="activeTool"
    :dashboard-url="dashboardUrl"
    :on-dashboard="onDashboard"
  >
    <div class="space-y-6">
      <section class="space-y-2">
        <div class="relative">
          <Search
            class="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
          />
          <Input
            type="search"
            :model-value="searchValue"
            :placeholder="$t('common.assets.search')"
            class="h-8 pl-8"
            @input="searchAssets"
          />
        </div>
      </section>

      <section class="space-y-1">
        <h2 class="px-2 text-xs font-medium text-muted-foreground">
          {{ $t("common.assets.filters") }}
        </h2>

        <button
          v-for="filterItem in filters"
          :key="filterItem.key"
          type="button"
          :class="[
            'flex w-full items-center gap-2 rounded-md px-2 py-2 text-sm transition-colors',
            sidebarProps.filter === filterItem.key
              ? 'bg-accent text-accent-foreground font-medium'
              : 'text-muted-foreground hover:bg-accent/50 hover:text-foreground',
          ]"
          @click="filterAssets(filterItem.key)"
        >
          <component :is="filterItem.icon" class="size-4 shrink-0" />
          <span class="min-w-0 flex-1 truncate text-left">{{ $t(filterItem.label) }}</span>
          <span class="text-xs tabular-nums text-muted-foreground">{{ filterItem.count }}</span>
        </button>
      </section>
    </div>
  </SidebarFrame>
</template>
