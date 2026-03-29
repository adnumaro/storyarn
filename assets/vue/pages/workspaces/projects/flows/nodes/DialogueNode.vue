<script setup>
import { computed, inject, nextTick, ref, watch } from "@/vue/index.js";
import { MessageSquare } from "lucide-vue-next";
import { Ref } from "rete-vue-plugin";
import { previewText, stripHtml } from "../lib/render-helpers.js";
import { FLOW_CONTEXT_KEY } from "../setup.js";
import EntityCombobox from "../../../../../components/form-fields/EntityCombobox.vue";
import NodeHeader from "../components/NodeHeader.vue";
import NodeShell from "../components/NodeShell.vue";

const props = defineProps({
	data: { type: Object, required: true },
	emit: { type: Function, required: true },
	config: { type: Object, required: true },
	color: { type: String, required: true },
	sheetsMap: { type: Object, default: () => ({}) },
	labels: { type: Object, default: () => ({}) },
});

const ctx = inject(FLOW_CONTEXT_KEY, { editingNodeId: null, onInlineEditSave: null, sheetsMap: {} });
const dialogueRef = ref(null);

const nodeData = computed(() => props.data.nodeData || {});
const editing = computed(() => ctx.editingNodeId === props.data.id);

const speaker = computed(() => {
	const sheetId = nodeData.value.speaker_sheet_id;
	if (!sheetId) return null;
	return props.sheetsMap[String(sheetId)] || null;
});

const speakerName = computed(() => speaker.value?.name || props.config.label);

// Avatar resolution: specific avatar_id override > default avatar_url > no avatar
const overrideAvatarUrl = computed(() => {
	const avatarId = nodeData.value.avatar_id;
	if (!avatarId) return null;
	const avatars = speaker.value?.avatars || [];
	const found = avatars.find((a) => a.id === avatarId);
	return found?.url || null;
});

const defaultAvatarUrl = computed(() => speaker.value?.avatar_url || null);

const stageDirections = computed(() => nodeData.value.stage_directions || "");
const menuText = computed(() => nodeData.value.menu_text || "");
const preview = computed(() => previewText(nodeData.value.text));
const plainText = computed(() => stripHtml(nodeData.value.text));
const hasTextContent = computed(() => stageDirections.value || menuText.value || preview.value);
const hasAudio = computed(() => !!nodeData.value.audio_asset_id);

// Visual strip: override avatar, default avatar, colored bg, or nothing
const hasVisual = computed(() => overrideAvatarUrl.value || defaultAvatarUrl.value || speaker.value);
const hasContent = computed(() => hasTextContent.value || hasVisual.value || responses.value.length > 0);

// Sockets
const inputs = computed(() => Object.entries(props.data?.inputs || {}));
const outputs = computed(() => Object.entries(props.data?.outputs || {}));
const responses = computed(() => nodeData.value.responses || []);

// Speaker list for inline edit dropdown
const speakerOptions = computed(() => {
	const map = ctx.sheetsMap || props.sheetsMap || {};
	return Object.values(map);
});

// Autofocus dialogue textarea when entering edit mode
watch(editing, (val) => {
	if (val) {
		nextTick(() => dialogueRef.value?.focus());
	}
});

function formatOutputLabel(key) {
	const resp = responses.value.find((r) => r.id === key);
	return resp?.text || "";
}

function getOutputBadges(key) {
	const resp = responses.value.find((r) => r.id === key);
	if (!resp) return [];
	const badges = [];
	if (!resp.text) badges.push({ type: "error", title: "Empty response text" });
	if (resp.has_type_warnings) badges.push({ type: "error", title: "Type mismatch" });
	if (resp.condition) badges.push({ type: "indicator", color: "#eab308", title: "Has condition" });
	if ((resp.instruction_assignments || []).length > 0) badges.push({ type: "indicator", color: "#ec4899", title: "Has instructions" });
	return badges;
}

function save(field, value) {
	ctx.onInlineEditSave?.(props.data.id, field, value);
}

function onStageDirectionsBlur(e) {
	const val = e.target.value.trim();
	if (val !== stageDirections.value) save("stage_directions", val);
}

function onMenuTextBlur(e) {
	const val = e.target.value.trim();
	if (val !== menuText.value) save("menu_text", val);
}

function onDialogueBlur(e) {
	const val = e.target.value.trim();
	if (val !== plainText.value) save("text", val);
}

function onInputKeydown(e) {
	e.stopPropagation();
	if (e.key === "Enter") e.target.blur();
}

function onTextareaKeydown(e) {
	e.stopPropagation();
	if (e.key === "Escape") e.target.blur();
}

function autoResize(e) {
	e.target.style.height = "auto";
	e.target.style.height = `${e.target.scrollHeight}px`;
}

function onSpeakerSelect(id) {
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
          :selected-id="nodeData.speaker_sheet_id || null"
          :placeholder="labels.no_speaker || config.label"
          @update:selected-id="onSpeakerSelect"
        />
      </div>
    </template>

    <!-- VIEW MODE HEADER -->
    <NodeHeader v-else :color="color" :icon="MessageSquare" :label="speakerName">
      <span v-if="hasAudio" class="ml-auto opacity-80 text-xs" title="Has audio">🔊</span>
    </NodeHeader>

    <!-- Visual strip: avatar (shared between modes) -->
    <template v-if="hasVisual">
      <img
        v-if="overrideAvatarUrl"
        :src="overrideAvatarUrl"
        alt=""
        class="block w-[calc(100%-24px)] max-h-[200px] object-contain rounded-lg mx-3 mt-3"
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
        :placeholder="labels.stage_directions || 'Stage directions…'"
        :value="stageDirections"
        @blur="onStageDirectionsBlur"
        @keydown="onInputKeydown"
        @pointerdown.stop
      />
      <input
        class="inline-input inline-input-menu"
        :placeholder="labels.menu_text || 'Menu text…'"
        :value="menuText"
        @blur="onMenuTextBlur"
        @keydown="onInputKeydown"
        @pointerdown.stop
      />
      <textarea
        ref="dialogueRef"
        class="inline-textarea"
        :placeholder="labels.dialogue_text || 'Dialogue text…'"
        :value="plainText"
        @blur="onDialogueBlur"
        @keydown="onTextareaKeydown"
        @input="autoResize"
        @pointerdown.stop
      />
    </div>

    <!-- VIEW MODE BODY -->
    <div v-else-if="hasTextContent" class="px-3.5 pt-2.5 pb-3">
      <div v-if="stageDirections" class="italic text-muted-foreground/55 text-xs mb-1 break-words">
        {{ stageDirections }}
      </div>
      <div v-if="menuText" class="text-xs text-primary/70 font-medium mb-1 break-words">
        ≡ {{ menuText }}
      </div>
      <div v-if="preview" class="text-sm text-foreground/85 leading-relaxed break-words whitespace-pre-wrap">
        {{ preview }}
      </div>
    </div>

    <!-- Sockets with response labels and badges -->
    <div class="py-1.5 border-t border-border/10">
      <!-- Inputs -->
      <div v-for="[key, input] in inputs" :key="'i-' + key" class="flex items-center py-1 text-[11px] text-muted-foreground justify-start">
        <Ref
          class="input-socket"
          :data="{ type: 'socket', side: 'input', key, nodeId: data.id, payload: input.socket }"
          :emit="emit"
          data-testid="input-socket"
        />
      </div>
      <!-- Outputs (responses) -->
      <div v-for="[key, output] in outputs" :key="'o-' + key" class="flex items-center py-1 text-[11px] text-muted-foreground justify-end">
        <!-- Response badges -->
        <template v-for="badge in getOutputBadges(key)" :key="badge.title">
          <div
            v-if="badge.type === 'error'"
            class="inline-flex items-center justify-center size-3.5 text-[10px] font-bold rounded-full mr-0.5 bg-destructive text-destructive-foreground cursor-help"
            :title="badge.title"
          >!</div>
          <span
            v-else-if="badge.type === 'indicator'"
            class="inline-block size-2 rounded-full mr-1"
            :style="{ backgroundColor: badge.color }"
            :title="badge.title"
          />
        </template>
        <!-- Response label -->
        <span class="px-2 max-w-[220px] break-words text-right" :title="formatOutputLabel(key)">
          {{ formatOutputLabel(key) }}
        </span>
        <Ref
          class="output-socket"
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
