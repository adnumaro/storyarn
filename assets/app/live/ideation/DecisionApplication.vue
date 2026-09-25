<script setup lang="ts">
import { computed, ref, type Component } from "vue";
import { useI18n } from "vue-i18n";
import {
  ArrowRight,
  ChevronDown,
  CircleCheck,
  CircleDashed,
  CircleDot,
  Clapperboard,
  ExternalLink,
  FileText,
  Workflow,
} from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import UserAvatar from "@components/UserAvatar.vue";
import LiveLink from "@components/navigation/LiveLink.vue";
import DecisionMarkForm from "./DecisionMarkForm.vue";
import { sectionHeading } from "./decisionSections";
import { orderTargets, targetState } from "./decisionStatus";
import type {
  ApplicationState,
  DecisionDeclaration,
  DecisionRecord,
  DecisionTarget,
  DecisionTargetType,
} from "./decisionTypes";

const { decision, pending = false } = defineProps<{
  decision: DecisionRecord;
  pending?: boolean;
}>();
const emit = defineEmits<{
  declare: [targetKey: string | null, state: ApplicationState, note: string | null];
}>();
const { t, locale } = useI18n();
const icons: Record<DecisionTargetType, Component> = {
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
const statePills: Record<ApplicationState, string> = {
  applied: "bg-emerald-500/12 text-emerald-700 dark:text-emerald-400",
  partially_applied: "bg-amber-500/12 text-amber-700 dark:text-amber-400",
  not_applied: "bg-amber-500/12 text-amber-700 dark:text-amber-400",
  no_change_needed: "bg-muted text-muted-foreground",
};
const pill =
  "inline-flex h-[22px] shrink-0 items-center gap-[5px] rounded-full px-[9px] text-xs font-medium";

const application = computed(() => decision.application);
const accepted = computed(() => decision.accepted !== null);
const proposalTargets = computed(() => decision.proposal.targets);
const rows = computed(() =>
  application.value
    ? orderTargets(application.value.targets, decision.status !== "superseded")
    : [],
);
const targetChoices: ApplicationState[] = [
  "applied",
  "partially_applied",
  "not_applied",
  "no_change_needed",
];
const noTargetChoices: ApplicationState[] = ["not_applied", "no_change_needed"];
const nextAction = computed(
  () =>
    (decision.status === "proposed" ? decision.proposal : (decision.accepted ?? decision.proposal))
      .nextAction,
);
const marking = ref<string | null>(null);

function open(key: string | null, value: boolean) {
  if (value) marking.value = key ?? "decision";
  else if (marking.value === (key ?? "decision")) marking.value = null;
}
function confirm(target: DecisionTarget | null, state: ApplicationState, note: string | null) {
  emit("declare", target?.key ?? null, state, note);
  marking.value = null;
}
// "Go apply" opens the content with this decision under its header.
function applyHref(target: DecisionTarget) {
  if (!target.href || !decision.sessionId) return null;
  return `${target.href}?${new URLSearchParams({ decision: String(decision.id), session: String(decision.sessionId) })}`;
}
function pendingRow(target: DecisionTarget) {
  const state = targetState(target);
  return state === "not_applied" || state === "partially_applied";
}
function when(declaration: DecisionDeclaration) {
  const parsed = new Date(declaration.at);
  return Number.isNaN(parsed.getTime())
    ? ""
    : new Intl.DateTimeFormat(locale.value, { month: "short", day: "numeric" }).format(parsed);
}
</script>
<template>
  <section id="decision-application" aria-labelledby="decision-application-heading">
    <div class="mb-2.5 flex items-center gap-2">
      <h3 id="decision-application-heading" :class="sectionHeading">
        {{ t("brainstormingDecisions.application") }}
      </h3>
      <span
        v-if="application && application.pending > 0 && decision.status !== 'superseded'"
        class="text-[11px] font-medium text-amber-700 dark:text-amber-400"
        >{{
          t("brainstormingDecisions.status.toApply", {
            pending: application.pending,
            total: application.total,
          })
        }}</span
      >
    </div>
    <div
      v-if="!accepted && proposalTargets.length"
      class="rounded-xl border border-dashed border-border px-3 py-2.5"
    >
      <div
        v-for="target in proposalTargets"
        :key="target.key"
        class="flex h-7 items-center gap-2 text-[13px]"
      >
        <component :is="icons[target.type]" class="size-3.5 shrink-0 text-muted-foreground" />
        <span class="truncate font-medium">{{ target.name }}</span>
        <span class="shrink-0 text-[11px] text-muted-foreground">{{
          t(`brainstormingDecisions.targetTypes.${target.type}`)
        }}</span>
        <span class="flex-1" /><span class="text-xs text-muted-foreground">—</span>
      </div>
      <p class="mt-1 text-xs text-muted-foreground">
        {{ t("brainstormingDecisions.applicationAfterAcceptance") }}
      </p>
    </div>
    <p
      v-else-if="!accepted"
      class="rounded-xl border border-dashed border-border px-3 py-2.5 text-xs text-muted-foreground"
    >
      {{ t("brainstormingDecisions.applicationAfterAcceptance") }}
    </p>
    <ul v-else-if="rows.length" class="space-y-2">
      <li
        v-for="target in rows"
        :key="target.key"
        :data-application-target="target.key"
        :data-state="targetState(target)"
        class="rounded-xl border border-border bg-card/60 p-3"
      >
        <div class="flex items-start gap-2.5">
          <component
            :is="icons[target.type]"
            class="mt-0.5 size-[15px] shrink-0 text-muted-foreground"
          />
          <div class="min-w-0 flex-1">
            <p
              class="truncate text-[13px] leading-[18px] font-medium"
              :class="target.available ? '' : 'text-muted-foreground line-through'"
            >
              {{ target.name }}
            </p>
            <p class="mt-0.5 truncate text-[11px] text-muted-foreground">
              {{
                target.isNew
                  ? t("brainstormingDecisions.targetNew")
                  : t(`brainstormingDecisions.targetTypes.${target.type}`)
              }}<template v-if="target.application">
                · {{ target.application.actorName || t("brainstormingDecisions.formerMember") }} ·
                {{ when(target.application) }}</template
              >
            </p>
          </div>
          <span :class="[pill, statePills[targetState(target)]]"
            ><component :is="stateIcons[targetState(target)]" class="size-3" />{{
              t(`brainstormingDecisions.states.${targetState(target)}`)
            }}</span
          >
        </div>
        <p
          v-if="target.application?.note"
          class="mt-2 ml-[25px] text-xs text-muted-foreground italic"
        >
          “{{ target.application.note }}”
        </p>
        <div v-if="decision.canDeclare" class="mt-2.5 flex justify-end gap-1.5">
          <Button
            v-if="pendingRow(target) && applyHref(target)"
            :id="`decision-go-apply-${target.key}`"
            variant="outline"
            size="xs"
            as-child
            ><LiveLink :to="applyHref(target) ?? ''"
              ><ExternalLink class="size-3" />{{
                t("brainstormingDecisions.about.goApply")
              }}</LiveLink
            ></Button
          >
          <Popover
            :open="marking === target.key"
            @update:open="(value: boolean) => open(target.key, value)"
          >
            <PopoverTrigger as-child>
              <Button
                :id="`decision-mark-${target.key}`"
                variant="ghost"
                size="xs"
                :disabled="pending"
                >{{
                  t(
                    target.application
                      ? "brainstormingDecisions.editApplication"
                      : "brainstormingDecisions.markApplied",
                  )
                }}<ChevronDown class="size-3"
              /></Button>
            </PopoverTrigger>
            <PopoverContent align="end" class="w-[300px] p-3">
              <DecisionMarkForm
                :name="target.name"
                :id-prefix="`decision-mark-${target.key}`"
                :initial="target.application?.state ?? 'applied'"
                :initial-note="target.application?.note ?? ''"
                :choices="targetChoices"
                :pending="pending"
                @confirm="(state, note) => confirm(target, state, note)"
                @cancel="marking = null"
              />
            </PopoverContent>
          </Popover>
        </div>
      </li>
    </ul>
    <div v-else-if="application?.decision" class="rounded-xl border border-border bg-card/60 p-3">
      <div class="flex min-h-[26px] flex-wrap items-center gap-2">
        <span :class="[pill, statePills[application.decision.state]]"
          ><component :is="stateIcons[application.decision.state]" class="size-3" />{{
            t(`brainstormingDecisions.states.${application.decision.state}`)
          }}</span
        >
        <span class="text-xs text-muted-foreground"
          >{{ application.decision.actorName || t("brainstormingDecisions.formerMember") }} ·
          {{ when(application.decision) }}</span
        >
        <span class="flex-1" />
        <Popover
          v-if="decision.canDeclare"
          :open="marking === 'decision'"
          @update:open="(value: boolean) => open(null, value)"
        >
          <PopoverTrigger as-child>
            <Button id="decision-edit-no-change" variant="ghost" size="xs" :disabled="pending"
              >{{ t("brainstormingDecisions.editApplication") }}<ChevronDown class="size-3"
            /></Button>
          </PopoverTrigger>
          <PopoverContent align="end" class="w-[300px] p-3">
            <DecisionMarkForm
              :name="decision.proposal.title"
              :title="t('brainstormingDecisions.editApplication')"
              id-prefix="decision-edit-no-change"
              :initial="application.decision.state"
              :initial-note="application.decision.note ?? ''"
              :choices="noTargetChoices"
              :pending="pending"
              @confirm="(state, note) => confirm(null, state, note)"
              @cancel="marking = null"
            />
          </PopoverContent>
        </Popover>
      </div>
      <p v-if="application.decision.note" class="mt-2 text-xs text-muted-foreground italic">
        “{{ application.decision.note }}”
      </p>
    </div>
    <div
      v-else
      class="flex items-center gap-2 rounded-xl border border-dashed border-border px-3 py-2.5"
    >
      <span class="flex-1 text-xs text-muted-foreground">{{
        t("brainstormingDecisions.nothingToApply")
      }}</span>
      <Button
        v-if="decision.canDeclare"
        id="decision-declare-no-change"
        variant="outline"
        size="xs"
        :disabled="pending"
        @click="confirm(null, 'no_change_needed', null)"
        >{{ t("brainstormingDecisions.declareNoChange") }}</Button
      >
    </div>
    <div
      v-if="nextAction"
      id="decision-next-action-line"
      class="mt-2 flex items-start gap-2 text-xs leading-[18px] text-muted-foreground"
    >
      <ArrowRight class="mt-[3px] size-3 shrink-0" />
      <span class="whitespace-nowrap">{{ t("brainstormingDecisions.nextAction") }}:</span>
      <span class="min-w-0 flex-1 text-pretty text-foreground">{{ nextAction.text }}</span>
      <span
        v-if="nextAction.ownerName"
        class="inline-flex shrink-0 items-center gap-[5px] whitespace-nowrap"
        ><UserAvatar :display-name="nextAction.ownerName" size="xs" class="!size-4 !text-[7px]" />{{
          nextAction.ownerName
        }}</span
      >
    </div>
  </section>
</template>
