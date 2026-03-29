<script setup>
import { Clapperboard } from "lucide-vue-next";
import { computed } from "vue";
import { ToolbarSeparator } from "@/vue/components/shared/toolbar/index.js";
import { useLive } from "@/vue/composables/useLive.js";
import {
	ToolbarAvatarPicker,
	ToolbarSearchableSelect,
} from "../../toolbar/index.js";

const props = defineProps({
	nodeData: { type: Object, required: true },
	allSheets: { type: Array, default: () => [] },
});

const live = useLive();

const intExtOptions = [
	["INT/EXT", "int_ext"],
	["INT", "int"],
	["EXT", "ext"],
];

const intExtLabel = computed(() => {
	const v = props.nodeData.int_ext;
	if (v === "int") return "INT";
	if (v === "ext") return "EXT";
	if (v === "int_ext") return "INT/EXT";
	return null;
});

const sheetOptions = computed(() => props.allSheets.map((s) => [s.name, s.id]));

const selectedLocationName = computed(() => {
	const locId = props.nodeData.location_sheet_id;
	if (!locId) return null;
	const sheet = props.allSheets.find((s) => String(s.id) === String(locId));
	return sheet?.name || null;
});

const timeOptions = [
	["Day", "day"],
	["Night", "night"],
	["Morning", "morning"],
	["Evening", "evening"],
	["Continuous", "continuous"],
];

const timeLabel = computed(() => {
	const v = props.nodeData.time_of_day;
	return v ? v.charAt(0).toUpperCase() + v.slice(1) : null;
});

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

function selectSlugSetting(value) {
	live.pushEvent("update_node_data", { node: { int_ext: value } });
}

function selectSlugLocation(sheetId) {
	live.pushEvent("update_node_data", { node: { location_sheet_id: sheetId } });
}

function selectSlugTime(value) {
	live.pushEvent("update_node_data", { node: { time_of_day: value } });
}

function selectAvatar(avatarId) {
	live.pushEvent("update_node_field", { field: "avatar_id", value: avatarId });
}
</script>

<template>
  <component :is="Clapperboard" class="size-4 opacity-60" />
  <ToolbarSeparator />
  <ToolbarSearchableSelect :options="intExtOptions" :selected-value="nodeData.int_ext" :selected-label="intExtLabel" placeholder="Setting…" @select="selectSlugSetting" />
  <ToolbarSearchableSelect :options="sheetOptions" :selected-value="nodeData.location_sheet_id" :selected-label="selectedLocationName" placeholder="Location…" @select="selectSlugLocation" />
  <ToolbarSearchableSelect :options="timeOptions" :selected-value="nodeData.time_of_day" :selected-label="timeLabel" placeholder="Time…" @select="selectSlugTime" />
  <ToolbarAvatarPicker
    v-if="speakerAvatars.length > 0"
    :avatars="speakerAvatars"
    :has-override="hasAvatarOverride"
    @select="selectAvatar"
  />
</template>
