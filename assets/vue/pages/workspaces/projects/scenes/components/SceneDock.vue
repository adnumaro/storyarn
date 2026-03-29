<script setup>
import {
	Cable,
	Circle,
	Hand,
	History,
	MapPin,
	MousePointer2,
	PenTool,
	Play,
	Ruler,
	Square,
	StickyNote,
	Triangle,
	X,
} from "lucide-vue-next";
import { nextTick, ref } from "vue";
import {
	Command,
	CommandEmpty,
	CommandGroup,
	CommandInput,
	CommandItem,
	CommandList,
} from "@/vue/components/ui/command";
import {
	Popover,
	PopoverContent,
	PopoverTrigger,
} from "@/vue/components/ui/popover";
import { useLive } from "@/vue/composables/useLive";

const props = defineProps({
	activeTool: { type: String, default: "select" },
	editMode: { type: Boolean, default: true },
	compact: { type: Boolean, default: false },
	pendingSheet: { type: Object, default: null },
	projectSheets: { type: Array, default: () => [] },
	workspaceSlug: { type: String, required: true },
	projectSlug: { type: String, required: true },
	sceneId: { type: [String, Number], required: true },
});

const live = useLive();

const shapesOpen = ref(false);
const pinsOpen = ref(false);
const sheetPickerOpen = ref(false);

const shapeTools = [
	{ id: "rectangle", icon: Square, title: "Rectangle" },
	{ id: "triangle", icon: Triangle, title: "Triangle" },
	{ id: "circle", icon: Circle, title: "Circle" },
	{ id: "freeform", icon: PenTool, title: "Freeform" },
];

const activeShapeIcon = () => {
	const shape = shapeTools.find((s) => s.id === props.activeTool);
	return shape ? shape.icon : PenTool;
};

const isShapeActive = () =>
	["rectangle", "triangle", "circle", "freeform"].includes(props.activeTool);

function setTool(type) {
	live.pushEvent("set_tool", { type });
	shapesOpen.value = false;
	pinsOpen.value = false;
}

async function openSheetPicker() {
	pinsOpen.value = false;
	await nextTick();
	sheetPickerOpen.value = true;
}

function selectSheet(sheetId) {
	sheetPickerOpen.value = false;
	live.pushEvent("start_pin_from_sheet", { "sheet-id": sheetId });
}

function cancelPendingSheet() {
	live.pushEvent("cancel_sheet_picker", {});
}

function openVersions() {
	live.pushEvent("open_versions_panel", {});
}

const playUrl = `/workspaces/${props.workspaceSlug}/projects/${props.projectSlug}/scenes/${props.sceneId}/explore`;
</script>

<template>
  <div v-if="editMode">
    <div
      class="absolute bottom-3 left-1/2 -translate-x-1/2 z-30 flex items-center gap-1 v2-surface-panel px-2 py-2"
    >
      <!-- Navigation group -->
      <div class="v2-dock-item group relative">
        <button
          type="button"
          class="v2-dock-btn"
          :class="{ 'v2-dock-btn-active': activeTool === 'select' }"
          @click="setTool('select')"
        >
          <MousePointer2 class="size-5" />
        </button>
        <div class="v2-dock-tooltip">
          <div class="text-sm font-semibold mb-0.5">Select</div>
          <div class="text-xs text-muted-foreground leading-relaxed">
            Select elements on the canvas
          </div>
        </div>
      </div>

      <div class="v2-dock-item group relative">
        <button
          type="button"
          class="v2-dock-btn"
          :class="{ 'v2-dock-btn-active': activeTool === 'pan' }"
          @click="setTool('pan')"
        >
          <Hand class="size-5" />
        </button>
        <div class="v2-dock-tooltip">
          <div class="text-sm font-semibold mb-0.5">Pan</div>
          <div class="text-xs text-muted-foreground leading-relaxed">
            Pan and scroll around the map
          </div>
        </div>
      </div>

      <!-- Separator -->
      <div class="w-px h-6 bg-border mx-0.5 shrink-0" />

      <!-- Creation group -->
      <!-- Zones dropdown -->
      <div class="v2-dock-item group relative">
        <Popover v-model:open="shapesOpen">
          <PopoverTrigger as-child>
            <button
              type="button"
              class="v2-dock-btn"
              :class="{ 'v2-dock-btn-active': isShapeActive() }"
            >
              <component :is="isShapeActive() ? activeShapeIcon() : PenTool" class="size-5" />
            </button>
          </PopoverTrigger>
          <PopoverContent side="top" :side-offset="12" class="w-52 p-3">
            <div class="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2 px-1">
              Zone Shapes
            </div>
            <div class="flex flex-col gap-0.5">
              <button
                v-for="shape in shapeTools"
                :key="shape.id"
                type="button"
                class="w-full flex items-start gap-2.5 px-2.5 py-2 rounded-lg text-sm text-start cursor-pointer hover:bg-accent transition-colors"
                @click="setTool(shape.id)"
              >
                <component :is="shape.icon" class="size-4 mt-0.5 shrink-0" />
                <div class="font-medium">{{ shape.title }}</div>
              </button>
            </div>
          </PopoverContent>
        </Popover>
        <div v-if="!shapesOpen" class="v2-dock-tooltip">
          <div class="text-sm font-semibold mb-0.5">Zones</div>
          <div class="text-xs text-muted-foreground leading-relaxed">
            Draw shapes to define areas on the map
          </div>
        </div>
      </div>

      <!-- Pins dropdown / Sheet picker -->
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
            <button
              type="button"
              class="v2-dock-btn v2-dock-btn-active"
            >
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
                    <span v-if="sheet.shortcut" class="ml-auto text-xs text-muted-foreground">#{{ sheet.shortcut }}</span>
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

      <!-- Annotation -->
      <div class="v2-dock-item group relative">
        <button
          type="button"
          class="v2-dock-btn"
          :class="{ 'v2-dock-btn-active': activeTool === 'annotation' }"
          @click="setTool('annotation')"
        >
          <StickyNote class="size-5" />
        </button>
        <div class="v2-dock-tooltip">
          <div class="text-sm font-semibold mb-0.5">Annotation</div>
          <div class="text-xs text-muted-foreground leading-relaxed">
            Add text notes directly on the canvas
          </div>
        </div>
      </div>

      <!-- Separator -->
      <div class="w-px h-6 bg-border mx-0.5 shrink-0" />

      <!-- Connector -->
      <div class="v2-dock-item group relative">
        <button
          type="button"
          class="v2-dock-btn"
          :class="{ 'v2-dock-btn-active': activeTool === 'connector' }"
          @click="setTool('connector')"
        >
          <Cable class="size-5" />
        </button>
        <div class="v2-dock-tooltip">
          <div class="text-sm font-semibold mb-0.5">Connector</div>
          <div class="text-xs text-muted-foreground leading-relaxed">
            Draw connections between two pins. Click the source pin, then the target.
          </div>
        </div>
      </div>

      <!-- Separator -->
      <div class="w-px h-6 bg-border mx-0.5 shrink-0" />

      <!-- Ruler -->
      <div class="v2-dock-item group relative">
        <button
          type="button"
          class="v2-dock-btn"
          :class="{ 'v2-dock-btn-active': activeTool === 'ruler' }"
          @click="setTool('ruler')"
        >
          <Ruler class="size-5" />
        </button>
        <div class="v2-dock-tooltip">
          <div class="text-sm font-semibold mb-0.5">Ruler</div>
          <div class="text-xs text-muted-foreground leading-relaxed">
            Measure distances between two points on the map
          </div>
        </div>
      </div>

      <!-- Actions group (not in compact mode) -->
      <template v-if="!compact">
        <!-- Separator -->
        <div class="w-px h-6 bg-border mx-0.5 shrink-0" />

        <!-- Version History -->
        <div class="v2-dock-item group relative">
          <button
            type="button"
            class="v2-dock-btn"
            @click="openVersions"
          >
            <History class="size-5" />
          </button>
          <div class="v2-dock-tooltip">
            <div class="text-sm font-semibold mb-0.5">Version History</div>
            <div class="text-xs text-muted-foreground leading-relaxed">
              View and manage version history
            </div>
          </div>
        </div>

        <!-- Play -->
        <div class="v2-dock-item group relative">
          <a
            :href="playUrl"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="v2-dock-btn"
          >
            <Play class="size-5" />
          </a>
          <div class="v2-dock-tooltip">
            <div class="text-sm font-semibold mb-0.5">Play</div>
            <div class="text-xs text-muted-foreground leading-relaxed">
              Play exploration mode
            </div>
          </div>
        </div>
      </template>
    </div>

    <!-- Pending sheet indicator -->
    <div
      v-if="pendingSheet"
      class="absolute bottom-24 left-1/2 -translate-x-1/2 z-30 bg-primary/10 border border-primary/30 rounded-lg px-3 py-1.5 text-xs flex items-center gap-2"
    >
      <MapPin class="size-3.5" />
      <span>
        Click on canvas to place <strong>{{ pendingSheet.name }}</strong>
      </span>
      <button
        type="button"
        class="v2-dock-btn !size-5 !rounded-md"
        @click="cancelPendingSheet"
      >
        <X class="size-3" />
      </button>
    </div>
  </div>
</template>
