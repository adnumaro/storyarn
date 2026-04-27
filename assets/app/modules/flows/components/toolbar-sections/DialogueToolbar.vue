<script setup lang="ts">
import { MessageSquare, Play as PlayIcon, Settings, Volume2 } from "lucide-vue-next";
import { computed } from "vue";
import { ToolbarSeparator } from "@components/toolbar/index.ts";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { useLive } from "@composables/useLive";
import { ToolbarAvatarPicker } from "../../toolbar";
import type { SheetAvatarEntry } from "../../types";
import type { NodeData } from "../../lib/node-configs";

defineOptions({ inheritAttrs: false });

interface DialogueToolbarData extends NodeData {
  speaker_sheet_id?: number | string | null;
  location_sheet_id?: number | string | null;
  technical_id?: string;
  audio_asset_id?: number | string | null;
  avatar_id?: number | string | null;
}

interface AvatarOption {
  id: number;
  url: string;
  name: string;
}

const {
  nodeData,
  nodeId,
  sheetAvatars = [],
} = defineProps<{
  nodeData: DialogueToolbarData;
  nodeId: string | number;
  sheetAvatars?: SheetAvatarEntry[];
}>();

const live = useLive();

function updateField(field: string, value: unknown) {
  live.pushEvent("update_node_data", { node: { [field]: value } });
}

function updateNodeField(field: string, value: unknown) {
  live.pushEvent("update_node_field", { field, value });
}

function openDialoguePanel() {
  live.pushEvent("open_dialogue_panel", { id: nodeId });
}

function startPreview() {
  live.pushEvent("start_preview", { id: nodeId });
}

function selectAvatar(avatarId: number | null) {
  updateNodeField("avatar_id", avatarId);
}

const speakerAvatars = computed<AvatarOption[]>(() => {
  const sheetId = nodeData.speaker_sheet_id || nodeData.location_sheet_id;
  if (!sheetId) return [];
  const sheet = sheetAvatars.find((s) => String(s.id) === String(sheetId));
  if (!sheet?.avatars) return [];
  return sheet.avatars
    .filter((a) => a.asset?.url)
    .sort((a, b) => (a.position || 0) - (b.position || 0))
    .map((a) => ({ id: a.id, url: a.asset!.url, name: a.name }));
});

const hasAvatarOverride = computed(() => {
  const aid = nodeData.avatar_id;
  return aid != null && aid !== "" && aid !== 0;
});
</script>

<template>
  <component :is="MessageSquare" class="size-4 opacity-60" />
  <ToolbarSeparator />
  <input
    type="text"
    class="toolbar-input text-xs font-mono"
    :placeholder="$t('flows.dialogue_toolbar.tech_id_placeholder')"
    :value="nodeData.technical_id || ''"
    @blur="(e: FocusEvent) => updateField('technical_id', (e.target as HTMLInputElement).value)"
    @keydown.enter="(e: KeyboardEvent) => (e.target as HTMLInputElement).blur()"
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
  <ToolbarTooltip :label="$t('flows.node_types.dialogue_toolbar_screenplay')">
    <button type="button" class="toolbar-btn" @click="openDialoguePanel">
      <Settings class="size-3.5" />
    </button>
  </ToolbarTooltip>
  <ToolbarTooltip :label="$t('flows.node_types.dialogue_toolbar_preview')">
    <button type="button" class="toolbar-btn" @click="startPreview">
      <PlayIcon class="size-3" />
    </button>
  </ToolbarTooltip>
</template>
