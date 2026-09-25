<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { ArrowLeft, ChevronDown, ChevronUp, ListChecks, Plus, RefreshCw, X } from "@lucide/vue";
import { Button } from "@components/ui/button";
import ConfirmDialog from "@components/ConfirmDialog.vue";
import Sidebar from "@shell/Sidebar.vue";
import DecisionCard from "./DecisionCard.vue";
import DecisionDetail from "./DecisionDetail.vue";
import DecisionDiscussion from "./DecisionDiscussion.vue";
import DecisionForm from "./DecisionForm.vue";
import DecisionSourcePicker from "./DecisionSourcePicker.vue";
import { orderDecisions, replaceable, shownRevision } from "./decisionStatus";
import { useDecisionRequests } from "./useDecisionRequests";
import type {
  ApplicationState,
  DecisionDraftInput,
  DecisionSource,
  DecisionSourceIdentity,
  DecisionSourceType,
  DecisionDiscussionState,
  DecisionsPanelState,
} from "./decisionTypes";

const {
  state,
  epoch,
  sessionId,
  discussion = { state: null, counts: {} },
} = defineProps<{
  state: DecisionsPanelState;
  epoch: string;
  sessionId: number;
  discussion?: DecisionDiscussionState;
}>();
const { t, te } = useI18n();
const { request, lookup, pending, notice } = useDecisionRequests(
  () => state,
  () => sessionId,
  () => epoch,
);
const editor = computed(() => state.mode === "create" || state.mode === "revise");
const editorContext = computed(() =>
  JSON.stringify([epoch, sessionId, state.context, state.mode, state.selected?.id]),
);
const ordered = computed(() => orderDecisions(state.items));
const showRetired = ref(false);
const roundCount = computed(() => state.rounds.length);
const draft = computed(() => {
  const selected = state.selected;
  if (state.mode !== "revise" || !selected) return null;
  return selected.status === "proposed" || !selected.accepted
    ? selected.proposal
    : selected.accepted;
});
// A revision of a replacement keeps naming the decision it already replaced.
const replacements = computed(() => {
  const revising = state.mode === "revise" ? state.selected : null;
  const options = replaceable(state.items, revising?.id ?? null).map((item) => ({
    id: item.id,
    title: shownRevision(item).title,
  }));
  const replaced = revising?.supersedes;
  return replaced && !options.some((item) => item.id === replaced.id)
    ? [replaced, ...options]
    : options;
});
const formOptions = computed(() => ({
  members: state.members,
  defaultOwnerId: state.defaultOwnerId,
  viewerId: state.viewerId,
  prefill: state.prefill,
  rounds: state.rounds,
  suggestions: state.targetSuggestions,
  results: state.targetResults,
  replaceable: replacements.value,
}));
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
    await nextTick();
    // Each view starts at its top: the detail's status must not stay scrolled
    // away behind the form it replaced.
    const scroller = document.getElementById("brainstorming-decisions-panel")?.parentElement;
    if (scroller) scroller.scrollTop = 0;
    if (state.open && !editor.value) heading.value?.focus({ preventScroll: true });
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
function transition(action: "accept" | "withdraw") {
  const selected = state.selected;
  if (!selected || !(action === "accept" ? selected.canAccept : selected.canWithdraw)) return;
  const payload = { decision_id: selected.id, revision: selected.version };
  request(action, payload, JSON.stringify([action, payload]));
}
function declare(targetKey: string | null, stateValue: ApplicationState, note: string | null) {
  const selected = state.selected;
  if (!selected?.canDeclare || !selected.accepted) return;
  const payload = {
    decision_id: selected.id,
    agreement: selected.accepted.revision,
    target_key: targetKey,
    state: stateValue,
    note,
  };
  request("declare", payload, JSON.stringify(["declare", payload]));
}
const tasksSaved = ref(0);
const taskPermission = {
  link_task: "canLinkTasks",
  edit_task: "canEditTasks",
  unlink_task: "canUnlinkTasks",
} as const;
function changeTask(
  action: keyof typeof taskPermission,
  change: { link_key?: string; url?: string; title?: string | null },
) {
  const selected = state.selected;
  if (!selected?.[taskPermission[action]]) return;
  const payload = { decision_id: selected.id, ...change };
  request(action, payload, JSON.stringify([action, payload]), () => {
    tasksSaved.value += 1;
  });
}
</script>
<template>
  <Sidebar
    side="right"
    :open="state.open"
    :close-on-outside="state.mode === 'list' || state.mode === 'detail'"
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
          <li v-for="decision in ordered.live" :key="decision.id">
            <button
              :id="`decision-open-${decision.id}`"
              type="button"
              :data-status="decision.status"
              class="block w-full rounded-xl text-left focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none"
              :disabled="!!pending"
              @click="request('select', { decision_id: decision.id })"
            >
              <DecisionCard
                :decision="decision"
                :round-count="roundCount"
                :comments="discussion.counts[decision.id] ?? 0"
              />
            </button>
          </li>
          <li v-if="ordered.retired.length" class="pt-1.5">
            <button
              id="decisions-retired"
              type="button"
              class="flex w-full items-center gap-2.5 text-[11px] text-muted-foreground hover:text-foreground"
              :aria-expanded="showRetired"
              @click="showRetired = !showRetired"
            >
              <span class="h-px flex-1 bg-border" /><span class="inline-flex items-center gap-[5px]"
                >{{ t("brainstormingDecisions.retired", { count: ordered.retired.length })
                }}<ChevronUp v-if="showRetired" class="size-3" /><ChevronDown
                  v-else
                  class="size-3" /></span
              ><span class="h-px flex-1 bg-border" />
            </button>
          </li>
          <template v-if="showRetired">
            <li v-for="decision in ordered.retired" :key="decision.id">
              <button
                :id="`decision-open-${decision.id}`"
                type="button"
                :data-status="decision.status"
                class="block w-full rounded-xl text-left focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none"
                :disabled="!!pending"
                @click="request('select', { decision_id: decision.id })"
              >
                <DecisionCard
                  :decision="decision"
                  :round-count="roundCount"
                  :comments="discussion.counts[decision.id] ?? 0"
                />
              </button>
            </li>
          </template>
        </ul>
      </template>
      <DecisionForm
        v-else-if="editor"
        :context="editorContext"
        :draft="draft"
        :draft-version="state.mode === 'revise' ? (state.selected?.version ?? null) : null"
        :sources="state.sources"
        :can-assign="state.mode === 'create' || !!state.selected?.canAssign"
        :enabled="state.mode === 'create' ? state.canPropose : !!state.selected?.canRevise"
        :pending="!!pending"
        :options="formOptions"
        @dirty="dirty = $event"
        @submit="save"
        @remove-source="removeSource"
        @refresh-sources="request('refresh_sources')"
        @browse-sources="picker = !picker"
        @search-targets="lookup('search_targets', { search: $event })"
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
      ></DecisionForm>
      <DecisionDetail
        v-else-if="state.selected"
        :decision="state.selected"
        :history="state.history"
        :round-count="roundCount"
        :pending="pending"
        @accept="transition('accept')"
        @withdraw="transition('withdraw')"
        @revise="
          request('begin_revision', {
            decision_id: state.selected.id,
            revision: state.selected.version,
          })
        "
        @select="request('select', { decision_id: $event })"
        @load-history="request('history', { decision_id: state.selected?.id })"
        :tasks-saved="tasksSaved"
        @declare="declare"
        @link-task="(url, title) => changeTask('link_task', { url, title })"
        @edit-task="(key, url, title) => changeTask('edit_task', { link_key: key, url, title })"
        @unlink-task="(key) => changeTask('unlink_task', { link_key: key })"
      >
        <template #discussion>
          <DecisionDiscussion
            v-if="discussion.state?.open && discussion.state.decisionId === state.selected.id"
            :state="discussion.state"
            :epoch="epoch"
            :session-id="sessionId"
            :title="shownRevision(state.selected).title"
            :current-user-id="state.viewerId"
          />
        </template>
      </DecisionDetail>
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
