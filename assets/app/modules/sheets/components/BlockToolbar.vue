<script setup lang="ts">
/**
 * Generic floating block toolbar — pure UI, no business logic.
 * Each block type composes this and passes its own config slot content.
 */

import { Hash, Lock, Settings, Unlock } from "lucide-vue-next";
import { ref } from "vue";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover/index.ts";
import { Tabs, TabsList, TabsTrigger } from "@components/ui/tabs/index.ts";
import ToolbarBase from "@components/toolbar/ToolbarBase.vue";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { Button } from "@components/ui/button";
import { generateId } from "@modules/shared/variables.ts";

const configOpen = ref(false);

const {
  blockId,
  isConstant = false,
  isVariable = false,
  variableName = "",
  scope = "self",
  showConstant = true,
  showScope = true,
  showConfig = true,
} = defineProps<{
  blockId: string | number;
  isConstant?: boolean;
  isVariable?: boolean;
  variableName?: string;
  scope?: string;
  required?: boolean;
  showConstant?: boolean;
  showScope?: boolean;
  showConfig?: boolean;
}>();

const emit = defineEmits<{
  toggleConstant: [];
  updateVariableName: [value: string];
  changeScope: [value: string];
  toggleRequired: [];
}>();
</script>

<template>
  <div
    :class="[
      'absolute -top-10 left-1/2 -translate-x-1/2 transition-opacity z-10',
      configOpen
        ? 'opacity-100 pointer-events-auto'
        : 'opacity-0 group-hover:opacity-100 pointer-events-none group-hover:pointer-events-auto',
    ]"
  >
    <ToolbarBase>
      <!-- Constant toggle -->
      <ToolbarTooltip
        v-if="showConstant"
        :label="
          isConstant
            ? $t('sheets.block_toolbar.make_variable')
            : $t('sheets.block_toolbar.make_constant')
        "
      >
        <Button
          size="icon-sm"
          variant="ghost"
          :class="[isConstant && 'text-primary']"
          @click="emit('toggleConstant')"
        >
          <Lock v-if="isConstant" class="size-4" />
          <Unlock v-else class="size-4" />
        </Button>
      </ToolbarTooltip>

      <!-- Variable name -->
      <div v-if="isVariable" class="flex items-center gap-1 pl-1 border-l border-border ml-0.5">
        <Hash class="size-3 text-muted-foreground/50" />
        <input
          :value="variableName"
          class="font-mono text-[11px] bg-transparent outline-none border-none px-0 pr-1 text-muted-foreground min-w-[4ch] max-w-[16ch]"
          style="field-sizing: content"
          @blur="(e) => emit('updateVariableName', (e.target as HTMLInputElement).value)"
          @keydown.enter.prevent="
            (e) => {
              (e.target as HTMLInputElement).blur();
            }
          "
        />
      </div>

      <!-- Scope tabs -->
      <div v-if="showScope" class="flex items-center gap-1 pl-1 border-l border-border ml-0.5">
        <Tabs :model-value="scope" @update:model-value="(v) => emit('changeScope', v as string)">
          <TabsList class="h-7 p-0.5 bg-background">
            <TabsTrigger value="self" class="text-[10px] px-1.5 py-0 h-6">
              {{ $t("sheets.block_toolbar.self") }}
            </TabsTrigger>
            <TabsTrigger value="children" class="text-[10px] px-1.5 py-0 h-6">
              {{ $t("sheets.block_toolbar.children") }}
            </TabsTrigger>
          </TabsList>
        </Tabs>
      </div>

      <!-- Config gear + slot for type-specific popover -->
      <Popover v-if="showConfig" @update:open="(v) => (configOpen = v)">
        <ToolbarTooltip :label="$t('sheets.block_toolbar.configure')">
          <PopoverTrigger as-child>
            <Button :id="`block-toolbar-${blockId}-${generateId()}`" size="icon-sm" variant="ghost">
              <Settings class="size-4" />
            </Button>
          </PopoverTrigger>
        </ToolbarTooltip>
        <PopoverContent align="center" :side-offset="8" class="w-64 p-3 space-y-3">
          <slot name="config" />
        </PopoverContent>
      </Popover>
    </ToolbarBase>
  </div>
</template>
