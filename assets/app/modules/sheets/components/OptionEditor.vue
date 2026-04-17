<script setup lang="ts">
import { Plus, X } from "lucide-vue-next";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import { useLive } from "@composables/useLive";
import type { SelectOption } from "../types";

const {
  scope,
  id,
  options = [],
} = defineProps<{
  scope: "block" | "column";
  id: number | string;
  options?: SelectOption[];
}>();

const live = useLive();

function addOption(): void {
  live.pushEvent("add_option", { scope, id });
}

function removeOption(index: number): void {
  live.pushEvent("remove_option", { scope, id, index });
}

function updateOption(index: number, field: "key" | "value", value: string): void {
  live.pushEvent("update_option", { scope, id, index, field, value });
}
</script>

<template>
  <label class="text-xs font-medium mb-1 block">{{ $t("sheets.option_editor.title") }}</label>
  <div class="space-y-1.5 mb-2">
    <div v-for="(opt, idx) in options" :key="idx" class="flex items-center gap-1">
      <Input
        :model-value="opt.key"
        class="bg-background dark:bg-background"
        size="xs"
        :placeholder="$t('sheets.option_editor.key_placeholder')"
        @blur="(e: Event) => updateOption(idx, 'key', (e.target as HTMLInputElement).value)"
      />
      <Input
        :model-value="opt.value"
        size="xs"
        class="bg-background dark:bg-background"
        :placeholder="$t('sheets.option_editor.label_placeholder')"
        @blur="(e: Event) => updateOption(idx, 'value', (e.target as HTMLInputElement).value)"
      />
      <Button
        variant="ghost"
        size="icon-sm"
        class="size-6 text-destructive dark:text-destructive hover:bg-destructive/10 dark:hover:bg-destructive/10"
        @click="() => removeOption(idx)"
      >
        <X class="size-3" />
      </Button>
    </div>
  </div>
  <button
    type="button"
    class="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground mt-1 p-1"
    @click="addOption"
  >
    <Plus class="size-3" />
    {{ $t("sheets.option_editor.add") }}
  </button>
</template>
