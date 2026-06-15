<script setup lang="ts">
import { File, GitBranch, Image, Link, MapPin, Music, Trash2, User, X } from "lucide-vue-next";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { Badge } from "@components/ui/badge/index.ts";
import { Button } from "@components/ui/button/index.ts";
import { useLive } from "@shared/composables/useLive.ts";

interface Asset {
  id: number;
  filename: string;
  url: string;
  contentType: string;
  size: number;
  insertedAt: string;
}

interface FlowNodeUsage {
  flowId: number;
  flowName: string;
}

interface SheetUsage {
  id: number;
  name: string;
}

interface SceneUsage {
  id: number;
  name: string;
}

interface ScenePinUsage {
  pinId: number;
  pinLabel: string | null;
  sceneId: number;
  sceneName: string;
}

interface AssetUsages {
  flowNodes: FlowNodeUsage[];
  sheetAvatars: SheetUsage[];
  sheetBanners: SheetUsage[];
  sceneBackgrounds: SceneUsage[];
  scenePinIcons: ScenePinUsage[];
}

interface UsageSummary {
  key: string;
  name: string;
  context: string;
}

const {
  assets = [],
  selectedAsset = null,
  assetUsages = {
    flowNodes: [],
    sheetAvatars: [],
    sheetBanners: [],
    sceneBackgrounds: [],
    scenePinIcons: [],
  },
  canEdit = false,
  workspaceSlug,
  projectSlug,
} = defineProps<{
  assets?: Asset[];
  selectedAsset?: Asset | null;
  assetUsages?: AssetUsages;
  canEdit?: boolean;
  workspaceSlug: string;
  projectSlug: string;
}>();

const live = useLive();
const { t } = useI18n();
const showDeleteConfirm = ref(false);

const usageSummaries = computed<UsageSummary[]>(() => {
  if (!assetUsages) return [];

  return [
    ...(assetUsages.flowNodes || []).map((usage) => ({
      key: `flow-${usage.flowId}`,
      name: usage.flowName,
      context: t("common.assets.flow_audio_context"),
    })),
    ...(assetUsages.sheetAvatars || []).map((sheet) => ({
      key: `avatar-${sheet.id}`,
      name: sheet.name,
      context: t("common.assets.avatar_context"),
    })),
    ...(assetUsages.sheetBanners || []).map((sheet) => ({
      key: `banner-${sheet.id}`,
      name: sheet.name,
      context: t("common.assets.banner_context"),
    })),
    ...(assetUsages.sceneBackgrounds || []).map((scene) => ({
      key: `scene-bg-${scene.id}`,
      name: scene.name,
      context: t("common.assets.scene_background_context"),
    })),
    ...(assetUsages.scenePinIcons || []).map((pin) => ({
      key: `scene-pin-${pin.pinId}`,
      name: pin.pinLabel || pin.sceneName,
      context: t("common.assets.scene_pin_icon_context", { scene: pin.sceneName }),
    })),
  ];
});

const totalUsages = computed(() => usageSummaries.value.length);

const deleteConfirmMessage = computed(() =>
  totalUsages.value > 0
    ? t(
        totalUsages.value === 1
          ? "common.assets.delete_confirm_used_one"
          : "common.assets.delete_confirm_used_many",
        { count: totalUsages.value },
      )
    : t("common.assets.delete_confirm_unused"),
);

const deleteConfirmConsequence = computed(() =>
  totalUsages.value > 0
    ? t("common.assets.delete_confirm_used_consequence")
    : t("common.assets.delete_confirm_unused_consequence"),
);

function selectAsset(id: number) {
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

function isImage(asset: Asset) {
  return asset.contentType?.startsWith("image/");
}

function isAudio(asset: Asset) {
  return asset.contentType?.startsWith("audio/");
}

function formatSize(bytes: number) {
  if (!bytes) return "";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1048576).toFixed(1)} MB`;
}

function typeLabel(asset: Asset) {
  if (isImage(asset)) return t("common.assets.type_image");
  if (isAudio(asset)) return t("common.assets.type_audio");
  return t("common.assets.type_file");
}

function typeBadgeVariant(asset: Asset) {
  if (isImage(asset)) return "default";
  if (isAudio(asset)) return "secondary";
  return "outline";
}

function formatDate(dateStr: string) {
  if (!dateStr) return "";
  const d = new Date(dateStr);
  return d.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

function usageFlowHref(usage: FlowNodeUsage) {
  return `/workspaces/${workspaceSlug}/projects/${projectSlug}/flows/${usage.flowId}`;
}

function usageSheetHref(sheet: SheetUsage) {
  return `/workspaces/${workspaceSlug}/projects/${projectSlug}/sheets/${sheet.id}`;
}

function usageSceneHref(sceneId: number) {
  return `/workspaces/${workspaceSlug}/projects/${projectSlug}/scenes/${sceneId}`;
}
</script>

<template>
  <div class="mx-auto w-full max-w-6xl px-4 py-4">
    <!-- Empty state -->
    <div
      v-if="assets.length === 0"
      class="flex flex-col items-center justify-center py-16 text-center"
    >
      <Image class="size-12 text-muted-foreground/30 mb-4" />
      <p class="text-sm text-muted-foreground">{{ $t("common.assets.empty") }}</p>
    </div>

    <!-- Asset grid + detail panel -->
    <div v-if="assets.length > 0" class="flex gap-6">
      <div
        :class="[
          'grid gap-4 flex-1',
          selectedAsset
            ? 'grid-cols-2 sm:grid-cols-2'
            : 'grid-cols-2 sm:grid-cols-3 md:grid-cols-4',
        ]"
      >
        <!-- Asset card -->
        <div
          v-for="asset in assets"
          :key="asset.id"
          :data-testid="`asset-card-${asset.id}`"
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
        class="w-80 shrink-0 border border-border rounded-lg bg-surface p-4 space-y-4 self-start"
      >
        <div class="flex items-center justify-between">
          <h3 class="font-semibold text-sm">{{ $t("common.assets.details") }}</h3>
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
            <dt class="text-muted-foreground">{{ $t("common.assets.filename") }}</dt>
            <dd class="font-medium break-all">{{ selectedAsset.filename }}</dd>
          </div>
          <div>
            <dt class="text-muted-foreground">{{ $t("common.assets.type") }}</dt>
            <dd>{{ selectedAsset.contentType }}</dd>
          </div>
          <div>
            <dt class="text-muted-foreground">{{ $t("common.assets.size") }}</dt>
            <dd>{{ formatSize(selectedAsset.size) }}</dd>
          </div>
          <div>
            <dt class="text-muted-foreground">{{ $t("common.assets.uploaded") }}</dt>
            <dd>{{ formatDate(selectedAsset.insertedAt) }}</dd>
          </div>
        </dl>

        <!-- Usage section -->
        <div class="border-t border-border pt-4">
          <h4 class="text-sm font-medium mb-2 flex items-center gap-2">
            <Link class="size-4" />
            {{ $t("common.assets.usage") }}
            <Badge variant="secondary" class="text-[10px] px-1.5 py-0">{{ totalUsages }}</Badge>
          </h4>

          <p v-if="totalUsages === 0" class="text-sm text-muted-foreground">
            {{ $t("common.assets.not_used") }}
          </p>

          <ul v-if="totalUsages > 0" class="text-sm space-y-1">
            <li
              v-for="usage in assetUsages.flowNodes"
              :key="'flow-' + usage.flowId"
              class="flex items-center gap-2"
            >
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
            <li
              v-for="sheet in assetUsages.sheetAvatars"
              :key="'avatar-' + sheet.id"
              class="flex items-center gap-2"
            >
              <User class="size-3 text-muted-foreground" />
              <a
                :href="usageSheetHref(sheet)"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="text-primary hover:underline truncate"
              >
                {{ sheet.name }}
                <span class="text-muted-foreground">{{ $t("common.assets.avatar_context") }}</span>
              </a>
            </li>
            <li
              v-for="sheet in assetUsages.sheetBanners"
              :key="'banner-' + sheet.id"
              class="flex items-center gap-2"
            >
              <Image class="size-3 text-muted-foreground" />
              <a
                :href="usageSheetHref(sheet)"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="text-primary hover:underline truncate"
              >
                {{ sheet.name }}
                <span class="text-muted-foreground">{{ $t("common.assets.banner_context") }}</span>
              </a>
            </li>
            <li
              v-for="scene in assetUsages.sceneBackgrounds"
              :key="'scene-bg-' + scene.id"
              class="flex items-center gap-2"
            >
              <Image class="size-3 text-muted-foreground" />
              <a
                :href="usageSceneHref(scene.id)"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="text-primary hover:underline truncate"
              >
                {{ scene.name }}
                <span class="text-muted-foreground">{{
                  $t("common.assets.scene_background_context")
                }}</span>
              </a>
            </li>
            <li
              v-for="pin in assetUsages.scenePinIcons"
              :key="'scene-pin-' + pin.pinId"
              class="flex items-center gap-2"
            >
              <MapPin class="size-3 text-muted-foreground" />
              <a
                :href="usageSceneHref(pin.sceneId)"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="text-primary hover:underline truncate"
              >
                {{ pin.pinLabel || pin.sceneName }}
                <span class="text-muted-foreground">
                  {{ $t("common.assets.scene_pin_icon_context", { scene: pin.sceneName }) }}
                </span>
              </a>
            </li>
          </ul>
        </div>

        <!-- Delete button -->
        <div v-if="canEdit" class="border-t border-border pt-4">
          <Button variant="destructive" size="sm" class="w-full" @click="requestDelete">
            <Trash2 class="size-4" />
            {{ $t("common.assets.delete_asset") }}
          </Button>
        </div>
      </div>
    </div>

    <!-- Delete confirmation dialog -->
    <Teleport to="body">
      <div v-if="showDeleteConfirm" class="fixed inset-0 z-50 flex items-center justify-center">
        <div class="fixed inset-0 bg-black/50" @click="cancelDelete" />
        <div
          class="relative z-10 bg-surface border border-border rounded-lg shadow-lg p-6 max-w-sm w-full mx-4"
        >
          <div class="flex items-start gap-3 mb-4">
            <div class="rounded-full bg-destructive/10 p-2">
              <Trash2 class="size-5 text-destructive" />
            </div>
            <div>
              <h3 class="font-semibold text-sm">{{ $t("common.assets.delete_confirm_title") }}</h3>
              <p class="text-sm text-muted-foreground mt-1">{{ deleteConfirmMessage }}</p>
              <p class="text-sm text-muted-foreground mt-2">{{ deleteConfirmConsequence }}</p>
            </div>
          </div>
          <ul
            v-if="usageSummaries.length > 0"
            class="mb-4 max-h-40 overflow-y-auto rounded-md border border-border bg-muted/30 p-2 text-sm"
          >
            <li
              v-for="usage in usageSummaries"
              :key="usage.key"
              class="flex items-center justify-between gap-3 py-1"
            >
              <span class="truncate text-foreground">{{ usage.name }}</span>
              <span class="shrink-0 text-xs text-muted-foreground">{{ usage.context }}</span>
            </li>
          </ul>
          <div class="flex justify-end gap-2">
            <Button variant="ghost" size="sm" @click="cancelDelete">{{
              $t("common.cancel")
            }}</Button>
            <Button variant="destructive" size="sm" @click="confirmDelete">{{
              $t("common.delete")
            }}</Button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
