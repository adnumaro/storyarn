<script setup>
import {
  ArrowLeft,
  ArrowLeftRight,
  Asterisk,
  Check,
  ChevronDown,
  ChevronRight,
  Layers,
  Lock,
  Settings,
  SlidersHorizontal,
  Trash2,
  X,
} from "lucide-vue-next";
import { ref } from "vue";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover/index.js";
import { Separator } from "@components/ui/separator/index.js";
import { useLive } from "@composables/useLive.js";
import { allTypes, typeIcon, typeLabels } from "./table-config.js";

const { column, columns, canManage } = defineProps({
  column: { type: Object, required: true },
  columns: { type: Array, required: true },
  canManage: { type: Boolean, default: false },
});

const live = useLive();

// ── Dropdown state ──
const isOpen = ref(false);
const panel = ref("main");
const renameValue = ref("");
const newOptionValue = ref("");
const optionEdits = ref({});

function open() {
  isOpen.value = true;
  panel.value = "main";
  renameValue.value = column.name;
  newOptionValue.value = "";
  optionEdits.value = {};
}

function close() {
  if (renameValue.value.trim() && renameValue.value.trim() !== column.name) {
    live.pushEvent("rename_table_column", {
      "column-id": column.id,
      value: renameValue.value.trim(),
    });
  }
  isOpen.value = false;
}

function saveRename() {
  const name = renameValue.value.trim();
  if (name && name !== column.name) {
    live.pushEvent("rename_table_column", {
      "column-id": column.id,
      value: name,
    });
  }
}

function toggleConstant() {
  live.pushEvent("toggle_table_column_constant", {
    "column-id": column.id,
  });
}

function toggleRequired() {
  live.pushEvent("toggle_table_column_required", {
    "column-id": column.id,
  });
}

function changeType(newType) {
  if (column.type !== newType) {
    live.pushEvent("change_table_column_type", {
      "column-id": column.id,
      "new-type": newType,
    });
  }
}

function deleteColumn() {
  live.pushEvent("delete_table_column", { "column-id": column.id });
  isOpen.value = false;
}

function addOption() {
  const label = newOptionValue.value.trim();
  if (!label) return;
  live.pushEvent("add_table_column_option", {
    "column-id": column.id,
    value: label,
  });
  newOptionValue.value = "";
}

function updateOption(index) {
  const val = optionEdits.value[index];
  if (val != null && val.trim()) {
    live.pushEvent("update_table_column_option", {
      "column-id": column.id,
      index,
      value: val.trim(),
    });
  }
}

function removeOption(key) {
  live.pushEvent("remove_table_column_option", {
    "column-id": column.id,
    key,
  });
}

function updateNumberConstraint(field, event) {
  live.pushEvent("update_number_constraint", {
    "column-id": column.id,
    field,
    value: event.target.value,
  });
}

function toggleReferenceMultiple() {
  live.pushEvent("toggle_reference_multiple", {
    "column-id": column.id,
  });
}
</script>

<template>
  <!-- ══ Editable: dropdown with management options (canManage) ══ -->
  <Popover v-if="canManage" :open="isOpen" @update:open="(v) => (v ? open() : close())">
    <PopoverTrigger as-child>
      <button
        type="button"
        class="flex flex-col items-start cursor-pointer hover:text-foreground w-full min-w-0 px-3 py-2"
      >
        <span class="flex items-center gap-1.5 max-w-full">
          <component :is="typeIcon(column.type)" class="size-3.5 opacity-50 shrink-0" />
          <span class="truncate">{{ column.name }}</span>
          <span v-if="column.required" class="text-destructive text-xs shrink-0">*</span>
          <ChevronDown class="size-3 opacity-40 shrink-0" />
        </span>
        <span class="text-[10px] font-normal text-muted-foreground/30 truncate max-w-full">{{
          column.slug
        }}</span>
      </button>
    </PopoverTrigger>
    <PopoverContent align="start" :side-offset="4" class="w-56 p-0">
      <!-- Main panel -->
      <div v-if="panel === 'main'" class="p-1">
        <div class="flex items-center gap-1.5 px-2 py-1.5 mb-1">
          <component :is="typeIcon(column.type)" class="size-3.5 opacity-50 shrink-0" />
          <input
            v-model="renameValue"
            class="bg-transparent outline-none border-none text-sm font-medium w-full px-0"
            @blur="saveRename()"
            @keydown.enter.prevent="saveRename()"
          />
        </div>
        <button
          class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-sm hover:bg-accent"
          @click="toggleConstant()"
        >
          <Lock class="size-3.5 opacity-60" /><span class="flex-1 text-left">Constant</span
          ><Check v-if="column.is_constant" class="size-3.5 opacity-60" />
        </button>
        <button
          class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-sm hover:bg-accent"
          @click="toggleRequired()"
        >
          <Asterisk class="size-3.5 opacity-60" /><span class="flex-1 text-left">Required</span
          ><Check v-if="column.required" class="size-3.5 opacity-60" />
        </button>
        <Separator class="my-1" />
        <button
          class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-sm hover:bg-accent"
          @click="panel = 'type'"
        >
          <ArrowLeftRight class="size-3.5 opacity-60" /><span class="flex-1 text-left"
            >Change type</span
          ><ChevronRight class="size-3.5 opacity-40" />
        </button>
        <button
          v-if="column.type === 'select' || column.type === 'multi_select'"
          class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-sm hover:bg-accent"
          @click="panel = 'options'"
        >
          <Settings class="size-3.5 opacity-60" /><span class="flex-1 text-left">Options</span
          ><ChevronRight class="size-3.5 opacity-40" />
        </button>
        <button
          v-if="column.type === 'number'"
          class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-sm hover:bg-accent"
          @click="panel = 'number'"
        >
          <SlidersHorizontal class="size-3.5 opacity-60" /><span class="flex-1 text-left"
            >Constraints</span
          ><ChevronRight class="size-3.5 opacity-40" />
        </button>
        <button
          v-if="column.type === 'reference'"
          class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-sm hover:bg-accent"
          @click="panel = 'reference'"
        >
          <Settings class="size-3.5 opacity-60" /><span class="flex-1 text-left">Settings</span
          ><ChevronRight class="size-3.5 opacity-40" />
        </button>
        <Separator class="my-1" />
        <button
          :disabled="columns.length <= 1"
          class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-sm hover:bg-accent text-destructive disabled:opacity-30 disabled:pointer-events-none"
          @click="deleteColumn()"
        >
          <Trash2 class="size-3.5" /><span>Delete column</span>
        </button>
      </div>
      <!-- Type panel -->
      <div v-else-if="panel === 'type'" class="p-1">
        <button
          class="flex items-center gap-2 w-full px-2 py-1.5 text-xs font-medium opacity-70 rounded-sm hover:bg-accent mb-1"
          @click="panel = 'main'"
        >
          <ArrowLeft class="size-3.5" /><span>Change type</span>
        </button>
        <Separator class="mb-1" />
        <button
          v-for="t in allTypes"
          :key="t"
          class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-sm hover:bg-accent"
          :class="column.type === t && 'bg-accent'"
          @click="changeType(t)"
        >
          <component :is="typeIcon(t)" class="size-3.5 opacity-60" /><span
            class="flex-1 text-left"
            >{{ typeLabels[t] }}</span
          ><Check v-if="column.type === t" class="size-3.5 opacity-60" />
        </button>
      </div>
      <!-- Options panel -->
      <div v-else-if="panel === 'options'" class="p-1">
        <button
          class="flex items-center gap-2 w-full px-2 py-1.5 text-xs font-medium opacity-70 rounded-sm hover:bg-accent mb-1"
          @click="panel = 'main'"
        >
          <ArrowLeft class="size-3.5" /><span>Options</span>
        </button>
        <Separator class="mb-1" />
        <div
          v-for="(opt, idx) in column.config?.options || []"
          :key="opt.key"
          class="flex items-center gap-1 mb-1 px-1"
        >
          <input
            :value="optionEdits[idx] ?? opt.value"
            class="bg-transparent border border-border rounded px-2 py-1 text-xs flex-1 outline-none focus:border-ring"
            @input="optionEdits[idx] = $event.target.value"
            @blur="updateOption(idx)"
          />
          <button
            class="size-5 rounded flex items-center justify-center hover:bg-accent shrink-0"
            @click="removeOption(opt.key)"
          >
            <X class="size-3 text-muted-foreground" />
          </button>
        </div>
        <div class="px-1">
          <input
            v-model="newOptionValue"
            placeholder="+ Add option"
            class="bg-transparent border border-border rounded px-2 py-1 text-xs w-full outline-none focus:border-ring"
            @keydown.enter.prevent="addOption()"
          />
        </div>
      </div>
      <!-- Number constraints panel -->
      <div v-else-if="panel === 'number'" class="p-1">
        <button
          class="flex items-center gap-2 w-full px-2 py-1.5 text-xs font-medium opacity-70 rounded-sm hover:bg-accent mb-1"
          @click="panel = 'main'"
        >
          <ArrowLeft class="size-3.5" /><span>Constraints</span>
        </button>
        <Separator class="mb-2" />
        <div class="space-y-2 px-2 pb-2">
          <div>
            <label class="text-xs font-medium opacity-70">Min value</label
            ><input
              type="number"
              :value="column.config?.min"
              placeholder="No limit"
              class="bg-transparent border border-border rounded px-2 py-1 text-xs w-full mt-0.5 outline-none focus:border-ring"
              @blur="updateNumberConstraint('min', $event)"
            />
          </div>
          <div>
            <label class="text-xs font-medium opacity-70">Max value</label
            ><input
              type="number"
              :value="column.config?.max"
              placeholder="No limit"
              class="bg-transparent border border-border rounded px-2 py-1 text-xs w-full mt-0.5 outline-none focus:border-ring"
              @blur="updateNumberConstraint('max', $event)"
            />
          </div>
          <div>
            <label class="text-xs font-medium opacity-70">Step</label
            ><input
              type="number"
              :value="column.config?.step"
              placeholder="1"
              min="0.001"
              class="bg-transparent border border-border rounded px-2 py-1 text-xs w-full mt-0.5 outline-none focus:border-ring"
              @blur="updateNumberConstraint('step', $event)"
            />
          </div>
        </div>
      </div>
      <!-- Reference settings panel -->
      <div v-else-if="panel === 'reference'" class="p-1">
        <button
          class="flex items-center gap-2 w-full px-2 py-1.5 text-xs font-medium opacity-70 rounded-sm hover:bg-accent mb-1"
          @click="panel = 'main'"
        >
          <ArrowLeft class="size-3.5" /><span>Settings</span>
        </button>
        <Separator class="mb-1" />
        <button
          class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-sm hover:bg-accent"
          @click="toggleReferenceMultiple()"
        >
          <Layers class="size-3.5 opacity-60" /><span class="flex-1 text-left">Allow multiple</span
          ><Check v-if="column.config?.multiple" class="size-3.5 opacity-60" />
        </button>
      </div>
    </PopoverContent>
  </Popover>

  <!-- Read-only header (inherited or viewer) -->
  <div v-else class="px-3 py-2 min-w-0">
    <span class="flex items-center gap-1.5 max-w-full">
      <component :is="typeIcon(column.type)" class="size-3.5 opacity-50 shrink-0" />
      <span class="truncate">{{ column.name }}</span>
      <span v-if="column.required" class="text-destructive text-xs shrink-0">*</span>
    </span>
    <span class="text-[10px] font-normal text-muted-foreground/30 truncate block max-w-full">{{
      column.slug
    }}</span>
  </div>
</template>
