<script setup lang="ts">
import {
  AlignLeft,
  Calendar,
  CircleDot,
  Hash,
  Image,
  Link,
  ListChecks,
  Plus,
  Table2,
  ToggleLeft,
  Type,
} from "lucide-vue-next";
import type { FunctionalComponent } from "vue";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu";
import { Tabs, TabsList, TabsTrigger } from "@components/ui/tabs";
import { generateId } from "../../../../../shared/domain/variables.ts";

interface BlockSelection {
  type: string;
  scope: string;
}

const emit = defineEmits<{
  select: [payload: BlockSelection];
}>();

const { t } = useI18n();
const scope = ref("self");

interface BlockTypeEntry {
  type: string;
  label: string;
  icon: FunctionalComponent;
}

const basicBlocks = computed<BlockTypeEntry[]>(() => [
  { type: "text", label: t("sheets.block_types.text"), icon: Type },
  { type: "rich_text", label: t("sheets.block_types.rich_text"), icon: AlignLeft },
  { type: "number", label: t("sheets.block_types.number"), icon: Hash },
  { type: "select", label: t("sheets.block_types.select"), icon: CircleDot },
  { type: "multi_select", label: t("sheets.block_types.multi_select"), icon: ListChecks },
  { type: "date", label: t("sheets.block_types.date"), icon: Calendar },
  { type: "boolean", label: t("sheets.block_types.boolean"), icon: ToggleLeft },
  { type: "reference", label: t("sheets.block_types.reference"), icon: Link },
]);

const structuredBlocks = computed<BlockTypeEntry[]>(() => [
  { type: "table", label: t("sheets.block_types.table"), icon: Table2 },
  { type: "gallery", label: t("sheets.block_types.gallery"), icon: Image },
]);

function selectBlock(type: string): void {
  emit("select", { type, scope: scope.value });
}
</script>

<template>
  <DropdownMenu>
    <DropdownMenuTrigger as-child>
      <Button
        :id="`add-block-menu-${generateId()}`"
        variant="ghost"
        size="sm"
        class="w-full justify-start gap-2 text-xs text-muted-foreground border border-dashed border-border"
      >
        <Plus class="size-3.5" />
        {{ $t("sheets.add_block.button") }}
      </Button>
    </DropdownMenuTrigger>
    <DropdownMenuContent align="start" :side-offset="4" class="w-52">
      <!-- Scope selector -->
      <DropdownMenuLabel class="text-xs text-muted-foreground uppercase tracking-wider">{{
        $t("sheets.add_block.scope")
      }}</DropdownMenuLabel>
      <div class="px-2 pb-1.5">
        <Tabs v-model="scope">
          <TabsList class="h-7 w-full">
            <TabsTrigger value="self" class="text-xs flex-1">{{
              $t("sheets.add_block.scope_self")
            }}</TabsTrigger>
            <TabsTrigger value="children" class="text-xs flex-1">{{
              $t("sheets.add_block.scope_children")
            }}</TabsTrigger>
          </TabsList>
        </Tabs>
      </div>

      <DropdownMenuSeparator />

      <!-- Basic Blocks -->
      <DropdownMenuLabel class="text-xs text-muted-foreground uppercase tracking-wider">{{
        $t("sheets.add_block.basic")
      }}</DropdownMenuLabel>
      <DropdownMenuItem
        v-for="bt in basicBlocks"
        :key="bt.type"
        class="gap-2 text-sm"
        @select="selectBlock(bt.type)"
      >
        <component :is="bt.icon" class="size-4 opacity-70" />
        {{ bt.label }}
      </DropdownMenuItem>

      <DropdownMenuSeparator />

      <!-- Structured Data -->
      <DropdownMenuLabel class="text-xs text-muted-foreground uppercase tracking-wider">{{
        $t("sheets.add_block.structured")
      }}</DropdownMenuLabel>
      <DropdownMenuItem
        v-for="bt in structuredBlocks"
        :key="bt.type"
        class="gap-2 text-sm"
        @select="selectBlock(bt.type)"
      >
        <component :is="bt.icon" class="size-4 opacity-70" />
        {{ bt.label }}
      </DropdownMenuItem>
    </DropdownMenuContent>
  </DropdownMenu>
</template>
