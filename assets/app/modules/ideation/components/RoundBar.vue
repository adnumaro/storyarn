<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { Plus, Square } from "@lucide/vue";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import EditableText from "@components/forms/EditableText.vue";
import { useBoardText } from "../composables/useBoardText";
import type { Round } from "../types";

// The header of a round band: number, question, status and, for the
// facilitator, the round actions. The line under the content is the band
// boundary; everything below it belongs to this round.
const {
  round,
  single = false,
  last = false,
  canManage = false,
  pending = false,
  contact = false,
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
}>();
const emit = defineEmits<{
  close: [id: number];
  newRound: [];
  updatePrompt: [id: number, prompt: string];
}>();
const { t } = useBoardText();
const active = computed(() => round.status === "active");
// The facilitator writes the question in place while the round is in progress.
const editable = computed(() => canManage && active.value);
// Enter saves and the blur that follows saves again; the draft makes the
// second one a no-op while the server's echo of the prompt is still on its way.
const draft = ref(round.prompt ?? "");
watch(
  () => round.prompt,
  (prompt) => {
    draft.value = prompt ?? "";
  },
);
const lineClass = computed(() => {
  if (contact) return "h-0.5 bg-primary shadow-[0_0_8px_hsl(var(--primary)/0.6)]";
  if (single) return "h-0 bg-transparent";
  return active.value ? "h-0.5 bg-foreground/20" : "h-px bg-border";
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
        class="min-w-0 flex-initial truncate text-sm"
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
      <span class="flex-1" />
      <template v-if="canManage && !single">
        <template v-if="active">
          <span aria-hidden="true" class="h-5 w-px bg-border" />
          <Button
            :id="`brainstorming-round-close-${round.id}`"
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
          variant="outline"
          size="sm"
          :disabled="pending"
          @click="emit('newRound')"
          ><Plus class="size-3.5" />{{ t("ideation.rounds.newRound") }}</Button
        >
      </template>
    </div>
    <div :class="lineClass" />
  </div>
</template>
