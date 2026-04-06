<script setup>
import { ChevronDown } from "lucide-vue-next";
import { computed, ref } from "vue";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@components/ui/command/index.ts";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover/index.ts";

const { options, selectedValue, selectedLabel, placeholder, disabled } = defineProps({
  options: { type: Array, default: () => [] },
  selectedValue: { type: [String, Number, null], default: null },
  selectedLabel: { type: String, default: null },
  placeholder: { type: String, default: "Select..." },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(["select"]);
const open = ref(false);

const displayLabel = computed(() => selectedLabel || null);

function select(value) {
  emit("select", value);
  open.value = false;
}
</script>

<template>
  <Popover v-model:open="open">
    <PopoverTrigger as-child>
      <button type="button" class="v2-toolbar-btn gap-1 text-xs max-w-[140px]" :disabled="disabled">
        <span class="truncate" :class="displayLabel ? '' : 'opacity-50'">
          {{ displayLabel || placeholder }}
        </span>
        <ChevronDown class="size-3 opacity-50 shrink-0" />
      </button>
    </PopoverTrigger>
    <PopoverContent class="w-56 p-0" :side-offset="8" side="top">
      <Command>
        <CommandInput :placeholder="placeholder" />
        <CommandList>
          <CommandEmpty>No results</CommandEmpty>
          <CommandGroup>
            <CommandItem value="__clear__" @select="select('')">
              <span class="text-muted-foreground">None</span>
            </CommandItem>
            <CommandItem
              v-for="[label, value] in options"
              :key="value"
              :value="label"
              @select="select(value)"
            >
              <span class="truncate">{{ label }}</span>
            </CommandItem>
          </CommandGroup>
        </CommandList>
      </Command>
    </PopoverContent>
  </Popover>
</template>
