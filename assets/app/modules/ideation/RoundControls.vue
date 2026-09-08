<script setup lang="ts">
import { computed, onUnmounted, ref, watch } from "vue";
import { Layers, Pencil, Play, Plus, Square, X } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import { Textarea } from "@components/ui/textarea";
import { Label } from "@components/ui/label";
import { useLive } from "@shared/composables/useLive";
import { useBoardText } from "./composables/useBoardText";
import type { Round, Session } from "./types";

const { session, epoch, rounds, roundsNext, activeRound, canManage, canEdit } = defineProps<{
  session: Session;
  epoch: string;
  rounds: Round[];
  roundsNext: number | null;
  activeRound: Round | null;
  canManage: boolean;
  canEdit: boolean;
}>();
const { t, error } = useBoardText();
const live = useLive();
const prompt = ref("");
const editing = ref<number | null>(null);
const editedPrompt = ref("");
const editingRevision = ref(session.revision);
const promptConflict = ref(false);
const failure = ref<string | null>(null);
const pending = ref(false);
const mayManage = computed(() => canManage && canEdit && session.status === "open");
const entries = computed(() => {
  const all = new Map(rounds.map((round) => [round.id, round]));
  if (activeRound) all.set(activeRound.id, activeRound);
  return [...all.values()].sort((a, b) => b.number - a.number);
});
let generation = 0;
function send(
  event: string,
  payload: Record<string, unknown>,
  success?: () => void,
  revision = session.revision,
  rejected?: (code: string) => void,
) {
  if (pending.value) return;
  pending.value = true;
  failure.value = null;
  const started = generation;
  live.pushEvent(
    event,
    {
      ...payload,
      epoch,
      session_id: session.id,
      ...(event === "browse_rounds" ? {} : { revision }),
    },
    (reply) => {
      if (started !== generation) return;
      pending.value = false;
      if (reply?.status === "ok") success?.();
      else {
        failure.value = String(reply?.code ?? "unavailable");
        rejected?.(failure.value);
      }
    },
    () => {
      if (started !== generation) return;
      pending.value = false;
      failure.value = "offline";
    },
  );
}
function create() {
  if (!mayManage.value) return;
  send("create_round", { prompt: prompt.value.trim() || null }, () => (prompt.value = ""));
}
function beginEdit(round: Round) {
  if (!mayManage.value || pending.value || round.status !== "planned") return;
  editing.value = round.id;
  editedPrompt.value = round.prompt ?? "";
  editingRevision.value = session.revision;
  promptConflict.value = false;
  failure.value = null;
}
function closeEdit() {
  editing.value = null;
  promptConflict.value = false;
  failure.value = null;
}
function savePrompt(round: Round, replaceCurrent = false) {
  if (!mayManage.value || pending.value || round.status !== "planned") return;
  if (replaceCurrent) {
    if (!promptConflict.value || session.revision === editingRevision.value) return;
    // Taking a newer revision requires an explicit choice after comparing the
    // current question with the preserved local draft.
    editingRevision.value = session.revision;
    promptConflict.value = false;
  } else if (promptConflict.value) return;
  send(
    "update_round",
    { round_id: round.id, prompt: editedPrompt.value.trim() || null },
    closeEdit,
    editingRevision.value,
    (code) => {
      if (code === "stale_revision") promptConflict.value = true;
    },
  );
}
function transition(round: Round, event: "start_round" | "close_round" | "cancel_round") {
  if (!mayManage.value) return;
  send(event, { round_id: round.id });
}
watch([() => epoch, () => session.id], () => {
  generation++;
  pending.value = false;
  failure.value = null;
  prompt.value = "";
  editing.value = null;
  editedPrompt.value = "";
  promptConflict.value = false;
});
watch(
  () => [entries.value, mayManage.value],
  () => {
    if (
      editing.value !== null &&
      (!mayManage.value ||
        !entries.value.some((round) => round.id === editing.value && round.status === "planned"))
    )
      closeEdit();
  },
);
onUnmounted(() => generation++);
</script>
<template>
  <Popover>
    <PopoverTrigger as-child>
      <button
        id="brainstorming-rounds-trigger"
        type="button"
        class="toolbar-btn gap-1.5"
        :class="activeRound ? 'text-primary' : ''"
        :aria-label="t('ideation.rounds.controls')"
      >
        <Layers class="size-3.5" />
        <span
          v-if="activeRound"
          id="brainstorming-active-round"
          class="hidden sm:inline"
          aria-live="polite"
          >{{ t("ideation.rounds.number", { number: activeRound.number }) }}</span
        >
        <span v-else class="hidden sm:inline">{{ t("ideation.rounds.title") }}</span>
      </button>
    </PopoverTrigger>
    <PopoverContent
      align="start"
      class="w-80 space-y-4 p-4"
      :aria-label="t('ideation.rounds.controls')"
    >
      <div>
        <h2 class="text-sm font-semibold">{{ t("ideation.rounds.title") }}</h2>
        <p class="mt-1 text-xs leading-relaxed text-muted-foreground">
          {{ t("ideation.rounds.help") }}
        </p>
      </div>
      <p
        v-if="failure && !(promptConflict && editing !== null)"
        role="alert"
        class="text-xs text-destructive"
      >
        {{ error(failure) }}
      </p>
      <div v-if="entries.length" class="max-h-72 space-y-2 overflow-y-auto">
        <section
          v-for="round in entries"
          :id="`brainstorming-round-${round.id}`"
          :key="round.id"
          :data-status="round.status"
          class="rounded-md border p-3"
          :class="round.status === 'active' ? 'border-primary/40 bg-primary/5' : ''"
        >
          <div class="flex items-center justify-between gap-2">
            <h3 class="text-xs font-medium">
              {{ t("ideation.rounds.number", { number: round.number }) }}
            </h3>
            <span class="text-[11px] text-muted-foreground">{{
              t(`ideation.rounds.${round.status}`)
            }}</span>
          </div>
          <form
            v-if="editing === round.id"
            class="mt-2 space-y-2"
            @submit.prevent="savePrompt(round)"
          >
            <Label :for="`brainstorming-round-edit-prompt-${round.id}`" class="text-xs">{{
              t("ideation.rounds.prompt")
            }}</Label>
            <Textarea
              :id="`brainstorming-round-edit-prompt-${round.id}`"
              v-model="editedPrompt"
              :disabled="pending"
              :maxlength="2000"
              :rows="3"
              class="min-h-20 resize-y text-xs"
            />
            <div
              v-if="promptConflict"
              role="alert"
              class="space-y-2 rounded-md border border-primary/30 bg-primary/5 p-2 text-xs"
            >
              <p>{{ t("ideation.rounds.promptChanged") }}</p>
              <template v-if="session.revision !== editingRevision">
                <p class="font-medium">{{ t("ideation.rounds.currentPrompt") }}</p>
                <p
                  :id="`brainstorming-round-current-prompt-${round.id}`"
                  class="whitespace-pre-wrap break-words"
                >
                  {{ round.prompt || t("ideation.rounds.noPrompt") }}
                </p>
              </template>
              <p v-else class="text-muted-foreground">{{ t("ideation.rounds.loadingPrompt") }}</p>
            </div>
            <div class="flex justify-end gap-1">
              <Button size="sm" variant="ghost" :disabled="pending" @click="closeEdit">{{
                t("ideation.cancel")
              }}</Button>
              <Button
                v-if="promptConflict"
                :id="`brainstorming-round-replace-${round.id}`"
                type="button"
                size="sm"
                :disabled="pending || session.revision === editingRevision"
                @click="savePrompt(round, true)"
                >{{ t("ideation.rounds.replacePrompt") }}</Button
              >
              <Button
                v-else
                :id="`brainstorming-round-save-${round.id}`"
                type="submit"
                size="sm"
                :disabled="pending"
                >{{ t("ideation.rounds.save") }}</Button
              >
            </div>
          </form>
          <template v-else>
            <p
              v-if="round.prompt"
              class="mt-2 whitespace-pre-wrap break-words text-xs leading-relaxed"
            >
              {{ round.prompt }}
            </p>
            <div
              v-if="mayManage && ['planned', 'active'].includes(round.status)"
              class="mt-2 flex items-center justify-end gap-1"
            >
              <template v-if="round.status === 'planned'">
                <Button
                  :id="`brainstorming-round-edit-${round.id}`"
                  size="sm"
                  variant="ghost"
                  :aria-label="t('ideation.rounds.edit')"
                  :title="t('ideation.rounds.edit')"
                  :disabled="pending"
                  @click="beginEdit(round)"
                  ><Pencil class="size-3"
                /></Button>
                <Button
                  :id="`brainstorming-round-cancel-${round.id}`"
                  size="sm"
                  variant="ghost"
                  :aria-label="t('ideation.rounds.cancelRound')"
                  :title="t('ideation.rounds.cancelRound')"
                  :disabled="pending"
                  @click="transition(round, 'cancel_round')"
                  ><X class="size-3"
                /></Button>
                <Button
                  :id="`brainstorming-round-start-${round.id}`"
                  size="sm"
                  variant="outline"
                  :disabled="pending || Boolean(activeRound)"
                  @click="transition(round, 'start_round')"
                  ><Play class="size-3" />{{ t("ideation.rounds.start") }}</Button
                >
              </template>
              <Button
                v-else
                :id="`brainstorming-round-close-${round.id}`"
                size="sm"
                variant="outline"
                :disabled="pending"
                @click="transition(round, 'close_round')"
                ><Square class="size-3" />{{ t("ideation.rounds.close") }}</Button
              >
            </div>
          </template>
        </section>
      </div>
      <p v-else class="text-xs text-muted-foreground">{{ t("ideation.rounds.empty") }}</p>
      <Button
        v-if="roundsNext"
        size="sm"
        variant="ghost"
        class="w-full"
        :disabled="pending"
        @click="send('browse_rounds', { before_id: roundsNext })"
        >{{ t("ideation.rounds.earlier") }}</Button
      >
      <form v-if="mayManage" class="space-y-2 border-t pt-3" @submit.prevent="create">
        <Label for="brainstorming-round-prompt" class="text-xs">{{
          t("ideation.rounds.prompt")
        }}</Label>
        <Textarea
          id="brainstorming-round-prompt"
          :disabled="pending"
          v-model="prompt"
          :maxlength="2000"
          :rows="2"
          :placeholder="t('ideation.rounds.promptPlaceholder')"
          class="min-h-16 resize-y text-xs"
        />
        <Button
          id="brainstorming-round-create"
          type="submit"
          variant="outline"
          size="sm"
          class="w-full"
          :disabled="pending"
          ><Plus class="size-3.5" />{{ t("ideation.rounds.prepare") }}</Button
        >
      </form>
    </PopoverContent>
  </Popover>
</template>
