<script setup lang="ts">
import { Clapperboard } from "lucide-vue-next";
import { computed } from "vue";
import { ToolbarSeparator } from "@components/toolbar/index.ts";
import { useLive } from "@composables/useLive";
import { ToolbarAvatarPicker, ToolbarSearchableSelect } from "../../toolbar";
import type { SheetAvatarEntry } from "../../types";
import type { NodeData } from "../../lib/node-configs";

defineOptions({ inheritAttrs: false });

interface SlugLineToolbarData extends NodeData {
  speaker_sheet_id?: number | string | null;
  location_sheet_id?: number | string | null;
  int_ext?: string;
  time_of_day?: string;
  avatar_id?: number | string | null;
}

interface AvatarOption {
  id: number;
  url: string;
  name: string;
}

const { nodeData, sheetAvatars = [] } = defineProps<{
  nodeData: SlugLineToolbarData;
  sheetAvatars?: SheetAvatarEntry[];
}>();

const live = useLive();

const intExtOptions: [string, string][] = [
  ["INT/EXT", "int_ext"],
  ["INT", "int"],
  ["EXT", "ext"],
];

const intExtLabel = computed(() => {
  const v = nodeData.int_ext;
  if (v === "int") return "INT";
  if (v === "ext") return "EXT";
  if (v === "int_ext") return "INT/EXT";
  return null;
});

const sheetOptions = computed<[string, number][]>(() => sheetAvatars.map((s) => [s.name, s.id]));

const selectedLocationName = computed(() => {
  const locId = nodeData.location_sheet_id;
  if (!locId) return null;
  const sheet = sheetAvatars.find((s) => String(s.id) === String(locId));
  return sheet?.name || null;
});

const timeOptions: [string, string][] = [
  ["Day", "day"],
  ["Night", "night"],
  ["Morning", "morning"],
  ["Evening", "evening"],
  ["Continuous", "continuous"],
];

const timeLabel = computed(() => {
  const v = nodeData.time_of_day;
  return v ? v.charAt(0).toUpperCase() + v.slice(1) : null;
});

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

function selectSlugSetting(value: string) {
  live.pushEvent("update_node_data", { node: { int_ext: value } });
}

function selectSlugLocation(sheetId: number | string) {
  live.pushEvent("update_node_data", { node: { location_sheet_id: sheetId } });
}

function selectSlugTime(value: string) {
  live.pushEvent("update_node_data", { node: { time_of_day: value } });
}

function selectAvatar(avatarId: number | null) {
  live.pushEvent("update_node_field", { field: "avatar_id", value: avatarId });
}
</script>

<template>
  <component :is="Clapperboard" class="size-4 opacity-60" />
  <ToolbarSeparator />
  <ToolbarSearchableSelect
    :options="intExtOptions"
    :selected-value="nodeData.int_ext"
    :selected-label="intExtLabel"
    :placeholder="$t('flows.slug_line_toolbar.setting_placeholder')"
    @select="(v: string | number) => selectSlugSetting(String(v))"
  />
  <ToolbarSearchableSelect
    :options="sheetOptions"
    :selected-value="nodeData.location_sheet_id"
    :selected-label="selectedLocationName"
    :placeholder="$t('flows.slug_line_toolbar.location_placeholder')"
    @select="(v: string | number) => selectSlugLocation(String(v))"
  />
  <ToolbarSearchableSelect
    :options="timeOptions"
    :selected-value="nodeData.time_of_day"
    :selected-label="timeLabel"
    :placeholder="$t('flows.slug_line_toolbar.time_placeholder')"
    @select="(v: string | number) => selectSlugTime(String(v))"
  />
  <ToolbarAvatarPicker
    v-if="speakerAvatars.length > 0"
    :avatars="speakerAvatars"
    :has-override="hasAvatarOverride"
    @select="selectAvatar"
  />
</template>
