<script setup>
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import { useLive } from "@composables/useLive";

const { label, icon, options, value, placeholder, disabled, event, paramKey } = defineProps({
  label: { type: String, default: "" },
  icon: { type: [Object, Function, null], default: null },
  options: { type: Array, required: true },
  value: { type: [String, Number], default: "" },
  placeholder: { type: String, default: "Select..." },
  disabled: { type: Boolean, default: false },
  event: { type: String, default: null },
  paramKey: { type: String, default: "value" },
});

const emit = defineEmits(["update"]);
const live = useLive();

function onChange(v) {
  emit("update", v);
  if (event) {
    live.pushEvent(event, { [paramKey]: v });
  }
}
</script>

<template>
  <div class="space-y-1.5">
    <label
      v-if="label"
      class="block text-xs font-medium text-foreground/70 flex items-center gap-1"
    >
      <component :is="icon" v-if="icon" class="size-3" />
      {{ label }}
    </label>
    <Select :model-value="String(value)" :disabled="disabled" @update:model-value="onChange">
      <SelectTrigger class="w-full h-8 text-xs">
        <SelectValue :placeholder="placeholder" />
      </SelectTrigger>
      <SelectContent>
        <SelectItem
          v-for="opt in options"
          :key="opt.id ?? opt.value"
          :value="String(opt.id ?? opt.value)"
        >
          {{ opt.name ?? opt.label }}
        </SelectItem>
      </SelectContent>
    </Select>
  </div>
</template>
