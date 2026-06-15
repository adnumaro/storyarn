<script setup lang="ts">
import { EyeOff, Image } from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import ConditionBuilder from "@components/builders/ConditionBuilder.vue";
import type { Assignment, ConditionData } from "@components/builders/types";
import ExpressionEditor from "@components/forms/ExpressionEditor.vue";
import {
  EntityCombobox,
  NumberField,
  SelectField,
  TextField,
  ToggleField,
} from "@components/forms/fields";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@components/ui/tabs";
import type { Variable } from "@shared/domain/variables.ts";
import { useLive } from "@shared/composables/useLive.ts";
import CollectionItemsEditor from "./zone/CollectionItemsEditor.vue";
import TargetPicker from "./zone/TargetPicker.vue";

const CONDITION_EFFECTS = [
  { id: "hide", name: "scenes.pin_properties.effect_hide" },
  { id: "disable", name: "scenes.pin_properties.effect_disable" },
];

interface ZoneActionData {
  assignments?: Assignment[];
  variable_ref?: string;
  display_mode?: string;
  items?: {
    id: string;
    sheet_id?: number | string | null;
    label?: string;
    condition?: ConditionData | null;
  }[];
  collect_all_enabled?: boolean;
  empty_message?: string;
}

interface ZoneElement {
  id: number | string;
  shortcut?: string;
  actionType?: string;
  isWalkable?: boolean;
  hidden?: boolean;
  tooltip?: string;
  targetType?: string;
  targetId?: number | string | null;
  actionData?: ZoneActionData;
  labelMode?: string;
  labelFontSize?: number | string;
  labelFontFamily?: string;
  labelFontWeight?: string;
  labelFontStyle?: string;
  labelIconAssetId?: number | string | null;
  labelIconAssetUrl?: string | null;
  conditionEffect?: string;
  condition?: ConditionData | null;
}

interface EntityOption {
  id: number | string;
  name: string;
  shortcut?: string;
}

const {
  element,
  canEdit = false,
  projectScenes = [],
  projectSheets = [],
  projectFlows = [],
  projectVariables = [],
} = defineProps<{
  element: ZoneElement;
  canEdit?: boolean;
  projectScenes?: EntityOption[];
  projectSheets?: EntityOption[];
  projectFlows?: EntityOption[];
  projectVariables?: Variable[];
}>();

const live = useLive();
const activeTab = ref("visual");
const MAX_ZONE_ICON_SIZE = 256 * 1024;
const ZONE_ICON_TYPES = new Set(["image/svg+xml", "image/png", "image/gif"]);

const LABEL_MODES = computed(() => [
  { id: "text", name: "scenes.zone_properties.label_mode_text" },
  { id: "icon", name: "scenes.zone_properties.label_mode_icon" },
  { id: "both", name: "scenes.zone_properties.label_mode_both" },
  { id: "none", name: "scenes.zone_properties.label_mode_none" },
]);

const DISPLAY_CONTENT_MODES = computed(() => [
  { id: "value", name: "scenes.zone_properties.display_content_value" },
  { id: "label_value", name: "scenes.zone_properties.display_content_label_value" },
]);

const FONT_FAMILIES = computed(() => [
  { id: "system", name: "scenes.zone_properties.font_family_system" },
  { id: "serif", name: "scenes.zone_properties.font_family_serif" },
  { id: "mono", name: "scenes.zone_properties.font_family_mono" },
  { id: "display", name: "scenes.zone_properties.font_family_display" },
]);

const FONT_WEIGHTS = computed(() => [
  { id: "400", name: "400" },
  { id: "500", name: "500" },
  { id: "600", name: "600" },
  { id: "700", name: "700" },
]);

const FONT_STYLES = computed(() => [
  { id: "normal", name: "scenes.zone_properties.font_style_normal" },
  { id: "italic", name: "scenes.zone_properties.font_style_italic" },
]);

const typeTab = computed(() => {
  switch (element.actionType) {
    case "collection":
      return "collection";
    case "walkable":
      return "pathing";
    default:
      return "action";
  }
});

const showTypeTab = computed(() => element.actionType !== "display");
const hasInstructions = computed(() => (element.actionData?.assignments || []).length > 0);
const hasTarget = computed(() => !!element.targetType && !!element.targetId);
const actionIsEmpty = computed(
  () => (element.actionType || "action") === "action" && !hasInstructions.value && !hasTarget.value,
);

watch(
  () => element.actionType,
  () => {
    const validTabs = ["visual", "availability", "settings"];
    if (showTypeTab.value) validTabs.push(typeTab.value);

    if (!validTabs.includes(activeTab.value)) {
      activeTab.value = element.actionType === "display" ? "visual" : typeTab.value;
    }
  },
);

function update(field: string, value: string | number | null | undefined) {
  live.pushEvent("update_zone", {
    id: String(element.id),
    field,
    value: value === null || value === undefined ? "" : String(value),
  });
}

function updateLabelMode(mode: string) {
  update("label_mode", mode);
}

function updateActionDataField(field: string, value: string | number | null | undefined) {
  live.pushEvent("update_zone_action_data", {
    "zone-id": String(element.id),
    field,
    value: value === null || value === undefined ? "" : String(value),
  });
}

function uploadZoneIcon() {
  const input = document.createElement("input");
  input.type = "file";
  input.accept = ".svg,.png,.gif,image/svg+xml,image/png,image/gif";
  input.onchange = (e: Event) => {
    const file = (e.target as HTMLInputElement).files?.[0];
    if (!file) return;

    if (!ZONE_ICON_TYPES.has(file.type)) {
      live.pushEvent("zone_icon_upload_validation_error", {
        reason: "invalid_type",
      });
      return;
    }

    if (file.size > MAX_ZONE_ICON_SIZE) {
      live.pushEvent("zone_icon_upload_validation_error", {
        reason: "too_large",
      });
      return;
    }

    const reader = new FileReader();
    reader.onload = () => {
      live.pushEvent("upload_zone_label_icon", {
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
  live.pushEvent("update_zone", {
    id: String(element.id),
    field,
    toggle: String(!currentValue),
  });
}

function updateTarget({
  targetType,
  targetId,
}: {
  targetType: string | null;
  targetId: string | number | null;
}) {
  live.pushEvent("update_zone", {
    id: String(element.id),
    field: "target",
    value: targetType || "",
    target_type: targetType || null,
    target_id: targetId ? String(targetId) : null,
  });
}

function updateAssignments(assignments: unknown[]) {
  live.pushEvent("update_zone_assignments", {
    "zone-id": String(element.id),
    assignments,
  });
}

function selectDisplayVar(varRef: string | number | null) {
  if (varRef == null) return;
  live.pushEvent(`select_zone_display_var:${element.id}`, {
    id: varRef,
  });
}
</script>

<template>
  <Tabs v-model="activeTab" class="space-y-3">
    <TabsList class="flex h-auto w-full gap-1 overflow-x-auto bg-background p-1">
      <TabsTrigger value="visual" class="shrink-0 text-xs">{{
        $t("scenes.zone_properties.tab_visual")
      }}</TabsTrigger>
      <TabsTrigger value="availability" class="shrink-0 text-xs">
        {{ $t("scenes.zone_properties.tab_availability") }}
      </TabsTrigger>
      <TabsTrigger v-if="showTypeTab" :value="typeTab" class="shrink-0 text-xs">
        {{ $t(`scenes.zone_properties.tab_${typeTab}`) }}
      </TabsTrigger>
      <TabsTrigger value="settings" class="shrink-0 text-xs">{{
        $t("scenes.zone_properties.tab_settings")
      }}</TabsTrigger>
    </TabsList>

    <TabsContent value="settings" class="space-y-3">
      <div v-if="element.shortcut" class="space-y-1">
        <label class="block text-xs font-medium text-foreground/70">{{
          $t("scenes.zone_properties.shortcut")
        }}</label>
        <div class="text-xs font-mono text-muted-foreground bg-accent/50 rounded px-2 py-1">
          {{ element.shortcut }}
        </div>
      </div>

      <ToggleField
        :label="$t('scenes.zone_properties.hidden_exploration')"
        :icon="EyeOff"
        :checked="!!element.hidden"
        :disabled="!canEdit"
        @toggle="toggle('hidden', element.hidden)"
      />

      <TextField
        :label="$t('scenes.zone_properties.tooltip')"
        :value="element.tooltip || ''"
        :placeholder="$t('scenes.zone_properties.tooltip_placeholder')"
        :disabled="!canEdit"
        @update="(v) => update('tooltip', v)"
      />
    </TabsContent>

    <TabsContent value="visual" class="space-y-3">
      <EntityCombobox
        v-if="element.actionType === 'display'"
        :label="$t('scenes.zone_properties.display_variable')"
        :placeholder="$t('scenes.zone_properties.display_variable_placeholder')"
        :options="
          projectVariables.map((v) => ({
            id: v.ref || `${v.sheet_shortcut}.${v.variable_name}`,
            name: v.label || `${v.sheet_shortcut}.${v.variable_name}`,
          }))
        "
        :selected-id="element.actionData?.variable_ref"
        :disabled="!canEdit"
        @update:selected-id="selectDisplayVar"
      />

      <SelectField
        v-if="element.actionType === 'display'"
        :label="$t('scenes.zone_properties.display_content')"
        :options="DISPLAY_CONTENT_MODES.map((opt) => ({ id: opt.id, name: $t(opt.name) }))"
        :value="element.actionData?.display_mode || 'value'"
        :disabled="!canEdit"
        @update="(v) => updateActionDataField('display_mode', v)"
      />

      <SelectField
        v-else
        :label="$t('scenes.zone_properties.label_mode')"
        :options="LABEL_MODES.map((opt) => ({ id: opt.id, name: $t(opt.name) }))"
        :value="element.labelMode || 'text'"
        :disabled="!canEdit"
        @update="updateLabelMode"
      />

      <p
        v-if="element.labelMode === 'none'"
        class="rounded-md border border-border bg-muted/30 px-2 py-1.5 text-xs leading-relaxed text-muted-foreground"
      >
        {{ $t("scenes.zone_properties.label_none_hint") }}
      </p>

      <div
        v-if="
          element.actionType !== 'display' &&
          (element.labelMode === 'icon' || element.labelMode === 'both')
        "
        class="space-y-2"
      >
        <button
          type="button"
          class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-sm transition-colors hover:bg-accent disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="!canEdit"
          @click="uploadZoneIcon"
        >
          <Image class="size-3.5" />
          {{
            element.labelIconAssetUrl
              ? $t("scenes.zone_properties.change_icon")
              : $t("scenes.zone_properties.upload_icon")
          }}
        </button>
        <p v-if="!element.labelIconAssetUrl" class="text-xs text-muted-foreground">
          {{ $t("scenes.zone_properties.upload_icon_hint") }}
        </p>
      </div>

      <div class="grid grid-cols-2 gap-2">
        <NumberField
          :label="$t('scenes.zone_properties.font_size')"
          :value="element.labelFontSize || 12"
          :min="8"
          :max="64"
          :disabled="!canEdit"
          @update="(v) => update('label_font_size', v)"
        />
        <SelectField
          :label="$t('scenes.zone_properties.font_family')"
          :options="FONT_FAMILIES.map((opt) => ({ id: opt.id, name: $t(opt.name) }))"
          :value="element.labelFontFamily || 'system'"
          :disabled="!canEdit"
          @update="(v) => update('label_font_family', v)"
        />
      </div>

      <div class="grid grid-cols-2 gap-2">
        <SelectField
          :label="$t('scenes.zone_properties.font_weight')"
          :options="FONT_WEIGHTS"
          :value="element.labelFontWeight || '600'"
          :disabled="!canEdit"
          @update="(v) => update('label_font_weight', v)"
        />
        <SelectField
          :label="$t('scenes.zone_properties.font_style')"
          :options="FONT_STYLES.map((opt) => ({ id: opt.id, name: $t(opt.name) }))"
          :value="element.labelFontStyle || 'normal'"
          :disabled="!canEdit"
          @update="(v) => update('label_font_style', v)"
        />
      </div>
    </TabsContent>

    <TabsContent v-if="showTypeTab" :value="typeTab" class="space-y-3">
      <template v-if="typeTab === 'action'">
        <div
          v-if="actionIsEmpty"
          class="rounded-md border border-warning/40 bg-warning/10 px-2 py-1.5 text-xs text-warning-content"
        >
          {{ $t("scenes.zone_properties.empty_action") }}
        </div>

        <TargetPicker
          :target-type="element.targetType"
          :target-id="element.targetId"
          :scenes="projectScenes"
          :flows="projectFlows"
          :disabled="!canEdit"
          @update:target="updateTarget"
        />

        <div class="space-y-1">
          <label class="block text-xs font-medium text-foreground/70">{{
            $t("scenes.zone_properties.instruction")
          }}</label>
          <ExpressionEditor
            :assignments="element.actionData?.assignments || []"
            :variables="projectVariables"
            :disabled="!canEdit"
            mode="instruction"
            @update:assignments="updateAssignments"
          />
        </div>
      </template>

      <CollectionItemsEditor
        v-else-if="typeTab === 'collection'"
        :zone-id="element.id"
        :action-data="element.actionData || {}"
        :can-edit="canEdit"
        :project-sheets="projectSheets"
        :project-variables="projectVariables"
      />

      <p v-else class="text-xs text-muted-foreground leading-relaxed">
        {{ $t("scenes.zone_properties.pathing_description") }}
      </p>
    </TabsContent>

    <TabsContent value="availability" class="space-y-2">
      <div class="flex items-center justify-between">
        <label class="text-xs font-medium text-foreground/70">{{
          $t("scenes.zone_properties.condition")
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
              live.pushEvent('update_zone_condition_effect', {
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
            live.pushEvent('update_zone_condition', { 'zone-id': String(element.id), condition: c })
        "
      />
    </TabsContent>
  </Tabs>
</template>
