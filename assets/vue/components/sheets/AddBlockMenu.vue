<script setup>
import {
	Type,
	Hash,
	ToggleLeft,
	List,
	ListChecks,
	Calendar,
	FileText,
	Table2,
	Plus,
} from "lucide-vue-next";
import { Button } from "@/vue/components/ui/button";
import {
	DropdownMenu,
	DropdownMenuContent,
	DropdownMenuItem,
	DropdownMenuSeparator,
	DropdownMenuLabel,
	DropdownMenuTrigger,
} from "@/vue/components/ui/dropdown-menu";

const emit = defineEmits(["select"]);

const blockTypes = [
	{ type: "text", label: "Text", icon: Type },
	{ type: "number", label: "Number", icon: Hash },
	{ type: "boolean", label: "Boolean", icon: ToggleLeft },
	{ type: "select", label: "Select", icon: List },
	{ type: "multi_select", label: "Multi Select", icon: ListChecks },
	{ type: "date", label: "Date", icon: Calendar },
	{ type: "rich_text", label: "Rich Text", icon: FileText },
	{ type: "table", label: "Table", icon: Table2 },
];
</script>

<template>
  <DropdownMenu>
    <DropdownMenuTrigger as-child>
      <Button variant="ghost" size="sm" class="w-full justify-start gap-2 text-xs text-muted-foreground border border-dashed border-border">
        <Plus class="size-3.5" />
        Add block
      </Button>
    </DropdownMenuTrigger>
    <DropdownMenuContent align="start" :side-offset="4" class="w-48 z-[1030]">
      <DropdownMenuLabel class="text-xs">Block type</DropdownMenuLabel>
      <DropdownMenuSeparator />
      <DropdownMenuItem
        v-for="bt in blockTypes"
        :key="bt.type"
        class="gap-2 text-xs"
        @select="emit('select', bt.type)"
      >
        <component :is="bt.icon" class="size-3.5" />
        {{ bt.label }}
      </DropdownMenuItem>
    </DropdownMenuContent>
  </DropdownMenu>
</template>
