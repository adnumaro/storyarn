<script setup lang="ts">
/**
 * Fullscreen modal version of the dialogue editor (M3.2). Reuses the same
 * `FlowDialogueEditorBody` as the sidebar `FlowDialoguePanel.vue` — only
 * the wrapper changes (shadcn Dialog instead of Sidebar). Backend gates
 * `open` via `editing_mode == :dialogue_fullscreen`.
 *
 * Three close paths:
 *   - Minimize2 button → pushes `minimize_dialogue_fullscreen` (back to panel).
 *   - X button / Esc / backdrop → pushes `close_editor` (closes everything).
 */

import { BookOpen, FileText, MessageSquare, Minimize2, Volume2 } from "lucide-vue-next";
import { computed } from "vue";
import { Button } from "@components/ui/button";
import { Dialog, DialogContent } from "@components/ui/dialog";
import FlowDialogueEditorBody, { type DialoguePanelData } from "./FlowDialogueEditorBody.vue";
import { useLive } from "../../../../../shared/composables/useLive";

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

function countWordsFromData(dialogueData: DialoguePanelData | null): number {
  const html = dialogueData?.text ?? "";
  const responseTexts = (dialogueData?.responses ?? []).map((response) => response.text);
  const text = [
    html.replace(/<[^>]+>/g, " "),
    dialogueData?.stageDirections,
    dialogueData?.menuText,
    ...responseTexts,
  ]
    .filter(Boolean)
    .join(" ");

  return text.trim().split(/\s+/).filter(Boolean).length;
}

/** Mirror of the panel's word-count helper. Strips HTML for the rich-text
 * body. Kept locally (not in the body component) because the footer status
 * bar is a wrapper concern, not a tab-content concern. */
const wordCount = computed<number>(() => countWordsFromData(data));

function minimize() {
  live.pushEvent("minimize_dialogue_fullscreen", {});
}

function close() {
  live.pushEvent("close_editor", {});
}

/** Esc / backdrop / outside click → close everything. We use reka-ui's
 * explicit dismissal events instead of `update:open` because the latter
 * also fires when the prop flips from true→false during a panel↔modal
 * transition (e.g. clicking Minimize2 sends `minimize_dialogue_fullscreen`
 * AND triggers `update:open=false` once the diff lands; firing
 * `close_editor` from there would overwrite the minimize). */
function onDismiss(e: Event) {
  e.preventDefault();
  close();
}
</script>

<template>
  <Dialog :open="open">
    <DialogContent
      class="!fixed !inset-0 !top-0 !left-0 !translate-x-0 !translate-y-0 !max-w-none !w-screen !h-screen !rounded-none !border-0 !p-0 !gap-0 flex flex-col"
      :show-close-button="false"
      @escape-key-down="onDismiss"
      @pointer-down-outside="onDismiss"
      @interact-outside="onDismiss"
    >
      <!-- Header — matches FlowDialoguePanel header layout but with
           Minimize2 (back to panel) instead of X (close all). -->
      <div class="flex items-center justify-between px-4 py-2.5 border-b border-border">
        <div class="flex items-center gap-2 text-sm font-medium">
          <BookOpen class="size-4" />
          {{ $t("flows.dialogue_panel.title") }}
        </div>
        <div class="flex items-center gap-1">
          <Button
            variant="ghost"
            size="icon"
            class="size-7"
            :title="$t('flows.dialogue_panel.minimize')"
            @click="minimize"
          >
            <Minimize2 class="size-4" />
          </Button>
        </div>
      </div>

      <!-- Body — screenplay-page rendering (sp-character / sp-parenthetical /
           sp-menu-text / sp-dialogue) instead of the sidebar's labelled
           fields. Responses + Settings tabs are identical to the sidebar.
           `flex-1` lets the body fill all viewport space between header and
           footer; inner overflow keeps long dialogues scrollable. -->
      <div class="flex-1 overflow-y-auto px-4 py-3">
        <FlowDialogueEditorBody :data="data" :can-edit="canEdit" display="fullscreen" />
      </div>

      <!-- Footer — V1-parity status bar (speaker · word count · audio). -->
      <div
        class="px-4 py-2 border-t border-border flex items-center gap-3 text-xs text-muted-foreground"
      >
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
    </DialogContent>
  </Dialog>
</template>
