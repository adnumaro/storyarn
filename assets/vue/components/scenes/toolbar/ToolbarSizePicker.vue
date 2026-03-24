<script setup>
import { ref } from "vue";
import {
	Popover,
	PopoverContent,
	PopoverTrigger,
} from "@/vue/components/ui/popover";

const SIZE_OPTIONS = [
	{ value: "sm", label: "S" },
	{ value: "md", label: "M" },
	{ value: "lg", label: "L" },
];

const props = defineProps({
	size: { type: String, default: "md" },
	disabled: { type: Boolean, default: false },
});

const emit = defineEmits(["update:size"]);
const open = ref(false);

function selectSize(s) {
	emit("update:size", s);
	open.value = false;
}

const currentLabel = () =>
	SIZE_OPTIONS.find((o) => o.value === props.size)?.label || "M";
</script>

<template>
  <Popover v-model:open="open">
    <PopoverTrigger as-child>
      <button
        type="button"
        class="v2-toolbar-btn text-xs font-semibold min-w-7"
        :disabled="disabled"
        title="Size"
      >
        {{ currentLabel() }}
      </button>
    </PopoverTrigger>
    <PopoverContent class="w-auto p-1" :side-offset="8" side="top">
      <div class="flex gap-0.5">
        <button
          v-for="opt in SIZE_OPTIONS"
          :key="opt.value"
          type="button"
          class="px-3 py-1 text-xs font-medium rounded cursor-pointer transition-colors"
          :class="opt.value === size ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'"
          @click="selectSize(opt.value)"
        >
          {{ opt.label }}
        </button>
      </div>
    </PopoverContent>
  </Popover>
</template>
