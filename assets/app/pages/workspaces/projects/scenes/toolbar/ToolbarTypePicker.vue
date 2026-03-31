<script setup>
import { MapPin, Star, User, Zap } from "lucide-vue-next";
import { ref } from "vue";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";

const TYPE_OPTIONS = [
  { value: "location", label: "Location", icon: MapPin },
  { value: "character", label: "Character", icon: User },
  { value: "event", label: "Event", icon: Zap },
  { value: "custom", label: "Custom", icon: Star },
];

const props = defineProps({
  type: { type: String, default: "location" },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(["update:type"]);
const open = ref(false);

function selectType(t) {
  emit("update:type", t);
  open.value = false;
}

const currentIcon = () => TYPE_OPTIONS.find((o) => o.value === props.type)?.icon || MapPin;
</script>

<template>
  <Popover v-model:open="open">
    <PopoverTrigger as-child>
      <button type="button" class="v2-toolbar-btn" :disabled="disabled" title="Pin type">
        <component :is="currentIcon()" class="size-3.5" />
      </button>
    </PopoverTrigger>
    <PopoverContent class="w-auto p-1" :side-offset="8" side="top">
      <div class="min-w-[120px]">
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
