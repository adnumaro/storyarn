<script setup lang="ts">
import {
  Building2,
  FileText,
  Folder,
  GitBranch,
  LoaderCircle,
  Map as MapIcon,
  Settings,
  Trash2,
  type LucideIcon,
} from "lucide-vue-next";
import { computed, nextTick, onUnmounted, ref, watch } from "vue";
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
const MUTATION_TIMEOUT_MS = 15_000;

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
  not_found: "palette.not_found",
  create_failed: "palette.create_failed",
  delete_failed: "palette.delete_failed",
  invalid_request: "palette.invalid_request",
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
const navErrorKey = ref<string | null>(null);
const createTargetsErrorKey = ref<string | null>(null);
const deleteItemsErrorKey = ref<string | null>(null);
const navLoading = ref(false);
const createTargetsLoading = ref(false);
const createTargetsLoaded = ref(false);
const deleteItemsLoading = ref(false);
// True while a create/delete pushEvent awaits its reply — blocks re-submits.
const pendingMutation = ref(false);
const pendingCommandId = ref<string | null>(null);
const paletteBody = ref<HTMLElement | null>(null);

// Stale-reply guard: only the latest request may update the results.
let navToken = 0;
let createTargetsToken = 0;
// Mutation replies are checked against this separately from navToken (typing
// must never invalidate an in-flight create/delete). The palette cannot close
// while one is pending, so every accepted mutation reply is reconciled.
let mutationToken = 0;
let retryOperation: { key: string; id: string } | null = null;
let navDebounce: ReturnType<typeof setTimeout> | null = null;
let mutationTimeout: ReturnType<typeof setTimeout> | null = null;
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

const inputKey = computed(() => {
  const current = step.value;
  return current.kind === "create-pick-project"
    ? `${current.kind}-${current.entityType}`
    : current.kind;
});

const busy = computed(() => pendingMutation.value || pendingCommandId.value !== null);

const canMutate = computed(
  () =>
    createTargetsLoaded.value &&
    !createTargetsLoading.value &&
    !createTargetsErrorKey.value &&
    createTargets.value.length > 0,
);

const activeErrorKey = computed<string | null>(() => {
  if (errorKey.value) return errorKey.value;

  switch (step.value.kind) {
    case "root":
      return navErrorKey.value;
    case "create-pick-project":
      return createTargetsErrorKey.value;
    case "delete-pick-entity":
      return deleteItemsErrorKey.value;
    case "delete-confirm":
      return null;
  }

  return null;
});

const activeLoading = computed(() => {
  switch (step.value.kind) {
    case "root":
      return navLoading.value;
    case "create-pick-project":
      return createTargetsLoading.value;
    case "delete-pick-entity":
      return deleteItemsLoading.value;
    case "delete-confirm":
      return pendingMutation.value;
  }

  return false;
});

useKeyboard(
  {
    "ctrl+k": () => {
      if (open.value) {
        closePalette();
      } else if (!anotherDialogOpen()) {
        openPalette();
      }
    },
  },
  {
    // The global shortcut remains suppressed in editors, but once the palette
    // owns focus the same shortcut must be able to close it.
    allowInEditable: (combo) => combo === "ctrl+k" && open.value,
  },
);

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

  if (step.value.kind === "root") {
    navLoading.value = true;
    navErrorKey.value = null;
  } else if (step.value.kind === "delete-pick-entity") {
    deleteItemsLoading.value = true;
    deleteItemsErrorKey.value = null;
  }

  navDebounce = setTimeout(() => fetchForStep(), NAV_DEBOUNCE_MS);
});

onUnmounted(() => {
  if (navDebounce) clearTimeout(navDebounce);
  clearMutationTimeout();
});

function openPalette(): void {
  navGroups.value = [];
  createTargets.value = [];
  deleteItems.value = [];
  errorKey.value = null;
  navErrorKey.value = null;
  createTargetsErrorKey.value = null;
  deleteItemsErrorKey.value = null;
  createTargetsLoaded.value = false;
  step.value = { kind: "root" };
  open.value = true;
  focusPaletteInput();
  fetchNavDestinations();
  fetchCreateTargets();
  track("palette_opened", {});
}

function closePalette(): void {
  if (busy.value) return;

  open.value = false;
  // Reset on CLOSE, not open: the query watcher ignores changes while
  // closed, so reopening never invalidates the immediate initial fetch.
  resetQuery();
  step.value = { kind: "root" };
  errorKey.value = null;
  ++mutationToken;
  ++createTargetsToken;
}

function startMutationTimeout(token: number): void {
  clearMutationTimeout();
  mutationTimeout = setTimeout(() => {
    if (token !== mutationToken) return;

    // Invalidate a reply that may arrive after the client has already offered
    // a retry. The stable operation ID is deliberately kept so the durable
    // server fence can return the original result if the first attempt landed.
    ++mutationToken;
    pendingMutation.value = false;
    errorKey.value = "palette.command_failed";
    mutationTimeout = null;
  }, MUTATION_TIMEOUT_MS);
}

function clearMutationTimeout(): void {
  if (!mutationTimeout) return;
  clearTimeout(mutationTimeout);
  mutationTimeout = null;
}

function settleMutation(token: number): boolean {
  if (token !== mutationToken) return false;

  clearMutationTimeout();
  pendingMutation.value = false;
  return true;
}

function anotherDialogOpen(): boolean {
  return document.querySelector("[data-slot='dialog-content'][data-state='open']") !== null;
}

function resetQuery(): void {
  if (query.value === "") return;
  suppressQueryWatch = true;
  query.value = "";
}

function enterStep(next: PaletteStep): void {
  if (busy.value) return;

  step.value = next;
  errorKey.value = null;
  ++mutationToken;
  ++navToken;
  if (navDebounce) clearTimeout(navDebounce);
  resetQuery();

  if (next.kind === "create-pick-project" && !createTargetsLoaded.value) {
    fetchCreateTargets();
  } else if (next.kind !== "create-pick-project") {
    fetchForStep();
  }

  focusPaletteInput();
}

function focusPaletteInput(): void {
  void nextTick(() => {
    paletteBody.value?.querySelector<HTMLInputElement>("[data-slot='command-input']")?.focus();
  });
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

function onPaletteKeydown(event: KeyboardEvent): void {
  if (step.value.kind === "root") return;

  if (event.key === "Backspace" && query.value === "") {
    event.preventDefault();
    event.stopPropagation();
    if (!busy.value) goBack();
  }
}

// Reka owns Escape at the dismiss layer. Preventing that event is the only
// reliable way to turn Escape into one-step-back for nested palette flows.
function onDialogEscape(event: KeyboardEvent): void {
  if (step.value.kind === "root" && !busy.value) return;

  event.preventDefault();
  event.stopPropagation();
  if (!busy.value) goBack();
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
  navLoading.value = true;
  navErrorKey.value = null;

  live.pushEvent(
    "palette_nav",
    { query: query.value.trim(), token },
    (reply: PaletteNavReply) => {
      if (reply?.token !== token || !open.value || step.value.kind !== "root") return;
      navLoading.value = false;
      navGroups.value = reply.groups ?? [];
    },
    () => {
      if (token !== navToken || !open.value || step.value.kind !== "root") return;
      navLoading.value = false;
      navGroups.value = [];
      navErrorKey.value = "palette.search_failed";
    },
  );
}

function fetchCreateTargets(): void {
  const token = ++createTargetsToken;
  createTargetsLoading.value = true;
  createTargetsErrorKey.value = null;

  live.pushEvent(
    "palette_create_targets",
    { token },
    (reply: CreateTargetsReply) => {
      if (!acceptsCreateTargetsReply(token, reply)) return;

      createTargetsLoading.value = false;
      createTargetsLoaded.value = true;
      createTargets.value = reply.projects ?? [];
    },
    () => {
      if (token !== createTargetsToken || !open.value) return;
      createTargetsLoading.value = false;
      createTargetsLoaded.value = true;
      createTargets.value = [];
      createTargetsErrorKey.value = "palette.search_failed";
    },
  );
}

function acceptsCreateTargetsReply(token: number, reply: CreateTargetsReply): boolean {
  const currentKind = step.value.kind;

  return (
    reply?.token === token &&
    token === createTargetsToken &&
    open.value &&
    (currentKind === "root" || currentKind === "create-pick-project")
  );
}

function fetchDeleteItems(): void {
  const token = ++navToken;
  deleteItemsLoading.value = true;
  deleteItemsErrorKey.value = null;

  live.pushEvent(
    "palette_delete_search",
    { query: query.value.trim(), token },
    (reply: DeleteSearchReply) => {
      if (reply?.token !== token || !open.value || step.value.kind !== "delete-pick-entity") {
        return;
      }
      deleteItemsLoading.value = false;
      deleteItems.value = reply.items ?? [];
    },
    () => {
      if (token !== navToken || !open.value || step.value.kind !== "delete-pick-entity") return;
      deleteItemsLoading.value = false;
      deleteItems.value = [];
      deleteItemsErrorKey.value = "palette.search_failed";
    },
  );
}

// A failing command keeps the palette open with an explicit error. Promise
// handlers remain pending until they settle and are tracked only on success.
async function runActionCommand(commandId: string, run: () => void | Promise<void>): Promise<void> {
  if (busy.value) return;

  errorKey.value = null;
  pendingCommandId.value = commandId;

  try {
    await run();
  } catch {
    pendingCommandId.value = null;
    errorKey.value = "palette.command_failed";
    return;
  }

  track("palette_command_executed", { command_id: commandId });
  pendingCommandId.value = null;
  closePalette();
}

function onSelect(command: PaletteCommand): void {
  if (command.href !== undefined) {
    runNavigationCommand(command.id, command.href);
  } else {
    void runActionCommand(command.id, command.run);
  }
}

function onSelectNav(item: NavItem): void {
  runNavigationCommand(item.id, item.url);
}

// Navigation tears down the current LiveView. Send telemetry first, while
// the socket is still connected, then close and navigate synchronously.
function runNavigationCommand(commandId: string, url: string): void {
  if (busy.value) return;

  errorKey.value = null;
  track("palette_command_executed", { command_id: commandId });
  closePalette();
  liveNavigate(url);
}

function enterCreateStep(entityType: EntityType): void {
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
  const operationKey = `create:${entityType}:${target.id}`;
  errorKey.value = null;
  pendingMutation.value = true;
  const token = ++mutationToken;
  startMutationTimeout(token);

  // useLive's pushEvent never throws — transport failures arrive through the
  // onError callback, which must clear the pending state or the palette
  // would be stuck unclickable.
  live.pushEvent(
    "palette_create",
    { type: entityType, project_id: target.id, operation_id: operationIdFor(operationKey) },
    (reply: MutationReply) => {
      if (!settleMutation(token)) return;
      finishOperation(operationKey);
      const url = reply?.url;
      if (url) {
        runNavigationCommand(`create.${entityType}`, url);
      } else {
        errorKey.value = errorMessageKeys[reply?.error ?? ""] ?? "palette.command_failed";
      }
    },
    () => {
      if (!settleMutation(token)) return;
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
  const operationKey = `delete:${item.type}:${item.projectId}:${item.id}`;
  errorKey.value = null;
  pendingMutation.value = true;
  const token = ++mutationToken;
  startMutationTimeout(token);

  // useLive's pushEvent never throws — transport failures arrive through the
  // onError callback, which must clear the pending state or the palette
  // would be stuck unclickable.
  live.pushEvent(
    "palette_delete",
    {
      type: item.type,
      id: item.id,
      project_id: item.projectId,
      operation_id: operationIdFor(operationKey),
    },
    (reply: MutationReply) => {
      if (!settleMutation(token)) return;
      finishOperation(operationKey);
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
      if (!settleMutation(token)) return;
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

function createOperationId(): string {
  if (typeof globalThis.crypto?.randomUUID === "function") {
    return globalThis.crypto.randomUUID();
  }

  return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function operationIdFor(key: string): string {
  if (retryOperation?.key === key) return retryOperation.id;

  const id = createOperationId();
  retryOperation = { key, id };
  return id;
}

function finishOperation(key: string): void {
  if (retryOperation?.key === key) retryOperation = null;
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
    @escape-key-down="onDialogEscape"
  >
    <div ref="paletteBody" class="contents" @keydown="onPaletteKeydown">
      <CommandInput
        v-if="!confirmItem"
        :key="inputKey"
        v-model="query"
        :disabled="busy"
        :placeholder="inputPlaceholder"
      />
      <p v-if="activeErrorKey" role="alert" class="border-b px-3 py-2 text-sm text-destructive">
        {{ t(activeErrorKey) }}
      </p>
      <p
        v-if="activeLoading"
        role="status"
        class="flex items-center justify-center gap-2 border-b px-3 py-2 text-sm text-muted-foreground"
      >
        <LoaderCircle class="size-4 animate-spin" />
        {{ t("palette.loading") }}
      </p>
      <CommandList>
        <template v-if="step.kind === 'root'">
          <PaletteEmpty :enabled="!navLoading && !navErrorKey" @no-results="onNoResults">
            {{ t("palette.no_results") }}
          </PaletteEmpty>
          <CommandGroup v-for="group in paletteGroups" :key="group.key" :heading="t(group.key)">
            <CommandItem
              v-for="command in group.commands"
              :key="command.id"
              :value="command.id"
              :disabled="busy || command.enabled?.() === false"
              :title="
                command.enabled?.() === false && command.disabledReasonKey
                  ? t(command.disabledReasonKey)
                  : undefined
              "
              @select="onSelect(command)"
            >
              <component :is="command.icon" v-if="command.icon" class="size-4 shrink-0" />
              <span>{{ commandLabel(command) }}</span>
              <CommandShortcut v-if="command.shortcut">{{ command.shortcut }}</CommandShortcut>
            </CommandItem>
          </CommandGroup>
          <CommandGroup v-if="canMutate" :heading="t('palette.groups.actions')">
            <CommandItem
              v-for="entityType in entityTypes"
              :key="`create.${entityType}`"
              :value="`create.${entityType}`"
              :disabled="busy"
              @select="enterCreateStep(entityType)"
            >
              <component :is="navIcons[entityType]" class="size-4 shrink-0" />
              <span>{{ t(createLabelKeys[entityType]) }}</span>
            </CommandItem>
            <CommandItem value="palette.delete-entity" :disabled="busy" @select="enterDeleteStep">
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
              :disabled="busy"
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
            v-if="!createTargetsLoading && !createTargetsErrorKey && createTargets.length === 0"
            class="py-6 text-center text-sm text-muted-foreground"
          >
            {{ t("palette.no_editable_projects") }}
          </p>
          <template v-else-if="!createTargetsErrorKey">
            <PaletteEmpty :enabled="!createTargetsLoading" @no-results="onNoResults">
              {{ t("palette.no_results") }}
            </PaletteEmpty>
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
          <PaletteEmpty
            :enabled="!deleteItemsLoading && !deleteItemsErrorKey"
            @no-results="onNoResults"
          >
            {{ t("palette.no_results") }}
          </PaletteEmpty>
          <p
            v-if="
              !deleteItemsLoading &&
              !deleteItemsErrorKey &&
              query.trim() === '' &&
              deleteItems.length === 0
            "
            class="py-6 text-center text-sm text-muted-foreground"
          >
            {{ t("palette.no_results") }}
          </p>
          <CommandGroup v-if="deleteItems.length > 0" :heading="t('palette.delete_entity')">
            <CommandItem
              v-for="item in deleteItems"
              :key="`delete-${item.type}-${item.id}`"
              :value="`delete-${item.type}-${item.id}`"
              :disabled="busy"
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
