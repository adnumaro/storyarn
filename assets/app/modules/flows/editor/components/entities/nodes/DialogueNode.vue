<script setup lang="ts">
import { EditorContent } from "@tiptap/vue-3";
import { MessageSquare, Volume2 } from "lucide-vue-next";
import { Ref } from "rete-vue-plugin";
import { computed, inject, nextTick, watch } from "vue";
import { useI18n } from "vue-i18n";
import EntityCombobox from "@components/forms/fields/EntityCombobox.vue";
import NodeHeader from "../node-shell/NodeHeader.vue";
import NodeShell from "../node-shell/NodeShell.vue";
import { useScreenplayEditor } from "../../../composables/useScreenplayEditor";
import { FLOW_CONTEXT_KEY } from "../../../lib/flow-context";
import { previewText } from "../../../lib/render-helpers";
import type { NodeConfig } from "../../../lib/node-configs";
import type {
  FlowContextInjection,
  ReteEmitFn,
  ReteNodeData,
  SheetMapEntry,
} from "../../../../types";

/** Raw rete state shape (snake_case from server canvas serializer). The
 * canvas wire stays snake_case for now — F3 of the relational refactor
 * (docs/features/flow-relational-refactor) will reshape `serialize_for_canvas`.
 * Internally the component works in camelCase via the `dialogue` adapter
 * computed below. */
interface RawDialogueData {
  speaker_sheet_id?: number | string | null;
  avatar_id?: number | string | null;
  audio_asset_id?: number | string | null;
  stage_directions?: string;
  menu_text?: string;
  text?: string;
  responses?: RawDialogueResponse[];
  location_sheet_id?: number | string | null;
}

interface RawDialogueResponse {
  id: string | number;
  text?: string;
  condition?: unknown;
  instruction_assignments?: unknown[];
  has_type_warnings?: boolean;
}

/** CamelCase internal projection. Aligns with `feedback_camelcase_props`. */
interface LocalDialogueResponse {
  id: string | number;
  text: string;
  condition: unknown;
  instructionAssignments: unknown[];
  hasTypeWarnings: boolean;
}

interface OutputBadge {
  type: "error" | "indicator";
  title: string;
  color?: string;
}

const {
  data,
  emit,
  config,
  color,
  sheetsMap = {},
  nodeDataOverride = null,
} = defineProps<{
  data: ReteNodeData;
  emit: ReteEmitFn;
  config: NodeConfig;
  color: string;
  sheetsMap?: Record<string, SheetMapEntry>;
  // The override (when set, e.g. by the editor's optimistic-update layer)
  // is still snake_case because it mirrors the rete `node.data` shape.
  // The adapter below normalizes it before the rest of the component
  // touches anything.
  nodeDataOverride?: RawDialogueData | null;
}>();

const { t } = useI18n();
const ctx = inject<FlowContextInjection>(FLOW_CONTEXT_KEY, {
  editingNodeId: null,
  onInlineEditSave: null,
  sheetsMap: {},
  hubsMap: {},
  lod: "full",
  nodeDataVersion: 0,
});

const editing = computed(() => ctx.editingNodeId === data.id);

/** Adapter: maps the raw rete `node.data` (snake_case canvas wire) into a
 * camelCase projection. Every accessor below reads from this — keeps the
 * component aligned with the camelCase prop convention without having to
 * refactor `Flows.serialize_for_canvas` (shared across 9 node types). */
const dialogue = computed(() => {
  const raw = nodeDataOverride || (data.nodeData as RawDialogueData) || {};
  const rawResponses = Array.isArray(raw.responses) ? raw.responses : [];

  return {
    speakerSheetId: raw.speaker_sheet_id ?? null,
    avatarId: raw.avatar_id ?? null,
    audioAssetId: raw.audio_asset_id ?? null,
    stageDirections: raw.stage_directions ?? "",
    menuText: raw.menu_text ?? "",
    text: raw.text ?? "",
    responses: rawResponses.map<LocalDialogueResponse>((r) => ({
      id: r.id,
      text: r.text ?? "",
      condition: r.condition,
      instructionAssignments: r.instruction_assignments ?? [],
      hasTypeWarnings: !!r.has_type_warnings,
    })),
  };
});

const speaker = computed(() => {
  const sheetId = dialogue.value.speakerSheetId;
  if (!sheetId) return null;
  return sheetsMap[String(sheetId)] || null;
});

const speakerName = computed(() => speaker.value?.name || config.label);

// Avatar resolution: specific override (from `avatarId`) > sheet default avatar > none.
const overrideAvatarUrl = computed(() => {
  const avatarId = dialogue.value.avatarId;
  if (!avatarId) return null;
  const avatars = speaker.value?.avatars || [];
  const found = avatars.find((a) => a.id === avatarId);
  return found?.url || null;
});

const defaultAvatarUrl = computed(() => speaker.value?.avatar_url || null);
const avatarUrl = computed(() => overrideAvatarUrl.value || defaultAvatarUrl.value);

const stageDirections = computed(() => dialogue.value.stageDirections);
const menuText = computed(() => dialogue.value.menuText);
const preview = computed(() => previewText(dialogue.value.text));

// Visual strip: avatar, speaker color bg, or nothing.
// Keep the container stable so swapping avatar overrides does not resize the
// node or leave Rete connections attached to stale socket positions.
const hasVisual = computed(() => avatarUrl.value || speaker.value);

// Sockets
const inputs = computed(() => Object.entries(data?.inputs || {}));
const outputs = computed(() => Object.entries(data?.outputs || {}));
const responses = computed<LocalDialogueResponse[]>(() => dialogue.value.responses);

// Speaker list for inline edit dropdown
const speakerOptions = computed(() => {
  const map = ctx.sheetsMap || sheetsMap || {};
  return Object.values(map);
});

let saveDebounce: ReturnType<typeof setTimeout> | undefined;
const inlineEditor = useScreenplayEditor({
  content: dialogue.value.text,
  placeholder: t("flows.nodes.dialogue.dialogue_placeholder"),
  editable: editing.value,
  onUpdate: (ed) => {
    clearTimeout(saveDebounce);
    saveDebounce = setTimeout(() => {
      const html = ed.isEmpty ? "" : ed.getHTML();
      if (html !== dialogue.value.text) save("text", html);
    }, 500);
  },
  onBlur: (ed) => {
    clearTimeout(saveDebounce);
    const html = ed.isEmpty ? "" : ed.getHTML();
    if (html !== dialogue.value.text) save("text", html);
  },
});

// Toggle editable + autofocus on edit-mode enter; blur (and cancel pending
// save) on exit so the node returns to view-mode without a trailing push.
watch(editing, (val) => {
  const ed = inlineEditor.value;
  if (!ed) return;
  ed.setEditable(val);
  if (val) {
    nextTick(() => ed.commands.focus("end"));
  } else {
    clearTimeout(saveDebounce);
  }
});

// Sync editor content when the server pushes a new value (collab refresh /
// undo / external write). emitUpdate:false to avoid the onUpdate save loop.
watch(
  () => dialogue.value.text,
  (newText) => {
    const ed = inlineEditor.value;
    if (!ed) return;
    if ((newText || "") !== ed.getHTML()) {
      ed.commands.setContent(newText || "", { emitUpdate: false });
    }
  },
);

function formatOutputLabel(key: string): string {
  const resp = responses.value.find((r) => r.id === key);
  return resp?.text || "";
}

function getOutputBadges(key: string): OutputBadge[] {
  const resp = responses.value.find((r) => r.id === key);
  if (!resp) return [];
  const badges: OutputBadge[] = [];
  if (!resp.text) badges.push({ type: "error", title: t("flows.nodes.dialogue.empty_response") });
  if (resp.hasTypeWarnings)
    badges.push({ type: "error", title: t("flows.nodes.dialogue.type_mismatch") });
  if (resp.condition)
    badges.push({
      type: "indicator",
      color: "#eab308",
      title: t("flows.nodes.dialogue.has_condition"),
    });
  if (resp.instructionAssignments.length > 0)
    badges.push({
      type: "indicator",
      color: "#ec4899",
      title: t("flows.nodes.dialogue.has_instructions"),
    });
  return badges;
}

function save(field: string, value: unknown) {
  ctx.onInlineEditSave?.(data.id, field, value);
}

function onStageDirectionsBlur(e: FocusEvent) {
  const val = (e.target as HTMLInputElement).value.trim();
  if (val !== stageDirections.value) save("stage_directions", val);
}

function onMenuTextBlur(e: FocusEvent) {
  const val = (e.target as HTMLInputElement).value.trim();
  if (val !== menuText.value) save("menu_text", val);
}

function onInputKeydown(e: KeyboardEvent) {
  e.stopPropagation();
  if (e.key === "Enter") (e.target as HTMLInputElement).blur();
}

function onSpeakerSelect(id: number | string | null) {
  save("speaker_sheet_id", id);
}
</script>

<template>
  <NodeShell
    :color="color"
    :selected="data.selected"
    extra-class="dialogue min-w-[280px] max-w-[350px]"
  >
    <!-- EDIT MODE HEADER: speaker combobox -->
    <template v-if="editing">
      <div
        class="header px-3 py-2 rounded-t-[10px] flex items-center gap-2 text-white font-medium text-[13px]"
        :style="`background: linear-gradient(to right, ${color} 40%, color-mix(in oklch, ${color} 85%, white) 100%)`"
        @pointerdown.stop
      >
        <MessageSquare class="size-4 shrink-0" />
        <EntityCombobox
          class="flex-1 min-w-0"
          variant="ghost"
          :options="speakerOptions"
          :selected-id="dialogue.speakerSheetId"
          :placeholder="t('flows.nodes.dialogue.no_speaker')"
          @update:selected-id="onSpeakerSelect"
        />
      </div>
    </template>

    <!-- VIEW MODE HEADER -->
    <NodeHeader v-else :color="color" :icon="MessageSquare" :label="speakerName">
      <Volume2
        v-if="dialogue.audioAssetId"
        class="ml-auto size-3.5 opacity-80"
        :aria-label="t('flows.dialogue_toolbar.has_audio')"
      />
    </NodeHeader>

    <!-- Visual strip: avatar (shared between modes) -->
    <template v-if="hasVisual">
      <div
        class="flow-dialogue-visual flex items-center justify-center px-3"
        :class="avatarUrl ? 'h-24 py-3' : 'h-3'"
        :style="{ backgroundColor: color + '20' }"
      >
        <img
          v-if="avatarUrl"
          :src="avatarUrl"
          alt=""
          class="max-h-full max-w-full rounded-lg object-contain"
        />
      </div>
    </template>

    <!-- EDIT MODE BODY -->
    <div v-if="editing" class="dialogue-screenplay px-3.5 pt-2.5 pb-3">
      <input
        class="inline-input"
        :placeholder="t('flows.nodes.dialogue.stage_placeholder')"
        :value="stageDirections"
        @blur="onStageDirectionsBlur"
        @keydown="onInputKeydown"
        @pointerdown.stop
      />
      <input
        class="inline-input inline-input-menu"
        :placeholder="t('flows.nodes.dialogue.menu_placeholder')"
        :value="menuText"
        @blur="onMenuTextBlur"
        @keydown="onInputKeydown"
        @pointerdown.stop
      />
      <EditorContent :editor="inlineEditor" class="inline-editor" @keydown.stop @pointerdown.stop />
    </div>

    <!-- VIEW MODE BODY: 3-row stack — value when present, muted placeholder
         otherwise. Mirrors edit-mode field structure so users can see what's
         editable. Stage directions render wrapped in `()` per screenplay
         §4.5 (parenthetical). -->
    <div v-else class="dialogue-screenplay px-3.5 pt-2.5 pb-3">
      <div
        v-if="stageDirections"
        class="sp-parenthetical italic text-muted-foreground/55 text-xs mb-1 wrap-break-word"
      >
        ({{ stageDirections }})
      </div>
      <div v-else class="sp-parenthetical italic text-muted-foreground/30 text-xs mb-1">
        ({{ t("flows.nodes.dialogue.stage_placeholder") }})
      </div>
      <div
        v-if="menuText"
        class="sp-menu-text text-xs text-primary/70 font-medium mb-1 wrap-break-word"
      >
        ≡ {{ menuText }}
      </div>
      <div v-else class="sp-menu-text text-xs text-primary/30 font-medium mb-1">
        ≡ {{ t("flows.nodes.dialogue.menu_placeholder") }}
      </div>
      <div
        v-if="preview"
        class="sp-dialogue text-sm text-foreground/85 leading-relaxed wrap-break-word whitespace-pre-wrap"
      >
        {{ preview }}
      </div>
      <div v-else class="sp-dialogue text-sm text-muted-foreground/30 leading-relaxed">
        {{ t("flows.nodes.dialogue.dialogue_placeholder") }}
      </div>
    </div>

    <!-- Sockets with response labels and badges -->
    <div class="relative py-1.5 border-t border-border/10">
      <!-- Inputs -->
      <div
        v-for="[key, input] in inputs"
        :key="'i-' + key"
        class="flex items-center py-1 text-[11px] text-muted-foreground justify-start"
      >
        <Ref
          class="input-socket absolute -left-1.5"
          :data="{ type: 'socket', side: 'input', key, nodeId: data.id, payload: input.socket }"
          :emit="emit"
          data-testid="input-socket"
        />
        <span class="ml-2">{{ key }}</span>
      </div>
      <!-- Outputs (responses) -->
      <div
        v-for="[key, output] in outputs"
        :key="'o-' + key"
        class="relative flex items-center py-1 text-[11px] text-muted-foreground justify-end"
      >
        <!-- Response badges -->
        <template v-for="badge in getOutputBadges(key)" :key="badge.title">
          <div
            v-if="badge.type === 'error'"
            class="inline-flex items-center justify-center size-3.5 text-[10px] font-bold rounded-full mr-0.5 bg-destructive text-destructive-foreground cursor-help"
            :title="badge.title"
          >
            !
          </div>
          <span
            v-else-if="badge.type === 'indicator'"
            class="inline-block size-2 rounded-full mr-1"
            :style="{ backgroundColor: badge.color }"
            :title="badge.title"
          />
        </template>
        <!-- Response label (or socket key when there are no responses) -->
        <span
          v-if="responses.length > 0"
          class="px-2 max-w-55 wrap-break-word text-right"
          :title="formatOutputLabel(key)"
        >
          {{ formatOutputLabel(key) }}
        </span>
        <span v-else class="mr-2">{{ key }}</span>
        <Ref
          class="output-socket absolute -right-1.5"
          :data="{ type: 'socket', side: 'output', key, nodeId: data.id, payload: output.socket }"
          :emit="emit"
          data-testid="output-socket"
        />
      </div>
    </div>
  </NodeShell>
</template>

<style scoped>
/* Screenplay typography: Courier Prime everywhere on the dialogue node body
 * (view + edit) and the header (speaker cue). screenplay.css is loaded
 * globally; the .sp-* classes in the template inherit its italic/opacity
 * but we override the absolute-pixel page indents (96-211px) — the canvas
 * node is 280-350px wide, far smaller than an 816px screenplay page. */
.dialogue :deep(.header) {
  font-family: "Courier Prime", "Courier New", Courier, monospace;
  text-transform: uppercase;
  letter-spacing: 0.02em;
}

/* EntityCombobox's <button> resets text-transform: none in edit mode —
 * force inherit so the speaker name stays uppercase. */
.dialogue :deep(.header *) {
  text-transform: inherit;
}

.dialogue-screenplay {
  font-family: "Courier Prime", "Courier New", Courier, monospace;
}

/* Neutralise screenplay.css page-layout indents inside the canvas node. */
.dialogue-screenplay :deep(.sp-parenthetical),
.dialogue-screenplay .sp-parenthetical,
.dialogue-screenplay :deep(.sp-dialogue),
.dialogue-screenplay .sp-dialogue {
  margin-left: 0;
  max-width: none;
  opacity: 1;
}

.inline-input {
  width: 100%;
  background: transparent;
  border: 0;
  border-bottom: 1px solid var(--color-border, #27272a);
  font-family: "Courier Prime", "Courier New", Courier, monospace;
  font-style: italic;
  font-size: 12px;
  padding: 2px 0;
  margin-bottom: 4px;
  outline: none;
  color: var(--color-muted-foreground, #a1a1aa);
}

.inline-input-menu {
  font-style: normal;
  font-weight: 500;
  color: var(--color-primary, #3b82f6);
  opacity: 0.7;
}

.inline-editor :deep(.tiptap) {
  width: 100%;
  background: transparent;
  border: 0;
  font-family: "Courier Prime", "Courier New", Courier, monospace;
  font-size: 14px;
  padding: 0;
  outline: none;
  line-height: 1.625;
  color: var(--color-foreground, #fafafa);
  opacity: 0.85;
  white-space: pre-wrap;
  word-wrap: break-word;
}

.inline-editor :deep(.tiptap p) {
  margin: 0;
}

.inline-editor :deep(.tiptap p.is-editor-empty:first-child::before) {
  content: attr(data-placeholder);
  float: left;
  color: var(--color-muted-foreground, #a1a1aa);
  pointer-events: none;
  height: 0;
}
</style>
