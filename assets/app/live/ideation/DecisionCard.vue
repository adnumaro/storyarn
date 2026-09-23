<script setup lang="ts">
import { computed, type Component } from "vue";
import { useI18n } from "vue-i18n";
import {
  Check,
  CircleCheck,
  CircleDashed,
  CircleDot,
  Clapperboard,
  EyeOff,
  FileText,
  Layers,
  ListChecks,
  MessageSquare,
  Pencil,
  Replace,
  StickyNote,
  Undo2,
  UserCheck,
  Workflow,
} from "@lucide/vue";
import UserAvatar from "@components/UserAvatar.vue";
import {
  hasUnavailableSource,
  orderTargets,
  primaryStatus,
  retired,
  revisionPending,
  roundTag,
  shownRevision,
  sourceLabel,
  splitTargets,
  targetState,
} from "./decisionStatus";
import type { ApplicationState, DecisionRecord, DecisionTarget } from "./decisionTypes";

const {
  decision,
  size = "row",
  roundCount = 1,
  selected = false,
  comments = 0,
} = defineProps<{
  decision: DecisionRecord;
  size?: "row" | "compact" | "canvas";
  roundCount?: number;
  selected?: boolean;
  /** Messages in the decision's open discussion. */
  comments?: number;
}>();
const { t, locale } = useI18n();

const statusIcons: Record<string, Component> = {
  toApply: CircleDot,
  accepted: Check,
  waitingForYou: UserCheck,
  proposal: CircleDashed,
  withdrawn: Undo2,
  superseded: Replace,
};
// Status colours: amber still to apply, emerald accepted, blue asks the reader
// to act; teal stays reserved for actions.
const statusTones: Record<string, { pill: string; text: string }> = {
  toApply: { pill: "bg-amber-500/12", text: "text-amber-700 dark:text-amber-400" },
  accepted: { pill: "bg-emerald-500/12", text: "text-emerald-700 dark:text-emerald-400" },
  waitingForYou: { pill: "bg-blue-500/14", text: "text-blue-700 dark:text-blue-400" },
  proposal: { pill: "bg-muted", text: "text-muted-foreground" },
  withdrawn: { pill: "bg-muted", text: "text-muted-foreground" },
  superseded: { pill: "bg-muted", text: "text-muted-foreground" },
};
const targetIcons: Record<string, Component> = {
  sheet: FileText,
  flow: Workflow,
  scene: Clapperboard,
};
const stateIcons: Record<ApplicationState, Component> = {
  applied: CircleCheck,
  partially_applied: CircleDot,
  not_applied: CircleDashed,
  no_change_needed: CircleCheck,
};
const stateTones: Record<ApplicationState, string> = {
  applied: "text-emerald-700 dark:text-emerald-400",
  partially_applied: "text-amber-700 dark:text-amber-400",
  not_applied: "text-amber-700 dark:text-amber-400",
  no_change_needed: "text-muted-foreground",
};

const status = computed(() => primaryStatus(decision));
const tone = computed(() => statusTones[status.value.kind]);
const revision = computed(() => shownRevision(decision));
const inForce = computed(() => decision.accepted !== null && !retired(decision));
const unavailable = computed(() => hasUnavailableSource(decision));
const isRetired = computed(() => retired(decision));
const statusText = computed(() => {
  const value = status.value;
  return value.kind === "toApply"
    ? t("brainstormingDecisions.status.toApply", { pending: value.pending, total: value.total })
    : t(`brainstormingDecisions.status.${value.kind}`);
});
const statusAside = computed(() => {
  const value = status.value;
  if (value.kind === "proposal")
    return t("brainstormingDecisions.waitingFor", {
      name: value.waitingFor || t("brainstormingDecisions.formerMember"),
    });
  if (value.kind === "withdrawn" && value.by)
    return t("brainstormingDecisions.withdrawnBy", { name: value.by });
  return null;
});
const targets = computed(() => {
  const list: DecisionTarget[] =
    inForce.value && decision.application ? decision.application.targets : revision.value.targets;
  return splitTargets(orderTargets(list, inForce.value));
});
const hiddenTitle = computed(() =>
  targets.value.hidden
    .map((target) =>
      inForce.value
        ? `${target.name} · ${t(`brainstormingDecisions.stateChips.${targetState(target)}`)}`
        : target.name,
    )
    .join(", "),
);
const objectSuffix = computed(() => {
  if (revision.value.targets.length) return null;
  return inForce.value && decision.application?.decision?.state === "no_change_needed"
    ? t("brainstormingDecisions.noChangeNeeded")
    : t("brainstormingDecisions.noAffectedContent");
});
const firstSource = computed(() => revision.value.sources[0] ?? null);
const round = computed(() => ({
  tag: roundTag(revision.value.round, roundCount),
  prompt: revision.value.round?.prompt ?? null,
}));
const date = computed(() => {
  const parsed = new Date(decision.updatedAt);
  return Number.isNaN(parsed.getTime())
    ? ""
    : new Intl.DateTimeFormat(locale.value, { month: "short", day: "numeric" }).format(parsed);
});
const responsible = computed(
  () => revision.value.responsibleName || t("brainstormingDecisions.formerMember"),
);
</script>
<template>
  <article
    v-if="size === 'row'"
    :data-decision-card="decision.id"
    :data-status="decision.status"
    class="rounded-xl border bg-surface px-4 py-3.5 transition-colors"
    :class="
      selected
        ? 'border-primary/60 ring-1 ring-primary/35'
        : 'border-border hover:border-primary/40 hover:bg-accent/30'
    "
  >
    <div :class="isRetired ? 'opacity-60' : ''">
      <div class="flex min-h-[22px] items-center gap-2">
        <span
          class="inline-flex h-[22px] shrink-0 items-center gap-[5px] rounded-full px-[9px] text-xs font-medium whitespace-nowrap"
          :class="[tone.pill, tone.text]"
          ><component :is="statusIcons[status.kind]" class="size-3" />{{ statusText }}</span
        ><span
          v-if="revisionPending(decision)"
          class="inline-flex shrink-0 items-center gap-[5px] text-xs font-medium whitespace-nowrap text-violet-700 dark:text-violet-400"
          ><Pencil class="size-3" />{{ t("brainstormingDecisions.revisionPending") }}</span
        ><span v-if="statusAside" class="truncate text-xs text-muted-foreground">{{
          statusAside
        }}</span
        ><span class="flex-1" /><span
          class="shrink-0 text-xs whitespace-nowrap text-muted-foreground"
          >{{ date }}</span
        >
      </div>
      <h3
        class="mt-2.5 text-[15px] leading-[21px] font-semibold text-pretty break-words"
        :class="decision.status === 'withdrawn' ? 'line-through' : ''"
      >
        {{ revision.title }}
      </h3>
      <div class="mt-2 flex items-start gap-2 text-xs leading-[22px]">
        <span class="shrink-0 text-muted-foreground">{{
          t(`brainstormingDecisions.verbs.${revision.verb}`)
        }}</span>
        <div class="flex min-w-0 flex-1 flex-wrap items-center gap-1.5">
          <span v-if="objectSuffix" class="text-muted-foreground">· {{ objectSuffix }}</span>
          <span
            v-for="target in targets.visible"
            :key="target.key"
            :data-decision-target="target.key"
            class="inline-flex h-[22px] max-w-full items-center gap-1.5 rounded-md border border-border bg-muted/45 pr-2 pl-[7px] text-xs whitespace-nowrap"
            ><component
              :is="targetIcons[target.type]"
              class="size-3 shrink-0 text-muted-foreground"
            /><span
              class="truncate"
              :class="target.available ? '' : 'text-muted-foreground line-through'"
              >{{ target.name }}</span
            ><span
              v-if="inForce"
              class="inline-flex items-center gap-[3px]"
              :class="stateTones[targetState(target)]"
              ><component :is="stateIcons[targetState(target)]" class="size-3" /><span
                class="text-[11.5px]"
                >{{ t(`brainstormingDecisions.stateChips.${targetState(target)}`) }}</span
              ></span
            ></span
          >
          <span
            v-if="targets.hidden.length"
            :title="hiddenTitle"
            class="inline-flex h-[22px] items-center rounded-md border border-dashed border-border px-[7px] text-xs whitespace-nowrap text-muted-foreground"
            >{{ t("brainstormingDecisions.moreTargets", { count: targets.hidden.length }) }}</span
          >
        </div>
      </div>
      <p
        v-if="decision.status === 'superseded' && decision.supersededBy"
        class="mt-2 flex items-center gap-1.5 text-xs text-muted-foreground"
      >
        <Replace class="size-3 shrink-0" />{{ t("brainstormingDecisions.supersededBy") }}
        <span class="truncate text-primary">{{ decision.supersededBy.title }}</span>
      </p>
      <p class="mt-2.5 line-clamp-2 text-[13px] leading-5 text-pretty text-muted-foreground">
        {{ revision.conclusion }}
      </p>
      <p
        v-if="unavailable"
        class="mt-2 flex items-center gap-1.5 text-xs text-amber-700 dark:text-amber-400"
      >
        <EyeOff class="size-[13px] shrink-0" />{{ t("brainstormingDecisions.replaceUnavailable") }}
      </p>
      <div
        class="mt-3 flex flex-col gap-1.5 border-t border-border/70 pt-2.5 text-xs leading-[18px] text-muted-foreground"
      >
        <div class="flex min-w-0 items-center gap-2 whitespace-nowrap">
          <UserAvatar :display-name="responsible" size="xs" class="!size-[18px] shrink-0" />
          <span class="shrink-0 text-foreground">{{ responsible }}</span>
          <span
            v-if="firstSource"
            class="inline-flex min-w-0 items-center gap-[5px] overflow-hidden"
            ><component
              :is="firstSource.type === 'group' ? Layers : StickyNote"
              class="size-3 shrink-0"
            /><span class="truncate">{{
              firstSource.available
                ? sourceLabel(firstSource)
                : t("brainstormingDecisions.sourceUnavailable")
            }}</span
            ><span v-if="revision.sources.length > 1" class="shrink-0">{{
              t("brainstormingDecisions.moreSources", { count: revision.sources.length - 1 })
            }}</span></span
          ><span class="flex-1" /><span
            v-if="comments > 0"
            data-decision-comments
            class="inline-flex shrink-0 items-center gap-1"
            :aria-label="t('brainstormingDecisions.comments', { count: comments })"
            ><MessageSquare class="size-3" />{{ comments }}</span
          >
        </div>
        <div
          v-if="round.tag || round.prompt"
          class="flex min-w-0 items-baseline gap-1.5 whitespace-nowrap"
        >
          <span v-if="round.tag" class="shrink-0 font-semibold text-foreground/80">{{
            round.tag
          }}</span
          ><span class="truncate">{{ round.prompt }}</span>
        </div>
      </div>
    </div>
  </article>
  <div
    v-else-if="size === 'compact'"
    :data-decision-card="decision.id"
    class="flex min-w-0 items-start gap-2"
    :class="isRetired ? 'opacity-60' : ''"
  >
    <component
      :is="unavailable ? EyeOff : statusIcons[status.kind]"
      class="mt-0.5 size-[15px] shrink-0"
      :class="unavailable ? 'text-amber-700 dark:text-amber-400' : tone.text"
    />
    <div class="min-w-0 flex-1">
      <p
        class="truncate text-[13px] leading-[19px] font-medium"
        :class="decision.status === 'withdrawn' ? 'line-through' : ''"
      >
        {{ revision.title }}
      </p>
      <div
        class="mt-[3px] flex flex-wrap items-center gap-x-1.5 gap-y-[3px] text-xs leading-[18px] text-muted-foreground"
      >
        <span class="font-medium" :class="tone.text">{{ statusText }}</span>
        <span
          v-if="revisionPending(decision)"
          class="inline-flex items-center gap-1 text-violet-700 dark:text-violet-400"
          ><Pencil class="size-[11px]" />{{ t("brainstormingDecisions.revisionPending") }}</span
        >
        <span>·</span><span>{{ t(`brainstormingDecisions.verbs.${revision.verb}`) }}</span>
        <span v-if="objectSuffix">· {{ objectSuffix }}</span>
        <span
          v-for="target in targets.visible"
          :key="target.key"
          class="inline-flex items-center gap-1 whitespace-nowrap text-foreground"
          ><component :is="targetIcons[target.type]" class="size-[11px] text-muted-foreground" />{{
            target.name
          }}<component
            :is="stateIcons[targetState(target)]"
            v-if="inForce"
            class="size-[11px]"
            :class="stateTones[targetState(target)]"
        /></span>
        <span v-if="targets.hidden.length" :title="hiddenTitle" class="whitespace-nowrap">{{
          t("brainstormingDecisions.moreTargets", { count: targets.hidden.length })
        }}</span>
      </div>
    </div>
  </div>
  <article
    v-else
    :data-decision-card="decision.id"
    class="w-80 rounded-xl border border-border bg-surface px-4 py-3.5"
    :class="
      selected
        ? 'shadow-[0_0_0_3px_hsl(var(--background)),0_0_0_6px_hsl(var(--primary))]'
        : 'shadow-xs'
    "
  >
    <div :class="isRetired ? 'opacity-60 grayscale' : ''">
      <div class="flex items-center gap-1.5">
        <ListChecks class="size-3.5 shrink-0 text-muted-foreground" />
        <span
          class="inline-flex h-5 shrink-0 items-center gap-1 rounded-full px-2 text-[11.5px] font-medium whitespace-nowrap"
          :class="[tone.pill, tone.text]"
          ><component :is="statusIcons[status.kind]" class="size-[11px]" />{{ statusText }}</span
        ><span
          v-if="revisionPending(decision)"
          class="inline-flex h-5 items-center gap-1 text-[11.5px] font-medium whitespace-nowrap text-violet-700 dark:text-violet-400"
          ><Pencil class="size-[11px]" />{{ t("brainstormingDecisions.revisionPending") }}</span
        ><span class="flex-1" /><span
          class="shrink-0 text-[11.5px] whitespace-nowrap text-muted-foreground"
          >{{ date }}</span
        >
      </div>
      <h3
        class="mt-2.5 text-[15px] leading-5 font-semibold text-pretty break-words"
        :class="decision.status === 'withdrawn' ? 'line-through' : ''"
      >
        {{ revision.title }}
      </h3>
      <div class="mt-2 flex items-start gap-2 text-xs leading-5">
        <span class="shrink-0 text-muted-foreground">{{
          t(`brainstormingDecisions.verbs.${revision.verb}`)
        }}</span>
        <div class="flex min-w-0 flex-1 flex-wrap items-center gap-x-1.5 gap-y-[5px]">
          <span v-if="objectSuffix" class="text-muted-foreground">· {{ objectSuffix }}</span>
          <span
            v-for="target in targets.visible"
            :key="target.key"
            class="inline-flex h-5 items-center gap-[5px] rounded-[5px] border border-border bg-muted/45 pr-[7px] pl-1.5 text-[11.5px] whitespace-nowrap"
            ><component
              :is="targetIcons[target.type]"
              class="size-[11px] text-muted-foreground" />{{ target.name
            }}<component
              :is="stateIcons[targetState(target)]"
              v-if="inForce"
              class="size-[11px]"
              :class="stateTones[targetState(target)]"
          /></span>
          <span
            v-if="targets.hidden.length"
            :title="hiddenTitle"
            class="inline-flex h-5 items-center rounded-md border border-dashed border-border px-[7px] text-[11.5px] whitespace-nowrap text-muted-foreground"
            >{{ t("brainstormingDecisions.moreTargets", { count: targets.hidden.length }) }}</span
          >
        </div>
      </div>
      <p class="mt-2.5 line-clamp-2 text-[12.5px] leading-[18px] text-pretty text-muted-foreground">
        {{ revision.conclusion }}
      </p>
      <div
        class="mt-3 flex items-center gap-[7px] overflow-hidden text-[11.5px] whitespace-nowrap text-muted-foreground"
      >
        <UserAvatar :display-name="responsible" size="xs" class="!size-4 shrink-0 !text-[7px]" />
        <span class="shrink-0 text-foreground">{{ responsible }}</span>
        <span v-if="firstSource" class="inline-flex min-w-0 items-center gap-1 overflow-hidden"
          ><component
            :is="firstSource.type === 'group' ? Layers : StickyNote"
            class="size-[11px] shrink-0"
          /><span class="truncate">{{
            firstSource.available
              ? sourceLabel(firstSource)
              : t("brainstormingDecisions.sourceUnavailable")
          }}</span
          ><span v-if="revision.sources.length > 1" class="shrink-0">{{
            t("brainstormingDecisions.moreSources", { count: revision.sources.length - 1 })
          }}</span></span
        ><span class="flex-1" /><span
          v-if="comments > 0"
          data-decision-comments
          class="inline-flex shrink-0 items-center gap-1"
          :aria-label="t('brainstormingDecisions.comments', { count: comments })"
          ><MessageSquare class="size-[11px]" />{{ comments }}</span
        >
      </div>
    </div>
  </article>
</template>
