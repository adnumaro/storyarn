<script setup lang="ts">
import { typeIcon } from "@modules/sheets/components/blocks/table/table-config.ts";
import {
  ArrowLeftRight,
  Asterisk,
  Check,
  ChevronRight,
  Lock,
  Settings,
  SlidersHorizontal,
  Trash2,
} from "lucide-vue-next";
import { Separator } from "@components/ui/separator";
import { TableColumn, THeadMenuType } from "@modules/sheets/types.ts";
import THeadBaseMenu from "@modules/sheets/components/blocks/table/theadMenus/THeadBaseMenu.vue";
import THeadMenuItem from "@modules/sheets/components/blocks/table/theadMenus/THeadMenuItem.vue";

const columnName = defineModel<string>({ required: true });
const { column, isLastColumn } = defineProps<{
  column: TableColumn;
  isLastColumn: boolean;
}>();

const emit = defineEmits<{
  (e: "columnNameChanged", columnName: string): void;
  (e: "menuTypeChanged", menuType: THeadMenuType): void;
  (e: "toggleConstant", constant: boolean): void;
  (e: "toggleRequired", required: boolean): void;
  (e: "columnDeleted"): void;
}>();

function columnRenamed(): void {
  emit("columnNameChanged", columnName.value.trim());
}

function menuTypeChanged(menuType: THeadMenuType): void {
  emit("menuTypeChanged", menuType);
}

function toggleConstant(): void {
  emit("toggleConstant", !column.is_constant);
}

function toggleRequired(): void {
  emit("toggleRequired", !column.required);
}

function deleteColumn(): void {
  emit("columnDeleted");
}
</script>

<template>
  <THeadBaseMenu>
    <THeadMenuItem class="mb-1" as="div">
      <component :is="typeIcon(column.type)" class="size-3.5 opacity-50 shrink-0" />
      <input
        v-model="columnName"
        class="bg-transparent outline-none border-none text-sm font-medium w-full px-0"
        @input="(e) => emit('columnNameChanged', (e.target as HTMLInputElement).value)"
        @keydown.enter.prevent="columnRenamed()"
      />
    </THeadMenuItem>
    <THeadMenuItem @click="toggleConstant()">
      <Lock class="size-3.5 opacity-60" />
      <span class="flex-1 text-left">{{ $t("sheets.table.main_menu.constant") }}</span>
      <Check v-if="column.is_constant" class="size-3.5 opacity-60" />
    </THeadMenuItem>
    <THeadMenuItem @click="toggleRequired()">
      <Asterisk class="size-3.5 opacity-60" />
      <span class="flex-1 text-left">{{ $t("sheets.table.main_menu.required") }}</span>
      <Check v-if="column.required" class="size-3.5 opacity-60" />
    </THeadMenuItem>
    <Separator class="my-1" />
    <THeadMenuItem @click="menuTypeChanged('type')">
      <ArrowLeftRight class="size-3.5 opacity-60" />
      <span class="flex-1 text-left">{{ $t("sheets.table.main_menu.change_type") }}</span>
      <ChevronRight class="size-3.5 opacity-40" />
    </THeadMenuItem>
    <THeadMenuItem
      v-if="column.type === 'select' || column.type === 'multi_select'"
      @click="menuTypeChanged('options')"
    >
      <Settings class="size-3.5 opacity-60" />
      <span class="flex-1 text-left">{{ $t("sheets.table.main_menu.options") }}</span>
      <ChevronRight class="size-3.5 opacity-40" />
    </THeadMenuItem>
    <THeadMenuItem v-if="column.type === 'number'" @click="menuTypeChanged('number')">
      <SlidersHorizontal class="size-3.5 opacity-60" />
      <span class="flex-1 text-left">{{ $t("sheets.table.main_menu.constraints") }}</span>
      <ChevronRight class="size-3.5 opacity-40" />
    </THeadMenuItem>
    <THeadMenuItem v-if="column.type === 'reference'" @click="menuTypeChanged('reference')">
      <Settings class="size-3.5 opacity-60" />
      <span class="flex-1 text-left">{{ $t("sheets.table.main_menu.settings") }}</span>
      <ChevronRight class="size-3.5 opacity-40" />
    </THeadMenuItem>
    <Separator class="my-1" />
    <THeadMenuItem
      :disabled="isLastColumn"
      class="text-destructive hover:bg-destructive/10 disabled:hover:bg-none disabled:cursor-not-allowed"
      @click="deleteColumn()"
    >
      <Trash2 class="size-3.5" />
      <span>{{ $t("sheets.table.main_menu.delete_column") }}</span>
    </THeadMenuItem>
  </THeadBaseMenu>
</template>
