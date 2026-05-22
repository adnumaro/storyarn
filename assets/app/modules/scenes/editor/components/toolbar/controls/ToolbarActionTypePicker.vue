<script setup lang="ts">
import { BarChart3, Footprints, PackageOpen, Zap } from "lucide-vue-next";
import type { Component } from "vue";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { Popover, PopoverAnchor, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";

const { t } = useI18n();

interface ActionTypeOption {
  value: string;
  label: string;
  icon: Component;
  desc: string;
}

const ACTION_TYPES = computed<ActionTypeOption[]>(() => [
  {
    value: "walkable",
    label: t("scenes.action_type_picker.walkable"),
    icon: Footprints,
    desc: t("scenes.action_type_picker.walkable_desc"),
  },
  {
    value: "action",
    label: t("scenes.action_type_picker.action"),
    icon: Zap,
    desc: t("scenes.action_type_picker.action_desc"),
  },
  {
    value: "display",
    label: t("scenes.action_type_picker.display"),
    icon: BarChart3,
    desc: t("scenes.action_type_picker.display_desc"),
  },
  {
    value: "collection",
    label: t("scenes.action_type_picker.collection"),
    icon: PackageOpen,
    desc: t("scenes.action_type_picker.collection_desc"),
  },
]);

const { actionType = "action", disabled = false } = defineProps<{
  actionType?: string;
  disabled?: boolean;
}>();

const emit = defineEmits<{
  "update:actionType": [value: string];
}>();
const open = ref(false);

function select(value: string) {
  emit("update:actionType", value);
  open.value = false;
}

const current = (): ActionTypeOption =>
  ACTION_TYPES.value.find((o) => o.value === actionType) || ACTION_TYPES.value[0];
</script>

<template>
  <Popover v-model:open="open">
    <PopoverAnchor as-child>
      <ToolbarTooltip :label="$t('scenes.action_type_picker.tooltip')">
        <PopoverTrigger
          class="toolbar-btn gap-1"
          :disabled="disabled"
          :aria-label="$t('scenes.action_type_picker.tooltip')"
          :title="$t('scenes.action_type_picker.tooltip')"
        >
          <component :is="current().icon" class="size-3.5" />
        </PopoverTrigger>
      </ToolbarTooltip>
    </PopoverAnchor>
    <PopoverContent class="w-56 p-1" :side-offset="8" side="top">
      <button
        v-for="opt in ACTION_TYPES"
        :key="opt.value"
        type="button"
        class="flex items-start gap-2 w-full px-2 py-1.5 rounded text-left cursor-pointer transition-colors"
        :class="opt.value === actionType ? 'bg-accent' : 'hover:bg-accent/50'"
        @click="select(opt.value)"
      >
        <component :is="opt.icon" class="size-3.5 mt-0.5 shrink-0" />
        <div>
          <div class="text-xs font-medium">{{ opt.label }}</div>
          <div class="text-[10px] text-muted-foreground">{{ opt.desc }}</div>
        </div>
      </button>
    </PopoverContent>
  </Popover>
</template>
