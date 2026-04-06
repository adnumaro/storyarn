<script setup lang="ts">
import { MapPin } from "lucide-vue-next";
import { nextTick, ref } from "vue";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@components/ui/command";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";

interface ProjectSheet {
  id: number | string;
  name: string;
  shortcut?: string;
}

const {
  activeTool = "select",
  projectSheets = [],
} = defineProps<{
  activeTool: string;
  projectSheets: ProjectSheet[];
}>();

const emit = defineEmits<{
  "set-tool": [type: string];
  "select-sheet": [sheetId: number | string];
}>();

const pinsOpen = ref(false);
const sheetPickerOpen = ref(false);

async function openSheetPicker(): Promise<void> {
  pinsOpen.value = false;
  await nextTick();
  sheetPickerOpen.value = true;
}

function setTool(type: string): void {
  emit("set-tool", type);
  pinsOpen.value = false;
}

function selectSheet(sheetId: number | string): void {
  sheetPickerOpen.value = false;
  emit("select-sheet", sheetId);
}
</script>

<template>
  <div class="v2-dock-item group relative">
    <!-- Pin menu (Free Pin / From Sheet) -->
    <Popover v-if="!sheetPickerOpen" v-model:open="pinsOpen">
      <PopoverTrigger as-child>
        <button
          type="button"
          class="v2-dock-btn"
          :class="{ 'v2-dock-btn-active': activeTool === 'pin' }"
        >
          <MapPin class="size-5" />
        </button>
      </PopoverTrigger>
      <PopoverContent side="top" :side-offset="12" class="w-52 p-3">
        <div class="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2 px-1">
          Place a Pin
        </div>
        <div class="flex flex-col gap-0.5">
          <button
            type="button"
            class="w-full flex items-start gap-2.5 px-2.5 py-2 rounded-lg text-sm text-start cursor-pointer hover:bg-accent transition-colors"
            @click="setTool('pin')"
          >
            <MapPin class="size-4 mt-0.5 shrink-0" />
            <div>
              <div class="font-medium">Free Pin</div>
              <div class="text-xs text-muted-foreground">Place anywhere on the map</div>
            </div>
          </button>
          <button
            type="button"
            class="w-full flex items-start gap-2.5 px-2.5 py-2 rounded-lg text-sm text-start cursor-pointer hover:bg-accent transition-colors"
            @click="openSheetPicker"
          >
            <MapPin class="size-4 mt-0.5 shrink-0" />
            <div>
              <div class="font-medium">From Sheet</div>
              <div class="text-xs text-muted-foreground">Link a character or item</div>
            </div>
          </button>
        </div>
      </PopoverContent>
    </Popover>
    <!-- Sheet picker (replaces pin menu when open) -->
    <Popover v-else v-model:open="sheetPickerOpen">
      <PopoverTrigger as-child>
        <button type="button" class="v2-dock-btn v2-dock-btn-active">
          <MapPin class="size-5" />
        </button>
      </PopoverTrigger>
      <PopoverContent side="top" :side-offset="12" class="w-56 p-0">
        <Command>
          <CommandInput placeholder="Search sheets..." />
          <CommandList>
            <CommandEmpty>No sheets found</CommandEmpty>
            <CommandGroup>
              <CommandItem
                v-for="sheet in projectSheets"
                :key="sheet.id"
                :value="sheet.name"
                @select="selectSheet(sheet.id)"
              >
                <span class="truncate">{{ sheet.name }}</span>
                <span v-if="sheet.shortcut" class="ml-auto text-xs text-muted-foreground"
                  >#{{ sheet.shortcut }}</span
                >
              </CommandItem>
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
    <div v-if="!pinsOpen && !sheetPickerOpen" class="v2-dock-tooltip">
      <div class="text-sm font-semibold mb-0.5">Pin</div>
      <div class="text-xs text-muted-foreground leading-relaxed">
        Place markers on the map, optionally linked to a sheet
      </div>
    </div>
  </div>
</template>
