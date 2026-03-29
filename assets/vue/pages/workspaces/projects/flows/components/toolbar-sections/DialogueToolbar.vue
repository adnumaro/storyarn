<script setup>
import {
	MessageSquare,
	Play as PlayIcon,
	Settings,
	Volume2,
} from "lucide-vue-next";
import { computed } from "vue";
import { ToolbarSeparator } from "@/vue/components/shared/toolbar/index.js";
import { useLive } from "@/vue/composables/useLive.js";
import { ToolbarAvatarPicker } from "../../toolbar/index.js";

const props = defineProps({
	nodeData: { type: Object, required: true },
	nodeId: { type: [String, Number], required: true },
	allSheets: { type: Array, default: () => [] },
});

const live = useLive();

function updateField(field, value) {
	live.pushEvent("update_node_data", { node: { [field]: value } });
}

function updateNodeField(field, value) {
	live.pushEvent("update_node_field", { field, value });
}

function openScreenplay() {
	live.pushEvent("open_screenplay", { id: props.nodeId });
}

function startPreview() {
	live.pushEvent("start_preview", { id: props.nodeId });
}

function selectAvatar(avatarId) {
	updateNodeField("avatar_id", avatarId);
}

const speakerAvatars = computed(() => {
	const sheetId =
		props.nodeData.speaker_sheet_id || props.nodeData.location_sheet_id;
	if (!sheetId) return [];
	const sheet = props.allSheets.find((s) => String(s.id) === String(sheetId));
	if (!sheet?.avatars) return [];
	return sheet.avatars
		.filter((a) => a.asset?.url)
		.sort((a, b) => (a.position || 0) - (b.position || 0))
		.map((a) => ({ id: a.id, url: a.asset.url, name: a.name }));
});

const hasAvatarOverride = computed(() => {
	const aid = props.nodeData.avatar_id;
	return aid != null && aid !== "" && aid !== 0;
});
</script>

<template>
  <component :is="MessageSquare" class="size-4 opacity-60" />
  <ToolbarSeparator />
  <input
    type="text"
    class="v2-toolbar-input text-xs font-mono"
    placeholder="tech_id"
    :value="nodeData.technical_id || ''"
    @blur="(e) => updateField('technical_id', e.target.value)"
    @keydown.enter="(e) => e.target.blur()"
    @pointerdown.stop
    @keydown.stop
  />
  <Volume2 v-if="nodeData.audio_asset_id" class="size-3.5 text-blue-500" />
  <ToolbarAvatarPicker
    v-if="speakerAvatars.length > 0"
    :avatars="speakerAvatars"
    :has-override="hasAvatarOverride"
    @select="selectAvatar"
  />
  <ToolbarSeparator />
  <button type="button" class="v2-toolbar-btn" title="Screenplay editor" @click="openScreenplay">
    <Settings class="size-3.5" />
  </button>
  <button type="button" class="v2-toolbar-btn" title="Preview" @click="startPreview">
    <PlayIcon class="size-3" />
  </button>
</template>
