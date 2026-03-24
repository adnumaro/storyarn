<script setup>
import { Switch } from "@/vue/components/ui/switch";

defineProps({
	label: { type: String, default: "" },
	icon: { type: [Object, Function, null], default: null },
	checked: { type: Boolean, default: false },
	disabled: { type: Boolean, default: false },
});

const emit = defineEmits(["toggle"]);
</script>

<template>
  <div class="flex items-center justify-between">
    <label class="text-xs font-medium text-muted-foreground flex items-center gap-1">
      <component :is="icon" v-if="icon" class="size-3" />
      {{ label }}
    </label>
    <Switch
      :model-value="checked"
      :disabled="disabled"
      @update:model-value="emit('toggle')"
    />
  </div>
</template>
