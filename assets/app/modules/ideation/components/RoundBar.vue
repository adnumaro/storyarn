<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from "vue";
import { Ellipsis, Eye, Lock, Plus, Settings2, Square } from "@lucide/vue";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu";
import EditableText from "@components/forms/EditableText.vue";
import { useBoardText } from "../composables/useBoardText";
import type { HeaderTier, Round, RoundPrivacy, RoundTimerContext } from "../types";
import RoundTimer from "./RoundTimer.vue";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";

// The header of a round band: number, question, status and, for the
// facilitator, the round actions. The line under the content is the band
// boundary; everything below it belongs to this round. The header is drawn
// over the canvas but only its controls take the pointer: a note that ends up
// under the header row stays reachable, and a drag can start across it.
//
// The question is the one piece that never gives way: whole, on one line, at
// every width. The header measures itself and everything else changes form
// by tier: the controls drop to a second row when the two groups do not fit,
// secondary pieces thin out, actions fold into a menu, and below 640 px the
// question stands alone on the first row.
const {
  round,
  single = false,
  last = false,
  canManage = false,
  pending = false,
  contact = false,
  timer = null,
  count = 0,
  sticky = false,
  inset = 0,
} = defineProps<{
  round: Round;
  /** The session has a single round: the header stays quiet about rounds. */
  single?: boolean;
  /** Last band of the session: a closed one still offers the next round. */
  last?: boolean;
  canManage?: boolean;
  pending?: boolean;
  /** A dragged note is pressing against this header's line. */
  contact?: boolean;
  /** The session timer, shown on the round in progress only. */
  timer?: RoundTimerContext | null;
  /** Notes in the band, hidden ones included. */
  count?: number;
  /** Pinned under the app chrome while the viewport is inside the band: frosted, no shadow. */
  sticky?: boolean;
  /** Room to leave on the left for the floating chrome while pinned, in px. */
  inset?: number;
}>();
const emit = defineEmits<{
  close: [id: number];
  newRound: [];
  updatePrompt: [id: number, prompt: string];
  updatePrivacy: [id: number, attrs: RoundPrivacy];
  reveal: [id: number];
}>();
const { t } = useBoardText();
const active = computed(() => round.status === "active");
// The facilitator writes the question in place while the round is in progress.
const editable = computed(() => canManage && active.value);
const noteCount = computed(() =>
  count === 1 ? t("ideation.rounds.noteCountOne") : t("ideation.rounds.noteCountOther", { count }),
);
// Width tiers, measured on the header itself; until measured, the desktop layout.
const root = ref<HTMLElement | null>(null);
const width = ref(1440);
let observer: ResizeObserver | undefined;
onMounted(() => {
  if (typeof ResizeObserver === "undefined" || !root.value) return;
  observer = new ResizeObserver(([entry]) => {
    width.value = entry!.contentRect.width;
  });
  observer.observe(root.value);
});
onUnmounted(() => observer?.disconnect());
const tier = computed<HeaderTier>(() => {
  if (width.value >= 1280) return "xl";
  if (width.value >= 1000) return "l";
  if (width.value >= 800) return "m";
  if (width.value >= 640) return "s";
  return "xs";
});
const wide = computed(() => tier.value === "xl" || tier.value === "l");
const roomy = computed(() => wide.value || tier.value === "m");
const stacked = computed(() => tier.value === "xs");
// Wider than its row, the question pans under an edge fade rather than wrap.
const questionEl = ref<HTMLElement | null>(null);
const panning = ref(false);
watch(
  [width, () => round.prompt, tier],
  () => {
    void nextTick(() => {
      const el = questionEl.value;
      panning.value = !!el && el.scrollWidth > el.clientWidth;
    });
  },
  { immediate: true },
);
const timerRef = ref<InstanceType<typeof RoundTimer> | null>(null);
// Folded actions: round actions and the timer's stop and settings, below 1000 px.
const overflow = computed(
  () => canManage && !wide.value && (active.value || (stacked.value && last && !single)),
);
const controls = computed(
  () => !!timer || (canManage && (round.private || !single || active.value)) || overflow.value,
);
function setPrivacy(attrs: RoundPrivacy) {
  emit("updatePrivacy", round.id, attrs);
}
// Enter saves and the blur that follows saves again; the draft makes the
// second one a no-op while the server's echo of the prompt is still on its way.
const draft = ref(round.prompt ?? "");
watch(
  () => round.prompt,
  (prompt) => {
    draft.value = prompt ?? "";
  },
);
// The line is the band boundary; with a timer running it also fills as time passes.
const progress = ref(0);
const timerState = computed(() => timer?.timer?.status ?? null);
const lineClass = computed(() => {
  if (contact) return "h-0.5 bg-primary shadow-[0_0_8px_hsl(var(--primary)/0.6)]";
  if (single && !timerState.value) return "h-0 bg-transparent";
  return active.value ? "h-0.5 bg-foreground/20" : "h-px bg-border";
});
const fillClass = computed(() => {
  if (timerState.value === "paused") return "bg-muted-foreground/60";
  if (timerState.value === "running" || timerState.value === "elapsed")
    return "bg-primary shadow-[0_0_8px_hsl(var(--primary)/0.6)]";
  return null;
});
</script>
<template>
  <div
    :id="`brainstorming-round-${round.id}`"
    ref="root"
    :data-status="round.status"
    :data-tier="tier"
    data-canvas-chrome
    class="relative select-none"
    :class="contact ? 'bg-primary/5' : sticky ? 'bg-background/[0.86] backdrop-blur-[12px]' : ''"
  >
    <div
      class="flex flex-wrap items-center gap-x-3 px-4"
      :style="inset ? { paddingLeft: `${inset}px` } : undefined"
    >
      <span
        v-if="!single"
        class="flex h-10 shrink-0 items-center text-sm font-semibold"
        :class="[
          active ? 'text-primary' : 'text-muted-foreground',
          stacked ? 'order-2' : 'order-1',
        ]"
        >{{ t("ideation.rounds.number", { number: round.number }) }}</span
      >
      <div
        class="order-1 flex h-10 max-w-full shrink-0 items-center gap-3 whitespace-nowrap"
        :class="stacked && 'basis-full'"
      >
        <span
          v-if="editable || round.prompt"
          ref="questionEl"
          class="flex min-w-0 shrink items-center overflow-x-auto [scrollbar-width:none]"
          :class="
            panning &&
            'pr-12 [mask-image:linear-gradient(to_right,black_calc(100%-48px),transparent)]'
          "
        >
          <EditableText
            v-if="editable"
            :id="`brainstorming-round-prompt-${round.id}`"
            v-model="draft"
            :placeholder="t('ideation.rounds.addQuestion')"
            :disabled="pending"
            class="pointer-events-auto text-sm"
            display-class="text-sm"
            @save="emit('updatePrompt', round.id, $event)"
          />
          <span
            v-else-if="round.prompt"
            class="text-sm"
            :class="active ? 'text-foreground' : 'text-muted-foreground'"
            >{{ round.prompt }}</span
          >
        </span>
        <Badge
          v-if="!single && wide"
          :variant="active ? 'outline' : 'secondary'"
          class="shrink-0 font-medium"
        >
          <span
            v-if="active"
            aria-hidden="true"
            class="mr-1.5 inline-block size-1.5 rounded-full bg-primary"
          />
          <span :class="active ? '' : 'text-muted-foreground'">{{
            t(active ? "ideation.rounds.active" : "ideation.rounds.closed")
          }}</span>
        </Badge>
        <span
          v-if="roomy"
          :id="`brainstorming-round-count-${round.id}`"
          class="shrink-0 text-xs tabular-nums text-muted-foreground"
          >{{ noteCount }}</span
        >
      </div>
      <span
        v-if="round.private"
        :id="`brainstorming-round-private-${round.id}`"
        class="flex h-10 shrink-0 items-center text-primary"
        :class="stacked ? 'order-2' : 'order-1'"
        :aria-label="t('ideation.rounds.private')"
      >
        <Badge v-if="roomy" variant="outline" class="gap-1 font-medium text-primary"
          ><Lock class="size-3" />{{ t("ideation.rounds.private") }}</Badge
        >
        <Lock v-else class="size-3.5" />
      </span>
      <div
        v-if="controls"
        :id="`brainstorming-round-controls-${round.id}`"
        class="ml-auto flex h-10 shrink-0 grow items-center justify-end gap-2"
        :class="stacked ? 'order-3' : 'order-1'"
      >
        <RoundTimer
          v-if="timer"
          ref="timerRef"
          :session="timer.session"
          :epoch="timer.epoch"
          :timer="timer.timer"
          :can-manage="canManage"
          :can-edit="timer.canEdit"
          :tier="tier"
          @progress="progress = $event"
        />
        <Button
          v-if="canManage && round.private"
          :id="`brainstorming-round-reveal-${round.id}`"
          class="pointer-events-auto"
          :class="wide ? '' : 'w-8 px-0'"
          variant="outline"
          size="sm"
          :disabled="pending"
          :aria-label="t('ideation.rounds.reveal')"
          @click="emit('reveal', round.id)"
          ><Eye class="size-3.5" /><span v-if="wide">{{
            t("ideation.rounds.reveal")
          }}</span></Button
        >
        <DropdownMenu v-if="canManage && active && wide">
          <DropdownMenuTrigger as-child>
            <button
              :id="`brainstorming-round-settings-${round.id}`"
              type="button"
              class="toolbar-btn pointer-events-auto"
              :aria-label="t('ideation.rounds.settings')"
              :disabled="pending"
            >
              <Settings2 class="size-3.5" />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuCheckboxItem
              :id="`brainstorming-round-private-toggle-${round.id}`"
              :model-value="round.private"
              :disabled="pending || !!round.revealed_at"
              @update:model-value="
                setPrivacy({ private: $event === true, reveal_on_expiry: round.reveal_on_expiry })
              "
              >{{ t("ideation.rounds.privateSetting") }}</DropdownMenuCheckboxItem
            >
            <DropdownMenuCheckboxItem
              :id="`brainstorming-round-reveal-on-expiry-${round.id}`"
              :model-value="round.reveal_on_expiry"
              :disabled="pending || !round.private"
              @update:model-value="
                setPrivacy({ private: round.private, reveal_on_expiry: $event === true })
              "
              >{{ t("ideation.rounds.revealOnExpiry") }}</DropdownMenuCheckboxItem
            >
          </DropdownMenuContent>
        </DropdownMenu>
        <template v-if="canManage && !single">
          <template v-if="active && wide">
            <span aria-hidden="true" class="h-5 w-px bg-border" />
            <ToolbarTooltip :label="t('ideation.rounds.closeHint')">
              <Button
                :id="`brainstorming-round-close-${round.id}`"
                class="pointer-events-auto"
                variant="ghost"
                size="sm"
                :disabled="pending"
                :aria-label="t('ideation.rounds.close')"
                @click="emit('close', round.id)"
                ><Square class="size-3.5" />{{ t("ideation.rounds.close") }}</Button
              >
            </ToolbarTooltip>
          </template>
          <Button
            v-if="(active || last) && !stacked"
            :id="`brainstorming-round-new-${round.id}`"
            class="pointer-events-auto"
            :class="roomy ? '' : 'w-8 px-0'"
            variant="outline"
            size="sm"
            :disabled="pending"
            :aria-label="t('ideation.rounds.newRound')"
            @click="emit('newRound')"
            ><Plus class="size-3.5" /><span v-if="roomy">{{
              t("ideation.rounds.newRound")
            }}</span></Button
          >
        </template>
        <DropdownMenu v-if="overflow">
          <DropdownMenuTrigger as-child>
            <button
              :id="`brainstorming-round-more-${round.id}`"
              type="button"
              class="toolbar-btn pointer-events-auto"
              :aria-label="t('ideation.rounds.more')"
              :disabled="pending"
            >
              <Ellipsis class="size-3.5" />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem
              v-if="active && !single"
              :id="`brainstorming-round-close-${round.id}`"
              @select="emit('close', round.id)"
              ><Square class="size-3.5" />{{ t("ideation.rounds.close") }}</DropdownMenuItem
            >
            <DropdownMenuItem
              v-if="stacked && (active || last) && !single"
              :id="`brainstorming-round-new-${round.id}`"
              @select="emit('newRound')"
              ><Plus class="size-3.5" />{{ t("ideation.rounds.newRound") }}</DropdownMenuItem
            >
            <template v-if="active">
              <DropdownMenuSeparator v-if="!single" />
              <DropdownMenuItem
                v-if="timerRef?.stoppable"
                id="brainstorming-round-timer-cancel"
                @select="timerRef?.cancel()"
                ><Square class="size-3.5" />{{ t("ideation.timer.cancel") }}</DropdownMenuItem
              >
              <DropdownMenuSub>
                <DropdownMenuSubTrigger
                  ><span :id="`brainstorming-round-settings-${round.id}`" class="flex items-center"
                    ><Settings2 class="mr-2 size-3.5" />{{ t("ideation.rounds.settings") }}</span
                  ></DropdownMenuSubTrigger
                >
                <DropdownMenuSubContent>
                  <DropdownMenuCheckboxItem
                    :id="`brainstorming-round-private-toggle-${round.id}`"
                    :model-value="round.private"
                    :disabled="pending || !!round.revealed_at"
                    @update:model-value="
                      setPrivacy({
                        private: $event === true,
                        reveal_on_expiry: round.reveal_on_expiry,
                      })
                    "
                    >{{ t("ideation.rounds.privateSetting") }}</DropdownMenuCheckboxItem
                  >
                  <DropdownMenuCheckboxItem
                    :id="`brainstorming-round-reveal-on-expiry-${round.id}`"
                    :model-value="round.reveal_on_expiry"
                    :disabled="pending || !round.private"
                    @update:model-value="
                      setPrivacy({ private: round.private, reveal_on_expiry: $event === true })
                    "
                    >{{ t("ideation.rounds.revealOnExpiry") }}</DropdownMenuCheckboxItem
                  >
                </DropdownMenuSubContent>
              </DropdownMenuSub>
            </template>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </div>
    <div class="relative" :class="lineClass">
      <div
        v-if="fillClass"
        :id="`brainstorming-round-progress-${round.id}`"
        class="absolute inset-y-0 left-0 transition-[width] duration-300"
        :class="fillClass"
        :style="{ width: `${Math.round(progress * 1000) / 10}%` }"
      />
    </div>
  </div>
</template>
