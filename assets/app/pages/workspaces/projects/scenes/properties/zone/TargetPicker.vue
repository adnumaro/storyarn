<script setup>
import { ArrowLeft, Link, Map as MapIcon, Workflow, X } from "lucide-vue-next";
import { computed, ref } from "vue";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";

const TARGET_TYPES = [
  { value: "flow", label: "Flow", icon: Workflow },
  { value: "scene", label: "Scene", icon: MapIcon },
];

const props = defineProps({
  targetType: { type: String, default: null },
  targetId: { type: [Number, null], default: null },
  scenes: { type: Array, default: () => [] },
  flows: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(["update:target"]);
const open = ref(false);
const step = ref("type"); // "type" | "entity"
const selectedType = ref(null);

const currentTargetName = computed(() => {
  if (!props.targetType || !props.targetId) return null;
  const list = props.targetType === "flow" ? props.flows : props.scenes;
  return list.find((e) => e.id === props.targetId)?.name || "Unknown";
});

const entityList = computed(() => {
  if (selectedType.value === "flow") return props.flows;
  if (selectedType.value === "scene") return props.scenes;
  return [];
});

function openTypeStep() {
  step.value = "type";
  selectedType.value = null;
}

function chooseType(type) {
  selectedType.value = type;
  step.value = "entity";
}

function chooseEntity(id) {
  emit("update:target", { targetType: selectedType.value, targetId: id });
  open.value = false;
  openTypeStep();
}

function removeLink() {
  emit("update:target", { targetType: null, targetId: null });
  open.value = false;
  openTypeStep();
}
</script>

<template>
  <div class="space-y-1">
    <label class="block text-xs font-medium text-foreground/70">Link to</label>
    <Popover
      v-model:open="open"
      @update:open="
        (v) => {
          if (v) openTypeStep();
        }
      "
    >
      <PopoverTrigger as-child>
        <button
          type="button"
          class="w-full flex items-center gap-2 text-left text-sm px-2 py-1.5 rounded-md border border-input bg-background dark:bg-card shadow-xs hover:dark:bg-card/80 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          :disabled="disabled"
        >
          <Link class="size-3 text-muted-foreground shrink-0" />
          <span :class="currentTargetName ? '' : 'text-muted-foreground'">
            {{ currentTargetName || "No link" }}
          </span>
        </button>
      </PopoverTrigger>
      <PopoverContent class="w-56 p-1" :side-offset="4" align="start">
        <!-- Step 1: Choose type -->
        <template v-if="step === 'type'">
          <button
            v-for="tt in TARGET_TYPES"
            :key="tt.value"
            type="button"
            class="flex items-center gap-2 w-full px-2 py-1.5 rounded text-sm cursor-pointer hover:bg-accent transition-colors"
            @click="chooseType(tt.value)"
          >
            <component :is="tt.icon" class="size-3.5" />
            {{ tt.label }}
          </button>
          <button
            v-if="targetType && targetId"
            type="button"
            class="flex items-center gap-2 w-full px-2 py-1.5 rounded text-sm cursor-pointer text-destructive hover:bg-destructive/10 transition-colors mt-1 border-t border-border pt-1.5"
            @click="removeLink"
          >
            <X class="size-3.5" />
            Remove link
          </button>
        </template>

        <!-- Step 2: Choose entity -->
        <template v-if="step === 'entity'">
          <button
            type="button"
            class="flex items-center gap-1 w-full px-2 py-1 rounded text-xs text-muted-foreground hover:text-foreground cursor-pointer mb-1"
            @click="openTypeStep"
          >
            <ArrowLeft class="size-3" />
            Back
          </button>
          <div class="max-h-48 overflow-y-auto">
            <button
              v-for="entity in entityList"
              :key="entity.id"
              type="button"
              class="flex items-center gap-2 w-full px-2 py-1.5 rounded text-sm cursor-pointer transition-colors"
              :class="entity.id === targetId ? 'bg-accent font-medium' : 'hover:bg-accent/50'"
              @click="chooseEntity(entity.id)"
            >
              {{ entity.name }}
            </button>
            <p
              v-if="entityList.length === 0"
              class="text-xs text-muted-foreground italic px-2 py-2"
            >
              No items
            </p>
          </div>
        </template>
      </PopoverContent>
    </Popover>
  </div>
</template>
