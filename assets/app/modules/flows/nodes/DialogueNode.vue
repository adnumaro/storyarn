<script setup lang="ts">
import { MessageSquare } from "lucide-vue-next";
import { Ref } from "rete-vue-plugin";
import { computed, inject, nextTick, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import EntityCombobox from "@components/form-fields/EntityCombobox.vue";
import NodeHeader from "../components/NodeHeader.vue";
import NodeShell from "../components/NodeShell.vue";
import { previewText, stripHtml } from "../lib/render-helpers";
import { FLOW_CONTEXT_KEY } from "../setup";
import type { NodeConfig } from "../lib/node-configs";
import type {
  FlowContextInjection,
  ReteEmitFn,
  ReteNodeData,
  SheetMapEntry,
} from "../types";
import DialogueAudioPreview from "./DialogueAudioPreview.vue";

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
const dialogueRef = ref<HTMLTextAreaElement | null>(null);

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

const stageDirections = computed(() => dialogue.value.stageDirections);
const menuText = computed(() => dialogue.value.menuText);
const preview = computed(() => previewText(dialogue.value.text));
const plainText = computed(() => stripHtml(dialogue.value.text));
const hasTextContent = computed(() => stageDirections.value || menuText.value || preview.value);

// Visual strip: override avatar, default avatar, colored bg, or nothing
const hasVisual = computed(
  () => overrideAvatarUrl.value || defaultAvatarUrl.value || speaker.value,
);
const hasContent = computed(
  () => hasTextContent.value || hasVisual.value || responses.value.length > 0,
);

// Sockets
const inputs = computed(() => Object.entries(data?.inputs || {}));
const outputs = computed(() => Object.entries(data?.outputs || {}));
const responses = computed<LocalDialogueResponse[]>(() => dialogue.value.responses);

// Speaker list for inline edit dropdown
const speakerOptions = computed(() => {
  const map = ctx.sheetsMap || sheetsMap || {};
  return Object.values(map);
});

// Autofocus dialogue textarea when entering edit mode
watch(editing, (val) => {
  if (val) {
    nextTick(() => dialogueRef.value?.focus());
  }
});

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

function onDialogueBlur(e: FocusEvent) {
  const val = (e.target as HTMLTextAreaElement).value.trim();
  if (val !== plainText.value) save("text", val);
}

function onInputKeydown(e: KeyboardEvent) {
  e.stopPropagation();
  if (e.key === "Enter") (e.target as HTMLInputElement).blur();
}

function onTextareaKeydown(e: KeyboardEvent) {
  e.stopPropagation();
  if (e.key === "Escape") (e.target as HTMLTextAreaElement).blur();
}

function autoResize(e: Event) {
  const target = e.target as HTMLTextAreaElement;
  target.style.height = "auto";
  target.style.height = `${target.scrollHeight}px`;
}

function onSpeakerSelect(id: number | string | null) {
  save("speaker_sheet_id", id);
}
</script>

<template>
  <NodeShell
    :color="color"
    :selected="data.selected"
    :extra-class="hasContent || editing ? 'dialogue min-w-[280px] max-w-[350px]' : 'dialogue'"
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
      <DialogueAudioPreview :audio-asset-id="dialogue.audioAssetId" />
    </NodeHeader>

    <!-- Visual strip: avatar (shared between modes) -->
    <template v-if="hasVisual">
      <img
        v-if="overrideAvatarUrl"
        :src="overrideAvatarUrl"
        alt=""
        class="block w-[calc(100%-24px)] max-h-50 object-contain rounded-lg mx-3 mt-3"
      />
      <div
        v-else-if="defaultAvatarUrl"
        class="flex items-center justify-center px-3 pt-3"
        :style="{ backgroundColor: color + '20' }"
      >
        <img :src="defaultAvatarUrl" alt="" class="size-16 rounded-lg object-cover shadow-md" />
      </div>
      <div
        v-else-if="speaker"
        class="flex items-center justify-center px-3 pt-3"
        :style="{ backgroundColor: color + '20' }"
      />
    </template>

    <!-- EDIT MODE BODY -->
    <div v-if="editing" class="px-3.5 pt-2.5 pb-3">
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
      <textarea
        ref="dialogueRef"
        class="inline-textarea"
        :placeholder="t('flows.nodes.dialogue.dialogue_placeholder')"
        :value="plainText"
        @blur="onDialogueBlur"
        @keydown="onTextareaKeydown"
        @input="autoResize"
        @pointerdown.stop
      />
    </div>

    <!-- VIEW MODE BODY -->
    <div v-else-if="hasTextContent" class="px-3.5 pt-2.5 pb-3">
      <div
        v-if="stageDirections"
        class="italic text-muted-foreground/55 text-xs mb-1 wrap-break-word"
      >
        {{ stageDirections }}
      </div>
      <div v-if="menuText" class="text-xs text-primary/70 font-medium mb-1 wrap-break-word">
        ≡ {{ menuText }}
      </div>
      <div
        v-if="preview"
        class="text-sm text-foreground/85 leading-relaxed wrap-break-word whitespace-pre-wrap"
      >
        {{ preview }}
      </div>
    </div>

    <!-- EMPTY STATE HINT -->
    <div v-else-if="!hasContent" class="px-3.5 pt-2.5 pb-3 text-xs italic text-muted-foreground/50">
      {{ t("flows.nodes.dialogue.empty_hint") }}
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
        <span v-if="responses.length === 0" class="ml-2">{{ key }}</span>
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
.inline-input {
  width: 100%;
  background: transparent;
  border: 0;
  border-bottom: 1px solid var(--color-border, #27272a);
  font-style: italic;
  font-size: 12px;
  padding: 2px 0;
  margin-bottom: 4px;
  outline: none;
  font-family: inherit;
  color: var(--color-muted-foreground, #a1a1aa);
}

.inline-input-menu {
  font-style: normal;
  font-weight: 500;
  color: var(--color-primary, #3b82f6);
  opacity: 0.7;
}

.inline-textarea {
  width: 100%;
  background: transparent;
  border: 0;
  font-size: 14px;
  padding: 0;
  resize: none;
  outline: none;
  line-height: 1.625;
  overflow: hidden;
  font-family: inherit;
  color: var(--color-foreground, #fafafa);
  opacity: 0.85;
}
</style>
