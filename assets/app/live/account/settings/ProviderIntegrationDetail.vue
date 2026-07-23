<script setup lang="ts">
import {
  ArrowLeft,
  Building2,
  CheckCircle2,
  CircleAlert,
  Clock3,
  Cpu,
  ExternalLink,
  KeyRound,
  Loader2,
  RefreshCw,
  Search,
  ShieldCheck,
  Sparkles,
} from "lucide-vue-next";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import ConfirmDialog from "@components/ConfirmDialog.vue";
import LiveLink from "@components/navigation/LiveLink.vue";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import { useLive } from "@shared/composables/useLive";
import ConnectKeyDialog from "./integrations/ConnectKeyDialog.vue";

export interface ProviderModelData {
  provider: string;
  model: string;
  catalog_version: number;
  capabilities: string[];
  input_modalities: string[];
  output_modalities: string[];
  api_family: string;
  implementation_status: "executable" | "configuration_only";
  release_stage: "stable" | "preview";
  structured_output: string;
  context_window: number | null;
  max_output_tokens: number | null;
  processing_locations: string[];
  pricing_version: number | null;
  deprecated: boolean;
  availability?: "available" | "unavailable" | "unknown" | "deprecated";
}

export interface ProviderWorkspaceAssignmentData {
  workspace_id: number;
  workspace_name: string;
  workspace_slug: string;
  role: string | null;
  assigned: boolean;
  assignment_id: number | null;
  can_assign: boolean;
  state: "available" | "assigned" | "blocked";
  reason:
    | "owner_allowed"
    | "member_policy_allowed"
    | "member_policy_disabled"
    | "workspace_membership_required";
}

export interface ProviderPreferenceImpactData {
  workspace_id: number;
  workspace_name: string;
  workspace_slug: string;
  slot: "general_assistant" | "writing_assistant" | "illustrator" | "voice";
  model: string;
  implementation_status: "executable" | "configuration_only" | null;
  status:
    | "ready"
    | "configured"
    | "workspace_policy_denied"
    | "provider_disconnected"
    | "assignment_required"
    | "model_unavailable"
    | "model_deprecated"
    | "capability_mismatch";
}

export interface ProviderIntegrationDetailData {
  integration_id: number | null;
  provider: string;
  name: string;
  key_generation_url: string;
  docs_url: string;
  key_placeholder: string;
  status: "not_connected" | "connected";
  account_email: string | null;
  account_display_name: string | null;
  key_last_four: string | null;
  connected_at: string | null;
  last_validated_at: string | null;
  catalog_status: string;
  capabilities: string[];
  models: ProviderModelData[];
  workspace_assignments: ProviderWorkspaceAssignmentData[];
  preference_impacts?: ProviderPreferenceImpactData[];
}

interface EventReply {
  status?: string;
  error?: string;
}

const { card, providersPath = "/users/settings/integrations" } = defineProps<{
  card: ProviderIntegrationDetailData;
  providersPath?: string;
}>();

const { locale, t, te } = useI18n();
const live = useLive();

const credentialMode = ref<"connect" | "replace" | null>(null);
const credentialPending = ref(false);
const revalidatePending = ref(false);
const disconnectOpen = ref(false);
const disconnectPending = ref(false);
const pendingAssignments = ref(new Set<number>());
const searchQuery = ref("");
const inlineError = ref<string | null>(null);
const successMessage = ref<string | null>(null);

let credentialSeq = 0;
let revalidateSeq = 0;
let disconnectSeq = 0;
const assignmentSequences = new Map<number, number>();

const connected = computed(() => card.status === "connected");

const initials = computed(() =>
  card.name
    .split(/\s+/)
    .map((part) => part.charAt(0).toUpperCase())
    .join("")
    .slice(0, 2),
);

const identifier = computed(() => {
  if (card.account_email) return card.account_email;
  if (card.account_display_name) return card.account_display_name;
  if (card.key_last_four) {
    return t("integrations.card.key_suffix", { suffix: card.key_last_four });
  }
  return t("integrations.card.personal_connection");
});

const assignedCount = computed(
  () => card.workspace_assignments.filter((workspace) => workspace.assigned).length,
);

const filteredWorkspaces = computed(() => {
  const query = searchQuery.value.trim().toLocaleLowerCase(locale.value);

  return [...card.workspace_assignments]
    .sort((left, right) => {
      if (left.assigned !== right.assigned) return left.assigned ? -1 : 1;
      return left.workspace_name.localeCompare(right.workspace_name, locale.value);
    })
    .filter((workspace) => {
      if (!query) return true;
      return workspace.workspace_name.toLocaleLowerCase(locale.value).includes(query);
    });
});

const orderedModels = computed(() =>
  [...card.models].sort((left, right) => {
    if (left.implementation_status !== right.implementation_status) {
      return left.implementation_status === "executable" ? -1 : 1;
    }

    const statusOrder = { available: 0, unknown: 1, unavailable: 2, deprecated: 3 };
    const leftStatus = modelAvailability(left);
    const rightStatus = modelAvailability(right);
    const statusDifference = statusOrder[leftStatus] - statusOrder[rightStatus];
    if (statusDifference) return statusDifference;

    if (left.release_stage !== right.release_stage) {
      return left.release_stage === "stable" ? -1 : 1;
    }

    return left.model.localeCompare(right.model);
  }),
);

const compatibleModelCount = computed(
  () =>
    card.models.filter(
      (model) =>
        model.implementation_status === "executable" && modelAvailability(model) === "available",
    ).length,
);

const orderedPreferenceImpacts = computed(() =>
  [...(card.preference_impacts ?? [])].sort((left, right) => {
    const leftHealthy = preferenceHealthy(left.status);
    const rightHealthy = preferenceHealthy(right.status);

    if (leftHealthy !== rightHealthy) {
      return leftHealthy ? 1 : -1;
    }

    return (
      left.workspace_name.localeCompare(right.workspace_name, locale.value) ||
      left.slot.localeCompare(right.slot)
    );
  }),
);

const disconnectTitle = computed(() => t("integrations.disconnect.title", { name: card.name }));

const disconnectDescription = computed(() =>
  t("integrations.disconnect.description", { name: card.name }),
);

function modelAvailability(
  model: ProviderModelData,
): "available" | "unavailable" | "unknown" | "deprecated" {
  if (model.deprecated || model.availability === "deprecated") return "deprecated";
  return model.availability ?? "unknown";
}

function preferenceHealthy(status: ProviderPreferenceImpactData["status"]): boolean {
  return status === "ready" || status === "configured";
}

function formatCapability(capability: string): string {
  const key = `integrations.capabilities.${capability}`;
  if (te(key)) return t(key);
  return capability.replaceAll("_", " ");
}

function formatDate(value: string | null): string {
  if (!value) return t("integrations.detail.never");

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return t("integrations.detail.unknown_date");

  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function clearMessages(): void {
  inlineError.value = null;
  successMessage.value = null;
}

function openCredentialDialog(mode: "connect" | "replace"): void {
  clearMessages();
  credentialSeq += 1;
  credentialMode.value = mode;
}

function closeCredentialDialog(): void {
  if (credentialPending.value) return;
  credentialSeq += 1;
  credentialMode.value = null;
}

function submitCredential(apiKey: string, onResult: (errorCode: string | null) => void): void {
  const mode = credentialMode.value;
  if (!mode) {
    onResult("no_target");
    return;
  }

  const seq = ++credentialSeq;
  credentialPending.value = true;

  live.pushEvent(
    mode === "connect" ? "connect" : "replace_key",
    { provider: card.provider, api_key: apiKey },
    (reply: EventReply) => {
      if (seq !== credentialSeq) return;
      credentialPending.value = false;

      if (reply?.status === "ok") {
        credentialMode.value = null;
        successMessage.value =
          mode === "connect"
            ? "integrations.detail.connection_saved"
            : "integrations.detail.key_replaced";
        onResult(null);
      } else {
        onResult(reply?.error ?? "unknown_error");
      }
    },
    () => {
      if (seq !== credentialSeq) return;
      credentialPending.value = false;
      onResult("connection_lost");
    },
  );
}

function revalidate(): void {
  if (!connected.value || revalidatePending.value) return;

  const seq = ++revalidateSeq;
  clearMessages();
  revalidatePending.value = true;

  live.pushEvent(
    "revalidate",
    { provider: card.provider },
    (reply: EventReply) => {
      if (seq !== revalidateSeq) return;
      revalidatePending.value = false;
      if (reply?.status === "ok") {
        successMessage.value = "integrations.detail.revalidated";
      } else {
        inlineError.value = reply?.error ?? "unknown_error";
      }
    },
    () => {
      if (seq !== revalidateSeq) return;
      revalidatePending.value = false;
      inlineError.value = "connection_lost";
    },
  );
}

function toggleWorkspace(workspace: ProviderWorkspaceAssignmentData): void {
  if (!connected.value || (!workspace.assigned && !workspace.can_assign)) return;

  const workspaceId = workspace.workspace_id;
  const seq = (assignmentSequences.get(workspaceId) ?? 0) + 1;
  assignmentSequences.set(workspaceId, seq);
  pendingAssignments.value = new Set(pendingAssignments.value).add(workspaceId);
  clearMessages();

  live.pushEvent(
    workspace.assigned ? "unassign_workspace" : "assign_workspace",
    { workspace_id: workspaceId },
    (reply: EventReply) => {
      if (!finishWorkspaceAssignment(workspaceId, seq)) return;
      if (reply?.status !== "ok") {
        inlineError.value = reply?.error ?? "unknown_error";
      }
    },
    () => {
      if (!finishWorkspaceAssignment(workspaceId, seq)) return;
      inlineError.value = "connection_lost";
    },
  );
}

function finishWorkspaceAssignment(workspaceId: number, seq: number): boolean {
  if (assignmentSequences.get(workspaceId) !== seq) return false;

  const nextPending = new Set(pendingAssignments.value);
  nextPending.delete(workspaceId);
  pendingAssignments.value = nextPending;
  return true;
}

function confirmDisconnect(): void {
  const seq = ++disconnectSeq;
  clearMessages();
  disconnectPending.value = true;

  live.pushEvent(
    "disconnect",
    { provider: card.provider },
    (reply: EventReply) => {
      if (seq !== disconnectSeq) return;
      disconnectPending.value = false;
      if (reply?.status === "ok") {
        disconnectOpen.value = false;
        successMessage.value = "integrations.detail.disconnected";
      } else {
        inlineError.value = reply?.error ?? "unknown_error";
      }
    },
    () => {
      if (seq !== disconnectSeq) return;
      disconnectPending.value = false;
      inlineError.value = "connection_lost";
    },
  );
}

function cancelDisconnect(): void {
  if (disconnectPending.value) return;
  disconnectSeq += 1;
  disconnectOpen.value = false;
}
</script>

<template>
  <div id="provider-integration-detail" class="space-y-7" :data-provider="card.provider">
    <LiveLink
      id="back-to-integrations"
      :to="providersPath"
      class="inline-flex items-center gap-1.5 text-xs font-medium text-muted-foreground transition-colors hover:text-foreground"
    >
      <ArrowLeft class="size-3.5" aria-hidden="true" />
      {{ t("integrations.detail.back") }}
    </LiveLink>

    <header class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
      <div class="flex min-w-0 items-start gap-3">
        <div
          class="flex size-12 shrink-0 items-center justify-center rounded-xl bg-muted text-sm font-semibold text-muted-foreground"
          aria-hidden="true"
        >
          {{ initials }}
        </div>
        <div class="min-w-0">
          <div class="flex flex-wrap items-center gap-2">
            <h1 class="text-2xl font-bold tracking-tight text-foreground">{{ card.name }}</h1>
            <span
              :class="[
                'inline-flex items-center gap-1 rounded-full px-2 py-1 text-[11px] font-medium',
                connected
                  ? 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-300'
                  : 'bg-muted text-muted-foreground',
              ]"
            >
              <CheckCircle2 v-if="connected" class="size-3" aria-hidden="true" />
              {{ t(connected ? "integrations.card.connected" : "integrations.card.not_connected") }}
            </span>
          </div>
          <p class="mt-1 max-w-2xl text-sm leading-relaxed text-muted-foreground">
            {{ t("integrations.detail.description", { name: card.name }) }}
          </p>
        </div>
      </div>

      <a
        :href="card.docs_url"
        target="_blank"
        rel="noopener noreferrer"
        data-live-link-exempt="external-provider-docs"
        class="inline-flex h-8 shrink-0 items-center gap-1.5 self-start rounded-md px-2.5 text-xs font-medium text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
      >
        {{ t("integrations.card.docs") }}
        <ExternalLink class="size-3" aria-hidden="true" />
      </a>
    </header>

    <div
      v-if="inlineError"
      role="alert"
      class="flex items-start gap-2 rounded-lg border border-destructive/35 bg-destructive/5 px-3 py-2.5 text-sm text-destructive"
    >
      <CircleAlert class="mt-0.5 size-4 shrink-0" aria-hidden="true" />
      {{ t(`integrations.errors.${inlineError}`, t("integrations.errors.unknown_error")) }}
    </div>

    <div
      v-if="successMessage"
      role="status"
      class="flex items-start gap-2 rounded-lg border border-emerald-500/30 bg-emerald-500/5 px-3 py-2.5 text-sm text-emerald-700 dark:text-emerald-300"
    >
      <CheckCircle2 class="mt-0.5 size-4 shrink-0" aria-hidden="true" />
      {{ t(successMessage) }}
    </div>

    <section
      id="provider-connection"
      class="overflow-hidden rounded-xl border border-border/70 bg-card shadow-sm"
      aria-labelledby="provider-connection-title"
    >
      <div class="flex items-center gap-2 border-b border-border/60 px-5 py-4">
        <KeyRound class="size-4 text-muted-foreground" aria-hidden="true" />
        <h2 id="provider-connection-title" class="text-sm font-semibold">
          {{ t("integrations.detail.connection.title") }}
        </h2>
      </div>

      <div
        v-if="connected"
        class="flex flex-col gap-5 p-5 lg:flex-row lg:items-center lg:justify-between"
      >
        <div class="min-w-0 space-y-2">
          <p class="truncate text-sm font-medium text-foreground">{{ identifier }}</p>
          <div class="flex flex-wrap gap-x-5 gap-y-1 text-xs text-muted-foreground">
            <span class="inline-flex items-center gap-1.5">
              <Clock3 class="size-3.5" aria-hidden="true" />
              {{
                t("integrations.detail.connection.connected_at", {
                  date: formatDate(card.connected_at),
                })
              }}
            </span>
            <span class="inline-flex items-center gap-1.5">
              <ShieldCheck class="size-3.5" aria-hidden="true" />
              {{
                t("integrations.detail.connection.validated_at", {
                  date: formatDate(card.last_validated_at),
                })
              }}
            </span>
          </div>
        </div>

        <div class="flex flex-wrap gap-2">
          <Button
            id="revalidate-provider"
            type="button"
            variant="outline"
            size="sm"
            :disabled="revalidatePending"
            @click="revalidate"
          >
            <Loader2 v-if="revalidatePending" class="size-3.5 animate-spin" aria-hidden="true" />
            <RefreshCw v-else class="size-3.5" aria-hidden="true" />
            {{ t("integrations.detail.connection.revalidate") }}
          </Button>
          <Button
            id="replace-provider-key"
            type="button"
            variant="secondary"
            size="sm"
            @click="openCredentialDialog('replace')"
          >
            <KeyRound class="size-3.5" aria-hidden="true" />
            {{ t("integrations.detail.connection.replace") }}
          </Button>
        </div>
      </div>

      <div v-else class="flex flex-col gap-4 p-5 sm:flex-row sm:items-center sm:justify-between">
        <div class="max-w-xl">
          <p class="text-sm font-medium text-foreground">
            {{ t("integrations.detail.connection.not_connected_title") }}
          </p>
          <p class="mt-1 text-xs leading-relaxed text-muted-foreground">
            {{ t("integrations.detail.connection.not_connected_description") }}
          </p>
        </div>
        <Button
          id="connect-provider"
          type="button"
          size="sm"
          @click="openCredentialDialog('connect')"
        >
          <KeyRound class="size-3.5" aria-hidden="true" />
          {{ t("integrations.card.connect") }}
        </Button>
      </div>
    </section>

    <section id="provider-models" class="space-y-4" aria-labelledby="provider-models-title">
      <div class="flex flex-col items-start justify-between gap-3 sm:flex-row sm:items-end">
        <div class="space-y-1">
          <h2 id="provider-models-title" class="text-sm font-semibold text-foreground">
            {{ t("integrations.detail.models.title") }}
          </h2>
          <p class="text-xs leading-relaxed text-muted-foreground">
            {{ t("integrations.detail.models.description") }}
          </p>
        </div>
        <span
          class="shrink-0 rounded-full bg-muted px-2.5 py-1 text-[11px] font-medium text-muted-foreground"
        >
          {{
            t("integrations.detail.models.compatible_count", {
              count: compatibleModelCount,
            })
          }}
        </span>
      </div>

      <div
        v-if="orderedModels.length > 0"
        class="divide-y divide-border/50 overflow-hidden rounded-xl border border-border/70 bg-card"
        role="list"
      >
        <div
          v-for="model in orderedModels"
          :key="model.model"
          class="flex flex-col gap-3 px-4 py-3.5 sm:flex-row sm:items-center sm:justify-between"
          :data-model="model.model"
          :data-model-availability="modelAvailability(model)"
          :data-model-implementation="model.implementation_status"
          :data-model-release-stage="model.release_stage"
          role="listitem"
        >
          <div class="min-w-0">
            <p class="truncate text-sm font-medium text-foreground" :title="model.model">
              {{ model.model }}
            </p>
            <div v-if="model.capabilities.length > 0" class="mt-1.5 flex flex-wrap gap-1.5">
              <span
                v-for="capability in model.capabilities"
                :key="capability"
                class="rounded-md bg-muted px-1.5 py-0.5 text-[10px] text-muted-foreground"
              >
                {{ formatCapability(capability) }}
              </span>
            </div>
            <p
              v-if="model.implementation_status === 'configuration_only'"
              class="mt-2 max-w-xl text-[11px] leading-relaxed text-sky-700 dark:text-sky-300"
            >
              {{ t("integrations.detail.models.configuration_only_description") }}
            </p>
          </div>
          <div class="flex w-fit shrink-0 flex-wrap items-center gap-1.5">
            <span
              v-if="model.release_stage === 'preview'"
              class="inline-flex items-center gap-1 rounded-full bg-violet-500/10 px-2 py-1 text-[11px] font-medium text-violet-700 dark:text-violet-300"
            >
              <Sparkles class="size-3" aria-hidden="true" />
              {{ t("integrations.detail.models.release_stage.preview") }}
            </span>
            <span
              :class="[
                'inline-flex w-fit items-center rounded-full px-2 py-1 text-[11px] font-medium',
                model.implementation_status === 'executable'
                  ? 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-300'
                  : 'bg-sky-500/10 text-sky-700 dark:text-sky-300',
              ]"
            >
              {{ t(`integrations.detail.models.implementation.${model.implementation_status}`) }}
            </span>
            <span
              :class="[
                'inline-flex w-fit items-center rounded-full px-2 py-1 text-[11px] font-medium',
                modelAvailability(model) === 'available'
                  ? 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-300'
                  : modelAvailability(model) === 'unknown'
                    ? 'bg-muted text-muted-foreground'
                    : 'bg-amber-500/10 text-amber-700 dark:text-amber-300',
              ]"
            >
              {{ t(`integrations.detail.models.status.${modelAvailability(model)}`) }}
            </span>
          </div>
        </div>
      </div>

      <div
        v-else
        class="flex items-start gap-3 rounded-xl border border-dashed border-border/70 bg-muted/10 p-4"
      >
        <Cpu class="mt-0.5 size-4 shrink-0 text-muted-foreground" aria-hidden="true" />
        <p class="text-xs leading-relaxed text-muted-foreground">
          {{ t("integrations.detail.models.empty") }}
        </p>
      </div>
    </section>

    <section
      v-if="orderedPreferenceImpacts.length > 0"
      id="provider-role-impacts"
      class="space-y-4"
      aria-labelledby="provider-role-impacts-title"
    >
      <div class="space-y-1">
        <h2 id="provider-role-impacts-title" class="text-sm font-semibold text-foreground">
          {{ t("integrations.detail.impacts.title") }}
        </h2>
        <p class="text-xs leading-relaxed text-muted-foreground">
          {{ t("integrations.detail.impacts.description") }}
        </p>
      </div>

      <div
        class="divide-y divide-border/50 overflow-hidden rounded-xl border border-border/70 bg-card"
        role="list"
      >
        <div
          v-for="impact in orderedPreferenceImpacts"
          :key="`${impact.workspace_id}:${impact.slot}`"
          class="flex flex-col gap-3 px-4 py-3.5 sm:flex-row sm:items-center sm:justify-between"
          :data-impact-workspace="impact.workspace_id"
          :data-impact-slot="impact.slot"
          :data-impact-status="impact.status"
          :data-impact-implementation="impact.implementation_status"
          role="listitem"
        >
          <div class="min-w-0">
            <p class="text-xs font-medium text-foreground">
              {{ t(`integrations.team.slots.${impact.slot}.title`) }}
              <span class="font-normal text-muted-foreground">· {{ impact.workspace_name }}</span>
            </p>
            <p class="mt-1 truncate text-[11px] text-muted-foreground">{{ impact.model }}</p>
            <p
              v-if="impact.status === 'configured'"
              class="mt-1.5 flex items-start gap-1.5 text-[11px] leading-relaxed text-sky-700 dark:text-sky-300"
            >
              <Sparkles class="mt-0.5 size-3 shrink-0" aria-hidden="true" />
              {{ t("integrations.team.configuration_only.saved_description") }}
            </p>
            <p
              v-else-if="!preferenceHealthy(impact.status)"
              class="mt-1.5 flex items-start gap-1.5 text-[11px] leading-relaxed text-amber-700 dark:text-amber-300"
            >
              <CircleAlert class="mt-0.5 size-3 shrink-0" aria-hidden="true" />
              {{ t(`integrations.team.repairs.${impact.status}`) }}
            </p>
          </div>
          <span
            :class="[
              'inline-flex w-fit shrink-0 items-center rounded-full px-2 py-1 text-[11px] font-medium',
              impact.status === 'ready'
                ? 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-300'
                : impact.status === 'configured'
                  ? 'bg-sky-500/10 text-sky-700 dark:text-sky-300'
                  : 'bg-amber-500/10 text-amber-700 dark:text-amber-300',
            ]"
          >
            {{ t(`integrations.team.status.${impact.status}`) }}
          </span>
        </div>
      </div>
    </section>

    <section
      v-if="connected"
      id="provider-workspaces"
      class="space-y-4"
      aria-labelledby="provider-workspaces-title"
    >
      <div class="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div class="space-y-1">
          <h2 id="provider-workspaces-title" class="text-sm font-semibold text-foreground">
            {{ t("integrations.assignments.title") }}
          </h2>
          <p class="max-w-xl text-xs leading-relaxed text-muted-foreground">
            {{ t("integrations.assignments.description") }}
          </p>
        </div>
        <span
          v-if="card.workspace_assignments.length > 0"
          class="w-fit shrink-0 rounded-full bg-muted px-2.5 py-1 text-[11px] font-medium text-muted-foreground"
        >
          {{
            t("integrations.assignments.summary", {
              assigned: assignedCount,
              total: card.workspace_assignments.length,
            })
          }}
        </span>
      </div>

      <div
        v-if="card.workspace_assignments.length > 0"
        class="overflow-hidden rounded-xl border border-border/70 bg-card"
      >
        <div class="border-b border-border/60 p-3">
          <div class="relative">
            <Search
              class="pointer-events-none absolute left-3 top-1/2 size-3.5 -translate-y-1/2 text-muted-foreground"
              aria-hidden="true"
            />
            <Input
              id="workspace-assignment-search"
              v-model="searchQuery"
              type="search"
              size="sm"
              class="pl-9"
              :aria-label="t('integrations.assignments.search')"
              :placeholder="t('integrations.assignments.search')"
            />
          </div>
        </div>

        <div
          v-if="filteredWorkspaces.length > 0"
          class="max-h-96 divide-y divide-border/50 overflow-y-auto"
        >
          <div
            v-for="workspace in filteredWorkspaces"
            :key="workspace.workspace_id"
            class="flex items-center justify-between gap-4 px-4 py-3.5 transition-colors hover:bg-muted/20"
            :data-workspace-id="workspace.workspace_id"
            :data-assignment-state="workspace.state"
          >
            <div class="flex min-w-0 items-start gap-3">
              <div
                :class="[
                  'mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-lg',
                  workspace.assigned
                    ? 'bg-primary/10 text-primary'
                    : 'bg-muted text-muted-foreground',
                ]"
              >
                <Building2 class="size-3.5" aria-hidden="true" />
              </div>
              <div class="min-w-0">
                <p class="truncate text-xs font-medium text-foreground">
                  {{ workspace.workspace_name }}
                </p>
                <p
                  :class="[
                    'mt-0.5 flex items-center gap-1 text-[11px]',
                    workspace.state === 'blocked'
                      ? 'text-amber-600 dark:text-amber-400'
                      : 'text-muted-foreground',
                  ]"
                >
                  <CircleAlert
                    v-if="workspace.state === 'blocked'"
                    class="size-3 shrink-0"
                    aria-hidden="true"
                  />
                  {{ t(`integrations.assignments.reasons.${workspace.reason}`) }}
                </p>
              </div>
            </div>

            <Button
              v-if="workspace.assigned || workspace.can_assign"
              type="button"
              size="sm"
              :variant="workspace.assigned ? 'outline' : 'secondary'"
              class="h-7 shrink-0 px-2.5 text-xs"
              :aria-label="
                t(
                  workspace.assigned
                    ? 'integrations.assignments.disable_for_workspace'
                    : 'integrations.assignments.enable_for_workspace',
                  { workspace: workspace.workspace_name },
                )
              "
              :disabled="pendingAssignments.has(workspace.workspace_id)"
              @click="toggleWorkspace(workspace)"
            >
              <Loader2
                v-if="pendingAssignments.has(workspace.workspace_id)"
                class="size-3 animate-spin"
                aria-hidden="true"
              />
              {{
                workspace.assigned
                  ? t("integrations.assignments.remove")
                  : t("integrations.assignments.allow")
              }}
            </Button>
            <span v-else class="shrink-0 text-[11px] font-medium text-muted-foreground">
              {{ t("integrations.assignments.blocked") }}
            </span>
          </div>
        </div>

        <p v-else class="px-4 py-8 text-center text-xs text-muted-foreground">
          {{ t("integrations.assignments.no_search_results") }}
        </p>

        <div class="flex items-start gap-2 border-t border-border/60 bg-muted/20 px-4 py-3">
          <ShieldCheck class="mt-0.5 size-3.5 shrink-0 text-muted-foreground" aria-hidden="true" />
          <p class="text-[11px] leading-relaxed text-muted-foreground">
            {{ t("integrations.assignments.consent_note") }}
          </p>
        </div>
      </div>

      <p
        v-else
        class="rounded-xl border border-dashed border-border/70 px-4 py-6 text-xs text-muted-foreground"
      >
        {{ t("integrations.assignments.no_workspaces") }}
      </p>
    </section>

    <section
      v-if="connected"
      id="provider-danger-zone"
      class="flex flex-col gap-4 rounded-xl border border-destructive/25 bg-destructive/[0.025] p-4 sm:flex-row sm:items-center sm:justify-between"
    >
      <div>
        <h2 class="text-sm font-semibold text-foreground">
          {{ t("integrations.detail.disconnect.title") }}
        </h2>
        <p class="mt-1 max-w-xl text-xs leading-relaxed text-muted-foreground">
          {{ t("integrations.detail.disconnect.description") }}
        </p>
      </div>
      <Button
        id="disconnect-provider"
        type="button"
        variant="destructive"
        size="sm"
        class="self-start sm:self-auto"
        @click="disconnectOpen = true"
      >
        {{ t("integrations.card.disconnect") }}
      </Button>
    </section>

    <ConnectKeyDialog
      v-if="credentialMode"
      :open="!!credentialMode"
      :card="card"
      :mode="credentialMode"
      :submitting="credentialPending"
      @submit="submitCredential"
      @cancel="closeCredentialDialog"
    />

    <ConfirmDialog
      v-model:open="disconnectOpen"
      :title="disconnectTitle"
      :description="disconnectDescription"
      :confirm-text="t('integrations.disconnect.confirm')"
      :cancel-text="t('integrations.disconnect.cancel')"
      variant="destructive"
      @confirm="confirmDisconnect"
      @cancel="cancelDisconnect"
    />
  </div>
</template>
