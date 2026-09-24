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
  FileText,
  Workflow,
} from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Textarea } from "@components/ui/textarea";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import UserAvatar from "@components/UserAvatar.vue";
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
const stateTones: Record<ApplicationState, string> = {
  applied: "text-emerald-700 dark:text-emerald-400",
  partially_applied: "text-amber-700 dark:text-amber-400",
  not_applied: "text-amber-700 dark:text-amber-400",
  no_change_needed: "text-muted-foreground",
};
const choices: ApplicationState[] = [
  "applied",
  "partially_applied",
  "not_applied",
  "no_change_needed",
];
const noTargetChoices: ApplicationState[] = ["not_applied", "no_change_needed"];

const application = computed(() => decision.application);
const accepted = computed(() => decision.accepted !== null);
const proposalTargets = computed(() => decision.proposal.targets);
const rows = computed(() =>
  application.value
    ? orderTargets(application.value.targets, decision.status !== "superseded")
    : [],
);
const nextAction = computed(
  () =>
    (decision.status === "proposed" ? decision.proposal : (decision.accepted ?? decision.proposal))
      .nextAction,
);
const marking = ref<string | null>(null);
const choice = ref<ApplicationState>("applied");
const note = ref("");

function declarationFor(target: DecisionTarget | null) {
  return target ? target.application : (application.value?.decision ?? null);
}
function beginMarking(target: DecisionTarget | null) {
  const key = target?.key ?? null;
  marking.value = key ?? "decision";
  const declaration = declarationFor(target);
  choice.value = declaration?.state ?? (target ? "applied" : "no_change_needed");
  note.value = declaration?.note ?? "";
}
function open(target: DecisionTarget | null, value: boolean) {
  if (value) beginMarking(target);
  else if (marking.value === (target?.key ?? "decision")) marking.value = null;
}
function confirm(target: DecisionTarget | null) {
  emit("declare", target?.key ?? null, choice.value, note.value.trim() || null);
  marking.value = null;
}
function declareNoChange() {
  emit("declare", null, "no_change_needed", null);
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
    <div class="mb-2 flex items-center gap-2">
      <h3 id="decision-application-heading" class="text-xs font-normal text-muted-foreground">
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
    <div v-else-if="rows.length" class="overflow-hidden rounded-xl border border-border">
      <div
        v-for="(target, index) in rows"
        :key="target.key"
        :data-application-target="target.key"
        :data-state="targetState(target)"
        class="px-3 py-2.5"
        :class="index ? 'border-t border-border' : ''"
      >
        <div class="flex min-h-[26px] flex-wrap items-center gap-x-2 gap-y-1">
          <component :is="icons[target.type]" class="size-3.5 shrink-0 text-muted-foreground" />
          <span
            class="min-w-0 truncate text-[13px] font-medium"
            :class="target.available ? '' : 'text-muted-foreground line-through'"
            >{{ target.name }}</span
          >
          <span class="shrink-0 text-[11px] text-muted-foreground">{{
            target.isNew
              ? t("brainstormingDecisions.targetNew")
              : t(`brainstormingDecisions.targetTypes.${target.type}`)
          }}</span>
          <span class="flex-1" />
          <span
            class="inline-flex shrink-0 items-center gap-[5px] text-xs font-medium"
            :class="stateTones[targetState(target)]"
            ><component :is="stateIcons[targetState(target)]" class="size-[13px]" />{{
              t(`brainstormingDecisions.states.${targetState(target)}`)
            }}</span
          >
          <span v-if="target.application" class="shrink-0 text-xs text-muted-foreground"
            >· {{ target.application.actorName || t("brainstormingDecisions.formerMember") }} ·
            {{ when(target.application) }}</span
          >
        </div>
        <p
          v-if="target.application?.note"
          class="mt-1 ml-[22px] text-xs text-muted-foreground italic"
        >
          “{{ target.application.note }}”
        </p>
        <div v-if="decision.canDeclare" class="mt-2 ml-[22px] flex gap-1.5">
          <Popover
            :open="marking === target.key"
            @update:open="(value: boolean) => open(target, value)"
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
            <PopoverContent align="start" class="w-[300px] p-3">
              <p class="text-[13px] font-medium">
                {{
                  t("brainstormingDecisions.markAs", {
                    name: target.name,
                    state: t(`brainstormingDecisions.stateChips.${choice}`),
                  })
                }}
              </p>
              <p class="mt-0.5 text-xs text-muted-foreground">
                {{ t("brainstormingDecisions.markStatement") }}
              </p>
              <div
                class="mt-2.5 grid grid-cols-2 rounded-md border border-border p-0.5"
                role="radiogroup"
              >
                <button
                  v-for="option in choices"
                  :id="`decision-mark-${target.key}-${option}`"
                  :key="option"
                  type="button"
                  role="radio"
                  :aria-checked="choice === option"
                  class="flex-1 rounded-[5px] px-1.5 py-1 text-[11.5px]"
                  :class="
                    choice === option
                      ? 'bg-accent font-medium text-foreground'
                      : 'text-muted-foreground'
                  "
                  @click="choice = option"
                >
                  {{ t(`brainstormingDecisions.states.${option}`) }}
                </button>
              </div>
              <Textarea
                v-model="note"
                class="mt-2.5"
                :rows="2"
                :maxlength="1000"
                :placeholder="t('brainstormingDecisions.notePlaceholder')"
              />
              <div class="mt-2.5 flex justify-end gap-1.5">
                <Button variant="ghost" size="sm" @click="marking = null">{{
                  t("brainstormingDecisions.cancel")
                }}</Button>
                <Button
                  :id="`decision-mark-${target.key}-confirm`"
                  size="sm"
                  :disabled="pending"
                  @click="confirm(target)"
                  >{{ t(`brainstormingDecisions.markConfirm.${choice}`) }}</Button
                >
              </div>
            </PopoverContent>
          </Popover>
        </div>
      </div>
    </div>
    <div v-else-if="application?.decision" class="rounded-xl border border-border px-3 py-2.5">
      <div class="flex min-h-[26px] flex-wrap items-center gap-2">
        <component
          :is="stateIcons[application.decision.state]"
          class="size-3.5"
          :class="stateTones[application.decision.state]"
        />
        <span class="text-[13px] font-medium">{{
          t(`brainstormingDecisions.states.${application.decision.state}`)
        }}</span>
        <span class="text-xs text-muted-foreground"
          >· {{ application.decision.actorName || t("brainstormingDecisions.formerMember") }} ·
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
            <p class="text-[13px] font-medium">{{ t("brainstormingDecisions.editApplication") }}</p>
            <p class="mt-0.5 text-xs text-muted-foreground">
              {{ t("brainstormingDecisions.markStatement") }}
            </p>
            <div
              class="mt-2.5 grid grid-cols-2 rounded-md border border-border p-0.5"
              role="radiogroup"
            >
              <button
                v-for="option in noTargetChoices"
                :id="`decision-no-target-${option}`"
                :key="option"
                type="button"
                role="radio"
                :aria-checked="choice === option"
                class="rounded-[5px] px-1.5 py-1 text-[11.5px]"
                :class="
                  choice === option
                    ? 'bg-accent font-medium text-foreground'
                    : 'text-muted-foreground'
                "
                @click="choice = option"
              >
                {{ t(`brainstormingDecisions.states.${option}`) }}
              </button>
            </div>
            <Textarea
              v-model="note"
              class="mt-2.5"
              :rows="2"
              :maxlength="1000"
              :placeholder="t('brainstormingDecisions.notePlaceholder')"
            />
            <div class="mt-2.5 flex justify-end gap-1.5">
              <Button variant="ghost" size="sm" @click="marking = null">{{
                t("brainstormingDecisions.cancel")
              }}</Button>
              <Button
                id="decision-edit-no-change-confirm"
                size="sm"
                :disabled="pending"
                @click="confirm(null)"
                >{{ t(`brainstormingDecisions.markConfirm.${choice}`) }}</Button
              >
            </div>
          </PopoverContent>
        </Popover>
      </div>
      <p
        v-if="application.decision.note"
        class="mt-1 ml-[22px] text-xs text-muted-foreground italic"
      >
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
        @click="declareNoChange"
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
