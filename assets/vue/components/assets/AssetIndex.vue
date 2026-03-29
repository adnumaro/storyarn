<script setup>
import {
	File,
	GitBranch,
	Image,
	Link,
	Music,
	Search,
	Trash2,
	Upload,
	User,
	X,
} from "lucide-vue-next";
import { computed, ref } from "vue";
import { Badge } from "@/vue/components/ui/badge";
import { Button } from "@/vue/components/ui/button";
import { Input } from "@/vue/components/ui/input";
import { useLive } from "@/vue/composables/useLive";

const props = defineProps({
	assets: { type: Array, default: () => [] },
	filter: { type: String, default: "all" },
	search: { type: String, default: "" },
	typeCounts: { type: Object, default: () => ({}) },
	selectedAsset: { type: Object, default: null },
	assetUsages: {
		type: Object,
		default: () => ({ flowNodes: [], sheetAvatars: [], sheetBanners: [] }),
	},
	uploading: { type: Boolean, default: false },
	canEdit: { type: Boolean, default: false },
	workspaceSlug: { type: String, required: true },
	projectSlug: { type: String, required: true },
});

const live = useLive();
const searchValue = ref(props.search);
const showDeleteConfirm = ref(false);

const filterTabs = computed(() => {
	const total = Object.values(props.typeCounts).reduce((a, b) => a + b, 0);
	const imageCount = props.typeCounts.image || 0;
	const audioCount = props.typeCounts.audio || 0;
	return [
		{ key: "all", label: "All", count: total },
		{ key: "image", label: "Images", count: imageCount },
		{ key: "audio", label: "Audio", count: audioCount },
	];
});

const totalUsages = computed(() => {
	if (!props.assetUsages) return 0;
	return (
		(props.assetUsages.flowNodes?.length || 0) +
		(props.assetUsages.sheetAvatars?.length || 0) +
		(props.assetUsages.sheetBanners?.length || 0)
	);
});

const deleteConfirmMessage = computed(() => {
	const total = totalUsages.value;
	if (total > 0) {
		return total === 1
			? "This asset is used in 1 place. Are you sure you want to delete it?"
			: `This asset is used in ${total} places. Are you sure you want to delete it?`;
	}
	return "Are you sure you want to delete this asset? This cannot be undone.";
});

function filterAssets(type) {
	live.pushEvent("filter_assets", { type });
}

function handleSearch(event) {
	searchValue.value = event.target.value;
	live.pushEvent("search_assets", { search: event.target.value });
}

function selectAsset(id) {
	live.pushEvent("select_asset", { id: String(id) });
}

function deselectAsset() {
	live.pushEvent("deselect_asset", {});
}

function requestDelete() {
	showDeleteConfirm.value = true;
}

function confirmDelete() {
	showDeleteConfirm.value = false;
	live.pushEvent("confirm_delete_asset", {});
}

function cancelDelete() {
	showDeleteConfirm.value = false;
}

function isImage(asset) {
	return asset.contentType?.startsWith("image/");
}

function isAudio(asset) {
	return asset.contentType?.startsWith("audio/");
}

function formatSize(bytes) {
	if (!bytes) return "";
	if (bytes < 1024) return `${bytes} B`;
	if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
	return `${(bytes / 1048576).toFixed(1)} MB`;
}

function typeLabel(asset) {
	if (isImage(asset)) return "Image";
	if (isAudio(asset)) return "Audio";
	return "File";
}

function typeBadgeVariant(asset) {
	if (isImage(asset)) return "default";
	if (isAudio(asset)) return "secondary";
	return "outline";
}

function formatDate(dateStr) {
	if (!dateStr) return "";
	const d = new Date(dateStr);
	return d.toLocaleDateString("en-US", {
		month: "short",
		day: "numeric",
		year: "numeric",
	});
}

function usageFlowHref(usage) {
	return `/workspaces/${props.workspaceSlug}/projects/${props.projectSlug}/flows/${usage.flowId}`;
}

function usageSheetHref(sheet) {
	return `/workspaces/${props.workspaceSlug}/projects/${props.projectSlug}/sheets/${sheet.id}`;
}
</script>

<template>
  <div class="max-w-4xl mx-auto mt-4">
    <!-- Filter tabs + Search -->
    <div class="flex items-center justify-between mb-4 gap-4">
      <div class="flex items-center gap-1 border-b border-border">
        <button
          v-for="tab in filterTabs"
          :key="tab.key"
          type="button"
          :class="[
            'px-3 py-2 text-sm font-medium border-b-2 transition-colors -mb-px',
            filter === tab.key
              ? 'border-primary text-foreground'
              : 'border-transparent text-muted-foreground hover:text-foreground hover:border-border',
          ]"
          @click="filterAssets(tab.key)"
        >
          {{ tab.label }}
          <Badge variant="secondary" class="ml-1.5 text-[10px] px-1.5 py-0">{{ tab.count }}</Badge>
        </button>
      </div>

      <div class="relative flex-shrink-0">
        <Search class="absolute left-2.5 top-1/2 -translate-y-1/2 size-4 text-muted-foreground" />
        <Input
          type="text"
          :model-value="searchValue"
          placeholder="Search files..."
          class="pl-8 h-8 w-48"
          @input="handleSearch"
        />
      </div>
    </div>

    <!-- Empty state -->
    <div v-if="assets.length === 0" class="flex flex-col items-center justify-center py-16 text-center">
      <Image class="size-12 text-muted-foreground/30 mb-4" />
      <p class="text-sm text-muted-foreground">No assets yet. Upload files to get started.</p>
    </div>

    <!-- Asset grid + detail panel -->
    <div v-if="assets.length > 0" class="flex gap-6">
      <div
        :class="[
          'grid gap-4 flex-1',
          selectedAsset ? 'grid-cols-2 sm:grid-cols-2' : 'grid-cols-2 sm:grid-cols-3 md:grid-cols-4',
        ]"
      >
        <!-- Asset card -->
        <div
          v-for="asset in assets"
          :key="asset.id"
          :class="[
            'rounded-lg border shadow-sm hover:shadow-md transition-shadow cursor-pointer overflow-hidden bg-surface',
            selectedAsset && selectedAsset.id === asset.id
              ? 'border-primary ring-2 ring-primary/20'
              : 'border-border',
          ]"
          @click="selectAsset(asset.id)"
        >
          <div class="h-32 bg-muted flex items-center justify-center">
            <img
              v-if="isImage(asset)"
              :src="asset.url"
              :alt="asset.filename"
              class="w-full h-full object-cover"
            />
            <Music v-else-if="isAudio(asset)" class="size-10 text-muted-foreground/30" />
            <File v-else class="size-10 text-muted-foreground/30" />
          </div>
          <div class="p-3">
            <p class="text-sm font-medium truncate" :title="asset.filename">{{ asset.filename }}</p>
            <div class="flex items-center justify-between text-xs text-muted-foreground mt-1">
              <span>{{ formatSize(asset.size) }}</span>
              <Badge :variant="typeBadgeVariant(asset)" class="text-[10px] px-1.5 py-0">
                {{ typeLabel(asset) }}
              </Badge>
            </div>
          </div>
        </div>
      </div>

      <!-- Detail panel -->
      <div
        v-if="selectedAsset"
        class="w-80 flex-shrink-0 border border-border rounded-lg bg-surface p-4 space-y-4 self-start"
      >
        <div class="flex items-center justify-between">
          <h3 class="font-semibold text-sm">Details</h3>
          <Button variant="ghost" size="icon-sm" class="size-7" @click="deselectAsset">
            <X class="size-4" />
          </Button>
        </div>

        <div class="rounded-lg overflow-hidden bg-muted">
          <img
            v-if="isImage(selectedAsset)"
            :src="selectedAsset.url"
            :alt="selectedAsset.filename"
            class="w-full object-contain max-h-48"
          />
          <div v-else-if="isAudio(selectedAsset)" class="p-4">
            <audio controls class="w-full">
              <source :src="selectedAsset.url" :type="selectedAsset.contentType" />
            </audio>
          </div>
          <div v-else class="p-6 flex items-center justify-center">
            <File class="size-12 text-muted-foreground/30" />
          </div>
        </div>

        <dl class="text-sm space-y-2">
          <div>
            <dt class="text-muted-foreground">Filename</dt>
            <dd class="font-medium break-all">{{ selectedAsset.filename }}</dd>
          </div>
          <div>
            <dt class="text-muted-foreground">Type</dt>
            <dd>{{ selectedAsset.contentType }}</dd>
          </div>
          <div>
            <dt class="text-muted-foreground">Size</dt>
            <dd>{{ formatSize(selectedAsset.size) }}</dd>
          </div>
          <div>
            <dt class="text-muted-foreground">Uploaded</dt>
            <dd>{{ formatDate(selectedAsset.insertedAt) }}</dd>
          </div>
        </dl>

        <!-- Usage section -->
        <div class="border-t border-border pt-4">
          <h4 class="text-sm font-medium mb-2 flex items-center gap-2">
            <Link class="size-4" />
            Usage
            <Badge variant="secondary" class="text-[10px] px-1.5 py-0">{{ totalUsages }}</Badge>
          </h4>

          <p v-if="totalUsages === 0" class="text-sm text-muted-foreground">Not used anywhere</p>

          <ul v-if="totalUsages > 0" class="text-sm space-y-1">
            <li v-for="usage in assetUsages.flowNodes" :key="'flow-' + usage.flowId" class="flex items-center gap-2">
              <GitBranch class="size-3 text-muted-foreground" />
              <a
                :href="usageFlowHref(usage)"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="text-primary hover:underline truncate"
              >
                {{ usage.flowName }}
              </a>
            </li>
            <li v-for="sheet in assetUsages.sheetAvatars" :key="'avatar-' + sheet.id" class="flex items-center gap-2">
              <User class="size-3 text-muted-foreground" />
              <a
                :href="usageSheetHref(sheet)"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="text-primary hover:underline truncate"
              >
                {{ sheet.name }}
                <span class="text-muted-foreground">(avatar)</span>
              </a>
            </li>
            <li v-for="sheet in assetUsages.sheetBanners" :key="'banner-' + sheet.id" class="flex items-center gap-2">
              <Image class="size-3 text-muted-foreground" />
              <a
                :href="usageSheetHref(sheet)"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="text-primary hover:underline truncate"
              >
                {{ sheet.name }}
                <span class="text-muted-foreground">(banner)</span>
              </a>
            </li>
          </ul>
        </div>

        <!-- Delete button -->
        <div v-if="canEdit" class="border-t border-border pt-4">
          <Button variant="destructive" size="sm" class="w-full" @click="requestDelete">
            <Trash2 class="size-4" />
            Delete asset
          </Button>
        </div>
      </div>
    </div>

    <!-- Delete confirmation dialog -->
    <Teleport to="body">
      <div
        v-if="showDeleteConfirm"
        class="fixed inset-0 z-50 flex items-center justify-center"
      >
        <div class="fixed inset-0 bg-black/50" @click="cancelDelete" />
        <div class="relative z-10 bg-surface border border-border rounded-lg shadow-lg p-6 max-w-sm w-full mx-4">
          <div class="flex items-start gap-3 mb-4">
            <div class="rounded-full bg-destructive/10 p-2">
              <Trash2 class="size-5 text-destructive" />
            </div>
            <div>
              <h3 class="font-semibold text-sm">Delete asset?</h3>
              <p class="text-sm text-muted-foreground mt-1">{{ deleteConfirmMessage }}</p>
            </div>
          </div>
          <div class="flex justify-end gap-2">
            <Button variant="ghost" size="sm" @click="cancelDelete">Cancel</Button>
            <Button variant="destructive" size="sm" @click="confirmDelete">Delete</Button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
