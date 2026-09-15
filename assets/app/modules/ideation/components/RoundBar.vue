<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { Eye, Lock, Plus, Settings2, Square } from "@lucide/vue";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu";
import EditableText from "@components/forms/EditableText.vue";
import { useBoardText } from "../composables/useBoardText";
import type { Round, RoundPrivacy, RoundTimerContext } from "../types";
import RoundTimer from "./RoundTimer.vue";

// The header of a round band: number, question, status and, for the
// facilitator, the round actions. The line under the content is the band
// boundary; everything below it belongs to this round. The header is drawn
// over the canvas but only its controls take the pointer: a note that ends up
// under the header row stays reachable, and a drag can start across it.
const {
  round,
  single = false,
  last = false,
  canManage = false,
  pending = false,
  contact = false,
  timer = null,
  count = 0,
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
const timerState = computed(() => (active.value ? (timer?.timer?.status ?? null) : null));
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
    :data-status="round.status"
    data-canvas-chrome
    class="relative select-none"
    :class="contact ? 'bg-primary/5' : ''"
  >
    <div class="flex min-h-10 items-center gap-3 px-4">
      <span
        v-if="!single"
        class="shrink-0 text-sm font-semibold"
        :class="active ? 'text-primary' : 'text-muted-foreground'"
        >{{ t("ideation.rounds.number", { number: round.number }) }}</span
      >
      <EditableText
        v-if="editable"
        :id="`brainstorming-round-prompt-${round.id}`"
        v-model="draft"
        :placeholder="t('ideation.rounds.addQuestion')"
        :disabled="pending"
        class="pointer-events-auto min-w-0 flex-initial truncate text-sm"
        display-class="text-sm"
        @save="emit('updatePrompt', round.id, $event)"
      />
      <span
        v-else-if="round.prompt"
        class="min-w-0 truncate text-sm"
        :class="active ? 'text-foreground' : 'text-muted-foreground'"
        :title="round.prompt"
        >{{ round.prompt }}</span
      >
      <Badge
        v-if="!single"
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
      <Badge
        v-if="round.private"
        :id="`brainstorming-round-private-${round.id}`"
        variant="outline"
        class="shrink-0 gap-1 font-medium text-primary"
        ><Lock class="size-3" />{{ t("ideation.rounds.private") }}</Badge
      >
      <span
        :id="`brainstorming-round-count-${round.id}`"
        class="shrink-0 text-xs tabular-nums text-muted-foreground"
        >{{ noteCount }}</span
      >
      <span class="flex-1" />
      <RoundTimer
        v-if="active && timer"
        :session="timer.session"
        :epoch="timer.epoch"
        :timer="timer.timer"
        :can-manage="canManage"
        :can-edit="timer.canEdit"
        @progress="progress = $event"
      />
      <Button
        v-if="canManage && round.private"
        :id="`brainstorming-round-reveal-${round.id}`"
        class="pointer-events-auto"
        variant="outline"
        size="sm"
        :disabled="pending"
        @click="emit('reveal', round.id)"
        ><Eye class="size-3.5" />{{ t("ideation.rounds.reveal") }}</Button
      >
      <DropdownMenu v-if="canManage && active">
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
        <template v-if="active">
          <span aria-hidden="true" class="h-5 w-px bg-border" />
          <Button
            :id="`brainstorming-round-close-${round.id}`"
            class="pointer-events-auto"
            variant="ghost"
            size="sm"
            :disabled="pending"
            @click="emit('close', round.id)"
            ><Square class="size-3.5" />{{ t("ideation.rounds.close") }}</Button
          >
        </template>
        <Button
          v-if="active || last"
          :id="`brainstorming-round-new-${round.id}`"
          class="pointer-events-auto"
          variant="outline"
          size="sm"
          :disabled="pending"
          @click="emit('newRound')"
          ><Plus class="size-3.5" />{{ t("ideation.rounds.newRound") }}</Button
        >
      </template>
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
