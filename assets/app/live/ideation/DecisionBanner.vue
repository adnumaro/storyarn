<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch, type Component } from "vue";
import { useI18n } from "vue-i18n";
import {
  Check,
  Clapperboard,
  FileText,
  Lightbulb,
  ListChecks,
  Undo2,
  Workflow,
  X,
} from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import LiveLink from "@components/navigation/LiveLink.vue";
import DecisionMarkForm from "./DecisionMarkForm.vue";
import type { ApplicationState, DecisionBannerState, DecisionTargetType } from "./decisionTypes";

type Mark = Exclude<ApplicationState, "not_applied">;

const UNDO_SECONDS = 5;

/**
 * Arriving from "Go apply", the decision sits under the editor header for this
 * visit. Marking is a statement about this content, never an automatic change.
 */
const { banner, pending = false } = defineProps<{
  banner: DecisionBannerState;
  pending?: boolean;
}>();
const emit = defineEmits<{
  declare: [state: ApplicationState, note: string | null];
  undo: [];
  dismiss: [];
}>();
const { t, te } = useI18n();
const errorText = computed(() => {
  const key = `brainstormingDecisions.errors.${banner.error}`;
  return t(te(key) ? key : "brainstormingDecisions.errors.unavailable");
});
const icons: Record<DecisionTargetType, Component> = {
  sheet: FileText,
  flow: Workflow,
  scene: Clapperboard,
};
const marks: Mark[] = ["applied", "partially_applied", "no_change_needed"];
const agreement = computed(() => banner.decision.accepted ?? banner.decision.proposal);
const target = computed(() =>
  agreement.value.targets.find((item) => item.key === banner.targetKey),
);
const expanded = ref(false);
const marking = ref<Mark | null>(null);
const seconds = ref(UNDO_SECONDS);
let timer: ReturnType<typeof setInterval> | null = null;

// The mark form closes once the mark is confirmed; a failure keeps the note.
function declare(state: ApplicationState, note: string | null) {
  emit("declare", state, note);
}
// The confirmation stays a few seconds for Undo, then the banner leaves.
watch(
  () => banner.marked?.state ?? null,
  (state) => {
    if (timer) clearInterval(timer);
    timer = null;
    if (!state) return;
    marking.value = null;
    seconds.value = UNDO_SECONDS;
    timer = setInterval(() => {
      seconds.value -= 1;
      if (seconds.value <= 0) {
        if (timer) clearInterval(timer);
        timer = null;
        emit("dismiss");
      }
    }, 1000);
  },
  { immediate: true },
);
onBeforeUnmount(() => timer && clearInterval(timer));
</script>
<template>
  <section
    id="decision-banner"
    :data-decision-banner="banner.decision.id"
    aria-labelledby="decision-banner-title"
    class="rounded-xl border border-border bg-popover py-2.5 pr-3 pl-3.5 text-popover-foreground shadow-lg"
  >
    <div v-if="banner.marked" class="flex items-center gap-2 text-[13px]" role="status">
      <Check class="size-4 shrink-0 text-emerald-700 dark:text-emerald-400" />
      <span id="decision-banner-title" class="min-w-0 flex-1 truncate">
        {{ t(`brainstormingDecisions.banner.marked.${banner.marked.state}`) }} ·
        <span class="text-muted-foreground">{{ t("brainstormingDecisions.banner.justNow") }}</span>
        · {{ target?.name }} ·
        <span class="text-muted-foreground">{{ agreement.title }}</span>
      </span>
      <Button
        id="decision-banner-undo"
        variant="ghost"
        size="xs"
        :disabled="pending"
        @click="emit('undo')"
        ><Undo2 class="size-3" />{{ t("brainstormingDecisions.banner.undo") }}</Button
      >
      <span class="w-6 text-right text-[11px] text-muted-foreground tabular-nums"
        >{{ seconds }} s</span
      >
    </div>
    <div v-else class="flex items-start gap-3">
      <ListChecks class="mt-0.5 size-[18px] shrink-0 text-emerald-700 dark:text-emerald-400" />
      <div class="min-w-0 flex-1">
        <div class="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1">
          <h2 id="decision-banner-title" class="truncate text-sm font-semibold">
            {{ agreement.title }}
          </h2>
          <span class="text-xs text-muted-foreground">{{
            t(`brainstormingDecisions.verbs.${agreement.verb}`)
          }}</span>
          <span
            v-if="target"
            class="inline-flex h-[22px] items-center gap-1.5 rounded-md border border-border bg-muted/45 pr-2 pl-[7px] text-xs whitespace-nowrap"
            ><component :is="icons[target.type]" class="size-3 text-muted-foreground" />{{
              target.name
            }}</span
          >
          <LiveLink
            :to="banner.sessionUrl"
            class="inline-flex min-w-0 items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground"
            ><Lightbulb class="size-3 shrink-0" /><span class="truncate">{{
              banner.sessionTitle
            }}</span></LiveLink
          >
        </div>
        <p
          class="mt-0.5 text-[13px] text-muted-foreground"
          :class="expanded ? 'whitespace-pre-wrap' : 'line-clamp-1'"
        >
          {{ agreement.conclusion }}
          <button
            v-if="!expanded"
            type="button"
            class="font-medium text-primary hover:underline"
            @click="expanded = true"
          >
            {{ t("brainstormingDecisions.banner.showMore") }}
          </button>
        </p>
        <p v-if="banner.error" role="alert" class="mt-1 text-xs text-destructive">
          {{ errorText }}
        </p>
      </div>
      <div v-if="banner.decision.canDeclare && target" class="flex shrink-0 items-center gap-1">
        <Popover
          v-for="mark in marks"
          :key="mark"
          :open="marking === mark"
          @update:open="(value: boolean) => (marking = value ? mark : null)"
        >
          <PopoverTrigger as-child>
            <Button
              :id="`decision-banner-${mark}`"
              :variant="mark === 'applied' ? 'default' : 'ghost'"
              size="xs"
              :disabled="pending"
              >{{ t(`brainstormingDecisions.banner.actions.${mark}`) }}</Button
            >
          </PopoverTrigger>
          <PopoverContent align="end" class="w-[300px] p-3">
            <DecisionMarkForm
              :name="target.name"
              id-prefix="decision-banner-mark"
              :initial="mark"
              :choosable="false"
              :pending="pending"
              @confirm="declare"
              @cancel="marking = null"
            />
          </PopoverContent>
        </Popover>
      </div>
      <button
        id="decision-banner-close"
        type="button"
        class="-mr-1 rounded-md p-1 text-muted-foreground hover:bg-accent hover:text-foreground"
        :aria-label="t('brainstormingDecisions.banner.close')"
        @click="emit('dismiss')"
      >
        <X class="size-4" />
      </button>
    </div>
  </section>
</template>
