<script setup lang="ts">
import { ChevronLeft, ChevronRight, File, Image, Link, Music, Trash2, X } from "lucide-vue-next";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { Badge } from "@components/ui/badge/index.ts";
import { Button } from "@components/ui/button/index.ts";
import { useLive } from "@shared/composables/useLive.ts";
import DashboardContent from "@shell/DashboardContent.vue";

interface Asset {
  id: number;
  filename: string;
  url: string;
  contentType: string;
  size: number;
  insertedAt: string;
}

interface FlowNodeUsage {
  nodeId: number;
  nodeType: string;
  flowId: number;
  flowName: string;
  trashed: boolean;
}

interface SequenceVisualLayerUsage {
  id: number;
  nodeId: number;
  flowId: number;
  flowName: string;
  sequenceName: string | null;
  label: string | null;
  kind: string;
  trashed: boolean;
}

interface SequenceTrackUsage {
  id: number;
  nodeId: number;
  flowId: number;
  flowName: string;
  sequenceName: string | null;
  kind: string;
  trashed: boolean;
}

interface SheetUsage {
  id: number;
  name: string;
  trashed: boolean;
}

interface SceneUsage {
  id: number;
  name: string;
  trashed: boolean;
}

interface ScenePinUsage {
  pinId: number;
  pinLabel: string | null;
  sceneId: number;
  sceneName: string;
  trashed: boolean;
}

interface SceneZoneUsage {
  zoneId: number;
  zoneName: string;
  sceneId: number;
  sceneName: string;
  trashed: boolean;
}

interface LocalizedVoiceoverUsage {
  id: number;
  localeCode: string;
  sourceType: string;
  sourceId: number;
  sourceText: string | null;
  archived: boolean;
}

interface GalleryImageUsage {
  id: number;
  blockId: number;
  sheetId: number;
  sheetName: string;
  label: string | null;
  trashed: boolean;
}

interface AssetMetadataLinkUsage {
  id: number;
  filename: string;
  relations: string[];
}

interface AssetUsages {
  assetMetadataLinks: AssetMetadataLinkUsage[];
  flowNodes: FlowNodeUsage[];
  sequenceVisualLayers: SequenceVisualLayerUsage[];
  sequenceTracks: SequenceTrackUsage[];
  sheetAvatars: SheetUsage[];
  sheetBanners: SheetUsage[];
  sceneBackgrounds: SceneUsage[];
  scenePinIcons: ScenePinUsage[];
  sceneZoneIcons: SceneZoneUsage[];
  localizedVoiceovers: LocalizedVoiceoverUsage[];
  galleryImages: GalleryImageUsage[];
}

interface UsageSummary {
  key: string;
  name: string;
  context: string;
  href: string | null;
}

const {
  assets = [],
  selectedAsset = null,
  assetUsages = {
    assetMetadataLinks: [],
    flowNodes: [],
    sequenceVisualLayers: [],
    sequenceTracks: [],
    sheetAvatars: [],
    sheetBanners: [],
    sceneBackgrounds: [],
    scenePinIcons: [],
    sceneZoneIcons: [],
    localizedVoiceovers: [],
    galleryImages: [],
  },
  canEdit = false,
  workspaceSlug,
  projectSlug,
  page = 1,
  totalPages = 1,
  totalCount = 0,
} = defineProps<{
  assets?: Asset[];
  selectedAsset?: Asset | null;
  assetUsages?: AssetUsages;
  canEdit?: boolean;
  workspaceSlug: string;
  projectSlug: string;
  page?: number;
  totalPages?: number;
  totalCount?: number;
}>();

const live = useLive();
const { t } = useI18n();
const showDeleteConfirm = ref(false);

const usageSummaries = computed<UsageSummary[]>(() => {
  return [
    ...assetUsages.assetMetadataLinks.map((asset) => ({
      key: `asset-metadata-${asset.id}`,
      name: asset.filename,
      context: t("common.assets.asset_metadata_context"),
      href: null,
    })),
    ...assetUsages.flowNodes.map((usage) => ({
      key: `flow-node-${usage.nodeId}`,
      name: usage.flowName,
      context: usageContext(t("common.assets.flow_audio_context"), usage.trashed),
      href: usage.trashed ? null : usageFlowHref(usage),
    })),
    ...assetUsages.sequenceVisualLayers.map((layer) => ({
      key: `sequence-visual-layer-${layer.id}`,
      name: layer.label || layer.sequenceName || layer.flowName,
      context: usageContext(
        t("common.assets.sequence_visual_layer_context", {
          flow: layer.flowName,
          kind: layer.kind,
        }),
        layer.trashed,
      ),
      href: layer.trashed ? null : usageFlowHref(layer),
    })),
    ...assetUsages.sequenceTracks.map((track) => ({
      key: `sequence-track-${track.id}`,
      name: track.sequenceName || track.flowName,
      context: usageContext(
        t("common.assets.sequence_track_context", {
          flow: track.flowName,
          kind: track.kind,
        }),
        track.trashed,
      ),
      href: track.trashed ? null : usageFlowHref(track),
    })),
    ...assetUsages.sheetAvatars.map((sheet) => ({
      key: `avatar-${sheet.id}`,
      name: sheet.name,
      context: usageContext(t("common.assets.avatar_context"), sheet.trashed),
      href: sheet.trashed ? null : usageSheetHref(sheet),
    })),
    ...assetUsages.sheetBanners.map((sheet) => ({
      key: `banner-${sheet.id}`,
      name: sheet.name,
      context: usageContext(t("common.assets.banner_context"), sheet.trashed),
      href: sheet.trashed ? null : usageSheetHref(sheet),
    })),
    ...assetUsages.sceneBackgrounds.map((scene) => ({
      key: `scene-bg-${scene.id}`,
      name: scene.name,
      context: usageContext(t("common.assets.scene_background_context"), scene.trashed),
      href: scene.trashed ? null : usageSceneHref(scene.id),
    })),
    ...assetUsages.scenePinIcons.map((pin) => ({
      key: `scene-pin-${pin.pinId}`,
      name: pin.pinLabel || pin.sceneName,
      context: usageContext(
        t("common.assets.scene_pin_icon_context", { scene: pin.sceneName }),
        pin.trashed,
      ),
      href: pin.trashed ? null : usageSceneHref(pin.sceneId),
    })),
    ...assetUsages.sceneZoneIcons.map((zone) => ({
      key: `scene-zone-${zone.zoneId}`,
      name: zone.zoneName,
      context: usageContext(
        t("common.assets.scene_zone_icon_context", { scene: zone.sceneName }),
        zone.trashed,
      ),
      href: zone.trashed ? null : usageSceneHref(zone.sceneId),
    })),
    ...assetUsages.localizedVoiceovers.map((voiceover) => ({
      key: `voiceover-${voiceover.id}`,
      name:
        voiceover.sourceText ||
        t("common.assets.voiceover_fallback", {
          type: voiceover.sourceType,
          id: voiceover.sourceId,
        }),
      context: usageContext(
        t("common.assets.voiceover_context", { locale: voiceover.localeCode }),
        false,
        voiceover.archived,
      ),
      href: usageLocalizationHref(voiceover),
    })),
    ...assetUsages.galleryImages.map((image) => ({
      key: `gallery-${image.id}`,
      name: image.label || image.sheetName,
      context: usageContext(
        t("common.assets.gallery_context", { sheet: image.sheetName }),
        image.trashed,
      ),
      href: image.trashed ? null : usageSheetHref({ id: image.sheetId }),
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

function changePage(nextPage: number) {
  if (nextPage < 1 || nextPage > totalPages || nextPage === page) return;
  live.pushEvent("change_asset_page", { page: nextPage });
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

function usageFlowHref(usage: { flowId: number }) {
  return `/workspaces/${workspaceSlug}/projects/${projectSlug}/flows/${usage.flowId}`;
}

function usageSheetHref(sheet: { id: number }) {
  return `/workspaces/${workspaceSlug}/projects/${projectSlug}/sheets/${sheet.id}`;
}

function usageSceneHref(sceneId: number) {
  return `/workspaces/${workspaceSlug}/projects/${projectSlug}/scenes/${sceneId}`;
}

function usageLocalizationHref(usage: LocalizedVoiceoverUsage) {
  return `/workspaces/${workspaceSlug}/projects/${projectSlug}/localization/texts/${usage.localeCode}/${usage.id}`;
}

function usageContext(context: string, trashed = false, archived = false) {
  if (trashed) return t("common.assets.trashed_context", { context });
  if (archived) return t("common.assets.archived_context", { context });
  return context;
}
</script>

<template>
  <DashboardContent
    :title="$t('common.assets.title')"
    :subtitle="$t('common.assets.subtitle')"
    :icon="Image"
    :is-empty="assets.length === 0"
    :empty-icon="Image"
    :empty-message="$t('common.assets.empty')"
  >
    <div v-if="assets.length > 0" class="flex flex-col gap-5 xl:flex-row">
      <div
        :class="[
          'grid flex-1 gap-4',
          selectedAsset
            ? 'grid-cols-2 sm:grid-cols-3 xl:grid-cols-2'
            : 'grid-cols-2 sm:grid-cols-3 lg:grid-cols-4',
        ]"
      >
        <div
          v-for="asset in assets"
          :key="asset.id"
          :data-testid="`asset-card-${asset.id}`"
          :class="[
            'group relative cursor-pointer overflow-hidden rounded-2xl border bg-card/85 shadow-sm transition-all duration-200 hover:-translate-y-0.5 hover:shadow-lg',
            selectedAsset && selectedAsset.id === asset.id
              ? 'border-primary ring-2 ring-primary/15'
              : 'border-border/70 hover:border-primary/30',
          ]"
          @click="selectAsset(asset.id)"
        >
          <div
            aria-hidden="true"
            class="absolute inset-x-0 top-0 z-10 h-0.5 bg-linear-to-r from-primary via-primary/75 to-project-accent opacity-0 transition-opacity group-hover:opacity-100"
          />
          <div class="flex h-36 items-center justify-center overflow-hidden bg-muted/70">
            <img
              v-if="isImage(asset)"
              :src="asset.url"
              :alt="asset.filename"
              class="h-full w-full object-cover transition-transform duration-300 group-hover:scale-[1.025]"
            />
            <span
              v-else
              class="grid size-14 place-items-center rounded-2xl border border-primary/15 bg-primary/[0.08] text-primary"
            >
              <Music v-if="isAudio(asset)" class="size-6" />
              <File v-else class="size-6" />
            </span>
          </div>
          <div class="p-3.5">
            <p class="text-sm font-medium truncate" :title="asset.filename">{{ asset.filename }}</p>
            <div class="mt-2 flex items-center justify-between text-xs text-muted-foreground">
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
        class="w-full shrink-0 self-start rounded-2xl border border-border/70 bg-card/85 p-4 shadow-sm xl:sticky xl:top-0 xl:w-88"
      >
        <div class="flex items-center justify-between">
          <h3 class="font-semibold text-sm">{{ $t("common.assets.details") }}</h3>
          <Button variant="ghost" size="icon-sm" class="size-7" @click="deselectAsset">
            <X class="size-4" />
          </Button>
        </div>

        <div class="overflow-hidden rounded-xl bg-muted">
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
        <div class="border-t border-border/60 pt-4">
          <h4 class="text-sm font-medium mb-2 flex items-center gap-2">
            <Link class="size-4" />
            {{ $t("common.assets.usage") }}
            <Badge variant="secondary" class="text-[10px] px-1.5 py-0">{{ totalUsages }}</Badge>
          </h4>

          <p v-if="totalUsages === 0" class="text-sm text-muted-foreground">
            {{ $t("common.assets.not_used") }}
          </p>

          <ul v-if="totalUsages > 0" class="text-sm space-y-1">
            <li v-for="usage in usageSummaries" :key="usage.key" class="flex items-center gap-2">
              <Link class="size-3 shrink-0 text-muted-foreground" />
              <a
                v-if="usage.href"
                :href="usage.href"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="text-primary hover:underline truncate"
              >
                {{ usage.name }}
              </a>
              <span v-else class="truncate text-foreground">{{ usage.name }}</span>
              <span class="truncate text-xs text-muted-foreground">{{ usage.context }}</span>
            </li>
          </ul>
        </div>

        <!-- Delete button -->
        <div v-if="canEdit" class="border-t border-border/60 pt-4">
          <Button variant="destructive" size="sm" class="w-full" @click="requestDelete">
            <Trash2 class="size-4" />
            {{ $t("common.assets.delete_asset") }}
          </Button>
        </div>
      </div>
    </div>

    <div
      v-if="totalPages > 1"
      class="flex items-center justify-between gap-4 rounded-2xl border border-border/70 bg-card/80 px-4 py-3 shadow-sm"
    >
      <p class="text-sm text-muted-foreground">
        {{ $t("common.assets.total_count", { count: totalCount }) }}
      </p>
      <div class="flex items-center gap-2">
        <Button
          variant="outline"
          size="sm"
          :disabled="page <= 1"
          :aria-label="$t('common.assets.previous_page')"
          @click="changePage(page - 1)"
        >
          <ChevronLeft class="size-4" />
        </Button>
        <span class="min-w-24 text-center text-sm text-muted-foreground">
          {{ $t("common.assets.page_of", { page, total: totalPages }) }}
        </span>
        <Button
          variant="outline"
          size="sm"
          :disabled="page >= totalPages"
          :aria-label="$t('common.assets.next_page')"
          @click="changePage(page + 1)"
        >
          <ChevronRight class="size-4" />
        </Button>
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
  </DashboardContent>
</template>
