<script setup lang="ts">
import {
  ArrowRight,
  Bot,
  Building2,
  CircleAlert,
  CircleCheck,
  CircleDashed,
  Clock3,
  Sparkles,
} from "lucide-vue-next";
import { useI18n } from "vue-i18n";
import LiveLink from "@components/navigation/LiveLink.vue";

type RoleSlot = "general_assistant" | "writing_assistant" | "illustrator" | "voice";

interface OverviewPreference {
  provider_name: string;
  model: string;
  implementation_status: "executable" | "configuration_only" | null;
  status: string;
}

interface OverviewSlot {
  slot: RoleSlot;
  kind: "role";
  required_capabilities: string[];
  available: boolean;
  preference: OverviewPreference | null;
}

export interface AITeamWorkspaceOverview {
  id: number;
  name: string;
  slug: string;
  role: string | null;
  policy_allowed: boolean;
  can_configure: boolean;
  edit_path: string | null;
  slots: OverviewSlot[];
}

const { workspaces = [] } = defineProps<{
  workspaces: AITeamWorkspaceOverview[];
}>();

const { t } = useI18n();

const roles: RoleSlot[] = ["general_assistant", "writing_assistant", "illustrator", "voice"];

function slotFor(workspace: AITeamWorkspaceOverview, role: RoleSlot): OverviewSlot | undefined {
  return workspace.slots.find((slot) => slot.slot === role);
}

function stateFor(
  slot: OverviewSlot | undefined,
): "ready" | "configured" | "broken" | "unconfigured" | "coming-soon" {
  if (!slot?.available) return "coming-soon";
  if (!slot.preference) return "unconfigured";
  if (slot.preference.status === "configured") return "configured";
  return slot.preference.status === "ready" ? "ready" : "broken";
}

function stateClasses(state: ReturnType<typeof stateFor>): string {
  if (state === "ready") {
    return "border-emerald-500/20 bg-emerald-500/8 text-emerald-700 dark:text-emerald-300";
  }

  if (state === "configured") {
    return "border-sky-500/20 bg-sky-500/8 text-sky-700 dark:text-sky-300";
  }

  if (state === "broken") {
    return "border-amber-500/25 bg-amber-500/8 text-amber-700 dark:text-amber-300";
  }

  return "border-border/60 bg-muted/40 text-muted-foreground";
}

function workspaceRoleLabel(role: string | null): string {
  if (!role) return t("integrations.team.overview.workspace_roles.limited");

  const knownRoles = ["owner", "admin", "member", "viewer"];

  return knownRoles.includes(role) ? t(`integrations.team.overview.workspace_roles.${role}`) : role;
}
</script>

<template>
  <div id="settings-ai-team-overview-page" class="space-y-7">
    <header class="max-w-3xl space-y-1.5">
      <div class="flex items-center gap-2">
        <Bot class="size-5 text-primary" aria-hidden="true" />
        <h1 class="text-2xl font-bold tracking-tight text-foreground">
          {{ t("integrations.team.overview.title") }}
        </h1>
      </div>
      <p class="text-sm leading-relaxed text-muted-foreground">
        {{ t("integrations.team.overview.description") }}
      </p>
    </header>

    <div
      class="flex items-start gap-3 rounded-xl border border-border/60 bg-muted/20 p-4"
      id="ai-team-personal-scope-note"
    >
      <CircleAlert class="mt-0.5 size-4 shrink-0 text-muted-foreground" aria-hidden="true" />
      <p class="max-w-3xl text-xs leading-relaxed text-muted-foreground">
        {{ t("integrations.team.overview.personal_scope_note") }}
      </p>
    </div>

    <section
      v-if="workspaces.length > 0"
      class="overflow-hidden rounded-xl border border-border/70 bg-card shadow-sm"
      aria-labelledby="ai-team-overview-list-title"
    >
      <h2 id="ai-team-overview-list-title" class="sr-only">
        {{ t("integrations.team.overview.list_title") }}
      </h2>

      <div
        id="ai-team-overview-columns"
        class="hidden min-w-0 grid-cols-[minmax(10rem,1.2fr)_repeat(4,minmax(8rem,1fr))_auto] gap-4 border-b border-border/70 bg-muted/30 px-5 py-3 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground xl:grid"
        aria-hidden="true"
      >
        <span>{{ t("integrations.team.overview.workspace") }}</span>
        <span v-for="role in roles" :key="role" class="text-center">
          {{ t(`integrations.team.slots.${role}.title`) }}
        </span>
        <span class="sr-only">{{ t("integrations.team.overview.actions") }}</span>
      </div>

      <div id="ai-team-workspace-overviews" class="divide-y divide-border/60">
        <article
          v-for="workspace in workspaces"
          :key="workspace.id"
          :id="`ai-team-workspace-${workspace.slug}`"
          class="grid min-w-0 gap-4 p-5 xl:grid-cols-[minmax(10rem,1.2fr)_repeat(4,minmax(8rem,1fr))_auto] xl:items-center"
          :data-workspace-slug="workspace.slug"
          :aria-labelledby="`ai-team-workspace-title-${workspace.slug}`"
        >
          <div class="flex min-w-0 items-start gap-3">
            <div
              class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary"
            >
              <Building2 class="size-4" aria-hidden="true" />
            </div>
            <div class="min-w-0">
              <h3
                :id="`ai-team-workspace-title-${workspace.slug}`"
                class="truncate text-sm font-semibold text-foreground"
              >
                {{ workspace.name }}
              </h3>
              <p class="mt-0.5 text-[11px] text-muted-foreground">
                {{ workspaceRoleLabel(workspace.role) }}
              </p>
              <p
                v-if="!workspace.role"
                class="mt-1.5 flex items-start gap-1 text-[11px] leading-tight text-muted-foreground"
              >
                <CircleAlert class="mt-px size-3 shrink-0" aria-hidden="true" />
                {{ t("integrations.team.overview.membership_required") }}
              </p>
              <p
                v-else-if="!workspace.policy_allowed"
                class="mt-1.5 flex items-start gap-1 text-[11px] leading-tight text-amber-700 dark:text-amber-300"
              >
                <CircleAlert class="mt-px size-3 shrink-0" aria-hidden="true" />
                {{ t("integrations.team.overview.policy_blocked") }}
              </p>
            </div>
          </div>

          <div
            v-for="role in roles"
            :key="role"
            class="min-w-0 rounded-lg border border-border/50 bg-muted/15 p-3 text-center xl:border-0 xl:bg-transparent xl:p-0"
            :data-role="role"
            :data-state="stateFor(slotFor(workspace, role))"
          >
            <p class="mb-2 text-[11px] font-semibold text-muted-foreground xl:sr-only">
              {{ t(`integrations.team.slots.${role}.title`) }}
            </p>

            <template
              v-if="['ready', 'configured', 'broken'].includes(stateFor(slotFor(workspace, role)))"
            >
              <p class="truncate text-xs font-medium text-foreground">
                {{ slotFor(workspace, role)?.preference?.provider_name }}
              </p>
              <p
                class="mt-0.5 truncate text-[11px] text-muted-foreground"
                :title="slotFor(workspace, role)?.preference?.model"
              >
                {{ slotFor(workspace, role)?.preference?.model }}
              </p>
            </template>

            <p v-else class="text-xs text-muted-foreground">
              {{
                t(
                  stateFor(slotFor(workspace, role)) === "coming-soon"
                    ? "integrations.team.overview.no_role_support"
                    : "integrations.team.overview.no_model",
                )
              }}
            </p>

            <span
              class="mt-2 inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[10px] font-medium"
              :class="stateClasses(stateFor(slotFor(workspace, role)))"
            >
              <CircleCheck
                v-if="stateFor(slotFor(workspace, role)) === 'ready'"
                class="size-2.5"
                aria-hidden="true"
              />
              <Sparkles
                v-else-if="stateFor(slotFor(workspace, role)) === 'configured'"
                class="size-2.5"
                aria-hidden="true"
              />
              <CircleAlert
                v-else-if="stateFor(slotFor(workspace, role)) === 'broken'"
                class="size-2.5"
                aria-hidden="true"
              />
              <Clock3
                v-else-if="stateFor(slotFor(workspace, role)) === 'coming-soon'"
                class="size-2.5"
                aria-hidden="true"
              />
              <CircleDashed v-else class="size-2.5" aria-hidden="true" />
              {{ t(`integrations.team.overview.states.${stateFor(slotFor(workspace, role))}`) }}
            </span>

            <p
              v-if="stateFor(slotFor(workspace, role)) === 'configured'"
              class="mt-1.5 text-[10px] leading-tight text-sky-700 dark:text-sky-300"
            >
              {{ t("integrations.team.overview.configured_hint") }}
            </p>
            <p
              v-else-if="
                stateFor(slotFor(workspace, role)) === 'broken' &&
                slotFor(workspace, role)?.preference
              "
              class="mt-1.5 text-[10px] leading-tight text-amber-700 dark:text-amber-300"
            >
              {{
                t(
                  `integrations.team.status.${slotFor(workspace, role)?.preference?.status}`,
                  t("integrations.team.overview.states.broken"),
                )
              }}
            </p>
          </div>

          <div class="flex justify-end xl:pl-1">
            <LiveLink
              v-if="workspace.can_configure && workspace.edit_path"
              :id="`configure-ai-team-${workspace.slug}`"
              :to="workspace.edit_path"
              :aria-label="
                t('integrations.team.overview.configure_workspace', {
                  workspace: workspace.name,
                })
              "
              class="inline-flex h-8 items-center gap-1.5 rounded-lg border border-border bg-background px-3 text-xs font-medium text-foreground transition-colors hover:bg-muted"
            >
              {{ t("integrations.team.overview.configure") }}
              <ArrowRight class="size-3" aria-hidden="true" />
            </LiveLink>
          </div>
        </article>
      </div>
    </section>

    <div
      v-else
      id="ai-team-overview-empty"
      class="flex flex-col items-center rounded-xl border border-dashed border-border/70 px-6 py-14 text-center"
    >
      <div
        class="mb-4 flex size-11 items-center justify-center rounded-xl bg-muted text-muted-foreground"
      >
        <Building2 class="size-5" aria-hidden="true" />
      </div>
      <h2 class="text-sm font-semibold text-foreground">
        {{ t("integrations.team.overview.empty.title") }}
      </h2>
      <p class="mt-1 max-w-md text-xs leading-relaxed text-muted-foreground">
        {{ t("integrations.team.overview.empty.description") }}
      </p>
    </div>
  </div>
</template>
