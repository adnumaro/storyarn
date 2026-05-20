<script setup lang="ts">
import { MapPin, Star, User, Zap } from "lucide-vue-next";
import type { Component } from "vue";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { Popover, PopoverAnchor, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";

const { t } = useI18n();

interface TypeOption {
  value: string;
  label: string;
  icon: Component;
}

const TYPE_OPTIONS = computed<TypeOption[]>(() => [
  { value: "location", label: t("scenes.type_picker.location"), icon: MapPin },
  { value: "character", label: t("scenes.type_picker.character"), icon: User },
  { value: "event", label: t("scenes.type_picker.event"), icon: Zap },
  { value: "custom", label: t("scenes.type_picker.custom"), icon: Star },
]);

const { type = "location", disabled = false } = defineProps<{
  type?: string;
  disabled?: boolean;
}>();

const emit = defineEmits<{
  "update:type": [value: string];
}>();
const open = ref(false);

function selectType(value: string) {
  emit("update:type", value);
  open.value = false;
}

const currentIcon = (): Component =>
  TYPE_OPTIONS.value.find((o) => o.value === type)?.icon || MapPin;
</script>

<template>
  <Popover v-model:open="open">
    <PopoverAnchor as-child>
      <ToolbarTooltip :label="$t('scenes.type_picker.pin_type')">
        <PopoverTrigger
          class="toolbar-btn"
          :disabled="disabled"
          :aria-label="$t('scenes.type_picker.pin_type')"
          :title="$t('scenes.type_picker.pin_type')"
        >
          <component :is="currentIcon()" class="size-3.5" />
        </PopoverTrigger>
      </ToolbarTooltip>
    </PopoverAnchor>
    <PopoverContent class="w-auto p-1" :side-offset="8" side="top">
      <div class="min-w-30">
        <button
          v-for="opt in TYPE_OPTIONS"
          :key="opt.value"
          type="button"
          class="flex items-center gap-2 w-full px-2 py-1 rounded text-sm cursor-pointer transition-colors"
          :class="opt.value === type ? 'font-semibold text-primary' : 'hover:bg-accent'"
          @click="selectType(opt.value)"
        >
          <component :is="opt.icon" class="size-3.5" />
          {{ opt.label }}
        </button>
      </div>
    </PopoverContent>
  </Popover>
</template>
