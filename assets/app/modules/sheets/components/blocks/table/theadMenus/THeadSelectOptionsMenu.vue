<script setup lang="ts">
import { Separator } from "@components/ui/separator";
import { ArrowLeft } from "lucide-vue-next";
import THeadBaseMenu from "@modules/sheets/components/blocks/table/theadMenus/THeadBaseMenu.vue";
import THeadMenuItem from "@modules/sheets/components/blocks/table/theadMenus/THeadMenuItem.vue";
import OptionEditor from "@modules/sheets/components/OptionEditor.vue";
import type { TableColumn } from "@modules/sheets/types.ts";

const { column } = defineProps<{
  column: TableColumn;
}>();

const emits = defineEmits<{
  (e: "backToMain"): void;
}>();
</script>

<template>
  <THeadBaseMenu class="p-1">
    <THeadMenuItem class="mb-1" @click="emits('backToMain')">
      <ArrowLeft class="size-3.5" />
      <span>Options</span>
    </THeadMenuItem>
    <Separator class="mb-1" />

    <div class="px-1 pb-1">
      <OptionEditor scope="column" :id="column.id" :options="column.config?.options || []" />
    </div>
  </THeadBaseMenu>
</template>
