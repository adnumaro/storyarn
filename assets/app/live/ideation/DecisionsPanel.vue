<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import {
  ArrowLeft,
  Check,
  History,
  ListChecks,
  Loader2,
  Pencil,
  Plus,
  RefreshCw,
  X,
} from "@lucide/vue";
import { Button } from "@components/ui/button";
import ConfirmDialog from "@components/ConfirmDialog.vue";
import Sidebar from "@shell/Sidebar.vue";
import DecisionEditor from "./DecisionEditor.vue";
import DecisionSourcePicker from "./DecisionSourcePicker.vue";
import DecisionSummary from "./DecisionSummary.vue";
import { useDecisionRequests } from "./useDecisionRequests";
import type {
  DecisionDraftInput,
  DecisionSource,
  DecisionSourceIdentity,
  DecisionSourceType,
  DecisionsPanelState,
} from "./decisionTypes";

const { state, epoch, sessionId } = defineProps<{
  state: DecisionsPanelState;
  epoch: string;
  sessionId: number;
}>();
const { t, te, locale } = useI18n();
const { request, pending, notice } = useDecisionRequests(
  () => state,
  () => sessionId,
  () => epoch,
);
const editor = computed(() => state.mode === "create" || state.mode === "revise");
const editorContext = computed(() =>
  JSON.stringify([epoch, sessionId, state.context, state.mode, state.selected?.id]),
);
const dirty = ref(false);
const picker = ref(false);
const discard = ref(false);
const exitAction = ref<"close" | "open">("close");
const heading = ref<HTMLElement | null>(null);
let returnFocus: HTMLElement | null = null;
watch(
  () => state.open,
  async (open, previous) => {
    if (open && !previous && document.activeElement instanceof HTMLElement)
      returnFocus = document.activeElement;
    if (!open && previous) {
      await nextTick();
      if (returnFocus?.isConnected) returnFocus.focus();
    }
  },
);
watch(
  editorContext,
  async () => {
    dirty.value = false;
    discard.value = false;
    picker.value = state.mode === "create" && !state.sources.length;
    if (state.open && !editor.value) {
      await nextTick();
      heading.value?.focus({ preventScroll: true });
    }
  },
  { immediate: true },
);
function errorText(code: string) {
  const key = `brainstormingDecisions.errors.${code}`;
  return t(te(key) ? key : "brainstormingDecisions.errors.unavailable");
}
function exit(action: "close" | "open") {
  if (pending.value) return;
  if (editor.value && dirty.value) {
    exitAction.value = action;
    discard.value = true;
  } else request(action);
}
function sourcePayload(sources: DecisionSource[]) {
  return sources
    .filter((source) => source.available && source.id !== null)
    .map(({ type, id, version, identity }) => ({ type, id, version, identity }));
}
function addSource(source: DecisionSource) {
  if (state.sources.length >= 20 || state.sources.some((item) => item.identity === source.identity))
    return;
  request("preview_sources", { sources: sourcePayload([...state.sources, source]) });
}
function removeSource(source: DecisionSourceIdentity) {
  request("preview_sources", {
    sources: sourcePayload(state.sources.filter((item) => item.identity !== source.identity)),
  });
}
function searchSources(
  type: DecisionSourceType,
  search: string,
  before: number | null,
  onSuccess: () => void,
) {
  request(
    "search_sources",
    { type, search, ...(before !== null ? { before_id: before } : {}) },
    undefined,
    onSuccess,
  );
}
function save(input: DecisionDraftInput) {
  const action = state.mode === "revise" ? "revise" : "create";
  if (action === "revise" ? !state.selected?.canRevise : !state.canPropose) return;
  const payload = {
    ...input,
    sources: sourcePayload(state.sources),
    ...(action === "revise" ? { decision_id: state.selected?.id } : {}),
  };
  request(action, payload, JSON.stringify([action, payload]));
}
function accept() {
  if (!state.selected?.canAccept) return;
  const payload = { decision_id: state.selected.id, revision: state.selected.revision };
  request("accept", payload, JSON.stringify(["accept", payload]));
}
function date(value: string) {
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime())
    ? value
    : new Intl.DateTimeFormat(locale.value, { dateStyle: "medium", timeStyle: "short" }).format(
        parsed,
      );
}
</script>
<template>
  <Sidebar
    v-if="state.open"
    side="right"
    :open="state.open"
    :close-on-outside="false"
    class="decision-panel"
    @close="exit('close')"
  >
    <template #header
      ><div class="flex items-center gap-2 py-2.5">
        <Button
          v-if="state.mode !== 'list'"
          id="decisions-back"
          size="icon-sm"
          variant="ghost"
          :disabled="!!pending"
          :aria-label="t('brainstormingDecisions.back')"
          @click="exit('open')"
          ><ArrowLeft class="size-4" /></Button
        ><ListChecks v-else class="ml-1 size-4 text-muted-foreground" />
        <h2
          id="decisions-panel-heading"
          ref="heading"
          tabindex="-1"
          class="min-w-0 flex-1 text-sm font-semibold outline-none"
        >
          {{
            t(
              state.mode === "create"
                ? "brainstormingDecisions.newProposal"
                : state.mode === "revise"
                  ? "brainstormingDecisions.revise"
                  : "brainstormingDecisions.title",
            )
          }}
        </h2>
        <Button
          id="decisions-close"
          size="icon-sm"
          variant="ghost"
          :disabled="!!pending"
          :aria-label="t('brainstormingDecisions.close')"
          @click="exit('close')"
          ><X class="size-4"
        /></Button></div
    ></template>
    <div
      id="brainstorming-decisions-panel"
      class="space-y-4 pb-2"
      :aria-busy="!!pending"
      aria-labelledby="decisions-panel-heading"
      @keydown.esc.stop.prevent="exit('close')"
    >
      <div
        v-if="notice"
        role="alert"
        class="rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-xs leading-relaxed text-destructive"
      >
        <p>{{ errorText(notice) }}</p>
        <Button
          id="decisions-reload"
          size="sm"
          variant="ghost"
          class="mt-1"
          :disabled="!!pending"
          @click="request('reload')"
          ><RefreshCw class="size-3.5" />{{ t("brainstormingDecisions.reload") }}</Button
        >
      </div>
      <template v-if="state.mode === 'list'">
        <p class="text-xs leading-relaxed text-muted-foreground">
          {{ t("brainstormingDecisions.intro") }}
        </p>
        <Button
          v-if="state.canPropose"
          id="decision-new"
          variant="outline"
          class="w-full"
          :disabled="!!pending"
          @click="request('new')"
          ><Plus class="size-4" />{{ t("brainstormingDecisions.newProposal") }}</Button
        >
        <div
          v-if="!state.items.length"
          class="rounded-xl border border-dashed px-4 py-8 text-center"
        >
          <ListChecks class="mx-auto mb-3 size-7 text-muted-foreground/60" />
          <p class="text-sm font-medium">{{ t("brainstormingDecisions.empty") }}</p>
          <p class="mt-2 text-xs leading-relaxed text-muted-foreground">
            {{ t("brainstormingDecisions.emptyHelp") }}
          </p>
        </div>
        <ul v-else class="space-y-2">
          <li v-for="decision in state.items" :key="decision.id">
            <button
              :id="`decision-open-${decision.id}`"
              type="button"
              :data-status="decision.status"
              class="w-full rounded-xl border border-border p-3 text-left transition-colors hover:border-primary/40 hover:bg-accent/30 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              :disabled="!!pending"
              @click="request('select', { decision_id: decision.id })"
            >
              <span
                class="mb-2 inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-medium"
                :class="
                  decision.status === 'accepted'
                    ? 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-400'
                    : 'bg-muted text-muted-foreground'
                "
                ><Check v-if="decision.status === 'accepted'" class="size-3" />{{
                  t(`brainstormingDecisions.status.${decision.status}`)
                }}</span
              ><span class="block break-words text-sm font-medium">{{ decision.title }}</span
              ><span
                class="mt-1 line-clamp-2 block text-xs leading-relaxed text-muted-foreground"
                >{{ decision.conclusion }}</span
              ><span class="mt-3 block text-[11px] text-muted-foreground"
                >{{ decision.ownerName || t("brainstormingDecisions.formerMember") }} ·
                {{
                  t("brainstormingDecisions.sourcesCount", { count: decision.sources.length })
                }}</span
              ><span
                v-if="decision.status === 'proposed' && decision.previousAgreement"
                class="mt-1 block text-[11px] text-muted-foreground"
                >{{ t("brainstormingDecisions.agreementRemains") }}</span
              >
            </button>
          </li>
        </ul>
        <Button
          v-if="state.nextCursor !== null"
          id="decisions-next"
          variant="outline"
          size="sm"
          class="w-full"
          :disabled="!!pending"
          @click="request('load_more', { cursor: state.nextCursor })"
          >{{ t("brainstormingDecisions.next") }}</Button
        >
      </template>
      <template v-else>
        <details
          v-if="
            (state.selected?.previousAgreement && state.selected.status === 'proposed') ||
            (state.mode === 'revise' && state.selected?.status === 'accepted')
          "
          id="decision-previous-agreement"
          class="rounded-lg border border-emerald-500/20 bg-emerald-500/5 p-3"
        >
          <summary
            class="cursor-pointer text-xs font-medium text-emerald-800 dark:text-emerald-400"
          >
            {{ t("brainstormingDecisions.previousAgreement") }}
          </summary>
          <div class="mt-3">
            <DecisionSummary
              v-if="state.selected"
              :agreement="state.selected.previousAgreement ?? state.selected"
            />
          </div>
        </details>
        <DecisionEditor
          v-if="editor"
          :context="editorContext"
          :draft="state.mode === 'revise' ? state.selected : null"
          :sources="state.sources"
          :members="state.members"
          :default-owner-id="state.defaultOwnerId"
          :can-assign="state.mode === 'create' || !!state.selected?.canAssign"
          :enabled="state.mode === 'create' ? state.canPropose : !!state.selected?.canRevise"
          :pending="!!pending"
          @dirty="dirty = $event"
          @submit="save"
          @remove-source="removeSource"
          @refresh-sources="request('refresh_sources')"
          @browse-sources="picker = !picker"
          ><template #picker
            ><DecisionSourcePicker
              v-if="picker"
              :sources="state.sources"
              :results="state.sourceResults"
              :next-cursor="state.sourceNextCursor"
              :searched="state.searched"
              :pending="!!pending"
              @close="picker = false"
              @search="searchSources"
              @select="addSource" /></template
        ></DecisionEditor>
        <template v-else-if="state.selected">
          <div
            class="flex items-center gap-2 text-xs font-medium"
            :class="
              state.selected.status === 'accepted'
                ? 'text-emerald-700 dark:text-emerald-400'
                : 'text-muted-foreground'
            "
          >
            <Check v-if="state.selected.status === 'accepted'" class="size-4" />{{
              t(`brainstormingDecisions.status.${state.selected.status}`)
            }}
          </div>
          <DecisionSummary :agreement="state.selected" />
          <div class="space-y-2 border-t pt-4">
            <Button
              v-if="state.selected.canAccept"
              id="decision-accept"
              class="w-full"
              :disabled="!!pending"
              @click="accept"
              ><Loader2 v-if="pending === 'accept'" class="size-4 animate-spin" /><Check
                v-else
                class="size-4"
              />{{ t("brainstormingDecisions.accept") }}</Button
            >
            <p
              v-if="state.selected.status === 'proposed'"
              class="text-xs leading-relaxed text-muted-foreground"
            >
              {{
                t(
                  state.selected.canAccept
                    ? "brainstormingDecisions.acceptHelp"
                    : "brainstormingDecisions.waitingForOwner",
                  { name: state.selected.ownerName || t("brainstormingDecisions.formerMember") },
                )
              }}
            </p>
            <Button
              v-if="state.selected.canRevise"
              id="decision-revise"
              variant="outline"
              class="w-full"
              :disabled="!!pending"
              @click="
                request('begin_revision', {
                  decision_id: state.selected.id,
                  revision: state.selected.revision,
                })
              "
              ><Pencil class="size-3.5" />{{
                t(
                  state.selected.status === "accepted"
                    ? "brainstormingDecisions.revise"
                    : "brainstormingDecisions.editProposal",
                )
              }}</Button
            >
          </div>
          <details
            id="decision-history"
            class="border-t pt-3"
            @toggle="
              (event) => {
                if ((event.target as HTMLDetailsElement).open && !state.history.length)
                  request('history', { decision_id: state.selected?.id });
              }
            "
          >
            <summary class="cursor-pointer text-xs font-medium text-muted-foreground">
              <History class="mr-1 inline size-3.5" />{{ t("brainstormingDecisions.history") }}
            </summary>
            <div class="mt-3 space-y-3">
              <p v-if="pending === 'history'" class="text-xs text-muted-foreground">
                {{ t("brainstormingDecisions.loading") }}
              </p>
              <details
                v-for="entry in state.history"
                :key="entry.revision"
                class="rounded-lg border p-3"
              >
                <summary class="cursor-pointer text-xs leading-relaxed">
                  <span class="font-medium">{{
                    t(`brainstormingDecisions.historyActions.${entry.operation}`)
                  }}</span>
                  · {{ date(entry.recordedAt)
                  }}<span class="mt-0.5 block text-[11px] text-muted-foreground">{{
                    entry.actorName || t("brainstormingDecisions.formerMember")
                  }}</span>
                </summary>
                <div class="mt-3"><DecisionSummary :agreement="entry" /></div>
              </details>
              <Button
                v-if="state.historyNextCursor"
                size="sm"
                variant="outline"
                :disabled="!!pending"
                @click="
                  request('history', {
                    decision_id: state.selected.id,
                    before_id: state.historyNextCursor,
                  })
                "
                >{{ t("brainstormingDecisions.olderHistory") }}</Button
              >
            </div>
          </details>
        </template>
      </template>
    </div>
  </Sidebar>
  <ConfirmDialog
    v-model:open="discard"
    :title="t('brainstormingDecisions.discardTitle')"
    :description="t('brainstormingDecisions.discardHelp')"
    :confirm-text="t('brainstormingDecisions.discard')"
    :cancel-text="t('brainstormingDecisions.keepEditing')"
    variant="warning"
    @confirm="request(exitAction)"
  />
</template>
<style scoped>
@media (min-width: 768px) {
  .decision-panel {
    width: min(28rem, calc(100vw - 1.5rem));
  }
}
</style>
