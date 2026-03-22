<script setup>
import {
	Type,
	AlignLeft,
	Hash,
	CircleDot,
	ListChecks,
	Calendar,
	ToggleLeft,
	Link,
	Table2,
	Image,
	Plus,
} from "lucide-vue-next";
import { ref } from "vue";
import { Button } from "@/vue/components/ui/button";
import { RadioGroup, RadioGroupItem } from "@/vue/components/ui/radio-group";
import { Label } from "@/vue/components/ui/label";
import {
	DropdownMenu,
	DropdownMenuContent,
	DropdownMenuItem,
	DropdownMenuSeparator,
	DropdownMenuLabel,
	DropdownMenuTrigger,
} from "@/vue/components/ui/dropdown-menu";

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
      <Button variant="ghost" size="sm" class="w-full justify-start gap-2 text-xs text-muted-foreground border border-dashed border-border">
        <Plus class="size-3.5" />
        Add block
      </Button>
    </DropdownMenuTrigger>
    <DropdownMenuContent align="start" :side-offset="4" class="w-52">
      <!-- Scope selector -->
      <DropdownMenuLabel class="text-xs text-muted-foreground uppercase tracking-wider">Scope</DropdownMenuLabel>
      <RadioGroup v-model="scope" class="px-2 pb-1.5 gap-1.5">
        <div class="flex items-center gap-2">
          <RadioGroupItem id="scope-self" value="self" />
          <Label for="scope-self" class="text-sm font-normal cursor-pointer">This sheet only</Label>
        </div>
        <div class="flex items-center gap-2">
          <RadioGroupItem id="scope-children" value="children" />
          <Label for="scope-children" class="text-sm font-normal cursor-pointer">This sheet and all children</Label>
        </div>
      </RadioGroup>

      <DropdownMenuSeparator />

      <!-- Basic Blocks -->
      <DropdownMenuLabel class="text-xs text-muted-foreground uppercase tracking-wider">Basic Blocks</DropdownMenuLabel>
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
      <DropdownMenuLabel class="text-xs text-muted-foreground uppercase tracking-wider">Structured Data</DropdownMenuLabel>
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
