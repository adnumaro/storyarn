<script setup lang="ts">
import { computed, type Component } from "vue";
import { useI18n } from "vue-i18n";
import {
  Check,
  ChevronRight,
  CircleDashed,
  CircleDot,
  Clapperboard,
  FileText,
  History,
  Loader2,
  Pencil,
  Replace,
  Undo2,
  UserCheck,
  Workflow,
} from "@lucide/vue";
import { Button } from "@components/ui/button";
import DecisionApplication from "./DecisionApplication.vue";
import DecisionHistory from "./DecisionHistory.vue";
import DecisionTasks from "./DecisionTasks.vue";
import DecisionSources from "./DecisionSources.vue";
import { revisionPending, roundTag } from "./decisionStatus";
import type {
  ApplicationState,
  DecisionHistoryEntry,
  DecisionRecord,
  DecisionRevision,
  DecisionTargetType,
} from "./decisionTypes";

const {
  decision,
  history,
  roundCount = 1,
  pending = null,
  tasksSaved = 0,
} = defineProps<{
  decision: DecisionRecord;
  history: DecisionHistoryEntry[];
  roundCount?: number;
  pending?: string | null;
  tasksSaved?: number;
}>();
const emit = defineEmits<{
  accept: [];
  revise: [];
  withdraw: [];
  select: [id: number];
  loadHistory: [];
  declare: [targetKey: string | null, state: ApplicationState, note: string | null];
  linkTask: [url: string, title: string | null];
  editTask: [key: string, url: string, title: string | null];
  unlinkTask: [key: string];
}>();
const { t, locale } = useI18n();
const targetIcons: Record<DecisionTargetType, Component> = {
  sheet: FileText,
  flow: Workflow,
  scene: Clapperboard,
};

const pendingRevision = computed(() => revisionPending(decision));
/** What the reader judges: the proposal when one is open, otherwise the agreement. */
const revision = computed<DecisionRevision>(() =>
  decision.status === "proposed" || !decision.accepted ? decision.proposal : decision.accepted,
);
const pill = computed(() => {
  if (decision.status === "withdrawn")
    return { icon: Undo2, text: t("brainstormingDecisions.status.withdrawn"), tone: "muted" };
  if (decision.status === "superseded")
    return { icon: Replace, text: t("brainstormingDecisions.status.superseded"), tone: "muted" };
  if (decision.status === "accepted") {
    const application = decision.application;
    return application && application.pending > 0
      ? {
          icon: CircleDot,
          text: t("brainstormingDecisions.status.toApply", {
            pending: application.pending,
            total: application.total,
          }),
          tone: "amber",
        }
      : { icon: Check, text: t("brainstormingDecisions.status.accepted"), tone: "emerald" };
  }
  if (decision.canAccept)
    return {
      icon: UserCheck,
      text: t("brainstormingDecisions.status.waitingForYou"),
      tone: "blue",
    };
  return { icon: CircleDashed, text: t("brainstormingDecisions.status.proposal"), tone: "muted" };
});
const tones: Record<string, string> = {
  muted: "bg-muted text-muted-foreground",
  amber: "bg-amber-500/12 text-amber-700 dark:text-amber-400",
  emerald: "bg-emerald-500/12 text-emerald-700 dark:text-emerald-400",
  blue: "bg-blue-500/14 text-blue-700 dark:text-blue-400",
};
const aside = computed(() => {
  const proposer = decision.proposerName || t("brainstormingDecisions.formerMember");
  if (pendingRevision.value)
    return t("brainstormingDecisions.revisionProposedBy", { name: proposer });
  if (decision.status === "withdrawn" && decision.withdrawnByName)
    return t("brainstormingDecisions.withdrawnBy", { name: decision.withdrawnByName });
  if (decision.status === "proposed" && decision.canAccept)
    return t("brainstormingDecisions.proposedBy", { name: proposer });
  if (decision.status === "proposed")
    return t("brainstormingDecisions.waitingFor", { name: responsible.value });
  return null;
});
const responsible = computed(
  () => revision.value.responsibleName || t("brainstormingDecisions.formerMember"),
);
const tag = computed(() => roundTag(revision.value.round, roundCount));
const recorded = computed(() => {
  const parsed = new Date(revision.value.recordedAt);
  return Number.isNaN(parsed.getTime())
    ? ""
    : new Intl.DateTimeFormat(locale.value, { dateStyle: "medium", timeStyle: "short" }).format(
        parsed,
      );
});
const busy = computed(() => pending !== null);
</script>
<template>
  <div class="flex flex-col gap-3.5 text-[13px]" :data-decision="decision.id">
    <details
      v-if="pendingRevision && decision.accepted"
      id="decision-previous-agreement"
      class="group rounded-[10px] border border-emerald-500/20 bg-emerald-500/5 px-3 py-2.5"
    >
      <summary
        class="flex cursor-pointer list-none items-center gap-2 text-[13px] font-medium text-emerald-700 dark:text-emerald-400"
      >
        <ChevronRight class="size-3 transition-transform group-open:rotate-90" />{{
          t("brainstormingDecisions.previousAgreement")
        }}
      </summary>
      <div class="mt-2.5 space-y-1.5 text-foreground">
        <p class="font-semibold">{{ decision.accepted.title }}</p>
        <p class="text-xs text-muted-foreground">
          {{ t(`brainstormingDecisions.verbs.${decision.accepted.verb}`) }}
          <template v-if="decision.accepted.targets.length">
            · {{ decision.accepted.targets.map((target) => target.name).join(", ") }}</template
          >
        </p>
        <p class="text-[13px] leading-5 text-pretty">{{ decision.accepted.conclusion }}</p>
      </div>
    </details>
    <div>
      <div class="flex flex-wrap items-center gap-2">
        <span
          id="decision-status"
          class="inline-flex h-[22px] items-center gap-[5px] rounded-full px-[9px] text-xs font-medium"
          :class="tones[pill.tone]"
          ><component :is="pill.icon" class="size-3" />{{ pill.text }}</span
        ><span v-if="aside" class="text-xs text-muted-foreground">{{ aside }}</span>
      </div>
      <h3
        class="mt-2.5 text-lg leading-6 font-semibold text-pretty break-words"
        :class="decision.status === 'withdrawn' ? 'line-through' : ''"
      >
        {{ revision.title }}
      </h3>
      <p class="mt-1 text-xs text-muted-foreground">
        {{ t("brainstormingDecisions.responsibleLine", { name: responsible }) }} · {{ recorded }}
      </p>
      <p
        v-if="decision.supersedes && decision.status !== 'proposed'"
        class="mt-1.5 flex items-center gap-1.5 text-xs text-muted-foreground"
      >
        <Replace class="size-3 shrink-0" />{{ t("brainstormingDecisions.supersedes") }}
        <button
          type="button"
          class="truncate text-primary hover:underline"
          @click="emit('select', decision.supersedes.id)"
        >
          {{ decision.supersedes.title }}
        </button>
      </p>
      <p
        v-else-if="decision.replaces && decision.status === 'proposed'"
        class="mt-1.5 flex items-center gap-1.5 text-xs text-muted-foreground"
      >
        <Replace class="size-3 shrink-0" />{{ t("brainstormingDecisions.replaces") }}
        <button
          type="button"
          class="truncate text-primary hover:underline"
          @click="emit('select', decision.replaces.id)"
        >
          {{ decision.replaces.title }}
        </button>
      </p>
      <p
        v-if="decision.status === 'superseded' && decision.supersededBy"
        class="mt-1.5 flex flex-wrap items-center gap-1.5 text-xs text-muted-foreground"
      >
        <Replace class="size-3 shrink-0" />{{ t("brainstormingDecisions.supersededBy") }}
        <button
          type="button"
          class="text-primary hover:underline"
          @click="emit('select', decision.supersededBy.id)"
        >
          {{ decision.supersededBy.title }}</button
        ><span>· {{ t("brainstormingDecisions.supersededKeepsRecords") }}</span>
      </p>
    </div>
    <div>
      <p class="mb-1.5 text-xs text-muted-foreground">
        {{ t("brainstormingDecisions.thisDecisionMeans") }}
      </p>
      <div class="flex items-start gap-2.5">
        <span
          id="decision-verb"
          class="shrink-0 text-[13px] leading-[26px] text-muted-foreground"
          >{{ t(`brainstormingDecisions.verbs.${revision.verb}`) }}</span
        >
        <div class="flex min-w-0 flex-1 flex-wrap items-center gap-1.5">
          <span
            v-if="!revision.targets.length"
            class="text-[13px] leading-[26px] text-muted-foreground"
            >· {{ t("brainstormingDecisions.noAffectedContent") }}</span
          >
          <span
            v-for="target in revision.targets"
            :key="target.key"
            class="inline-flex h-[26px] max-w-full items-center gap-1.5 rounded-[7px] border border-border pr-2.5 pl-2 text-[13px]"
            ><component
              :is="targetIcons[target.type]"
              class="size-[13px] shrink-0 text-muted-foreground"
            /><span
              class="truncate"
              :class="target.available ? '' : 'text-muted-foreground line-through'"
              >{{ target.name }}</span
            ><span class="shrink-0 text-[11px] text-muted-foreground">{{
              target.isNew
                ? t("brainstormingDecisions.targetNew")
                : target.available
                  ? t(`brainstormingDecisions.targetTypes.${target.type}`)
                  : t("brainstormingDecisions.targetUnavailable")
            }}</span></span
          >
        </div>
      </div>
      <p
        v-if="tag || revision.round?.prompt"
        class="mt-2.5 flex items-baseline gap-1.5 text-xs text-muted-foreground"
      >
        <span v-if="tag" class="font-semibold text-foreground/80">{{ tag }}</span
        ><span>{{ revision.round?.prompt }}</span>
      </p>
    </div>
    <div>
      <p class="mb-1 text-xs text-muted-foreground">{{ t("brainstormingDecisions.conclusion") }}</p>
      <p class="text-[15px] leading-[23px] text-pretty break-words whitespace-pre-wrap">
        {{ revision.conclusion }}
      </p>
    </div>
    <div v-if="revision.reason">
      <p class="mb-1 text-xs text-muted-foreground">{{ t("brainstormingDecisions.reason") }}</p>
      <p class="text-[15px] leading-[23px] text-pretty break-words whitespace-pre-wrap">
        {{ revision.reason }}
      </p>
    </div>
    <div>
      <p class="mb-2 text-xs text-muted-foreground">
        {{ t("brainstormingDecisions.sourcesCount", { count: revision.sources.length }) }}
      </p>
      <DecisionSources :sources="revision.sources" />
    </div>
    <DecisionApplication
      :decision="decision"
      :pending="busy"
      @declare="(key, state, note) => emit('declare', key, state, note)"
    />
    <DecisionTasks
      :decision="decision"
      :pending="busy"
      :saved="tasksSaved"
      @link="(url, title) => emit('linkTask', url, title)"
      @edit="(key, url, title) => emit('editTask', key, url, title)"
      @unlink="(key) => emit('unlinkTask', key)"
    />
    <slot name="discussion" />
    <div class="flex flex-col gap-2">
      <template v-if="decision.canAccept">
        <Button id="decision-accept" class="w-full" :disabled="busy" @click="emit('accept')"
          ><Loader2 v-if="pending === 'accept'" class="size-4 animate-spin" /><Check
            v-else
            class="size-4"
          />{{ t("brainstormingDecisions.accept") }}</Button
        >
        <p class="-mt-0.5 text-xs text-muted-foreground">
          {{ t("brainstormingDecisions.acceptHelp") }}
        </p>
      </template>
      <p
        v-else-if="decision.status === 'proposed' && decision.canRevise"
        class="text-xs text-muted-foreground"
      >
        {{ t("brainstormingDecisions.waitingForOwner", { name: responsible }) }}
      </p>
      <Button
        v-if="decision.status === 'proposed' && decision.canRevise"
        id="decision-revise"
        variant="outline"
        class="w-full"
        :disabled="busy"
        @click="emit('revise')"
        ><Pencil class="size-3.5" />{{ t("brainstormingDecisions.editProposal") }}</Button
      >
      <template v-if="decision.canWithdraw">
        <Button
          id="decision-withdraw"
          variant="ghost"
          size="sm"
          class="w-full text-muted-foreground"
          :disabled="busy"
          @click="emit('withdraw')"
          ><Loader2 v-if="pending === 'withdraw'" class="size-3.5 animate-spin" /><Undo2
            v-else
            class="size-3.5"
          />{{ t("brainstormingDecisions.withdraw") }}</Button
        >
        <p class="-mt-1 text-center text-[11px] text-muted-foreground">
          {{
            pendingRevision
              ? t("brainstormingDecisions.withdrawRevisionHelp")
              : t("brainstormingDecisions.withdrawHelp")
          }}
        </p>
      </template>
      <Button
        v-if="decision.status === 'accepted' && decision.canRevise"
        id="decision-revise"
        variant="outline"
        class="w-full"
        :disabled="busy"
        @click="emit('revise')"
        ><Pencil class="size-3.5" />{{ t("brainstormingDecisions.revise") }}</Button
      >
      <p
        v-if="decision.status === 'withdrawn' || decision.status === 'superseded'"
        class="text-xs text-muted-foreground"
      >
        {{
          decision.status === "withdrawn"
            ? t("brainstormingDecisions.retiredWithdrawn")
            : t("brainstormingDecisions.retiredSuperseded")
        }}
      </p>
    </div>
    <details
      id="decision-history"
      class="group"
      @toggle="
        (event) => {
          if ((event.target as HTMLDetailsElement).open && !history.length) emit('loadHistory');
        }
      "
    >
      <summary
        class="flex cursor-pointer list-none items-center gap-1.5 text-[13px] text-muted-foreground"
      >
        <ChevronRight class="size-3 transition-transform group-open:rotate-90" /><History
          class="size-3.5"
        />{{ t("brainstormingDecisions.history") }}<span class="flex-1" /><span
          v-if="history.length"
          class="text-[11px]"
          >{{ t("brainstormingDecisions.historyCount", { count: history.length }) }}</span
        >
      </summary>
      <p v-if="pending === 'history'" class="mt-2 text-xs text-muted-foreground">
        {{ t("brainstormingDecisions.loading") }}
      </p>
      <DecisionHistory v-else-if="history.length" :entries="history" />
    </details>
  </div>
</template>
