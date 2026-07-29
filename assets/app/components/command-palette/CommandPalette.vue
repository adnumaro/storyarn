<script setup lang="ts">
import {
  ArrowLeft,
  Building2,
  CircleHelp,
  FileText,
  Folder,
  GitBranch,
  History,
  LoaderCircle,
  Map as MapIcon,
  Play,
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
  isAIPaletteCommand,
  runAICommandCta,
  runAIPaletteCommand,
  type AICommandContext,
  type AICommandCta,
} from "@shared/command-palette/aiCommands";
import { openAIDestination } from "@shared/command-palette/aiDestinationRouter";
import {
  paletteGroups,
  primarySurface,
  type PaletteCommand,
} from "@shared/command-palette/registry";
import {
  firstMissingRequiredParameterId,
  nextOperationParameterId,
  operationParameter,
  operationReady,
  operationSearchText,
  type OperationCompletionSource,
  type OperationDefinition,
  type OperationErrors,
  type OperationParameterDefinition,
  type OperationValue,
  type OperationValues,
} from "@shared/command-palette/operationCatalog";
import { liveNavigate } from "@shared/navigation/liveNavigate";
import type { PaletteLookupResult } from "@shared/command-palette/lookupResults";
import { classifyReferencePattern } from "@plugins/expression-editor/reference-pattern";
import PaletteEmpty from "./PaletteEmpty.vue";
import PaletteLookupResults from "./PaletteLookupResults.vue";
import PaletteOperationInput from "./PaletteOperationInput.vue";

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

interface OperationOptionsReply {
  token?: number;
  items?: OperationValue[];
  truncated?: boolean;
  error?: string;
}

interface RawLookupResult {
  id: string;
  kind: string;
  type: string;
  label: string;
  context?: string | null;
  url: string;
  meta?: Record<string, unknown>;
}

interface LookupReply {
  token?: number;
  items?: RawLookupResult[];
  truncated?: boolean;
  error?: string;
}

interface OperationAvailability {
  enabled: boolean;
  reasonKey?: string;
}

// The palette is a small state machine: the root page plus the multi-step
// create/delete flows and the catalog-backed guided door. Every step happens
// INSIDE the palette; Escape or Backspace-at-the-template-start walks back.
type PaletteStep =
  | { kind: "root" }
  | { kind: "operation"; operationId: string }
  | { kind: "lookup-results"; operationId: string }
  | { kind: "create-pick-project"; entityType: EntityType }
  | { kind: "delete-pick-entity" }
  | {
      kind: "delete-confirm";
      item: DeleteItem;
      source: "legacy" | "operation";
      operationId?: string;
    };

type DeleteConfirmStep = Extract<PaletteStep, { kind: "delete-confirm" }>;

const NAV_DEBOUNCE_MS = 200;
const MUTATION_TIMEOUT_MS = 15_000;
const RECENT_OPERATIONS_KEY = "storyarn.command-palette.recent-operations.v1";
const MAX_RECENT_OPERATIONS = 5;
const LOOKUP_OPERATION_IDS = new Set([
  "variable_definition",
  "variable_usages",
  "entity_usages",
  "flow_callers",
]);

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
  unavailable: "palette.operation_unavailable.project_context",
  lookup_failed: "palette.lookup_failed",
};

const lookupKindLabelKeys: Record<string, string> = {
  definition: "palette.lookup_kinds.definition",
  read: "palette.lookup_kinds.read",
  write: "palette.lookup_kinds.write",
  formula_read: "palette.lookup_kinds.formula_read",
  entity_usage: "palette.lookup_kinds.entity_usage",
  flow_caller: "palette.lookup_kinds.flow_caller",
};

function navGroupHeading(key: string): string | undefined {
  const labelKey = navGroupLabelKeys[key];
  return labelKey ? t(labelKey) : undefined;
}

const { t } = useI18n();
const live = useLive();
const { operationCatalog = [], projectContext = false } = defineProps<{
  operationCatalog?: OperationDefinition[];
  projectContext?: boolean;
}>();

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
const activeAICta = ref<{ cta: AICommandCta; context: AICommandContext } | null>(null);
const paletteBody = ref<HTMLElement | null>(null);
const operationInput = ref<InstanceType<typeof PaletteOperationInput> | null>(null);
const operationValues = ref<OperationValues>({});
const operationErrors = ref<OperationErrors>({});
const activeParameterId = ref<string | null>(null);
const operationOptions = ref<OperationValue[]>([]);
const operationOptionsLoading = ref(false);
const operationOptionsErrorKey = ref<string | null>(null);
const lookupResults = ref<PaletteLookupResult[]>([]);
const lookupLoading = ref(false);
const lookupErrorKey = ref<string | null>(null);
const lookupTruncated = ref(false);
const recentOperationIds = ref<string[]>([]);
const activeGuidedOperationId = ref<string | null>(null);
const lookupResultsList = ref<InstanceType<typeof PaletteLookupResults> | null>(null);

// Stale-reply guard: only the latest request may update the results.
let navToken = 0;
let createTargetsToken = 0;
let operationOptionsToken = 0;
let lookupToken = 0;
// Mutation replies are checked against this separately from navToken (typing
// must never invalidate an in-flight create/delete). The palette cannot close
// while one is pending, so every accepted mutation reply is reconciled.
let mutationToken = 0;
let retryExecution: { key: string; id: string } | null = null;
let navDebounce: ReturnType<typeof setTimeout> | null = null;
let mutationTimeout: ReturnType<typeof setTimeout> | null = null;
let suppressQueryWatch = false;
let rootComposing = false;
let compositionFetchPending = false;

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

const lookupStep = computed(() => (step.value.kind === "lookup-results" ? step.value : null));

const referencePattern = computed(() => classifyReferencePattern(query.value));
const patternDoorActive = computed(() => referencePattern.value.state !== "normal");
const remoteLookupMode = computed(
  () =>
    step.value.kind === "lookup-results" || (step.value.kind === "root" && patternDoorActive.value),
);

const activeOperation = computed<OperationDefinition | null>(() => {
  const current = step.value;
  if (current.kind !== "operation") return null;
  return operationCatalog.find((operation) => operation.id === current.operationId) ?? null;
});

const operationGroups = computed(() => {
  const grouped = new Map<string, OperationDefinition[]>();

  for (const operation of operationCatalog) {
    const existing = grouped.get(operation.domain);
    if (existing) {
      existing.push(operation);
    } else {
      grouped.set(operation.domain, [operation]);
    }
  }

  return Array.from(grouped, ([domain, operations]) => ({ domain, operations }));
});

const recentOperations = computed(() =>
  recentOperationIds.value.flatMap((operationId) => {
    const operation = operationCatalog.find((candidate) => candidate.id === operationId);
    return operation ? [operation] : [];
  }),
);

const showHelpIntro = computed(() => {
  const normalized = query.value.trim().toLocaleLowerCase();
  if (normalized === "") return true;

  return t("palette.help_keywords")
    .split(/\s+/)
    .some((keyword) => keyword.toLocaleLowerCase() === normalized);
});

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

// Reka emits `select` before consulting its reactive disabled state, while its
// list item DOM memo may still expose stale attributes. Every in-flight action
// therefore treats the handler-level busy guard as the authoritative fence.
const busy = computed(() => pendingMutation.value || pendingCommandId.value !== null);

const canMutate = computed(
  () =>
    createTargetsLoaded.value &&
    !createTargetsLoading.value &&
    !createTargetsErrorKey.value &&
    createTargets.value.length > 0,
);

function editOperationAvailability(): OperationAvailability {
  if (!createTargetsLoaded.value && createTargetsLoading.value) {
    return {
      enabled: false,
      reasonKey: "palette.operation_unavailable.checking",
    };
  }

  if (createTargetsErrorKey.value) {
    return {
      enabled: false,
      reasonKey: "palette.operation_unavailable.availability_failed",
    };
  }

  return canMutate.value
    ? { enabled: true }
    : {
        enabled: false,
        reasonKey: "palette.operation_unavailable.edit_content",
      };
}

function contextualOperationAvailability(operation: OperationDefinition): OperationAvailability {
  if (operation.authorization !== "contextual") return { enabled: true };

  const contextualParameter = operation.parameters.find(
    (parameter) =>
      parameter.completionMode === "client" &&
      (parameter.completionSource === "commands" || parameter.completionSource === "views"),
  );
  if (!contextualParameter) return { enabled: true };

  const contextualOptions = localOperationOptions(contextualParameter.completionSource);
  if (contextualOptions.length > 0) {
    return { enabled: true };
  }

  return {
    enabled: false,
    reasonKey:
      contextualParameter.completionSource === "commands"
        ? "palette.operation_unavailable.commands"
        : "palette.operation_unavailable.views",
  };
}

function resolveOperationAvailability(operation: OperationDefinition): OperationAvailability {
  if (LOOKUP_OPERATION_IDS.has(operation.id) && !projectContext) {
    return {
      enabled: false,
      reasonKey: "palette.operation_unavailable.project_context",
    };
  }

  if (operation.authorization === "edit_content") {
    return editOperationAvailability();
  }

  return contextualOperationAvailability(operation);
}

const operationAvailabilityById = computed(
  () =>
    new Map<string, OperationAvailability>(
      operationCatalog.map(
        (operation) => [operation.id, resolveOperationAvailability(operation)] as const,
      ),
    ),
);

function operationAvailability(operation: OperationDefinition): OperationAvailability {
  return (
    operationAvailabilityById.value.get(operation.id) ?? resolveOperationAvailability(operation)
  );
}

function operationAvailabilityKey(operation: OperationDefinition): string {
  const availability = operationAvailability(operation);
  return `${availability.enabled ? "enabled" : "disabled"}:${availability.reasonKey ?? "ready"}`;
}

function operationAvailable(operation: OperationDefinition): boolean {
  return operationAvailability(operation).enabled;
}

function operationUnavailableReason(operation: OperationDefinition): string | undefined {
  const reasonKey = operationAvailability(operation).reasonKey;
  return reasonKey ? t(reasonKey) : undefined;
}

const activeErrorKey = computed<string | null>(() => {
  if (errorKey.value) return errorKey.value;

  switch (step.value.kind) {
    case "root":
      return patternDoorActive.value ? lookupErrorKey.value : navErrorKey.value;
    case "operation":
      return operationOptionsErrorKey.value;
    case "lookup-results":
      return lookupErrorKey.value;
    case "create-pick-project":
      return createTargetsErrorKey.value;
    case "delete-pick-entity":
      return deleteItemsErrorKey.value;
    case "delete-confirm":
      return null;
  }

  return null;
});

const operationEmptyMessageKey = computed(() =>
  activeOperation.value?.id === "delete" && query.value.trim() === ""
    ? "palette.no_deletable_content"
    : "palette.no_operation_options",
);

const activeLoading = computed(() => {
  switch (step.value.kind) {
    case "root":
      return patternDoorActive.value ? lookupLoading.value : navLoading.value;
    case "operation":
      return operationOptionsLoading.value;
    case "lookup-results":
      return lookupLoading.value;
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

watch(query, handleQueryChange);

function handleQueryChange(): void {
  if (suppressQueryWatch) {
    suppressQueryWatch = false;
    return;
  }

  if (!open.value) return;

  errorKey.value = null;
  activeAICta.value = null;
  clearActiveOperationValueForEdit();

  // Typing immediately invalidates any in-flight request — a reply for the
  // previous query must never land after the user has kept typing.
  ++navToken;
  ++operationOptionsToken;
  ++lookupToken;
  if (navDebounce) clearTimeout(navDebounce);

  if (step.value.kind === "root" && (rootComposing || compositionFetchPending)) {
    navLoading.value = false;
    lookupLoading.value = false;
    return;
  }

  if (prepareStepForQueryChange()) return;

  // Client-backed operation completions returned above without a timer.
  // Server-backed completions use the same measured cadence as root search
  // so typing cannot amplify the authorized 1+N lookup path.
  navDebounce = setTimeout(() => fetchForStep(), NAV_DEBOUNCE_MS);
}

function clearActiveOperationValueForEdit(): void {
  if (step.value.kind !== "operation" || query.value === "") return;

  const parameterId = activeParameterId.value;
  if (!parameterId || !operationValues.value[parameterId]) return;

  operationValues.value = { ...operationValues.value, [parameterId]: null };
  const { [parameterId]: _removed, ...remainingErrors } = operationErrors.value;
  operationErrors.value = remainingErrors;
}

function prepareStepForQueryChange(): boolean {
  switch (step.value.kind) {
    case "root":
      return prepareRootForQueryChange();
    case "operation":
      return prepareOperationForQueryChange();
    case "delete-pick-entity":
      deleteItemsLoading.value = true;
      deleteItemsErrorKey.value = null;
      return false;
    default:
      return false;
  }
}

function prepareRootForQueryChange(): boolean {
  const classification = referencePattern.value;

  if (classification.state === "normal") {
    if (activeGuidedOperationId.value === "variable_definition") {
      abandonActiveOperation();
    }
    resetLookupState();
    navLoading.value = true;
    navErrorKey.value = null;
    return false;
  }

  navLoading.value = false;
  navErrorKey.value = null;
  navGroups.value = [];
  lookupErrorKey.value = null;

  if (classification.state !== "ready") {
    lookupLoading.value = false;
    lookupResults.value = [];
    lookupTruncated.value = false;
    return true;
  }

  lookupLoading.value = true;
  return false;
}

function prepareOperationForQueryChange(): boolean {
  operationOptionsErrorKey.value = null;

  const parameter = activeOperationParameter();
  const usesServer = parameter?.completionMode === "server";
  operationOptionsLoading.value = usesServer;

  if (!parameter || usesServer) return false;

  fetchOperationOptions();
  return true;
}

function onRootCompositionStart(): void {
  if (step.value.kind !== "root") return;

  rootComposing = true;
  compositionFetchPending = false;
  ++navToken;
  ++lookupToken;
  if (navDebounce) clearTimeout(navDebounce);
}

function onRootCompositionEnd(): void {
  if (step.value.kind !== "root") return;

  rootComposing = false;
  compositionFetchPending = true;

  void nextTick(() => {
    if (!compositionFetchPending || !open.value || step.value.kind !== "root") return;
    compositionFetchPending = false;
    handleQueryChange();
  });
}

onUnmounted(() => {
  if (navDebounce) clearTimeout(navDebounce);
  clearMutationTimeout();
});

function openPalette(): void {
  activeGuidedOperationId.value = null;
  recentOperationIds.value = loadRecentOperationIds();
  navGroups.value = [];
  createTargets.value = [];
  deleteItems.value = [];
  errorKey.value = null;
  navErrorKey.value = null;
  createTargetsErrorKey.value = null;
  deleteItemsErrorKey.value = null;
  activeAICta.value = null;
  resetOperationState();
  resetLookupState();
  createTargetsLoaded.value = false;
  rootComposing = false;
  compositionFetchPending = false;
  step.value = { kind: "root" };
  open.value = true;
  focusPaletteInput();
  fetchNavDestinations();
  fetchCreateTargets();
  track("palette_opened", {});
}

function closePalette(): void {
  if (busy.value) return;

  abandonActiveOperation();
  open.value = false;
  // Reset on CLOSE, not open: the query watcher ignores changes while
  // closed, so reopening never invalidates the immediate initial fetch.
  resetQuery();
  step.value = { kind: "root" };
  errorKey.value = null;
  activeAICta.value = null;
  resetOperationState();
  resetLookupState();
  ++mutationToken;
  ++createTargetsToken;
  ++operationOptionsToken;
  ++lookupToken;
}

function startMutationTimeout(token: number): void {
  clearMutationTimeout();
  mutationTimeout = setTimeout(() => {
    if (token !== mutationToken) return;

    // Invalidate a reply that may arrive after the client has already offered
    // a retry. The stable execution ID is deliberately kept so the durable
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
  activeAICta.value = null;
  ++mutationToken;
  ++navToken;
  ++operationOptionsToken;
  ++lookupToken;
  if (navDebounce) clearTimeout(navDebounce);
  resetQuery();

  if (next.kind === "create-pick-project" && !createTargetsLoaded.value) {
    fetchCreateTargets();
  } else if (next.kind !== "create-pick-project" && next.kind !== "lookup-results") {
    fetchForStep();
  }

  focusPaletteInput();
}

function focusPaletteInput(): void {
  void nextTick(() => {
    if (step.value.kind === "operation") {
      operationInput.value?.focusActive();
    } else if (step.value.kind !== "lookup-results") {
      paletteBody.value?.querySelector<HTMLInputElement>("[data-slot='command-input']")?.focus();
    }
  });
}

function goBack(): void {
  const current = step.value;
  if (current.kind === "root") return;

  if (current.kind === "delete-confirm") {
    if (current.source === "operation" && current.operationId) {
      enterStep({ kind: "operation", operationId: current.operationId });
    } else {
      enterStep({ kind: "delete-pick-entity" });
    }
  } else if (current.kind === "lookup-results") {
    resetLookupState();
    enterStep({ kind: "operation", operationId: current.operationId });
  } else {
    if (current.kind === "operation") abandonActiveOperation();
    resetOperationState();
    enterStep({ kind: "root" });
  }
}

function onPaletteKeydown(event: KeyboardEvent): void {
  if (
    step.value.kind === "root" &&
    rootImeActive(event) &&
    ["Enter", "Escape", "ArrowUp", "ArrowDown"].includes(event.key)
  ) {
    event.stopPropagation();
    return;
  }

  if (step.value.kind === "root" || step.value.kind === "operation") return;

  if (event.key === "Backspace" && query.value === "") {
    event.preventDefault();
    event.stopPropagation();
    if (!busy.value) goBack();
  }
}

// Reka owns Escape at the dismiss layer. Preventing that event is the only
// reliable way to turn Escape into one-step-back for nested palette flows.
function onDialogEscape(event: KeyboardEvent): void {
  if (step.value.kind === "root" && rootImeActive(event)) {
    event.preventDefault();
    event.stopPropagation();
    return;
  }

  if (step.value.kind === "root" && !busy.value) return;

  event.preventDefault();
  event.stopPropagation();
  if (!busy.value) goBack();
}

function rootImeActive(event: KeyboardEvent): boolean {
  return rootComposing || event.isComposing || event.keyCode === 229;
}

function fetchForStep(): void {
  const current = step.value;

  if (current.kind === "root") {
    if (referencePattern.value.state === "ready") {
      fetchReferencePattern();
    } else if (referencePattern.value.state === "normal") {
      fetchNavDestinations();
    }
  } else if (current.kind === "operation") {
    fetchOperationOptions();
  } else if (current.kind === "delete-pick-entity") {
    fetchDeleteItems();
  }
  // create-pick-project filters its already-loaded targets client-side;
  // delete-confirm has no data to fetch.
}

function fetchReferencePattern(): void {
  const classification = referencePattern.value;
  if (classification.state !== "ready") {
    lookupLoading.value = false;
    lookupResults.value = [];
    return;
  }

  if (!projectContext) {
    lookupLoading.value = false;
    lookupResults.value = [];
    lookupTruncated.value = false;
    lookupErrorKey.value = "palette.operation_unavailable.project_context";
    return;
  }

  if (activeGuidedOperationId.value !== "variable_definition") {
    activeGuidedOperationId.value = "variable_definition";
    track("palette_operation_selected", { operation_id: "variable_definition" });
  }

  const pattern = classification.pattern.raw;
  const token = ++lookupToken;
  const highlightedResultId = lookupResultsList.value?.highlightedResultId() ?? null;
  lookupLoading.value = true;
  lookupErrorKey.value = null;

  live.pushEvent(
    "palette_reference_pattern",
    { pattern, token },
    (reply: LookupReply) => {
      if (!acceptsPatternReply(token, pattern, reply)) return;

      lookupLoading.value = false;
      if (reply.error) {
        lookupResults.value = [];
        lookupTruncated.value = false;
        lookupErrorKey.value =
          reply.error === "invalid_request"
            ? "palette.pattern_invalid"
            : (errorMessageKeys[reply.error] ?? "palette.lookup_failed");
        return;
      }

      const latestHighlightedResultId =
        lookupResultsList.value?.highlightedResultId() ?? highlightedResultId;
      lookupResults.value = reconcileLookupResults(
        lookupResults.value,
        normalizeLookupResults(reply.items ?? []),
      );
      lookupTruncated.value = reply.truncated ?? false;
      completeActiveOperation();
      void restoreLookupHighlight(latestHighlightedResultId);
    },
    () => {
      if (!acceptsPatternRequest(token, pattern)) return;
      lookupLoading.value = false;
      lookupResults.value = [];
      lookupTruncated.value = false;
      lookupErrorKey.value = "palette.lookup_failed";
    },
  );
}

function acceptsPatternReply(token: number, pattern: string, reply: LookupReply): boolean {
  return reply?.token === token && acceptsPatternRequest(token, pattern);
}

function acceptsPatternRequest(token: number, pattern: string): boolean {
  const classification = referencePattern.value;

  return (
    token === lookupToken &&
    open.value &&
    step.value.kind === "root" &&
    classification.state === "ready" &&
    classification.pattern.raw === pattern
  );
}

function fetchNavDestinations(): void {
  const token = ++navToken;
  navLoading.value = true;
  navErrorKey.value = null;

  live.pushEvent(
    "palette_nav",
    { query: query.value.trim(), token },
    (reply: PaletteNavReply) => {
      if (
        reply?.token !== token ||
        token !== navToken ||
        !open.value ||
        step.value.kind !== "root"
      ) {
        return;
      }
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
      refreshEditableProjectOptions();
    },
    () => {
      if (token !== createTargetsToken || !open.value) return;
      createTargetsLoading.value = false;
      createTargetsLoaded.value = true;
      createTargets.value = [];
      createTargetsErrorKey.value = "palette.search_failed";
      refreshEditableProjectOptions();
    },
  );
}

function acceptsCreateTargetsReply(token: number, reply: CreateTargetsReply): boolean {
  const currentKind = step.value.kind;

  return (
    reply?.token === token &&
    token === createTargetsToken &&
    open.value &&
    (currentKind === "root" || currentKind === "operation" || currentKind === "create-pick-project")
  );
}

function refreshEditableProjectOptions(): void {
  const parameter = activeOperationParameter();
  if (
    step.value.kind !== "operation" ||
    parameter?.completionMode !== "client" ||
    parameter.completionSource !== "editable_projects"
  ) {
    return;
  }

  fetchOperationOptions();
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

function resetOperationState(): void {
  operationValues.value = {};
  operationErrors.value = {};
  activeParameterId.value = null;
  operationOptions.value = [];
  operationOptionsLoading.value = false;
  operationOptionsErrorKey.value = null;
}

function resetLookupState(): void {
  lookupResults.value = [];
  lookupLoading.value = false;
  lookupErrorKey.value = null;
  lookupTruncated.value = false;
}

function normalizeLookupResults(items: RawLookupResult[]): PaletteLookupResult[] {
  return items.flatMap((item) => {
    if (
      typeof item.id !== "string" ||
      typeof item.url !== "string" ||
      typeof item.label !== "string"
    ) {
      return [];
    }

    const icon: PaletteLookupResult["icon"] =
      item.type === "sheet" || item.type === "flow" || item.type === "scene"
        ? item.type
        : "reference";
    const detailKey = lookupKindLabelKeys[item.kind];

    return [
      {
        id: item.id,
        url: item.url,
        label: item.label,
        context: typeof item.context === "string" ? item.context : undefined,
        detail: detailKey ? t(detailKey) : undefined,
        icon,
      },
    ];
  });
}

function reconcileLookupResults(
  current: PaletteLookupResult[],
  incoming: PaletteLookupResult[],
): PaletteLookupResult[] {
  const incomingById = new Map(incoming.map((result) => [result.id, result]));
  const retained = current.flatMap((result) => {
    const updated = incomingById.get(result.id);
    if (!updated) return [];
    incomingById.delete(result.id);
    return [updated];
  });
  const appended = incoming.filter((result) => incomingById.has(result.id));

  return [...retained, ...appended];
}

async function restoreLookupHighlight(resultId: string | null): Promise<void> {
  await nextTick();

  if (!open.value || lookupResults.value.length === 0) return;
  await lookupResultsList.value?.restoreHighlightedResult(resultId);
}

function activeOperationParameter(): OperationParameterDefinition | undefined {
  const operation = activeOperation.value;
  const parameterId = activeParameterId.value;
  if (!operation || !parameterId) return undefined;
  return operationParameter(operation, parameterId);
}

function fetchOperationOptions(): void {
  const operation = activeOperation.value;
  const parameter = activeOperationParameter();
  if (!operation || !parameter) {
    operationOptions.value = [];
    operationOptionsLoading.value = false;
    return;
  }

  operationOptionsErrorKey.value = null;

  if (parameter.completionMode === "client") {
    fetchClientOperationOptions(parameter.completionSource);
    return;
  }

  const token = ++operationOptionsToken;
  const operationId = operation.id;
  const parameterId = parameter.id;
  const highlightedOptionId = operationInput.value?.highlightedOptionId() ?? null;
  operationOptionsLoading.value = true;

  live.pushEvent(
    "palette_operation_options",
    {
      operation_id: operationId,
      parameter_id: parameterId,
      query: query.value.trim(),
      token,
    },
    (reply: OperationOptionsReply) => {
      if (
        reply?.token !== token ||
        !acceptsOperationOptionsRequest(token, operationId, parameterId)
      ) {
        return;
      }

      operationOptionsLoading.value = false;
      if (reply.error) {
        operationOptions.value = [];
        operationOptionsErrorKey.value = "palette.operation_options_failed";
        return;
      }

      const latestHighlightedOptionId =
        operationInput.value?.highlightedOptionId() ?? highlightedOptionId;
      operationOptions.value = reconcileOperationOptions(operationOptions.value, reply.items ?? []);
      void restoreOperationHighlight(latestHighlightedOptionId);
    },
    () => {
      if (!acceptsOperationOptionsRequest(token, operationId, parameterId)) {
        return;
      }

      operationOptionsLoading.value = false;
      operationOptions.value = [];
      operationOptionsErrorKey.value = "palette.operation_options_failed";
    },
  );
}

function acceptsOperationOptionsRequest(
  token: number,
  operationId: string,
  parameterId: string,
): boolean {
  const currentStep = step.value;

  return (
    token === operationOptionsToken &&
    open.value &&
    currentStep.kind === "operation" &&
    currentStep.operationId === operationId &&
    activeParameterId.value === parameterId
  );
}

function fetchClientOperationOptions(source: OperationCompletionSource): void {
  if (source === "editable_projects" && !createTargetsLoaded.value) {
    operationOptionsLoading.value = createTargetsLoading.value;
    operationOptions.value = [];
    return;
  }

  operationOptions.value = localOperationOptions(source);
  operationOptionsLoading.value = false;
  void highlightFirstOperationOption();
}

function reconcileOperationOptions(
  current: OperationValue[],
  incoming: OperationValue[],
): OperationValue[] {
  const incomingById = new Map(incoming.map((option) => [option.id, option]));
  const retained = current.flatMap((option) => {
    const updated = incomingById.get(option.id);
    if (!updated) return [];
    incomingById.delete(option.id);
    return [updated];
  });
  const appended = incoming.filter((option) => incomingById.has(option.id));

  return [...retained, ...appended];
}

async function restoreOperationHighlight(optionId: string | null): Promise<void> {
  await nextTick();

  if (!open.value || step.value.kind !== "operation" || operationOptions.value.length === 0) return;

  await operationInput.value?.restoreHighlightedOption(optionId);
}

async function highlightFirstOperationOption(): Promise<void> {
  await nextTick();

  if (!open.value || step.value.kind !== "operation" || operationOptions.value.length === 0) return;

  await operationInput.value?.highlightFirstOption();
}

function localOperationOptions(source: OperationCompletionSource): OperationValue[] {
  if (source === "entity_types") {
    return entityTypes.map((entityType) => ({
      id: `entity-type:${entityType}`,
      value: entityType,
      label: t(createLabelKeys[entityType]),
    }));
  }

  if (source === "editable_projects") {
    return createTargets.value.map((target) => ({
      id: `project:${target.id}`,
      value: target.id,
      label: target.label,
      context: target.context,
    }));
  }

  if (source !== "commands" && source !== "views") return [];

  return paletteGroups.value.flatMap((group) =>
    group.commands
      .filter((command) => {
        if (!commandEnabled(command)) return false;
        return source === "views" ? command.href !== undefined : command.href === undefined;
      })
      .map((command) => ({
        id: `command:${command.id}`,
        value: command.id,
        label: commandLabel(command),
        context: t(group.key),
        meta: { commandId: command.id },
      })),
  );
}

function enterOperation(operation: OperationDefinition): void {
  if (busy.value || step.value.kind !== "root" || !operationAvailable(operation)) return;

  if (activeGuidedOperationId.value && activeGuidedOperationId.value !== operation.id) {
    abandonActiveOperation();
  }
  activeGuidedOperationId.value = operation.id;
  track("palette_operation_selected", { operation_id: operation.id });
  resetOperationState();
  activeParameterId.value = operation.parameters[0]?.id ?? null;
  enterStep({ kind: "operation", operationId: operation.id });
}

function activateOperationParameter(parameterId: string): void {
  const operation = activeOperation.value;
  if (!operation || !operationParameter(operation, parameterId)) return;

  activeParameterId.value = parameterId;
  operationOptions.value = [];
  operationOptionsErrorKey.value = null;
  resetQuery();
  fetchOperationOptions();
  focusPaletteInput();
}

function clearOperationParameter(parameterId: string): void {
  operationValues.value = { ...operationValues.value, [parameterId]: null };
  const { [parameterId]: _removed, ...remainingErrors } = operationErrors.value;
  operationErrors.value = remainingErrors;
  activateOperationParameter(parameterId);
}

function selectOperationOption(option: OperationValue): void {
  if (busy.value || step.value.kind !== "operation") return;

  const operation = activeOperation.value;
  const parameterId = activeParameterId.value;
  if (!operation || !parameterId || !operationParameter(operation, parameterId)) return;

  // Accepting a value is a state boundary: neither an in-flight reply nor a
  // debounce queued for the previous query may repopulate and auto-highlight
  // options after the selection has been committed.
  ++operationOptionsToken;
  if (navDebounce) {
    clearTimeout(navDebounce);
    navDebounce = null;
  }
  operationOptionsLoading.value = false;

  operationValues.value = { ...operationValues.value, [parameterId]: option };
  const { [parameterId]: _removed, ...remainingErrors } = operationErrors.value;
  operationErrors.value = remainingErrors;
  operationOptions.value = [];
  resetQuery();

  const nextParameterId = nextOperationParameterId(operation, parameterId);
  if (nextParameterId) {
    activeParameterId.value = nextParameterId;
    fetchOperationOptions();
  }

  focusPaletteInput();
}

function cancelOperation(): void {
  if (busy.value) return;
  abandonActiveOperation();
  resetOperationState();
  enterStep({ kind: "root" });
}

function submitOperation(): void {
  const operation = activeOperation.value;
  if (!operation || busy.value) return;

  if (query.value.trim() !== "") {
    if (activeParameterId.value) activateOperationParameter(activeParameterId.value);
    return;
  }

  const missingParameterId = firstMissingRequiredParameterId(operation, operationValues.value);
  if (missingParameterId) {
    activateOperationParameter(missingParameterId);
    return;
  }

  executeOperation(operation);
}

function completeActiveOperation(): void {
  const operationId = activeGuidedOperationId.value;
  if (!operationId) return;

  rememberOperation(operationId);
  track("palette_operation_completed", { operation_id: operationId });
  activeGuidedOperationId.value = null;
}

function abandonActiveOperation(): void {
  const operationId = activeGuidedOperationId.value;
  if (!operationId) return;

  track("palette_operation_abandoned", { operation_id: operationId });
  activeGuidedOperationId.value = null;
}

function loadRecentOperationIds(): string[] {
  try {
    const parsed: unknown = JSON.parse(localStorage.getItem(RECENT_OPERATIONS_KEY) ?? "[]");
    if (!Array.isArray(parsed)) return [];

    const knownIds = new Set(operationCatalog.map((operation) => operation.id));
    return parsed
      .filter((id): id is string => typeof id === "string" && knownIds.has(id))
      .slice(0, MAX_RECENT_OPERATIONS);
  } catch {
    return [];
  }
}

function rememberOperation(operationId: string): void {
  const next = [
    operationId,
    ...recentOperationIds.value.filter((candidate) => candidate !== operationId),
  ].slice(0, MAX_RECENT_OPERATIONS);

  recentOperationIds.value = next;
  try {
    // Operation IDs are the only persisted value. Parameters, queries and
    // authored content never leave the in-memory interaction.
    localStorage.setItem(RECENT_OPERATIONS_KEY, JSON.stringify(next));
  } catch {
    // Storage can be unavailable in strict browser modes; recents are optional.
  }
}

function executeOperation(operation: OperationDefinition): void {
  operationExecutors[operation.id]?.();
}

const operationExecutors: Readonly<Record<string, () => void>> = {
  goto: executeGotoOperation,
  variable_definition: () => executeReferenceOperation("variable_definition", "variable"),
  variable_usages: () => executeReferenceOperation("variable_usages", "variable"),
  entity_usages: () => executeReferenceOperation("entity_usages", "entity"),
  flow_callers: () => executeReferenceOperation("flow_callers", "flow"),
  create: executeCreateOperation,
  delete: executeDeleteOperation,
  run_command: () => runSelectedClientCommand("command"),
  open_view: () => runSelectedClientCommand("destination"),
};

function executeGotoOperation(): void {
  const destination = operationValues.value.destination;
  if (typeof destination?.value !== "string") {
    invalidateOperationParameter("destination");
    return;
  }

  runNavigationCommand(destination.id, destination.value, completeActiveOperation);
}

function executeReferenceOperation(operationId: string, parameterId: string): void {
  const target = operationRecord(operationValues.value[parameterId]);
  if (!target || !projectContext) {
    invalidateOperationParameter(parameterId);
    return;
  }

  if (activeGuidedOperationId.value !== operationId) {
    activeGuidedOperationId.value = operationId;
    track("palette_operation_selected", { operation_id: operationId });
  }

  resetLookupState();
  enterStep({ kind: "lookup-results", operationId });
  const token = ++lookupToken;
  lookupLoading.value = true;

  live.pushEvent(
    "palette_reference_lookup",
    {
      operation_id: operationId,
      target,
      token,
    },
    (reply: LookupReply) => {
      if (!acceptsLookupReply(token, operationId, reply)) return;

      lookupLoading.value = false;
      if (reply.error) {
        handleReferenceOperationError(operationId, parameterId, reply.error);
        return;
      }

      lookupResults.value = reconcileLookupResults(
        lookupResults.value,
        normalizeLookupResults(reply.items ?? []),
      );
      lookupTruncated.value = reply.truncated ?? false;
      completeActiveOperation();
      void restoreLookupHighlight(null);
    },
    () => {
      if (!acceptsLookupRequest(token, operationId)) return;
      lookupLoading.value = false;
      lookupResults.value = [];
      lookupTruncated.value = false;
      lookupErrorKey.value = "palette.lookup_failed";
    },
  );
}

function acceptsLookupReply(token: number, operationId: string, reply: LookupReply): boolean {
  return reply?.token === token && acceptsLookupRequest(token, operationId);
}

function acceptsLookupRequest(token: number, operationId: string): boolean {
  const current = step.value;

  return (
    token === lookupToken &&
    open.value &&
    current.kind === "lookup-results" &&
    current.operationId === operationId
  );
}

function handleReferenceOperationError(
  operationId: string,
  parameterId: string,
  replyError: string,
): void {
  lookupResults.value = [];
  lookupTruncated.value = false;

  if (!["unauthorized", "not_found", "invalid_request", "unavailable"].includes(replyError)) {
    lookupErrorKey.value = errorMessageKeys[replyError] ?? "palette.lookup_failed";
    return;
  }

  operationErrors.value = {
    ...operationErrors.value,
    [parameterId]: t(errorMessageKeys[replyError] ?? "palette.invalid_request"),
  };
  activeParameterId.value = parameterId;
  enterStep({ kind: "operation", operationId });
}

function onSelectLookupResult(result: PaletteLookupResult): void {
  if (busy.value || lookupLoading.value) return;

  track("palette_command_executed", { command_id: "reference.open" });
  closePalette();
  liveNavigate(result.url);
}

function executeCreateOperation(): void {
  const entityType = operationValues.value.entity_type?.value;
  const project = operationValues.value.project;

  if (!validEntityType(entityType)) {
    invalidateOperationParameter("entity_type");
    return;
  }

  if (typeof project?.value !== "number") {
    invalidateOperationParameter("project");
    return;
  }

  createEntity(entityType, {
    id: project.value,
    label: project.label,
    context: project.context,
  });
}

function executeDeleteOperation(): void {
  const item = deleteItemFromOperationValue(operationValues.value.entity);
  if (!item) {
    invalidateOperationParameter("entity");
    return;
  }

  enterStep({
    kind: "delete-confirm",
    item,
    source: "operation",
    operationId: "delete",
  });
}

function invalidateOperationParameter(parameterId: string): void {
  operationErrors.value = {
    ...operationErrors.value,
    [parameterId]: t("palette.not_found"),
  };
  activateOperationParameter(parameterId);
}

function deleteItemFromOperationValue(value: OperationValue | null | undefined): DeleteItem | null {
  if (!value) return null;

  const raw = operationRecord(value);
  if (!raw) return null;

  const type = raw.type;
  const id = raw.id;
  const projectId = raw.projectId;
  if (!validEntityType(type) || typeof id !== "number" || typeof projectId !== "number")
    return null;

  return {
    id,
    type,
    label: value.label,
    context: value.context,
    shortcut: typeof value.meta?.shortcut === "string" ? value.meta.shortcut : null,
    projectId,
  };
}

function operationRecord(value: OperationValue | null | undefined): Record<string, unknown> | null {
  if (!value || typeof value.value !== "object" || value.value === null) return null;
  return Array.isArray(value.value) ? null : value.value;
}

function validEntityType(value: unknown): value is EntityType {
  return typeof value === "string" && entityTypes.includes(value as EntityType);
}

function operationOptionSearchText(option: OperationValue): string {
  const shortcut = typeof option.meta?.shortcut === "string" ? option.meta.shortcut : undefined;
  return [option.label, option.context, shortcut].filter(Boolean).join(" ");
}

function runSelectedClientCommand(parameterId: string): void {
  const selected = operationValues.value[parameterId];
  if (typeof selected?.value !== "string") {
    invalidateOperationParameter(parameterId);
    return;
  }

  const command = paletteGroups.value
    .flatMap((group) => group.commands)
    .find((candidate) => candidate.id === selected.value && commandEnabled(candidate));

  if (!command) {
    invalidateOperationParameter(parameterId);
    return;
  }

  onSelect(command, completeActiveOperation);
}

// A failing command keeps the palette open with an explicit error. Promise
// handlers remain pending until they settle and are tracked only on success.
async function runActionCommand(
  commandId: string,
  run: () => void | Promise<void>,
  onSuccess?: () => void,
): Promise<void> {
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
  onSuccess?.();
  pendingCommandId.value = null;
  closePalette();
}

async function runPaletteAICommand(command: PaletteCommand, onSuccess?: () => void): Promise<void> {
  if (busy.value || !isAIPaletteCommand(command)) return;

  errorKey.value = null;
  activeAICta.value = null;
  pendingCommandId.value = command.id;

  const result = await runAIPaletteCommand(command, { open: openAIDestination });
  pendingCommandId.value = null;

  if (result.status === "completed") {
    track("palette_command_executed", { command_id: command.id });
    onSuccess?.();
    closePalette();
    return;
  }

  if (result.status === "destination_failed") {
    track("palette_command_executed", { command_id: command.id });
    onSuccess?.();
    errorKey.value = result.reasonKey;
    return;
  }

  errorKey.value = result.reasonKey;
  if (result.status === "blocked" && result.cta) {
    activeAICta.value = { cta: result.cta, context: command.context };
  }
}

async function runActiveAICta(): Promise<void> {
  if (busy.value || !activeAICta.value) return;

  const { cta, context } = activeAICta.value;
  errorKey.value = null;
  pendingCommandId.value = `cta:${cta.labelKey}`;

  const result = await runAICommandCta(cta, context, { open: openAIDestination });
  pendingCommandId.value = null;

  if (result.status === "completed") {
    activeAICta.value = null;
    closePalette();
    return;
  }

  errorKey.value = result.reasonKey;
  if (result.status === "blocked" && result.cta) {
    activeAICta.value = { cta: result.cta, context };
  }
}

function onSelect(command: PaletteCommand, onSuccess?: () => void): void {
  if (isAIPaletteCommand(command)) {
    void runPaletteAICommand(command, onSuccess);
  } else if (command.href !== undefined) {
    runNavigationCommand(command.id, command.href, onSuccess);
  } else {
    void runActionCommand(command.id, command.run, onSuccess);
  }
}

function commandEnabled(command: PaletteCommand): boolean {
  if (isAIPaletteCommand(command)) {
    return command.availability.state === "ready" || command.availability.state === "cta";
  }

  return command.enabled?.() !== false;
}

function commandDisabledReasonKey(command: PaletteCommand): string | undefined {
  if (isAIPaletteCommand(command)) {
    return command.availability.state === "blocked" ? command.availability.reasonKey : undefined;
  }

  return command.disabledReasonKey;
}

function onSelectNav(item: NavItem): void {
  runNavigationCommand(item.id, item.url);
}

// Navigation tears down the current LiveView. Send telemetry first, while
// the socket is still connected, then close and navigate synchronously.
function runNavigationCommand(commandId: string, url: string, onSuccess?: () => void): void {
  if (busy.value) return;

  errorKey.value = null;
  track("palette_command_executed", { command_id: commandId });
  onSuccess?.();
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

  createEntity(current.entityType, target);
}

function createEntity(entityType: EntityType, target: CreateTarget): void {
  if (pendingMutation.value) return;

  const guidedOperation = step.value.kind === "operation";
  const executionKey = `create:${entityType}:${target.id}`;
  errorKey.value = null;
  pendingMutation.value = true;
  const token = ++mutationToken;
  startMutationTimeout(token);

  // useLive's pushEvent never throws — transport failures arrive through the
  // onError callback, which must clear the pending state or the palette
  // would be stuck unclickable.
  live.pushEvent(
    "palette_create",
    { type: entityType, project_id: target.id, execution_id: executionIdFor(executionKey) },
    (reply: MutationReply) => {
      if (!settleMutation(token)) return;
      finishExecution(executionKey);
      const url = reply?.url;
      if (url) {
        runNavigationCommand(
          `create.${entityType}`,
          url,
          guidedOperation ? completeActiveOperation : undefined,
        );
      } else {
        const replyError = reply?.error ?? "";
        if (guidedOperation && ["unauthorized", "not_found"].includes(replyError)) {
          invalidateOperationParameter("project");
        } else {
          errorKey.value = errorMessageKeys[replyError] ?? "palette.command_failed";
        }
      }
    },
    () => {
      if (!settleMutation(token)) return;
      errorKey.value = "palette.command_failed";
    },
  );
}

function onSelectDeleteItem(item: DeleteItem): void {
  enterStep({ kind: "delete-confirm", item, source: "legacy" });
}

function confirmDelete(): void {
  const current = step.value;
  if (current.kind !== "delete-confirm" || pendingMutation.value) return;

  const item = current.item;
  const executionKey = `delete:${item.type}:${item.projectId}:${item.id}`;
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
      execution_id: executionIdFor(executionKey),
    },
    (reply: MutationReply) => {
      if (!settleMutation(token)) return;
      finishExecution(executionKey);
      handleDeleteReply(reply, current, item);
    },
    () => {
      if (!settleMutation(token)) return;
      errorKey.value = "palette.command_failed";
    },
  );
}

function handleDeleteReply(
  reply: MutationReply,
  current: DeleteConfirmStep,
  item: DeleteItem,
): void {
  if (reply?.deleted) {
    handleDeleteSuccess(current, item);
    return;
  }

  handleDeleteFailure(reply?.error ?? "", current);
}

function handleDeleteSuccess(current: DeleteConfirmStep, item: DeleteItem): void {
  track("palette_command_executed", { command_id: `delete.${item.type}` });
  if (current.source === "operation") {
    completeActiveOperation();
    closePalette();
    return;
  }

  // Drop the stale listing BEFORE showing it again: the deleted entity must
  // never reappear as selectable while the refresh is in flight.
  deleteItems.value = [];
  enterStep({ kind: "delete-pick-entity" });
}

function handleDeleteFailure(replyError: string, current: DeleteConfirmStep): void {
  const shouldReturnToOperation =
    current.source === "operation" &&
    !!current.operationId &&
    ["unauthorized", "not_found"].includes(replyError);

  if (!shouldReturnToOperation) {
    errorKey.value = errorMessageKeys[replyError] ?? "palette.command_failed";
    return;
  }

  operationErrors.value = {
    ...operationErrors.value,
    entity: t(errorMessageKeys[replyError] ?? "palette.not_found"),
  };
  activeParameterId.value = "entity";
  enterStep({ kind: "operation", operationId: current.operationId! });
}

function onNoResults(queryLength: number): void {
  track("palette_search_no_results", { query_length: queryLength });
}

function commandLabel(command: PaletteCommand): string {
  if (command.label !== undefined) return command.label;
  return t(command.labelKey);
}

function createExecutionId(): string {
  if (typeof globalThis.crypto?.randomUUID === "function") {
    return globalThis.crypto.randomUUID();
  }

  return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function executionIdFor(key: string): string {
  if (retryExecution?.key === key) return retryExecution.id;

  const id = createExecutionId();
  retryExecution = { key, id };
  return id;
}

function finishExecution(key: string): void {
  if (retryExecution?.key === key) retryExecution = null;
}

// Analytics is fire-and-forget. useLive owns transport failures and never
// throws them into the interaction that emitted the event.
function track(event: string, payload: Record<string, unknown>): void {
  live.pushEvent(event, { ...payload, surface: primarySurface.value });
}
</script>

<template>
  <CommandDialog
    v-model:open="localOpen"
    :title="t('palette.title')"
    :description="t('palette.description')"
    :disable-filter="remoteLookupMode"
    @escape-key-down="onDialogEscape"
  >
    <div ref="paletteBody" class="contents" @keydown="onPaletteKeydown">
      <CommandInput
        v-if="!confirmItem && !activeOperation && !lookupStep"
        :key="inputKey"
        v-model="query"
        :disabled="busy"
        :placeholder="inputPlaceholder"
        :aria-label="inputPlaceholder"
        @compositionstart="onRootCompositionStart"
        @compositionend="onRootCompositionEnd"
      />
      <PaletteOperationInput
        v-else-if="activeOperation"
        ref="operationInput"
        v-model:query="query"
        :definition="activeOperation"
        :values="operationValues"
        :errors="operationErrors"
        :active-parameter="activeParameterId"
        :disabled="busy"
        @activate="activateOperationParameter"
        @clear="clearOperationParameter"
        @cancel="cancelOperation"
        @submit="submitOperation"
      />
      <div
        v-else-if="lookupStep"
        class="flex items-center gap-2 border-b px-3 py-2"
        data-testid="palette-lookup-header"
      >
        <button
          type="button"
          class="rounded-md p-1 text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/40"
          :aria-label="t('palette.back_to_operation')"
          :disabled="busy"
          @click="goBack"
        >
          <ArrowLeft class="size-4" />
        </button>
        <p class="min-w-0 flex-1 truncate text-sm font-medium">
          {{ t("palette.lookup_results") }}
        </p>
      </div>
      <div
        v-if="activeErrorKey"
        role="alert"
        class="flex items-center justify-between gap-3 border-b px-3 py-2 text-sm text-destructive"
      >
        <span>{{ t(activeErrorKey) }}</span>
        <button
          v-if="activeAICta"
          type="button"
          class="shrink-0 rounded-md px-2 py-1 text-xs font-medium transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/40 disabled:pointer-events-none disabled:opacity-50"
          :disabled="busy"
          @click="runActiveAICta"
        >
          {{ t(activeAICta.cta.labelKey) }}
        </button>
      </div>
      <p
        v-if="activeLoading"
        role="status"
        class="flex items-center justify-center gap-2 border-b px-3 py-2 text-sm text-muted-foreground"
      >
        <LoaderCircle class="size-4 animate-spin" />
        {{ t("palette.loading") }}
      </p>
      <CommandList>
        <template v-if="activeOperation">
          <PaletteEmpty
            :enabled="!operationOptionsLoading && !operationOptionsErrorKey"
            @no-results="onNoResults"
          >
            {{ t(operationEmptyMessageKey) }}
          </PaletteEmpty>
          <p
            v-if="
              !operationOptionsLoading &&
              !operationOptionsErrorKey &&
              query.trim() === '' &&
              operationOptions.length === 0 &&
              !operationReady(activeOperation, operationValues, operationErrors)
            "
            class="py-6 text-center text-sm text-muted-foreground"
          >
            {{ t(operationEmptyMessageKey) }}
          </p>
          <CommandGroup
            v-if="operationOptions.length > 0"
            :heading="
              activeParameterId
                ? t(operationParameter(activeOperation, activeParameterId)?.labelKey ?? '')
                : undefined
            "
          >
            <CommandItem
              v-for="option in operationOptions"
              :key="option.id"
              :value="`operation-option-${option.id}`"
              :data-operation-option-id="option.id"
              :search-text="operationOptionSearchText(option)"
              :disabled="busy"
              @select="selectOperationOption(option)"
            >
              <span class="min-w-0 flex-1 truncate">{{ option.label }}</span>
              <span v-if="option.context" class="truncate text-xs text-muted-foreground">
                {{ option.context }}
              </span>
              <span v-if="typeof option.meta?.shortcut === 'string'" class="sr-only">
                {{ option.meta.shortcut }}
              </span>
            </CommandItem>
          </CommandGroup>
          <CommandGroup
            v-if="
              query.trim() === '' &&
              operationReady(activeOperation, operationValues, operationErrors)
            "
            :heading="t('palette.groups.actions')"
          >
            <CommandItem value="operation.execute" :disabled="busy" @select="submitOperation">
              <Play class="size-4 shrink-0" />
              <span>{{ t("palette.run_operation") }}</span>
            </CommandItem>
          </CommandGroup>
        </template>

        <template v-else-if="lookupStep">
          <PaletteLookupResults
            ref="lookupResultsList"
            :items="lookupResults"
            :heading="t('palette.lookup_results')"
            :disabled="busy || lookupLoading"
            :loading="lookupLoading"
            :truncated="lookupTruncated"
            :truncated-label="t('palette.lookup_truncated')"
            @select="onSelectLookupResult"
          />
          <p
            v-if="!lookupLoading && !lookupErrorKey && lookupResults.length === 0"
            class="py-6 text-center text-sm text-muted-foreground"
          >
            {{ t("palette.no_lookup_results") }}
          </p>
          <p v-if="lookupResults.length > 0" aria-live="polite" class="sr-only">
            {{ t("palette.lookup_results_count", { count: lookupResults.length }) }}
          </p>
        </template>

        <template v-else-if="step.kind === 'root'">
          <template v-if="patternDoorActive">
            <p
              v-if="referencePattern.state === 'incomplete'"
              class="py-6 text-center text-sm text-muted-foreground"
            >
              {{ t("palette.pattern_incomplete") }}
            </p>
            <p
              v-else-if="referencePattern.state === 'invalid'"
              class="py-6 text-center text-sm text-muted-foreground"
            >
              {{ t("palette.pattern_invalid") }}
            </p>
            <template v-else>
              <PaletteLookupResults
                ref="lookupResultsList"
                :items="lookupResults"
                :heading="t('palette.lookup_results')"
                :disabled="busy || lookupLoading"
                :loading="lookupLoading"
                :truncated="lookupTruncated"
                :truncated-label="t('palette.lookup_truncated')"
                @select="onSelectLookupResult"
              />
              <p
                v-if="!lookupLoading && !lookupErrorKey && lookupResults.length === 0"
                class="py-6 text-center text-sm text-muted-foreground"
              >
                {{ t("palette.no_lookup_results") }}
              </p>
              <p v-if="lookupResults.length > 0" aria-live="polite" class="sr-only">
                {{ t("palette.lookup_results_count", { count: lookupResults.length }) }}
              </p>
            </template>
          </template>

          <template v-else>
            <PaletteEmpty :enabled="!navLoading && !navErrorKey" @no-results="onNoResults">
              {{ t("palette.no_results") }}
            </PaletteEmpty>
            <div v-if="showHelpIntro" class="border-b px-3 py-3">
              <div class="flex items-start gap-2.5">
                <div class="rounded-md bg-primary/10 p-1.5 text-primary">
                  <CircleHelp class="size-4" />
                </div>
                <div>
                  <p class="text-sm font-medium">{{ t("palette.capabilities_title") }}</p>
                  <p class="mt-0.5 text-xs text-muted-foreground">
                    {{ t("palette.capabilities_description") }}
                  </p>
                </div>
              </div>
            </div>
            <!-- Reka's listbox item memoizes disabled and fallthrough attrs.
                 The full availability signature belongs in both operation-row
                 keys so enabled and reason changes remount the affected row. -->
            <CommandGroup
              v-if="recentOperations.length > 0"
              :heading="t('palette.recent_operations')"
            >
              <CommandItem
                v-for="operation in recentOperations"
                :key="`recent-operation-${operation.id}-${operationAvailabilityKey(operation)}`"
                :value="`recent-operation-${operation.id}`"
                :data-operation-id="operation.id"
                :data-operation-available="operationAvailable(operation)"
                :search-text="`${operationSearchText(operation, t)} ${t('palette.help_keywords')}`"
                :disabled="busy || !operationAvailable(operation)"
                :title="operationUnavailableReason(operation)"
                @select="enterOperation(operation)"
              >
                <History class="size-4 shrink-0" />
                <span class="min-w-0">
                  <span class="block">{{ t(operation.help.labelKey) }}</span>
                  <span
                    v-if="!operationAvailable(operation)"
                    class="block truncate text-xs font-normal text-muted-foreground"
                  >
                    {{ operationUnavailableReason(operation) }}
                  </span>
                </span>
              </CommandItem>
            </CommandGroup>
            <CommandGroup
              v-for="operationGroup in operationGroups"
              :key="`operations-${operationGroup.domain}`"
              :heading="t(`palette.operation_domains.${operationGroup.domain}`)"
            >
              <CommandItem
                v-for="operation in operationGroup.operations"
                :key="`operation-${operation.id}-${operationAvailabilityKey(operation)}`"
                :value="`operation-${operation.id}`"
                :data-operation-id="operation.id"
                :data-operation-available="operationAvailable(operation)"
                :search-text="`${operationSearchText(operation, t)} ${t('palette.help_keywords')}`"
                class="items-start py-2.5"
                :disabled="busy || !operationAvailable(operation)"
                :title="operationUnavailableReason(operation)"
                @select="enterOperation(operation)"
              >
                <div class="min-w-0 flex-1">
                  <div class="flex items-center justify-between gap-3">
                    <span class="font-medium">{{ t(operation.help.labelKey) }}</span>
                    <span class="shrink-0 text-xs text-muted-foreground">
                      {{ t(operation.help.exampleKey) }}
                    </span>
                  </div>
                  <p class="mt-0.5 text-xs leading-relaxed text-muted-foreground">
                    {{ t(operation.help.descriptionKey) }}
                  </p>
                  <p
                    v-if="!operationAvailable(operation)"
                    class="mt-1 text-xs font-medium text-muted-foreground"
                  >
                    {{ operationUnavailableReason(operation) }}
                  </p>
                  <p
                    v-if="operation.help.pattern"
                    class="mt-1 font-mono text-[11px] text-muted-foreground"
                  >
                    {{ operation.help.pattern }}
                  </p>
                </div>
              </CommandItem>
            </CommandGroup>
            <CommandGroup v-for="group in paletteGroups" :key="group.key" :heading="t(group.key)">
              <CommandItem
                v-for="command in group.commands"
                :key="command.id"
                :value="command.id"
                :disabled="busy || !commandEnabled(command)"
                :title="
                  !commandEnabled(command) && commandDisabledReasonKey(command)
                    ? t(commandDisabledReasonKey(command)!)
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
            {{ t("palette.no_deletable_content") }}
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
