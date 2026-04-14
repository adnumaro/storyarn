<script setup lang="ts">
import { ArrowLeft, Check, ChevronDown, Layers, X } from "lucide-vue-next";
import { ref } from "vue";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover/index.ts";
import { Separator } from "@components/ui/separator/index.ts";
import { useLive } from "@composables/useLive";
import type { TableColumn, THeadMenuType } from "../../../types";
import { typeIcon } from "./table-config";
import THeadMainMenu from "@modules/sheets/components/blocks/table/theadMenus/THeadMainMenu.vue";
import THeadCellTypeMenu from "@modules/sheets/components/blocks/table/theadMenus/THeadCellTypeMenu.vue";
import THeadSelectOptionsMenu from "@modules/sheets/components/blocks/table/theadMenus/THeadSelectOptionsMenu.vue";

const {
  column,
  canManage = false,
  isLastColumn = false,
} = defineProps<{
  column: TableColumn;
  isLastColumn: boolean;
  canManage?: boolean;
}>();

const live = useLive();

// ── Dropdown state ──
const isOpen = ref(false);
const menuType = ref<THeadMenuType>("main");
const renameValue = ref("");
const newOptionValue = ref("");
const optionEdits = ref<Record<number, string>>({});
const menuTypesComponent = {
  main: "Dropdown",
  type: "Dropdown",
  options: "Dropdown",
  number: "Dropdown",
  reference: "Dropdown",
};

function open(): void {
  isOpen.value = true;
  menuType.value = "main";
  renameValue.value = column.name;
  newOptionValue.value = "";
  optionEdits.value = {};
}

function close(): void {
  if (renameValue.value.trim() && renameValue.value.trim() !== column.name) {
    live.pushEvent("rename_table_column", {
      "column-id": column.id,
      value: renameValue.value.trim(),
    });
  }
  isOpen.value = false;
}

function saveRename(): void {
  const name = renameValue.value.trim();
  if (name && name !== column.name) {
    live.pushEvent("rename_table_column", {
      "column-id": column.id,
      value: name,
    });
  }
}

function toggleConstant(): void {
  live.pushEvent("toggle_table_column_constant", {
    "column-id": column.id,
  });
}

function toggleRequired(): void {
  live.pushEvent("toggle_table_column_required", {
    "column-id": column.id,
  });
}

function changeMenuType(newMenuType: THeadMenuType): void {
  console.log("changeMenuType", newMenuType);
  menuType.value = newMenuType;
}

function changeType(newType: string): void {
  if (column.type !== newType) {
    live.pushEvent("change_table_column_type", {
      "column-id": column.id,
      "new-type": newType,
    });
  }
}

function deleteColumn(): void {
  live.pushEvent("delete_table_column", { "column-id": column.id });
  isOpen.value = false;
}

function updateNumberConstraint(field: string, event: Event): void {
  live.pushEvent("update_number_constraint", {
    "column-id": column.id,
    field,
    value: (event.target as HTMLInputElement).value,
  });
}

function toggleReferenceMultiple(): void {
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
          <ChevronDown class="size-3 shrink-0" />
        </span>
        <span class="text-xs font-normal text-foreground/70 truncate max-w-full">
          {{ column.slug }}
        </span>
      </button>
    </PopoverTrigger>
    <PopoverContent align="start" :side-offset="4" class="w-56 p-0">
      <!-- Main panel -->
      <THeadMainMenu
        v-if="menuType === 'main'"
        v-model="renameValue"
        :column="column"
        :is-last-column="isLastColumn"
        @column-name-changed="saveRename"
        @menu-type-changed="(type: THeadMenuType) => changeMenuType(type)"
        @toggle-constant="toggleConstant"
        @toggleRequired="toggleRequired"
        @column-deleted="deleteColumn"
      />

      <THeadCellTypeMenu
        v-else-if="menuType === 'type'"
        :column="column"
        @back-to-main="() => changeMenuType('main')"
        @column-type-changed="(type: string) => changeType(type)"
      />

      <THeadSelectOptionsMenu
        v-else-if="menuType === 'options'"
        :column="column"
        @back-to-main="() => changeMenuType('main')"
      />

      <!-- Number constraints panel -->
      <div v-else-if="menuType === 'number'" class="p-1">
        <button
          class="flex items-center gap-2 w-full px-2 py-1.5 text-xs font-medium opacity-70 rounded-sm hover:bg-accent mb-1"
          @click="menuType = 'main'"
        >
          <ArrowLeft class="size-3.5" />
          <span>Constraints</span>
        </button>
        <Separator class="mb-2" />
        <div class="space-y-2 px-2 pb-2">
          <div>
            <label class="text-xs font-medium opacity-70"> Min value</label>
            <input
              type="number"
              :value="column.config?.min"
              placeholder="No limit"
              class="bg-transparent border border-border rounded px-2 py-1 text-xs w-full mt-0.5 outline-none focus:border-ring"
              @blur="updateNumberConstraint('min', $event)"
            />
          </div>
          <div>
            <label class="text-xs font-medium opacity-70"> Max value</label>
            <input
              type="number"
              :value="column.config?.max"
              placeholder="No limit"
              class="bg-transparent border border-border rounded px-2 py-1 text-xs w-full mt-0.5 outline-none focus:border-ring"
              @blur="updateNumberConstraint('max', $event)"
            />
          </div>
          <div>
            <label class="text-xs font-medium opacity-70"> Step</label>
            <input
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
      <div v-else-if="menuType === 'reference'" class="p-1">
        <button
          class="flex items-center gap-2 w-full px-2 py-1.5 text-xs font-medium opacity-70 rounded-sm hover:bg-accent mb-1"
          @click="menuType = 'main'"
        >
          <ArrowLeft class="size-3.5" />
          <span>Settings</span>
        </button>
        <Separator class="mb-1" />
        <button
          class="flex items-center gap-2 w-full px-2 py-1.5 text-sm rounded-sm hover:bg-accent"
          @click="toggleReferenceMultiple()"
        >
          <Layers class="size-3.5 opacity-60" />
          <span class="flex-1 text-left">Allow multiple</span>
          <Check v-if="column.config?.multiple" class="size-3.5 opacity-60" />
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
    <span class="text-[10px] font-normal text-muted-foreground/30 truncate block max-w-full">
      {{ column.slug }}
    </span>
  </div>
</template>
