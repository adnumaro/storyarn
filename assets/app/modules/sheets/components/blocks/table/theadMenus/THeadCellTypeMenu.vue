<script setup lang="ts">
import {
  allTypes,
  typeIcon,
  typeLabels,
} from "@modules/sheets/components/blocks/table/table-config.ts";
import { Separator } from "@components/ui/separator";
import { ArrowLeft, Check } from "lucide-vue-next";
import { TableColumn, type THeadMenuType } from "@modules/sheets/types.ts";
import THeadBaseMenu from "@modules/sheets/components/blocks/table/theadMenus/THeadBaseMenu.vue";
import THeadMenuItem from "@modules/sheets/components/blocks/table/theadMenus/THeadMenuItem.vue";

const { column } = defineProps<{
  column: TableColumn;
}>();

const emit = defineEmits<{
  (e: "columnTypeChanged", type: string): void;
  (e: "backToMain"): void;
}>();

function backToMain(): void {
  emit("backToMain");
}

function columnTypeChanged(type: THeadMenuType): void {
  emit("columnTypeChanged", type);
}
</script>

<template>
  <THeadBaseMenu>
    <THeadMenuItem class="mb-1" @click="backToMain()">
      <ArrowLeft class="size-3.5" />
      <span>Change type</span>
    </THeadMenuItem>
    <Separator class="mb-1" />
    <THeadMenuItem
      v-for="columnType in allTypes"
      :key="columnType"
      :class="column.type === columnType && 'bg-accent'"
      @click="columnTypeChanged(columnType as THeadMenuType)"
    >
      <component :is="typeIcon(columnType)" class="size-3.5 opacity-60" />
      <span class="flex-1 text-left">{{ typeLabels[columnType] }}</span>
      <Check v-if="column.type === columnType" class="size-3.5 opacity-60" />
    </THeadMenuItem>
  </THeadBaseMenu>
</template>

<style scoped></style>
