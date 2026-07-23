<script setup lang="ts">
import {
  Building2,
  CheckCircle2,
  CircleAlert,
  Cpu,
  ExternalLink,
  Loader2,
  ShieldCheck,
} from "lucide-vue-next";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";

export interface IntegrationCardData {
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
  catalog_status:
    | "catalog_ready"
    | "ready"
    | "connection_only"
    | "model_deprecated"
    | "model_unavailable";
  models: Array<{
    provider: string;
    model: string;
    catalog_version: number;
    capabilities: string[];
    modalities: string[];
    structured_output: string;
    context_window: number | null;
    max_output_tokens: number | null;
    processing_locations: string[];
    pricing_version: number | null;
    deprecated: boolean;
  }>;
  workspace_assignments: WorkspaceAssignmentData[];
}

export interface WorkspaceAssignmentData {
  workspace_id: number;
  workspace_name: string;
  workspace_slug: string;
  role: string | null;
  assigned: boolean;
  assignment_id: number | null;
  can_assign: boolean;
  state: "available" | "assigned" | "blocked";
  reason: "owner_allowed" | "member_policy_allowed" | "member_policy_disabled";
}

const { card, assignmentPendingKey = null } = defineProps<{
  card: IntegrationCardData;
  assignmentPendingKey?: string | null;
}>();

const emit = defineEmits<{
  connect: [];
  disconnect: [];
  toggleWorkspace: [workspace: WorkspaceAssignmentData];
}>();

const { t } = useI18n();

const isConnected = computed(() => card.status === "connected");

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
  if (card.key_last_four) return t("integrations.card.key_suffix", { suffix: card.key_last_four });
  return "";
});

const assignedCount = computed(
  () => card.workspace_assignments.filter((workspace) => workspace.assigned).length,
);

function workspaceKey(workspaceId: number): string {
  return `${card.integration_id ?? "missing"}:${workspaceId}`;
}

function assignmentPending(workspaceId: number): boolean {
  return assignmentPendingKey === workspaceKey(workspaceId);
}
</script>

<template>
  <article
    v-if="isConnected"
    class="overflow-hidden rounded-xl border border-border/70 bg-card shadow-sm"
    :data-provider="card.provider"
    :data-status="card.status"
    data-layout="connected"
  >
    <header class="flex flex-col gap-4 p-5 sm:flex-row sm:items-center sm:justify-between">
      <div class="flex items-center gap-3">
        <div
          aria-hidden="true"
          class="flex size-11 items-center justify-center rounded-lg bg-muted text-sm font-semibold text-muted-foreground"
        >
          {{ initials }}
        </div>
        <div class="min-w-0">
          <h3 class="text-sm font-semibold leading-tight">{{ card.name }}</h3>
          <p class="mt-1 flex items-center gap-1.5 text-xs text-emerald-600 dark:text-emerald-400">
            <CheckCircle2 class="size-3.5 shrink-0" aria-hidden="true" />
            <span class="truncate">{{ t("integrations.card.connected_as", { identifier }) }}</span>
          </p>
        </div>
      </div>

      <div class="flex items-center gap-2 self-end sm:self-auto">
        <a
          :href="card.docs_url"
          target="_blank"
          rel="noopener noreferrer"
          data-live-link-exempt="external-provider-docs"
          class="inline-flex h-8 items-center gap-1 rounded-md px-2.5 text-xs text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
        >
          {{ t("integrations.card.docs") }}
          <ExternalLink class="size-3" aria-hidden="true" />
        </a>
        <Button variant="outline" size="sm" @click="emit('disconnect')">
          {{ t("integrations.card.disconnect") }}
        </Button>
      </div>
    </header>

    <div class="grid border-t border-border/60 lg:grid-cols-[minmax(0,0.8fr)_minmax(0,1.5fr)]">
      <section class="space-y-3 bg-muted/15 p-5">
        <div class="flex items-center gap-2 text-xs font-medium text-muted-foreground">
          <Cpu class="size-4" aria-hidden="true" />
          <h4>{{ t("integrations.card.model_status") }}</h4>
        </div>
        <div class="space-y-1">
          <p class="text-sm font-medium text-foreground">
            {{
              card.catalog_status === "ready"
                ? t("integrations.card.routing_ready")
                : t(`integrations.card.catalog_states.${card.catalog_status}`)
            }}
          </p>
          <p v-if="card.models.length > 0" class="text-xs leading-relaxed text-muted-foreground">
            {{ card.models.map((model) => model.model).join(", ") }}
          </p>
          <p v-else class="text-xs leading-relaxed text-muted-foreground">
            {{ t("integrations.card.no_executable_model") }}
          </p>
        </div>
      </section>

      <section class="space-y-3 border-t border-border/60 p-5 lg:border-l lg:border-t-0">
        <div class="flex items-start justify-between gap-4">
          <div class="space-y-1">
            <div class="flex items-center gap-2 text-xs font-medium text-muted-foreground">
              <Building2 class="size-4" aria-hidden="true" />
              <h4>{{ t("integrations.assignments.title") }}</h4>
            </div>
            <p class="text-xs leading-relaxed text-muted-foreground">
              {{ t("integrations.assignments.description") }}
            </p>
          </div>
          <span
            v-if="card.workspace_assignments.length > 0"
            class="shrink-0 rounded-full bg-muted px-2.5 py-1 text-[11px] font-medium text-muted-foreground"
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
          class="divide-y divide-border/50 overflow-hidden rounded-lg border border-border/60"
        >
          <div
            v-for="workspace in card.workspace_assignments"
            :key="workspace.workspace_id"
            class="flex items-center justify-between gap-4 bg-background/45 px-3 py-3 transition-colors hover:bg-background"
            :data-workspace-id="workspace.workspace_id"
            :data-assignment-state="workspace.state"
          >
            <div class="min-w-0">
              <p class="truncate text-xs font-medium text-foreground">
                {{ workspace.workspace_name }}
              </p>
              <p
                class="mt-0.5 flex items-center gap-1 text-[11px]"
                :class="
                  workspace.state === 'blocked'
                    ? 'text-amber-600 dark:text-amber-400'
                    : 'text-muted-foreground'
                "
              >
                <CircleAlert
                  v-if="workspace.state === 'blocked'"
                  class="size-3 shrink-0"
                  aria-hidden="true"
                />
                {{ t(`integrations.assignments.reasons.${workspace.reason}`) }}
              </p>
            </div>

            <Button
              v-if="workspace.assigned || workspace.can_assign"
              type="button"
              size="sm"
              :variant="workspace.assigned ? 'outline' : 'secondary'"
              class="h-7 shrink-0 px-2.5 text-xs"
              :disabled="assignmentPending(workspace.workspace_id)"
              @click="emit('toggleWorkspace', workspace)"
            >
              <Loader2
                v-if="assignmentPending(workspace.workspace_id)"
                class="mr-1 size-3 animate-spin"
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

        <p
          v-else
          class="rounded-lg border border-dashed border-border/60 px-3 py-4 text-xs text-muted-foreground"
        >
          {{ t("integrations.assignments.no_workspaces") }}
        </p>

        <div class="flex items-start gap-2 rounded-lg bg-muted/35 px-3 py-2.5">
          <ShieldCheck class="mt-0.5 size-3.5 shrink-0 text-muted-foreground" aria-hidden="true" />
          <p class="text-[11px] leading-relaxed text-muted-foreground">
            {{ t("integrations.assignments.consent_note") }}
          </p>
        </div>
      </section>
    </div>
  </article>

  <article
    v-else
    class="flex min-h-32 flex-col justify-between gap-4 rounded-xl border border-border/60 bg-card p-4 shadow-sm transition-all hover:border-border hover:shadow-md"
    :data-provider="card.provider"
    :data-status="card.status"
    data-layout="available"
  >
    <header class="flex items-center gap-3">
      <div
        aria-hidden="true"
        class="flex size-10 items-center justify-center rounded-lg bg-muted text-sm font-semibold text-muted-foreground"
      >
        {{ initials }}
      </div>
      <div>
        <h3 class="text-sm font-semibold leading-tight">{{ card.name }}</h3>
        <p class="mt-0.5 text-xs text-muted-foreground">
          {{ t("integrations.card.not_connected") }}
        </p>
      </div>
    </header>

    <footer class="flex items-center justify-between gap-3">
      <a
        :href="card.docs_url"
        target="_blank"
        rel="noopener noreferrer"
        data-live-link-exempt="external-provider-docs"
        class="inline-flex items-center gap-1 text-xs text-muted-foreground transition-colors hover:text-foreground hover:underline"
      >
        {{ t("integrations.card.docs") }}
        <ExternalLink class="size-3" aria-hidden="true" />
      </a>
      <Button size="sm" @click="emit('connect')">
        {{ t("integrations.card.connect") }}
      </Button>
    </footer>
  </article>
</template>
