<script setup>
import {
	ArrowRightToLine,
	Box,
	Clapperboard,
	Crosshair,
	ExternalLink,
	GitBranch,
	LogIn,
	LogOut,
	MessageSquare,
	Play as PlayIcon,
	Settings,
	StickyNote,
	Trash2,
	Volume2,
	Zap,
} from "lucide-vue-next";
import { computed, nextTick, ref, watch } from "@/vue/index.js";
import { ToolbarColorPicker, ToolbarSeparator, ToolbarSizePicker } from "@/vue/components/shared/toolbar/index.js";
import { ToolbarAvatarPicker, ToolbarExitModePicker, ToolbarSearchableSelect } from "./toolbar/index.js";
import { Badge } from "@/vue/components/ui/badge/index.js";
import { useLive } from "@/vue/composables/useLive.js";

const props = defineProps({
	toolbarState: { type: Object, required: true },
	canEdit: { type: Boolean, default: false },
	// Server data for complex types
	flowHubs: { type: Array, default: () => [] },
	availableFlows: { type: Array, default: () => [] },
	allSheets: { type: Array, default: () => [] },
	availableScenes: { type: Array, default: () => [] },
	subflowExits: { type: Array, default: () => [] },
	referencingJumps: { type: Array, default: () => [] },
	referencingFlows: { type: Array, default: () => [] },
	nodeSelectLoading: { type: Boolean, default: false },
	flowSearchHasMore: { type: Boolean, default: false },
});

const live = useLive();
const toolbarRef = ref(null);

const visible = computed(() => props.toolbarState.visible && props.canEdit);
const nodeType = computed(() => props.toolbarState.nodeType);
const nodeData = computed(() => props.toolbarState.nodeData || {});
const nodeId = computed(() => props.toolbarState.nodeId);

// Toolbar position style
const toolbarStyle = computed(() => {
	if (!visible.value) return { display: "none" };
	const s = props.toolbarState;
	const el = toolbarRef.value;
	const toolbarW = el?.offsetWidth || 200;
	const left = s.x + s.width / 2 - toolbarW / 2;
	const top = s.y - 48;
	return {
		display: "flex",
		left: `${Math.round(left)}px`,
		top: `${Math.round(top)}px`,
	};
});

watch([nodeType, visible], () => nextTick(() => {}));

// ── Event helpers ──

function updateField(field, value) {
	live.pushEvent("update_node_data", { node: { [field]: value } });
}

function updateNodeField(field, value) {
	live.pushEvent("update_node_field", { field, value });
}

function openBuilder() {
	live.pushEvent("open_builder", {});
}

function openScreenplay() {
	live.pushEvent("open_screenplay", { id: nodeId.value });
}

function startPreview() {
	live.pushEvent("start_preview", { id: nodeId.value });
}

function deleteNode() {
	live.pushEvent("delete_node", { id: nodeId.value });
}

function navigateToJumps() {
	live.pushEvent("navigate_to_jumps", { id: nodeId.value });
}

function navigateToHub() {
	live.pushEvent("navigate_to_hub", { id: nodeId.value });
}

function navigateToSubflow(flowId) {
	live.pushEvent("navigate_to_subflow", { "flow-id": String(flowId) });
}

function navigateToExitFlow(flowId) {
	live.pushEvent("navigate_to_exit_flow", { "flow-id": String(flowId) });
}

function toggleSwitchMode() {
	live.pushEvent("toggle_switch_mode", {});
}

function updateAnnotationColor(color) {
	live.pushEvent("update_annotation_color", { value: color });
}

function updateAnnotationFontSize(size) {
	live.pushEvent("update_annotation_font_size", { value: size });
}

function updateExitMode(mode) {
	live.pushEvent("update_exit_mode", { mode });
}

function updateOutcomeColor(color) {
	live.pushEvent("update_outcome_color", { value: color });
}

function selectHub(hubId) {
	live.pushEvent("update_node_data", { node: { target_hub_id: hubId || "" } });
}

function selectSubflowRef(flowId) {
	live.pushEvent("update_subflow_reference", { referenced_flow_id: flowId });
}

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
	updateNodeField("avatar_id", avatarId);
}

// ── Computed data for complex types ──

const hubOptions = computed(() => props.flowHubs.map((h) => [h.hub_id, h.hub_id]));
const selectedHubLabel = computed(() => {
	const target = nodeData.value.target_hub_id;
	if (!target) return null;
	const hub = props.flowHubs.find((h) => h.hub_id === target);
	return hub?.hub_id || null;
});

const flowOptions = computed(() => props.availableFlows.map((f) => [f.name, f.id]));
const selectedFlowName = computed(() => {
	const refId = nodeData.value.referenced_flow_id;
	if (!refId) return null;
	const flow = props.availableFlows.find((f) => String(f.id) === String(refId));
	return flow?.name || null;
});

const sheetOptions = computed(() => props.allSheets.map((s) => [s.name, s.id]));
const selectedLocationName = computed(() => {
	const locId = nodeData.value.location_sheet_id;
	if (!locId) return null;
	const sheet = props.allSheets.find((s) => String(s.id) === String(locId));
	return sheet?.name || null;
});

const intExtOptions = [["INT/EXT", "int_ext"], ["INT", "int"], ["EXT", "ext"]];
const intExtLabel = computed(() => {
	const v = nodeData.value.int_ext;
	if (v === "int") return "INT";
	if (v === "ext") return "EXT";
	if (v === "int_ext") return "INT/EXT";
	return null;
});

const timeOptions = [["Day", "day"], ["Night", "night"], ["Morning", "morning"], ["Evening", "evening"], ["Continuous", "continuous"]];
const timeLabel = computed(() => {
	const v = nodeData.value.time_of_day;
	return v ? v.charAt(0).toUpperCase() + v.slice(1) : null;
});

const speakerAvatars = computed(() => {
	const sheetId = nodeData.value.speaker_sheet_id || nodeData.value.location_sheet_id;
	if (!sheetId) return [];
	const sheet = props.allSheets.find((s) => String(s.id) === String(sheetId));
	if (!sheet?.avatars) return [];
	return sheet.avatars
		.filter((a) => a.asset?.url)
		.sort((a, b) => (a.position || 0) - (b.position || 0))
		.map((a) => ({ id: a.id, url: a.asset.url, name: a.name }));
});

const hasAvatarOverride = computed(() => {
	const aid = nodeData.value.avatar_id;
	return aid != null && aid !== "" && aid !== 0;
});

// ── Node type icons ──
const TYPE_ICONS = {
	entry: PlayIcon,
	dialogue: MessageSquare,
	condition: GitBranch,
	instruction: Zap,
	hub: LogIn,
	jump: LogOut,
	exit: ArrowRightToLine,
	subflow: Box,
	slug_line: Clapperboard,
	annotation: StickyNote,
};
</script>

<template>
  <div
    ref="toolbarRef"
    :style="toolbarStyle"
    class="absolute z-30 items-center gap-1.5 v2-surface-panel px-2 py-1.5 text-sm pointer-events-auto"
  >
    <!-- Entry -->
    <template v-if="nodeType === 'entry'">
      <component :is="TYPE_ICONS.entry" class="size-4 opacity-60" />
      <ToolbarSeparator />
      <span class="text-xs font-medium opacity-70">Entry point</span>
      <Badge v-if="referencingFlows.length > 0" variant="secondary" class="text-[10px] px-1.5 py-0 rounded-full">
        {{ referencingFlows.length }} ref{{ referencingFlows.length === 1 ? '' : 's' }}
      </Badge>
    </template>

    <!-- Condition -->
    <template v-else-if="nodeType === 'condition'">
      <component :is="TYPE_ICONS.condition" class="size-4 opacity-60" />
      <ToolbarSeparator />
      <button type="button" class="v2-toolbar-btn text-xs" @click="toggleSwitchMode">
        {{ nodeData.switch_mode ? 'Routes' : 'Multi' }}
      </button>
      <Badge v-if="nodeData.condition?.rules?.length" variant="secondary" class="text-[10px] px-1.5 py-0 rounded-full">
        {{ nodeData.condition.rules.length }} rule{{ nodeData.condition.rules.length === 1 ? '' : 's' }}
      </Badge>
      <ToolbarSeparator />
      <button type="button" class="v2-toolbar-btn" title="Edit condition" @click="openBuilder">
        <Settings class="size-3.5" />
      </button>
    </template>

    <!-- Instruction -->
    <template v-else-if="nodeType === 'instruction'">
      <component :is="TYPE_ICONS.instruction" class="size-4 opacity-60" />
      <ToolbarSeparator />
      <Badge v-if="nodeData.assignments?.length" variant="secondary" class="text-[10px] px-1.5 py-0 rounded-full">
        {{ nodeData.assignments.length }} assignment{{ nodeData.assignments.length === 1 ? '' : 's' }}
      </Badge>
      <ToolbarSeparator />
      <button type="button" class="v2-toolbar-btn" title="Edit instructions" @click="openBuilder">
        <Settings class="size-3.5" />
      </button>
    </template>

    <!-- Hub -->
    <template v-else-if="nodeType === 'hub'">
      <component :is="TYPE_ICONS.hub" class="size-4 opacity-60" />
      <ToolbarSeparator />
      <input
        type="text"
        class="v2-toolbar-input text-xs"
        placeholder="Label"
        :value="nodeData.label || ''"
        @blur="(e) => updateField('label', e.target.value)"
        @keydown.enter="(e) => e.target.blur()"
        @pointerdown.stop
        @keydown.stop
      />
      <input
        type="text"
        class="v2-toolbar-input text-xs font-mono"
        placeholder="hub_id"
        :value="nodeData.hub_id || ''"
        @blur="(e) => updateField('hub_id', e.target.value)"
        @keydown.enter="(e) => e.target.blur()"
        @pointerdown.stop
        @keydown.stop
      />
      <button v-if="referencingJumps.length > 0" type="button" class="v2-toolbar-btn" title="Locate jumps" @click="navigateToJumps">
        <Crosshair class="size-3.5" />
      </button>
    </template>

    <!-- Annotation -->
    <template v-else-if="nodeType === 'annotation'">
      <ToolbarColorPicker :color="nodeData.color || '#fbbf24'" @update:color="updateAnnotationColor" />
      <ToolbarSizePicker :size="nodeData.font_size || 'md'" @update:size="updateAnnotationFontSize" />
      <ToolbarSeparator />
      <button type="button" class="v2-toolbar-btn text-destructive" title="Delete" @click="deleteNode">
        <Trash2 class="size-3.5" />
      </button>
    </template>

    <!-- Dialogue -->
    <template v-else-if="nodeType === 'dialogue'">
      <component :is="TYPE_ICONS.dialogue" class="size-4 opacity-60" />
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

    <!-- Jump -->
    <template v-else-if="nodeType === 'jump'">
      <component :is="TYPE_ICONS.jump" class="size-4 opacity-60" />
      <ToolbarSeparator />
      <ToolbarSearchableSelect
        :options="hubOptions"
        :selected-value="nodeData.target_hub_id"
        :selected-label="selectedHubLabel"
        placeholder="Target hub…"
        @select="selectHub"
      />
      <button
        v-if="nodeData.target_hub_id"
        type="button"
        class="v2-toolbar-btn"
        title="Locate target hub"
        @click="navigateToHub"
      >
        <Crosshair class="size-3.5" />
      </button>
    </template>

    <!-- Exit -->
    <template v-else-if="nodeType === 'exit'">
      <component :is="TYPE_ICONS.exit" class="size-4 opacity-60" />
      <ToolbarSeparator />
      <input
        type="text"
        class="v2-toolbar-input text-xs"
        placeholder="Label…"
        :value="nodeData.label || ''"
        @blur="(e) => updateField('label', e.target.value)"
        @keydown.enter="(e) => e.target.blur()"
        @pointerdown.stop
        @keydown.stop
      />
      <ToolbarExitModePicker :mode="nodeData.exit_mode || 'terminal'" @update:mode="updateExitMode" />
      <ToolbarColorPicker :color="nodeData.outcome_color || '#22c55e'" @update:color="updateOutcomeColor" />
      <button
        v-if="nodeData.referenced_flow_id"
        type="button"
        class="v2-toolbar-btn"
        title="Open referenced flow"
        @click="navigateToExitFlow(nodeData.referenced_flow_id)"
      >
        <ExternalLink class="size-3.5" />
      </button>
    </template>

    <!-- Subflow -->
    <template v-else-if="nodeType === 'subflow'">
      <component :is="TYPE_ICONS.subflow" class="size-4 opacity-60" />
      <ToolbarSeparator />
      <ToolbarSearchableSelect
        :options="flowOptions"
        :selected-value="nodeData.referenced_flow_id"
        :selected-label="selectedFlowName"
        placeholder="Select flow…"
        @select="selectSubflowRef"
      />
      <button
        v-if="nodeData.referenced_flow_id"
        type="button"
        class="v2-toolbar-btn"
        title="Open flow"
        @click="navigateToSubflow(nodeData.referenced_flow_id)"
      >
        <ExternalLink class="size-3.5" />
      </button>
      <Badge v-if="subflowExits.length > 0" variant="secondary" class="text-[10px] px-1.5 py-0 rounded-full">
        {{ subflowExits.length }} exit{{ subflowExits.length === 1 ? '' : 's' }}
      </Badge>
    </template>

    <!-- Slug Line -->
    <template v-else-if="nodeType === 'slug_line'">
      <component :is="TYPE_ICONS.slug_line" class="size-4 opacity-60" />
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

    <!-- Fallback -->
    <template v-else>
      <span class="text-xs opacity-50">{{ nodeType }}</span>
    </template>
  </div>
</template>
