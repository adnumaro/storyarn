<script setup lang="ts">
import { computed, ref } from "vue";
import { useLiveVue } from "live_vue";
import CollabToast from "@modules/sheets/components/collab/CollabToast.vue";
import SheetCanvasComments from "@modules/sheets/components/chrome/SheetCanvasComments.vue";
import SheetContentHeader from "@modules/sheets/components/chrome/header/SheetContentHeader.vue";
import BlockList from "@modules/sheets/components/entities/blocks/BlockList.vue";
import SheetShowPanels from "@modules/sheets/components/panels/SheetShowPanels.vue";
import SheetTabs from "@modules/sheets/components/panels/tabs/SheetTabs.vue";
import {
  type SheetDeepLinkTarget,
  useSheetHighlight,
} from "@modules/sheets/composables/useSheetHighlight";
import type { Sheet, SheetHealth } from "@modules/sheets/types";
import type { SheetCommentsPanelState, SheetCommentThread } from "@modules/sheets/types/comments";

type ServerPayload = any;

interface SheetSurfaceTabs {
  currentTab: string;
  canEdit: boolean;
  compact: boolean;
}

interface SheetSurfaceContent {
  blocks: ServerPayload[];
  inheritedGroups: ServerPayload[];
  workspaceSlug: string;
  projectSlug: string;
  canEdit: boolean;
  formulaEditing: ServerPayload;
  blockLocks: Record<string, ServerPayload>;
  currentUserId: number | null;
  commentPins?: SheetCommentThread[];
  comments?: SheetCommentsPanelState | null;
  commentFocusThreadId?: number | null;
}

interface SheetSurface {
  health: SheetHealth | null;
  tabs: SheetSurfaceTabs;
  content: SheetSurfaceContent | null;
}

interface SheetPanelsProps {
  currentTab: string;
  compact: boolean;
  references: ServerPayload | null;
  audio: ServerPayload | null;
  history: ServerPayload | null;
  comments?: SheetCommentsPanelState;
}

const {
  sheet: initialSheet = null,
  canEdit: initialCanEdit = false,
  sourceShortcut: initialSourceShortcut = null,
  highlightTarget: initialHighlightTarget = null,
  surface: initialSurface,
  panels: initialPanels = null,
} = defineProps<{
  sheet?: Sheet | null;
  canEdit?: boolean;
  sourceShortcut?: string | null;
  highlightTarget?: SheetDeepLinkTarget | null;
  surface: SheetSurface;
  panels?: SheetPanelsProps | null;
}>();

const live = useLiveVue();

// Injected LiveVue boundaries stay mounted while LiveView diffs replace props.
const sheet = computed(() => (live.vue?.props?.sheet as Sheet | null | undefined) ?? initialSheet);
const canEdit = computed(() => (live.vue?.props?.canEdit as boolean | undefined) ?? initialCanEdit);
const sourceShortcut = computed(
  () => (live.vue?.props?.sourceShortcut as string | null | undefined) ?? initialSourceShortcut,
);
const highlightTarget = computed(() => {
  const liveTarget = live.vue?.props?.highlightTarget as SheetDeepLinkTarget | null | undefined;
  return liveTarget === undefined ? initialHighlightTarget : liveTarget;
});
const surface = computed(
  () => (live.vue?.props?.surface as SheetSurface | undefined) ?? initialSurface,
);
const panels = computed(
  () => (live.vue?.props?.panels as SheetPanelsProps | null | undefined) ?? initialPanels,
);
const surfaceRoot = ref<HTMLElement | null>(null);
const localCommentInteractionActive = ref(false);
const commentsActive = computed(
  () =>
    Boolean(surface.value.content?.comments?.open || surface.value.content?.comments?.placing) ||
    localCommentInteractionActive.value,
);
const commentPlacementActive = computed(
  () =>
    surface.value.content?.comments?.placing === true && surface.value.content.comments.canComment,
);
const commentDraftStorageKey = computed(() => {
  const sheetId = sheet.value?.id;
  const userId = surface.value.content?.currentUserId;
  return sheetId == null || userId == null
    ? null
    : `storyarn:sheet-comment-draft:${userId}:${sheetId}`;
});

function getSurfaceRoot(): HTMLElement | null {
  return surfaceRoot.value;
}

useSheetHighlight(
  highlightTarget,
  computed(() => surface.value.content != null),
);
</script>

<template>
  <div
    v-if="sheet"
    ref="surfaceRoot"
    data-sheet-comment-surface="true"
    :role="commentPlacementActive ? 'region' : undefined"
    :aria-label="commentPlacementActive ? $t('sheets.comments.surface_label') : undefined"
    class="relative mx-auto max-w-4xl rounded-2xl border border-border bg-surface p-6 shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
    :class="{
      'cursor-crosshair': commentPlacementActive,
    }"
    :tabindex="commentPlacementActive ? 0 : -1"
    :aria-describedby="
      commentPlacementActive ? 'sheet-comment-surface-keyboard-instructions' : undefined
    "
  >
    <SheetContentHeader
      :sheet="sheet"
      :can-edit="canEdit"
      :source-shortcut="sourceShortcut"
      :sheet-health="surface.tabs.compact ? surface.health : null"
    />

    <div class="pb-6">
      <div id="sheet-tabs" class="contents">
        <SheetTabs
          :current-tab="surface.tabs.currentTab"
          :can-edit="surface.tabs.canEdit"
          :compact="surface.tabs.compact"
        />
      </div>

      <div v-if="surface.content" id="block-list" class="contents">
        <BlockList
          :blocks="surface.content.blocks"
          :inherited-groups="surface.content.inheritedGroups"
          :workspace-slug="surface.content.workspaceSlug"
          :project-slug="surface.content.projectSlug"
          :can-edit="surface.content.canEdit"
          :formula-editing="surface.content.formulaEditing"
          :block-locks="surface.content.blockLocks"
          :current-user-id="surface.content.currentUserId"
          :comments-active="commentsActive"
        />
      </div>

      <SheetCanvasComments
        v-if="surface.content?.comments"
        :container="getSurfaceRoot"
        :state="surface.content.comments"
        :comment-pins="surface.content.commentPins ?? []"
        :focus-thread-id="surface.content.commentFocusThreadId ?? null"
        :draft-storage-key="commentDraftStorageKey"
        @interaction-change="localCommentInteractionActive = $event"
      />

      <div id="collab-toast" class="contents">
        <CollabToast />
      </div>

      <SheetShowPanels v-if="panels" :panels="panels" />
    </div>
  </div>

  <div v-else class="flex justify-center py-20">
    <div
      class="size-6 border-2 border-muted-foreground/20 border-t-muted-foreground/60 rounded-full animate-spin"
    />
  </div>
</template>
