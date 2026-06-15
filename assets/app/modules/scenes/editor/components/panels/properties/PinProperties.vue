<script setup lang="ts">
import { EyeOff, Image } from "lucide-vue-next";
import { ref } from "vue";
import ConditionBuilder from "@components/builders/ConditionBuilder.vue";
import type { ConditionData } from "@components/builders/types";
import { EntityCombobox, TextField, ToggleField } from "@components/forms/fields";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@components/ui/tabs";
import type { Variable } from "@shared/domain/variables.ts";
import { useLive } from "@shared/composables/useLive.ts";
import PinPatrolSection from "./pin/PinPatrolSection.vue";
import PinPlayableSection from "./pin/PinPlayableSection.vue";

const CONDITION_EFFECTS = [
  { id: "hide", name: "scenes.pin_properties.effect_hide" },
  { id: "disable", name: "scenes.pin_properties.effect_disable" },
];

const MAX_PIN_ICON_SIZE = 256 * 1024;
const PIN_ICON_TYPES = new Set(["image/svg+xml", "image/png", "image/gif"]);

interface PinElement {
  id: number | string;
  shortcut?: string;
  tooltip?: string;
  sheetId?: number | string | null;
  flowId?: number | string | null;
  isPlayable?: boolean;
  isLeader?: boolean;
  patrolMode?: string;
  patrolSpeed?: number;
  patrolPauseMs?: number;
  hidden?: boolean;
  conditionEffect?: string;
  condition?: ConditionData | null;
  iconAssetUrl?: string | null;
}

interface EntityOption {
  id: number | string;
  name: string;
  shortcut?: string;
}

const {
  element,
  canEdit = false,
  projectSheets = [],
  projectFlows = [],
  projectVariables = [],
} = defineProps<{
  element: PinElement;
  canEdit?: boolean;
  projectSheets?: EntityOption[];
  projectFlows?: EntityOption[];
  projectVariables?: Variable[];
}>();

const live = useLive();
const activeTab = ref("visual");

function update(field: string, value: string | number | null | undefined) {
  live.pushEvent("update_pin", {
    id: String(element.id),
    field,
    value: value === null || value === undefined ? "" : String(value),
  });
}

function uploadIcon() {
  const input = document.createElement("input");
  input.type = "file";
  input.accept = ".svg,.png,.gif,image/svg+xml,image/png,image/gif";
  input.onchange = (e: Event) => {
    const file = (e.target as HTMLInputElement).files?.[0];
    if (!file) return;

    if (!PIN_ICON_TYPES.has(file.type)) {
      live.pushEvent("pin_icon_upload_validation_error", {
        reason: "invalid_type",
      });
      return;
    }

    if (file.size > MAX_PIN_ICON_SIZE) {
      live.pushEvent("pin_icon_upload_validation_error", {
        reason: "too_large",
      });
      return;
    }

    const reader = new FileReader();
    reader.onload = () => {
      live.pushEvent("upload_pin_icon", {
        id: String(element.id),
        filename: file.name,
        content_type: file.type,
        data: reader.result,
      });
    };
    reader.readAsDataURL(file);
  };
  input.click();
}

function toggle(field: string, currentValue: boolean | undefined) {
  live.pushEvent("update_pin", {
    id: String(element.id),
    field,
    toggle: String(!currentValue),
  });
}
</script>

<template>
  <Tabs v-model="activeTab" class="space-y-3">
    <TabsList class="flex h-auto w-full gap-1 overflow-x-auto bg-background p-1">
      <TabsTrigger value="visual" class="shrink-0 text-xs">{{
        $t("scenes.pin_properties.tab_visual")
      }}</TabsTrigger>
      <TabsTrigger value="behavior" class="shrink-0 text-xs">{{
        $t("scenes.pin_properties.tab_behavior")
      }}</TabsTrigger>
      <TabsTrigger value="rules" class="shrink-0 text-xs">{{
        $t("scenes.pin_properties.tab_rules")
      }}</TabsTrigger>
      <TabsTrigger value="settings" class="shrink-0 text-xs">{{
        $t("scenes.pin_properties.tab_settings")
      }}</TabsTrigger>
    </TabsList>

    <TabsContent value="visual" class="space-y-3">
      <EntityCombobox
        :label="$t('scenes.pin_properties.sheet')"
        :placeholder="$t('scenes.pin_properties.sheet_placeholder')"
        :options="projectSheets"
        :selected-id="element.sheetId"
        :disabled="!canEdit"
        @update:selected-id="(id) => update('sheet_id', id)"
      />

      <button
        v-if="canEdit"
        type="button"
        class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-sm transition-colors hover:bg-accent"
        @click="uploadIcon"
      >
        <Image class="size-3.5" />
        {{
          element.iconAssetUrl
            ? $t("scenes.pin_properties.change_icon")
            : $t("scenes.pin_properties.upload_icon")
        }}
      </button>
    </TabsContent>

    <TabsContent value="behavior" class="space-y-3">
      <PinPlayableSection
        :is-playable="!!element.isPlayable"
        :is-leader="!!element.isLeader"
        :disabled="!canEdit"
        @toggle-playable="toggle('is_playable', element.isPlayable)"
        @toggle-leader="toggle('is_leader', element.isLeader)"
      />

      <EntityCombobox
        :label="$t('scenes.pin_properties.flow')"
        :placeholder="$t('scenes.pin_properties.flow_placeholder')"
        :options="projectFlows"
        :selected-id="element.flowId"
        :disabled="!canEdit"
        @update:selected-id="(id) => update('flow_id', id)"
      />

      <p
        v-if="!element.flowId"
        class="rounded-md border border-border bg-muted/30 px-2 py-1.5 text-xs leading-relaxed text-muted-foreground"
      >
        {{ $t("scenes.pin_properties.no_flow_hint") }}
      </p>

      <PinPatrolSection
        v-if="!element.isPlayable"
        :patrol-mode="element.patrolMode"
        :patrol-speed="element.patrolSpeed"
        :patrol-pause-ms="element.patrolPauseMs"
        :disabled="!canEdit"
        @update-mode="(v) => update('patrol_mode', v)"
        @update-speed="(v) => update('patrol_speed', v)"
        @update-pause="(v) => update('patrol_pause_ms', v)"
      />
    </TabsContent>

    <TabsContent value="rules" class="space-y-3">
      <ToggleField
        :label="$t('scenes.pin_properties.hidden_exploration')"
        :icon="EyeOff"
        :checked="!!element.hidden"
        :disabled="!canEdit"
        @toggle="toggle('hidden', element.hidden)"
      />

      <div class="flex items-center justify-between">
        <label class="text-xs font-medium text-foreground/70">{{
          $t("scenes.pin_properties.condition")
        }}</label>
        <div class="flex gap-0.5">
          <button
            v-for="opt in CONDITION_EFFECTS"
            :key="opt.id"
            type="button"
            class="px-1.5 py-0.5 text-[10px] rounded transition-colors"
            :class="
              (element.conditionEffect || 'hide') === opt.id
                ? 'bg-muted text-foreground font-medium'
                : 'text-muted-foreground hover:text-foreground'
            "
            :disabled="!canEdit"
            @click="
              live.pushEvent('update_pin_condition_effect', {
                id: String(element.id),
                effect: opt.id,
              })
            "
          >
            {{ $t(opt.name) }}
          </button>
        </div>
      </div>
      <ConditionBuilder
        :condition="element.condition"
        :variables="projectVariables"
        :disabled="!canEdit"
        @update:condition="
          (c) =>
            live.pushEvent('update_pin_condition', { 'pin-id': String(element.id), condition: c })
        "
      />
    </TabsContent>

    <TabsContent value="settings" class="space-y-3">
      <div v-if="element.shortcut" class="space-y-1">
        <label class="block text-xs font-medium text-foreground/70">{{
          $t("scenes.pin_properties.shortcut")
        }}</label>
        <div class="text-xs font-mono text-muted-foreground bg-accent/50 rounded px-2 py-1">
          {{ element.shortcut }}
        </div>
      </div>

      <TextField
        :label="$t('scenes.pin_properties.tooltip')"
        :value="element.tooltip || ''"
        :placeholder="$t('scenes.pin_properties.tooltip_placeholder')"
        :disabled="!canEdit"
        @update="(v) => update('tooltip', v)"
      />
    </TabsContent>
  </Tabs>
</template>
