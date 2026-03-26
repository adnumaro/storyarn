<script setup>
import { computed } from "vue";
import { Ref } from "rete-vue-plugin";
import { previewText } from "../lib/render-helpers.js";
import NodeHeader from "../components/NodeHeader.vue";
import NodeShell from "../components/NodeShell.vue";

const props = defineProps({
	data: { type: Object, required: true },
	emit: { type: Function, required: true },
	config: { type: Object, required: true },
	color: { type: String, required: true },
	sheetsMap: { type: Object, default: () => ({}) },
});

const nodeData = computed(() => props.data.nodeData || {});

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
const hasTextContent = computed(() => stageDirections.value || menuText.value || preview.value);
const hasAudio = computed(() => !!nodeData.value.audio_asset_id);

// Visual strip: override avatar, default avatar, colored bg, or nothing
const hasVisual = computed(() => overrideAvatarUrl.value || defaultAvatarUrl.value || speaker.value);
const hasContent = computed(() => hasTextContent.value || hasVisual.value || responses.value.length > 0);

// Sockets
const inputs = computed(() => Object.entries(props.data?.inputs || {}));
const outputs = computed(() => Object.entries(props.data?.outputs || {}));
const responses = computed(() => nodeData.value.responses || []);

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
</script>

<template>
  <NodeShell
    :color="color"
    :selected="data.selected"
    :extra-class="hasContent ? 'dialogue min-w-[280px] max-w-[350px]' : 'dialogue'"
  >
    <!-- Header: icon + speaker name (no avatar in header) -->
    <NodeHeader :color="color" :icon="config.icon" :label="speakerName">
      <span v-if="hasAudio" class="ml-auto opacity-80 text-xs" title="Has audio">🔊</span>
    </NodeHeader>

    <!-- Visual strip: avatar -->
    <template v-if="hasVisual">
      <!-- Override avatar (specific avatar_id) — full width -->
      <img
        v-if="overrideAvatarUrl"
        :src="overrideAvatarUrl"
        alt=""
        class="block w-[calc(100%-24px)] max-h-[200px] object-contain rounded-lg mx-3 mt-3"
      />
      <!-- Default avatar — centered in colored bg -->
      <div
        v-else-if="defaultAvatarUrl"
        class="flex items-center justify-center px-3 pt-3"
        :style="{ backgroundColor: color + '20' }"
      >
        <img :src="defaultAvatarUrl" alt="" class="size-16 rounded-lg object-cover shadow-md" />
      </div>
      <!-- Speaker exists but no avatar — empty colored bg -->
      <div
        v-else-if="speaker"
        class="flex items-center justify-center px-3 pt-3"
        :style="{ backgroundColor: color + '20' }"
      />
    </template>

    <!-- Body: stage directions + menu text + preview -->
    <div v-if="hasTextContent" class="px-3.5 pt-2.5 pb-3">
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
