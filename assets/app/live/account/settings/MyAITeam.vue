<script setup lang="ts">
import { ArrowLeft, Bot, CircleAlert, KeyRound, ShieldCheck } from "lucide-vue-next";
import { ref } from "vue";
import { useI18n } from "vue-i18n";
import LiveLink from "@components/navigation/LiveLink.vue";
import { useLive } from "@shared/composables/useLive";
import PreferenceCard, { type PreferenceSlotData } from "./integrations/PreferenceCard.vue";

interface WorkspaceData {
  id: number;
  name: string;
  slug: string;
}

interface EventReply {
  status?: string;
  error?: string;
}

const {
  workspace,
  policyAllowed,
  slots = [],
  providersPath,
  overviewPath,
} = defineProps<{
  workspace: WorkspaceData;
  policyAllowed: boolean;
  slots: PreferenceSlotData[];
  providersPath: string;
  overviewPath: string;
}>();

const { t } = useI18n();
const live = useLive();
const pendingSlots = ref(new Set<string>());
const inlineError = ref<string | null>(null);
const mutationSequences = new Map<string, number>();

function beginMutation(slot: string): number {
  const seq = (mutationSequences.get(slot) ?? 0) + 1;
  mutationSequences.set(slot, seq);
  pendingSlots.value = new Set(pendingSlots.value).add(slot);
  inlineError.value = null;
  return seq;
}

function finishMutation(slot: string, seq: number): boolean {
  if (mutationSequences.get(slot) !== seq) return false;

  const nextPending = new Set(pendingSlots.value);
  nextPending.delete(slot);
  pendingSlots.value = nextPending;
  return true;
}

function savePreference(payload: { slot: string; integration_id: number; model: string }): void {
  const seq = beginMutation(payload.slot);

  live.pushEvent(
    "save_preference",
    payload,
    (reply: EventReply) => {
      if (!finishMutation(payload.slot, seq)) return;
      if (reply?.status !== "ok") inlineError.value = reply?.error ?? "unknown_error";
    },
    () => {
      if (!finishMutation(payload.slot, seq)) return;
      inlineError.value = "connection_lost";
    },
  );
}

function removePreference(slot: string): void {
  const seq = beginMutation(slot);

  live.pushEvent(
    "delete_preference",
    { slot },
    (reply: EventReply) => {
      if (!finishMutation(slot, seq)) return;
      if (reply?.status !== "ok") inlineError.value = reply?.error ?? "unknown_error";
    },
    () => {
      if (!finishMutation(slot, seq)) return;
      inlineError.value = "connection_lost";
    },
  );
}
</script>

<template>
  <div id="settings-ai-team-page" class="space-y-7">
    <LiveLink
      id="back-to-ai-team-overview"
      :to="overviewPath"
      class="inline-flex items-center gap-1.5 text-xs font-medium text-muted-foreground transition-colors hover:text-foreground"
    >
      <ArrowLeft class="size-3.5" aria-hidden="true" />
      {{ t("integrations.team.configuration.back") }}
    </LiveLink>

    <header class="max-w-3xl space-y-1.5">
      <div class="flex items-center gap-2">
        <Bot class="size-5 text-primary" aria-hidden="true" />
        <h1 class="text-2xl font-bold tracking-tight text-foreground">
          {{ t("integrations.team.configuration.title", { workspace: workspace.name }) }}
        </h1>
      </div>
      <p class="text-sm leading-relaxed text-muted-foreground">
        {{ t("integrations.team.configuration.description") }}
      </p>
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
      v-if="!policyAllowed"
      id="ai-team-policy-warning"
      class="flex items-start gap-3 rounded-xl border border-amber-500/30 bg-amber-500/5 p-4 text-amber-800 dark:text-amber-200"
    >
      <CircleAlert class="mt-0.5 size-4 shrink-0" aria-hidden="true" />
      <div>
        <p class="text-sm font-medium">{{ t("integrations.team.policy_blocked.title") }}</p>
        <p class="mt-1 text-xs leading-relaxed opacity-85">
          {{ t("integrations.team.policy_blocked.description") }}
        </p>
      </div>
    </div>

    <div
      class="flex flex-col gap-3 rounded-xl border border-border/60 bg-muted/20 p-4 sm:flex-row sm:items-center sm:justify-between"
    >
      <div class="flex max-w-2xl items-start gap-3">
        <ShieldCheck class="mt-0.5 size-4 shrink-0 text-muted-foreground" aria-hidden="true" />
        <p class="text-xs leading-relaxed text-muted-foreground">
          {{ t("integrations.team.workspace_scope_note") }}
        </p>
      </div>
      <LiveLink
        id="manage-ai-integrations"
        :to="providersPath"
        class="inline-flex shrink-0 items-center gap-1.5 self-start text-xs font-medium text-foreground underline-offset-4 hover:underline sm:self-auto"
      >
        <KeyRound class="size-3.5" aria-hidden="true" />
        {{ t("integrations.team.manage_integrations") }}
      </LiveLink>
    </div>

    <section class="space-y-4" aria-labelledby="ai-roles-title">
      <div class="space-y-1">
        <h2 id="ai-roles-title" class="text-sm font-semibold text-foreground">
          {{ t("integrations.team.roles_section.title") }}
        </h2>
        <p class="text-xs leading-relaxed text-muted-foreground">
          {{ t("integrations.team.roles_section.description") }}
        </p>
      </div>

      <div v-if="slots.length > 0" class="space-y-4">
        <PreferenceCard
          v-for="slot in slots"
          :key="slot.slot"
          :slot-data="slot"
          :pending="pendingSlots.has(slot.slot)"
          :disabled="!policyAllowed"
          @save="savePreference"
          @remove="removePreference"
        />
      </div>

      <div
        v-else
        class="rounded-xl border border-dashed border-border/70 px-5 py-10 text-center text-xs text-muted-foreground"
      >
        {{ t("integrations.team.no_roles") }}
      </div>
    </section>
  </div>
</template>
