<script setup lang="ts">
import {
  Building2,
  FileText,
  Folder,
  GitBranch,
  Map as MapIcon,
  Settings,
  type LucideIcon,
} from "lucide-vue-next";
import { computed, onUnmounted, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import {
  CommandDialog,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
  CommandShortcut,
} from "@components/ui/command";
import { useKeyboard } from "@shared/composables/useKeyboard";
import { useLive } from "@shared/composables/useLive";
import {
  paletteGroups,
  primarySurface,
  type PaletteCommand,
} from "@shared/command-palette/registry";
import { liveNavigate } from "@shared/navigation/liveNavigate";
import PaletteEmpty from "./PaletteEmpty.vue";

interface NavItem {
  id: string;
  type: string;
  label: string;
  url: string;
  context?: string;
  shortcut?: string | null;
}

interface NavGroup {
  key: string;
  items: NavItem[];
}

interface PaletteNavReply {
  token?: number;
  groups?: NavGroup[];
}

const NAV_DEBOUNCE_MS = 200;

const navIcons: Record<string, LucideIcon> = {
  workspace: Building2,
  project: Folder,
  settings: Settings,
  sheet: FileText,
  flow: GitBranch,
  scene: MapIcon,
};

// Group headings reuse the canonical name each concept already has in the
// UI (sidebar, navbar) — one concept, one name, everywhere.
const navGroupLabelKeys: Record<string, string> = {
  workspaces: "workspace.sidebar.my_workspaces",
  projects: "palette.nav.projects",
  project_settings: "layout.project_navbar_context.project_settings",
  workspace_settings: "palette.nav.workspace_settings",
  entities: "palette.nav.entities",
};

function navGroupHeading(key: string): string | undefined {
  const labelKey = navGroupLabelKeys[key];
  return labelKey ? t(labelKey) : undefined;
}

const { t } = useI18n();
const live = useLive();

const open = ref(false);
const query = ref("");
const navGroups = ref<NavGroup[]>([]);
const commandFailed = ref(false);

// Stale-reply guard: only the latest request may update the results.
let navToken = 0;
let navDebounce: ReturnType<typeof setTimeout> | null = null;

const localOpen = computed({
  get: () => open.value,
  set: (value: boolean) => {
    if (value) {
      openPalette();
    } else {
      closePalette();
    }
  },
});

useKeyboard({
  "ctrl+k": () => {
    if (open.value) {
      closePalette();
    } else {
      openPalette();
    }
  },
});

watch(query, () => {
  if (!open.value) return;

  // Typing immediately invalidates any in-flight request — a reply for the
  // previous query must never land after the user has kept typing.
  ++navToken;
  if (navDebounce) clearTimeout(navDebounce);
  navDebounce = setTimeout(() => fetchNavDestinations(), NAV_DEBOUNCE_MS);
});

onUnmounted(() => {
  if (navDebounce) clearTimeout(navDebounce);
});

function openPalette(): void {
  query.value = "";
  navGroups.value = [];
  commandFailed.value = false;
  open.value = true;
  fetchNavDestinations();
  track("palette_opened", {});
}

function closePalette(): void {
  open.value = false;
}

function fetchNavDestinations(): void {
  const token = ++navToken;

  try {
    live.pushEvent("palette_nav", { query: query.value, token }, (reply: PaletteNavReply) => {
      if (reply?.token !== token || !open.value) return;
      navGroups.value = reply.groups ?? [];
    });
  } catch {
    // socket unavailable — static commands keep working, results just don't load
  }
}

// A failing command keeps the palette open with an explicit error — it is
// never recorded as executed and never fails silently.
function runCommand(commandId: string, run: () => void): void {
  commandFailed.value = false;

  try {
    run();
  } catch {
    commandFailed.value = true;
    return;
  }

  track("palette_command_executed", { command_id: commandId });
  closePalette();
}

function onSelect(command: PaletteCommand): void {
  runCommand(command.id, command.run);
}

function onSelectNav(item: NavItem): void {
  runCommand(item.id, () => liveNavigate(item.url));
}

function onNoResults(queryLength: number): void {
  track("palette_search_no_results", { query_length: queryLength });
}

function commandLabel(command: PaletteCommand): string {
  if (command.label !== undefined) return command.label;
  return t(command.labelKey);
}

// Analytics is fire-and-forget: a dropped event must never break the palette
// (pushEvent throws when the socket is gone mid-navigation).
function track(event: string, payload: Record<string, unknown>): void {
  try {
    live.pushEvent(event, { ...payload, surface: primarySurface.value });
  } catch {
    // socket unavailable — drop the analytics event, never the interaction
  }
}
</script>

<template>
  <CommandDialog
    v-model:open="localOpen"
    :title="t('palette.title')"
    :description="t('palette.description')"
  >
    <CommandInput v-model="query" :placeholder="t('palette.placeholder')" />
    <p v-if="commandFailed" role="alert" class="border-b px-3 py-2 text-sm text-destructive">
      {{ t("palette.command_failed") }}
    </p>
    <CommandList>
      <PaletteEmpty @no-results="onNoResults">{{ t("palette.no_results") }}</PaletteEmpty>
      <CommandGroup v-for="group in paletteGroups" :key="group.key" :heading="t(group.key)">
        <CommandItem
          v-for="command in group.commands"
          :key="command.id"
          :value="command.id"
          @select="onSelect(command)"
        >
          <component :is="command.icon" v-if="command.icon" class="size-4 shrink-0" />
          <span>{{ commandLabel(command) }}</span>
          <CommandShortcut v-if="command.shortcut">{{ command.shortcut }}</CommandShortcut>
        </CommandItem>
      </CommandGroup>
      <CommandGroup
        v-for="group in navGroups"
        :key="`nav-${group.key}`"
        :heading="navGroupHeading(group.key)"
      >
        <CommandItem
          v-for="item in group.items"
          :key="item.id"
          :value="item.id"
          @select="onSelectNav(item)"
        >
          <component :is="navIcons[item.type]" v-if="navIcons[item.type]" class="size-4 shrink-0" />
          <span>{{ item.label }}</span>
          <span v-if="item.context" class="text-xs text-muted-foreground">{{ item.context }}</span>
          <!-- Entities can match by shortcut server-side; keep it in the
               filterable textContent without showing it. -->
          <span v-if="item.shortcut" class="sr-only">{{ item.shortcut }}</span>
        </CommandItem>
      </CommandGroup>
    </CommandList>
  </CommandDialog>
</template>
