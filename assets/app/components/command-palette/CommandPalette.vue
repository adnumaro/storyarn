<script setup lang="ts">
import {
  Building2,
  FileText,
  Folder,
  GitBranch,
  Map as MapIcon,
  Settings,
  Trash2,
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

type EntityType = "sheet" | "flow" | "scene";

interface CreateTarget {
  id: number;
  label: string;
  context?: string;
}

interface CreateTargetsReply {
  token?: number;
  projects?: CreateTarget[];
}

interface DeleteItem {
  id: number;
  type: EntityType;
  label: string;
  context?: string;
  shortcut?: string | null;
  projectId: number;
}

interface DeleteSearchReply {
  token?: number;
  items?: DeleteItem[];
}

interface MutationReply {
  url?: string;
  deleted?: boolean;
  error?: string;
}

// The palette is a small state machine: the root page plus the multi-step
// create/delete flows. Every step happens INSIDE the palette (owner
// decision); Escape or Backspace-on-empty-query walks one step back.
type PaletteStep =
  | { kind: "root" }
  | { kind: "create-pick-project"; entityType: EntityType }
  | { kind: "delete-pick-entity" }
  | { kind: "delete-confirm"; item: DeleteItem };

const NAV_DEBOUNCE_MS = 200;

const navIcons: Record<string, LucideIcon> = {
  workspace: Building2,
  project: Folder,
  settings: Settings,
  sheet: FileText,
  flow: GitBranch,
  scene: MapIcon,
};

const entityTypes: EntityType[] = ["sheet", "flow", "scene"];

// Labels reuse each tree's own "New X" / delete-confirm keys — one concept,
// one name, no matter which surface runs it.
const createLabelKeys: Record<EntityType, string> = {
  sheet: "sheets.tree.new_sheet",
  flow: "flows.tree.new_flow",
  scene: "scenes.tree.new_scene",
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

// Server error codes map to explicit messages; unknown codes fall back to
// the generic failure text — never to silence.
const errorMessageKeys: Record<string, string> = {
  limit_reached: "palette.limit_reached",
  unauthorized: "palette.not_allowed",
};

function navGroupHeading(key: string): string | undefined {
  const labelKey = navGroupLabelKeys[key];
  return labelKey ? t(labelKey) : undefined;
}

const { t } = useI18n();
const live = useLive();

const open = ref(false);
const query = ref("");
const step = ref<PaletteStep>({ kind: "root" });
const navGroups = ref<NavGroup[]>([]);
const createTargets = ref<CreateTarget[]>([]);
const deleteItems = ref<DeleteItem[]>([]);
const errorKey = ref<string | null>(null);
// True while a create/delete pushEvent awaits its reply — blocks re-submits.
const pendingMutation = ref(false);

// Stale-reply guard: only the latest request may update the results.
let navToken = 0;
// Mutation replies are checked against this separately from navToken (typing
// must never invalidate an in-flight create/delete): closing the palette or
// changing step abandons the flow, so a late reply must not navigate or
// mutate the reopened palette's state.
let mutationToken = 0;
let navDebounce: ReturnType<typeof setTimeout> | null = null;
let suppressQueryWatch = false;

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

// vue-tsc cannot narrow the step union inside the template; these computeds
// expose the step-specific payloads already narrowed.
const createEntityType = computed<EntityType | null>(() =>
  step.value.kind === "create-pick-project" ? step.value.entityType : null,
);

const confirmItem = computed<DeleteItem | null>(() =>
  step.value.kind === "delete-confirm" ? step.value.item : null,
);

const inputPlaceholder = computed<string>(() =>
  step.value.kind === "create-pick-project"
    ? t("palette.pick_project_placeholder")
    : t("palette.placeholder"),
);

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
  if (suppressQueryWatch) {
    suppressQueryWatch = false;
    return;
  }

  if (!open.value) return;

  // Typing immediately invalidates any in-flight request — a reply for the
  // previous query must never land after the user has kept typing.
  ++navToken;
  if (navDebounce) clearTimeout(navDebounce);
  navDebounce = setTimeout(() => fetchForStep(), NAV_DEBOUNCE_MS);
});

onUnmounted(() => {
  if (navDebounce) clearTimeout(navDebounce);
});

function openPalette(): void {
  navGroups.value = [];
  errorKey.value = null;
  step.value = { kind: "root" };
  open.value = true;
  fetchNavDestinations();
  track("palette_opened", {});
}

function closePalette(): void {
  open.value = false;
  // Reset on CLOSE, not open: the query watcher ignores changes while
  // closed, so reopening never invalidates the immediate initial fetch.
  resetQuery();
  step.value = { kind: "root" };
  errorKey.value = null;
  pendingMutation.value = false;
  ++mutationToken;
}

function resetQuery(): void {
  if (query.value === "") return;
  suppressQueryWatch = true;
  query.value = "";
}

function enterStep(next: PaletteStep): void {
  step.value = next;
  errorKey.value = null;
  pendingMutation.value = false;
  ++mutationToken;
  ++navToken;
  if (navDebounce) clearTimeout(navDebounce);
  resetQuery();

  if (next.kind === "create-pick-project") {
    fetchCreateTargets();
  } else {
    fetchForStep();
  }
}

function goBack(): void {
  const current = step.value;
  if (current.kind === "root") return;

  if (current.kind === "delete-confirm") {
    enterStep({ kind: "delete-pick-entity" });
  } else {
    enterStep({ kind: "root" });
  }
}

// Attached to the wrapper AROUND the whole palette body (not the input): the
// input is hidden during delete-confirm, and Escape must still mean "one
// step back" there instead of letting the dialog's dismiss layer close.
function onPaletteKeydown(event: KeyboardEvent): void {
  if (step.value.kind === "root") return;

  if (event.key === "Escape" || (event.key === "Backspace" && query.value === "")) {
    // Swallow the key before the dialog's dismiss layer sees it: inside a
    // step it means "one step back", never "close".
    event.preventDefault();
    event.stopPropagation();
    goBack();
  }
}

function fetchForStep(): void {
  const current = step.value;

  if (current.kind === "root") {
    fetchNavDestinations();
  } else if (current.kind === "delete-pick-entity") {
    fetchDeleteItems();
  }
  // create-pick-project filters its already-loaded targets client-side;
  // delete-confirm has no data to fetch.
}

function fetchNavDestinations(): void {
  const token = ++navToken;

  try {
    live.pushEvent("palette_nav", { query: query.value, token }, (reply: PaletteNavReply) => {
      if (reply?.token !== token || !open.value || step.value.kind !== "root") return;
      navGroups.value = reply.groups ?? [];
    });
  } catch {
    // socket unavailable — static commands keep working, results just don't load
  }
}

function fetchCreateTargets(): void {
  const token = ++navToken;

  try {
    live.pushEvent("palette_create_targets", { token }, (reply: CreateTargetsReply) => {
      if (reply?.token !== token || !open.value || step.value.kind !== "create-pick-project") {
        return;
      }
      createTargets.value = reply.projects ?? [];
    });
  } catch {
    // socket unavailable — the step shows its empty state
  }
}

function fetchDeleteItems(): void {
  const token = ++navToken;

  try {
    live.pushEvent(
      "palette_delete_search",
      { query: query.value, token },
      (reply: DeleteSearchReply) => {
        if (reply?.token !== token || !open.value || step.value.kind !== "delete-pick-entity") {
          return;
        }
        deleteItems.value = reply.items ?? [];
      },
    );
  } catch {
    // socket unavailable — the step shows its empty state
  }
}

// A failing command keeps the palette open with an explicit error — it is
// never recorded as executed and never fails silently.
function runCommand(commandId: string, run: () => void): void {
  errorKey.value = null;

  try {
    run();
  } catch {
    errorKey.value = "palette.command_failed";
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

function enterCreateStep(entityType: EntityType): void {
  createTargets.value = [];
  enterStep({ kind: "create-pick-project", entityType });
}

function enterDeleteStep(): void {
  deleteItems.value = [];
  enterStep({ kind: "delete-pick-entity" });
}

function onSelectCreateTarget(target: CreateTarget): void {
  const current = step.value;
  if (current.kind !== "create-pick-project" || pendingMutation.value) return;

  const entityType = current.entityType;
  errorKey.value = null;
  pendingMutation.value = true;
  const token = ++mutationToken;

  // useLive's pushEvent never throws — transport failures arrive through the
  // onError callback, which must clear the pending state or the palette
  // would be stuck unclickable.
  live.pushEvent(
    "palette_create",
    { type: entityType, project_id: target.id },
    (reply: MutationReply) => {
      if (token !== mutationToken) return;
      pendingMutation.value = false;
      const url = reply?.url;
      if (url) {
        runCommand(`create.${entityType}`, () => liveNavigate(url));
      } else {
        errorKey.value = errorMessageKeys[reply?.error ?? ""] ?? "palette.command_failed";
      }
    },
    () => {
      if (token !== mutationToken) return;
      pendingMutation.value = false;
      errorKey.value = "palette.command_failed";
    },
  );
}

function onSelectDeleteItem(item: DeleteItem): void {
  enterStep({ kind: "delete-confirm", item });
}

function confirmDelete(): void {
  const current = step.value;
  if (current.kind !== "delete-confirm" || pendingMutation.value) return;

  const item = current.item;
  errorKey.value = null;
  pendingMutation.value = true;
  const token = ++mutationToken;

  // useLive's pushEvent never throws — transport failures arrive through the
  // onError callback, which must clear the pending state or the palette
  // would be stuck unclickable.
  live.pushEvent(
    "palette_delete",
    { type: item.type, id: item.id, project_id: item.projectId },
    (reply: MutationReply) => {
      if (token !== mutationToken) return;
      pendingMutation.value = false;
      if (reply?.deleted) {
        track("palette_command_executed", { command_id: `delete.${item.type}` });
        // Drop the stale listing BEFORE showing it again: the deleted
        // entity must never reappear as a selectable target while the
        // refresh is in flight.
        deleteItems.value = [];
        // Back to the refreshed listing — the flow never leaves the palette.
        enterStep({ kind: "delete-pick-entity" });
      } else {
        errorKey.value = errorMessageKeys[reply?.error ?? ""] ?? "palette.command_failed";
      }
    },
    () => {
      if (token !== mutationToken) return;
      pendingMutation.value = false;
      errorKey.value = "palette.command_failed";
    },
  );
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
    <div class="contents" @keydown="onPaletteKeydown">
      <CommandInput v-if="!confirmItem" v-model="query" :placeholder="inputPlaceholder" />
      <p v-if="errorKey" role="alert" class="border-b px-3 py-2 text-sm text-destructive">
        {{ t(errorKey) }}
      </p>
      <CommandList>
        <template v-if="step.kind === 'root'">
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
          <CommandGroup :heading="t('palette.groups.actions')">
            <CommandItem
              v-for="entityType in entityTypes"
              :key="`create.${entityType}`"
              :value="`create.${entityType}`"
              @select="enterCreateStep(entityType)"
            >
              <component :is="navIcons[entityType]" class="size-4 shrink-0" />
              <span>{{ t(createLabelKeys[entityType]) }}</span>
            </CommandItem>
            <CommandItem value="palette.delete-entity" @select="enterDeleteStep">
              <Trash2 class="size-4 shrink-0" />
              <span>{{ t("palette.delete_entity") }}</span>
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
              <component
                :is="navIcons[item.type]"
                v-if="navIcons[item.type]"
                class="size-4 shrink-0"
              />
              <span>{{ item.label }}</span>
              <span v-if="item.context" class="text-xs text-muted-foreground">{{
                item.context
              }}</span>
              <!-- Entities can match by shortcut server-side; keep it in the
                 filterable textContent without showing it. -->
              <span v-if="item.shortcut" class="sr-only">{{ item.shortcut }}</span>
            </CommandItem>
          </CommandGroup>
        </template>

        <template v-else-if="createEntityType">
          <p
            v-if="createTargets.length === 0"
            class="py-6 text-center text-sm text-muted-foreground"
          >
            {{ t("palette.no_editable_projects") }}
          </p>
          <template v-else>
            <PaletteEmpty @no-results="onNoResults">{{ t("palette.no_results") }}</PaletteEmpty>
            <CommandGroup :heading="t(createLabelKeys[createEntityType])">
              <CommandItem
                v-for="target in createTargets"
                :key="`create-target-${target.id}`"
                :value="`create-target-${target.id}`"
                :disabled="pendingMutation"
                @select="onSelectCreateTarget(target)"
              >
                <Folder class="size-4 shrink-0" />
                <span>{{ target.label }}</span>
                <span v-if="target.context" class="text-xs text-muted-foreground">{{
                  target.context
                }}</span>
              </CommandItem>
            </CommandGroup>
          </template>
        </template>

        <template v-else-if="step.kind === 'delete-pick-entity'">
          <p v-if="deleteItems.length === 0" class="py-6 text-center text-sm text-muted-foreground">
            {{ t("palette.no_results") }}
          </p>
          <CommandGroup v-else :heading="t('palette.delete_entity')">
            <CommandItem
              v-for="item in deleteItems"
              :key="`delete-${item.type}-${item.id}`"
              :value="`delete-${item.type}-${item.id}`"
              @select="onSelectDeleteItem(item)"
            >
              <component
                :is="navIcons[item.type]"
                v-if="navIcons[item.type]"
                class="size-4 shrink-0"
              />
              <span>{{ item.label }}</span>
              <span v-if="item.context" class="text-xs text-muted-foreground">{{
                item.context
              }}</span>
              <span v-if="item.shortcut" class="sr-only">{{ item.shortcut }}</span>
            </CommandItem>
          </CommandGroup>
        </template>

        <template v-else-if="confirmItem">
          <div class="px-3 py-4 text-sm">
            <p class="font-medium">{{ t(`${confirmItem.type}s.tree.delete_title`) }}</p>
            <p class="mt-1 text-muted-foreground">
              {{ t(`${confirmItem.type}s.tree.delete_description`, { name: confirmItem.label }) }}
            </p>
          </div>
          <CommandGroup>
            <CommandItem
              value="palette.confirm-delete"
              class="text-destructive"
              :disabled="pendingMutation"
              @select="confirmDelete"
            >
              <Trash2 class="size-4 shrink-0" />
              <span>{{ t(`${confirmItem.type}s.tree.delete`) }}</span>
            </CommandItem>
            <CommandItem value="palette.cancel-delete" :disabled="pendingMutation" @select="goBack">
              <span>{{ t("common.cancel") }}</span>
            </CommandItem>
          </CommandGroup>
        </template>
      </CommandList>
    </div>
  </CommandDialog>
</template>
