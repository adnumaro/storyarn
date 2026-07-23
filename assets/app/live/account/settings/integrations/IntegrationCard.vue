<script setup lang="ts">
import {
  Building2,
  CheckCircle2,
  ChevronDown,
  CircleAlert,
  Cpu,
  ExternalLink,
  Loader2,
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
    class="flex flex-col gap-4 rounded-xl border border-border/60 bg-card p-4 shadow-sm transition-all hover:border-border hover:shadow-md"
    :data-provider="card.provider"
    :data-status="card.status"
  >
    <header class="flex items-start justify-between gap-3">
      <div class="flex items-center gap-3">
        <div
          aria-hidden="true"
          class="flex size-10 items-center justify-center rounded-md bg-muted text-sm font-semibold text-muted-foreground"
        >
          {{ initials }}
        </div>
        <div>
          <h2 class="text-sm font-semibold leading-tight">{{ card.name }}</h2>
          <p
            v-if="isConnected"
            class="mt-0.5 flex items-center gap-1 text-xs text-emerald-600 dark:text-emerald-400"
          >
            <CheckCircle2 class="size-3" aria-hidden="true" />
            <span>{{ t("integrations.card.connected_as", { identifier }) }}</span>
          </p>
          <p v-else class="mt-0.5 text-xs text-muted-foreground">
            {{ t("integrations.card.not_connected") }}
          </p>
        </div>
      </div>
    </header>

    <section v-if="isConnected" class="space-y-3 border-t border-border/50 pt-3">
      <div class="flex items-start gap-2.5">
        <Cpu class="mt-0.5 size-4 shrink-0 text-muted-foreground" aria-hidden="true" />
        <div class="min-w-0">
          <p class="text-xs font-medium text-foreground">
            {{
              card.catalog_status === "ready"
                ? t("integrations.card.routing_ready")
                : t(`integrations.card.catalog_states.${card.catalog_status}`)
            }}
          </p>
          <p v-if="card.models.length > 0" class="mt-0.5 truncate text-xs text-muted-foreground">
            {{ card.models.map((model) => model.model).join(", ") }}
          </p>
          <p v-else class="mt-0.5 text-xs text-muted-foreground">
            {{ t("integrations.card.no_executable_model") }}
          </p>
        </div>
      </div>

      <details
        v-if="card.workspace_assignments.length > 0"
        class="group rounded-lg border border-border/50 bg-muted/20"
      >
        <summary
          class="flex cursor-pointer list-none items-center justify-between gap-3 px-3 py-2.5 text-xs font-medium"
        >
          <span class="flex items-center gap-2">
            <Building2 class="size-4 text-muted-foreground" aria-hidden="true" />
            {{
              t("integrations.assignments.summary", {
                assigned: assignedCount,
                total: card.workspace_assignments.length,
              })
            }}
          </span>
          <ChevronDown
            class="size-4 text-muted-foreground transition-transform group-open:rotate-180"
            aria-hidden="true"
          />
        </summary>

        <div class="space-y-1 border-t border-border/50 p-2">
          <div
            v-for="workspace in card.workspace_assignments"
            :key="workspace.workspace_id"
            class="flex items-center justify-between gap-3 rounded-md px-2 py-2 hover:bg-background/70"
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

          <p class="px-2 pb-1 pt-1 text-[11px] leading-relaxed text-muted-foreground">
            {{ t("integrations.assignments.consent_note") }}
          </p>
        </div>
      </details>

      <p v-else class="text-xs text-muted-foreground">
        {{ t("integrations.assignments.no_workspaces") }}
      </p>
    </section>

    <footer class="flex items-center justify-between gap-2">
      <a
        :href="card.docs_url"
        target="_blank"
        rel="noopener noreferrer"
        data-live-link-exempt="external-provider-docs"
        class="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground hover:underline"
      >
        {{ t("integrations.card.docs") }}
        <ExternalLink class="size-3" aria-hidden="true" />
      </a>

      <Button v-if="isConnected" variant="outline" size="sm" @click="emit('disconnect')">
        {{ t("integrations.card.disconnect") }}
      </Button>
      <Button v-else size="sm" @click="emit('connect')">
        {{ t("integrations.card.connect") }}
      </Button>
    </footer>
  </article>
</template>
