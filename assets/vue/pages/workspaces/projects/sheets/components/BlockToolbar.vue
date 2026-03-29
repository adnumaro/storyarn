<script setup>
/**
 * Generic floating block toolbar — pure UI, no business logic.
 * Each block type composes this and passes its own config slot content.
 */
import { ref } from "@/vue/index.js";
import { Lock, Unlock, Hash, Settings } from "lucide-vue-next";
import {
	Popover,
	PopoverContent,
	PopoverTrigger,
} from "@/vue/components/ui/popover/index.js";
import { Tabs, TabsList, TabsTrigger } from "@/vue/components/ui/tabs/index.js";

const configOpen = ref(false);

defineProps({
	isConstant: { type: Boolean, default: false },
	isVariable: { type: Boolean, default: false },
	variableName: { type: String, default: "" },
	scope: { type: String, default: "self" },
	required: { type: Boolean, default: false },
	showConstant: { type: Boolean, default: true },
	showScope: { type: Boolean, default: true },
	showConfig: { type: Boolean, default: true },
});

const emit = defineEmits([
	"toggleConstant",
	"updateVariableName",
	"changeScope",
	"toggleRequired",
]);
</script>

<template>
  <div :class="[
    'absolute -top-3.5 left-1/2 -translate-x-1/2 transition-opacity z-10',
    configOpen ? 'opacity-100 pointer-events-auto' : 'opacity-0 group-hover:opacity-100 pointer-events-none group-hover:pointer-events-auto',
  ]">
    <div class="flex items-center gap-1 rounded-lg v2-surface-panel px-1.5 py-1">
      <!-- Constant toggle -->
      <button
        v-if="showConstant"
        type="button"
        :class="['size-7 rounded flex items-center justify-center text-muted-foreground transition-colors hover:bg-accent hover:text-foreground', isConstant && 'text-primary']"
        :title="isConstant ? 'Make variable' : 'Make constant'"
        @click="emit('toggleConstant')"
      >
        <Lock v-if="isConstant" class="size-4" />
        <Unlock v-else class="size-4" />
      </button>

      <!-- Variable name -->
      <div v-if="isVariable" class="flex items-center gap-1 pl-1 border-l border-border ml-0.5">
        <Hash class="size-3 text-muted-foreground/50" />
        <input
          :value="variableName"
          class="font-mono text-[11px] bg-transparent outline-none border-none px-0 pr-1 text-muted-foreground min-w-[4ch] max-w-[16ch]"
          style="field-sizing: content"
          @blur="(e) => emit('updateVariableName', e.target.value)"
          @keydown.enter.prevent="(e) => { e.target.blur() }"
        />
      </div>

      <!-- Scope tabs -->
      <div v-if="showScope" class="flex items-center gap-1 pl-1 border-l border-border ml-0.5">
        <Tabs :model-value="scope" @update:model-value="(v) => emit('changeScope', v)">
          <TabsList class="h-6 p-0.5">
            <TabsTrigger value="self" class="text-[10px] px-1.5 py-0 h-5">Self</TabsTrigger>
            <TabsTrigger value="children" class="text-[10px] px-1.5 py-0 h-5">Children</TabsTrigger>
          </TabsList>
        </Tabs>

      </div>

      <!-- Config gear + slot for type-specific popover -->
      <Popover v-if="showConfig" @update:open="(v) => configOpen = v">
        <PopoverTrigger as-child>
          <button
            type="button"
            class="size-6 rounded flex items-center justify-center text-muted-foreground hover:bg-accent transition-colors ml-0.5 border-l border-border pl-1"
            title="Configure"
          >
            <Settings class="size-4" />
          </button>
        </PopoverTrigger>
        <PopoverContent align="center" :side-offset="8" class="w-64 p-3 space-y-3">
          <slot name="config" />
        </PopoverContent>
      </Popover>
    </div>
  </div>
</template>
