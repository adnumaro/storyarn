<script setup lang="ts">
/**
 * Side panel for editing a dialogue flow_node.
 *
 * Vue port of V1's `lib/storyarn_web/live/flow_live/components/screenplay_editor.ex`
 * LiveComponent (V1 also misnamed it — this panel has nothing to do with the
 * Storyarn.Screenplays domain; it edits a `type="dialogue"` flow_node).
 *
 * Thin shell — header (title + close) + footer (status bar) + body. The
 * tabs / TipTap editor / save handlers live in `FlowDialogueEditorBody.vue`,
 * shared with `FlowDialogueFullscreenEditor.vue`.
 */

import { BookOpen, FileText, MessageSquare, Volume2, X } from "lucide-vue-next";
import { computed } from "vue";
import Sidebar from "@components/layout/Sidebar.vue";
import FlowDialogueEditorBody, {
  type AudioAssetItem,
  type DialoguePanelData,
  type DialogueResponseShape,
  type SheetOption,
} from "./FlowDialogueEditorBody.vue";
import { useLive } from "@composables/useLive";

// Re-export the body's types so existing test fixtures (and any other
// importer that points at this panel) keep working without churn.
export type { AudioAssetItem, DialoguePanelData, DialogueResponseShape, SheetOption };

const {
  open = false,
  data = null,
  canEdit = false,
} = defineProps<{
  open?: boolean;
  data?: DialoguePanelData | null;
  canEdit?: boolean;
}>();

const live = useLive();

const speakerName = computed<string>(() => {
  const id = data?.speakerSheetId;
  if (id == null) return "";
  return (data?.allSheets ?? []).find((s) => String(s.id) === String(id))?.name ?? "";
});

const hasAudio = computed<boolean>(() => data?.audioAssetId != null);

/** Word count over plain text + stageDirections + menuText + response texts.
 * Strips HTML for the rich-text body. Mirrors V1's `WordCount.for_node_data`. */
const wordCount = computed<number>(() => {
  const parts: string[] = [];
  const html = data?.text || "";
  if (html) {
    const stripped = html.replace(/<[^>]+>/g, " ");
    parts.push(stripped);
  }
  if (data?.stageDirections) parts.push(data.stageDirections);
  if (data?.menuText) parts.push(data.menuText);
  for (const r of data?.responses ?? []) if (r.text) parts.push(r.text);
  return parts.join(" ").trim().split(/\s+/).filter(Boolean).length;
});

function close() {
  live.pushEvent("close_editor", {});
}
</script>

<template>
  <Sidebar side="right" :open="open" @close="close">
    <template #header>
      <div class="flex items-center justify-between py-2.5">
        <div class="flex items-center gap-2 text-sm font-medium">
          <BookOpen class="size-4" />
          {{ $t("flows.dialogue_panel.title") }}
        </div>
        <button
          type="button"
          class="p-1 rounded hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
          @click="close"
        >
          <X class="size-4" />
        </button>
      </div>
    </template>

    <FlowDialogueEditorBody :data="data" :can-edit="canEdit" />

    <!-- Footer (V1 parity: speaker · word count · audio attached). Lives
         outside the Tabs so it's visible on every tab. The Sidebar primitive
         already owns padding + border-top + `flex justify-end` on the slot
         wrapper — we add `flex-1 justify-start` to override the default
         right alignment for status content. -->
    <template #footer>
      <div class="flex-1 flex items-center gap-3 text-xs text-muted-foreground">
        <span v-if="speakerName" class="flex items-center gap-1 truncate">
          <MessageSquare class="size-3 shrink-0" />
          <span class="truncate">{{ speakerName }}</span>
        </span>
        <span class="flex items-center gap-1">
          <FileText class="size-3" />
          {{ $t("flows.dialogue_panel.word_count", { count: wordCount }, wordCount) }}
        </span>
        <span v-if="hasAudio" class="flex items-center gap-1">
          <Volume2 class="size-3" />
          {{ $t("flows.dialogue_panel.audio_attached") }}
        </span>
      </div>
    </template>
  </Sidebar>
</template>
