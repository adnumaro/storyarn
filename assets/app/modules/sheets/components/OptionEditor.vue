<script setup lang="ts">
/**
 * Shared option editor for select/multi_select blocks.
 * Renders editable key+label rows with add/remove.
 */
import { Plus, X } from "lucide-vue-next";
import { useLive } from "@composables/useLive";
import type { SelectOption } from "../types";
import { Button } from '@components/ui/button'
import { Input } from '@components/ui/input'

const { blockId, options = [] } = defineProps<{
  blockId: number | string;
  options?: SelectOption[];
}>();

const live = useLive();

function addOption(): void {
  live.pushEvent("add_select_option", { "block-id": blockId });
}

function removeOption(index: number): void {
  live.pushEvent("remove_select_option", {
    "block-id": blockId,
    index,
  });
}

function updateOption(index: number, field: string, value: string): void {
  live.pushEvent("update_select_option", {
    "block-id": blockId,
    index,
    field,
    value,
  });
}
</script>

<template>
  <div>
    <label class="text-xs font-medium mb-1 block">Options</label>
    <div class="space-y-1">
      <div v-for="(opt, idx) in options" :key="opt.key" class="flex items-center gap-1">
        <Input
          :model-value="opt.key"
          class="bg-background dark:bg-background"
          size="xs"
          placeholder="key"
          @blur="(e: Event) => updateOption(idx, 'key', (e.target as HTMLInputElement).value)"
        />
        <Input
          :model-value="opt.value"
          size="xs"
          class="bg-background dark:bg-background"
          placeholder="Label"
          @blur="(e: Event) => updateOption(idx, 'value', (e.target as HTMLInputElement).value)"
        />
        <Button
          variant="ghost"
          size="icon-sm"
          class="size-6 text-destructive dark:text-destructive hover:bg-destructive/10 dark:hover:bg-destructive/10"
          @click="removeOption(idx)"
        >
          <X class="size-3" />
        </Button>
      </div>
    </div>
    <button
      type="button"
      class="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground mt-1 px-1 py-0.5"
      @click="addOption"
    >
      <Plus class="size-3" />
      Add option
    </button>
  </div>
</template>
