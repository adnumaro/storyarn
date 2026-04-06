<script setup lang="ts">
import { Check, ChevronsUpDown } from "lucide-vue-next";
import { computed, ref } from "vue";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@components/ui/command";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";

interface EntityOption {
  id: number | string;
  name: string;
}

const {
  options = [],
  selectedId = null,
  label = "",
  placeholder = "Select...",
  disabled = false,
  variant = "default",
} = defineProps<{
  options?: EntityOption[];
  selectedId?: number | string | null;
  label?: string;
  placeholder?: string;
  disabled?: boolean;
  variant?: "default" | "ghost";
}>();

const triggerClass = computed(() => {
  if (variant === "ghost") {
    return "w-full flex items-center justify-between text-left text-[13px] font-medium bg-transparent border-none text-inherit cursor-pointer p-0 outline-none disabled:opacity-50 disabled:cursor-not-allowed";
  }
  return "w-full flex items-center justify-between text-left text-sm px-2 py-1.5 rounded-md border border-input bg-background dark:bg-card shadow-xs hover:dark:bg-card/80 transition-colors disabled:opacity-50 disabled:cursor-not-allowed";
});

const emit = defineEmits<{
  "update:selectedId": [id: number | string | null];
}>();
const open = ref(false);

const selectedName = computed(() => {
  if (!selectedId) return null;
  const id = String(selectedId);
  const opt = options.find((o) => String(o.id) === id);
  return opt?.name || null;
});

function select(id) {
  emit("update:selectedId", id);
  open.value = false;
}
</script>

<template>
  <div>
    <label v-if="label" class="block text-xs font-medium text-foreground/70 mb-1">
      {{ label }}
    </label>
    <Popover v-model:open="open">
      <PopoverTrigger as-child>
        <button type="button" :class="triggerClass" :disabled="disabled">
          <span
            class="overflow-hidden text-ellipsis whitespace-nowrap"
            :class="
              selectedName ? '' : variant === 'ghost' ? 'opacity-60' : 'text-muted-foreground'
            "
          >
            {{ selectedName || placeholder }}
          </span>
          <ChevronsUpDown
            class="size-3 shrink-0 ml-1"
            :class="variant === 'ghost' ? 'opacity-60' : 'text-muted-foreground'"
          />
        </button>
      </PopoverTrigger>
      <PopoverContent class="p-0" :side-offset="4" align="start">
        <Command>
          <CommandInput placeholder="Search..." />
          <CommandList>
            <CommandEmpty>No results</CommandEmpty>
            <CommandGroup>
              <CommandItem value="__none__" @select="select(null)">
                <span class="text-muted-foreground">None</span>
                <Check v-if="!selectedId" class="size-3 ml-auto" />
              </CommandItem>
              <CommandItem
                v-for="opt in options"
                :key="opt.id"
                :value="opt.name"
                @select="select(opt.id)"
              >
                {{ opt.name }}
                <Check v-if="String(opt.id) === String(selectedId)" class="size-3 ml-auto" />
              </CommandItem>
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  </div>
</template>
