<script setup>
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
import { ref } from "vue";
import { Button } from "@components/ui/button/index.ts";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu/index.ts";
import { Tabs, TabsList, TabsTrigger } from "@components/ui/tabs/index.ts";

const emit = defineEmits(["select"]);

const scope = ref("self");

const basicBlocks = [
  { type: "text", label: "Text", icon: Type },
  { type: "rich_text", label: "Rich Text", icon: AlignLeft },
  { type: "number", label: "Number", icon: Hash },
  { type: "select", label: "Select", icon: CircleDot },
  { type: "multi_select", label: "Multi Select", icon: ListChecks },
  { type: "date", label: "Date", icon: Calendar },
  { type: "boolean", label: "Boolean", icon: ToggleLeft },
  { type: "reference", label: "Reference", icon: Link },
];

const structuredBlocks = [
  { type: "table", label: "Table", icon: Table2 },
  { type: "gallery", label: "Gallery", icon: Image },
];

function selectBlock(type) {
  emit("select", { type, scope: scope.value });
}
</script>

<template>
  <DropdownMenu>
    <DropdownMenuTrigger as-child>
      <Button
        variant="ghost"
        size="sm"
        class="w-full justify-start gap-2 text-xs text-muted-foreground border border-dashed border-border"
      >
        <Plus class="size-3.5" />
        Add block
      </Button>
    </DropdownMenuTrigger>
    <DropdownMenuContent align="start" :side-offset="4" class="w-52">
      <!-- Scope selector -->
      <DropdownMenuLabel class="text-xs text-muted-foreground uppercase tracking-wider"
        >Scope</DropdownMenuLabel
      >
      <div class="px-2 pb-1.5">
        <Tabs v-model="scope">
          <TabsList class="h-7 w-full">
            <TabsTrigger value="self" class="text-xs flex-1">This sheet only</TabsTrigger>
            <TabsTrigger value="children" class="text-xs flex-1">All children</TabsTrigger>
          </TabsList>
        </Tabs>
      </div>

      <DropdownMenuSeparator />

      <!-- Basic Blocks -->
      <DropdownMenuLabel class="text-xs text-muted-foreground uppercase tracking-wider"
        >Basic Blocks</DropdownMenuLabel
      >
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
      <DropdownMenuLabel class="text-xs text-muted-foreground uppercase tracking-wider"
        >Structured Data</DropdownMenuLabel
      >
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
