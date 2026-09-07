<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { Lightbulb, Plus, Settings2, Send, PanelLeft, RefreshCw } from "@lucide/vue";
import { Button } from "@components/ui/button";
import ConfirmDialog from "@components/ConfirmDialog.vue";
import SessionsPane from "./components/SessionsPane.vue";
import IdeasCollection from "./components/IdeasCollection.vue";
import IdeaPanel from "./components/IdeaPanel.vue";
import IdeaComposer from "./components/IdeaComposer.vue";
import SessionDialog from "./components/SessionDialog.vue";
import RevealDialog from "./components/RevealDialog.vue";
import IdeaEditor from "./components/IdeaEditor.vue";
import { useBoardConnection } from "./composables/useBoardConnection";
import { useIdeaDrafts } from "./composables/useIdeaDrafts";
import { useBoardText } from "./composables/useBoardText";
import type {
  Board,
  BoardContext,
  Idea,
  IdeaContent,
  IdeaRevision,
  EditReceipt,
  HistoryPage,
  Inspection,
  Session,
} from "./types";

const { board, baseUrl } = defineProps<{ board: Board; baseUrl: string }>();
const { t, error } = useBoardText();
const inspection = ref<Inspection | null>(null);
const inspectionLoading = ref(false);
const selectedId = ref<number | null>(null);
const sidebarOpen = ref(false);
const sessionDialog = ref<"new" | "settings" | null>(null);
const composer = ref<{ context: BoardContext; session: Session; source?: Idea } | null>(null);
const reveal = ref<{ context: BoardContext; idea?: Idea } | null>(null);
const purge = ref<Session | null>(null);
const purging = ref(false);
const failure = ref<string | null>(null);
const resetReason = ref<string | null>(null);
const savedCompositions = ref<IdeaContent[]>([]);
let selectionGeneration = 0;
let preserveAllowed = true;

const { request, context, online, sync } = useBoardConnection(() => board, reset);
const drafts = useIdeaDrafts(request, context);
const draft = computed(() =>
  selectedId.value === null ? undefined : drafts.drafts.get(selectedId.value),
);
const writable = computed(() => board.can_edit && board.session?.status === "open");
const currentIdea = computed(() => draft.value?.idea ?? inspection.value?.idea);
const pendingDrafts = computed(() =>
  [...drafts.drafts.values()].filter((item) => item.status !== "saved"),
);

function reset(reason: string) {
  preserveAllowed = reason !== "access_changed";
  selectionGeneration++;
  selectedId.value = null;
  inspection.value = null;
  composer.value = null;
  sessionDialog.value = null;
  reveal.value = null;
  purge.value = null;
  drafts.reset(reason !== "access_changed");
  if (reason === "access_changed") savedCompositions.value = [];
  resetReason.value = reason;
}

function preserve(content: IdeaContent) {
  if (preserveAllowed && board.error !== "unauthorized") savedCompositions.value.push(content);
}

async function select(id: number) {
  const generation = ++selectionGeneration;
  const at = context();
  selectedId.value = id;
  inspection.value = null;
  inspectionLoading.value = true;
  const reply = await request<Inspection>("inspect_idea", { idea_id: id }, at);
  if (generation !== selectionGeneration) return;
  inspectionLoading.value = false;
  if (reply.status === "ok") {
    inspection.value = reply.value;
    if (reply.value.idea.author_id === board.current_user_id) drafts.open(reply.value.idea);
  } else {
    selectedId.value = null;
    failure.value = reply.status === "error" ? reply.code : "unavailable";
  }
}

function closePanel() {
  selectionGeneration++;
  inspection.value = null;
  selectedId.value = null;
  inspectionLoading.value = false;
}

function newIdea(source?: Idea) {
  if (!board.session) return;
  composer.value = {
    context: context(),
    session: structuredClone({
      ...board.session,
      configuration: { ...board.session.configuration },
    }),
    source,
  };
}

async function action(event: string, payload: Record<string, unknown>, at = context()) {
  const reply = await request(event, payload, at);
  if (reply.status === "error") failure.value = reply.code;
  return reply;
}

function created(idea: Idea) {
  composer.value = null;
  void action("browse_ideas", { before_id: null });
  void select(idea.id);
}

async function sessionCreated(id: number) {
  sessionDialog.value = null;
  await action("open_session", { id });
}

async function browseSessions(status: string, before: number | null) {
  await action("browse_sessions", { status, before_id: before });
}

async function recover(session: Session) {
  const reply = await action(
    "recover_session",
    { revision: session.revision },
    { epoch: board.epoch, session_id: session.id },
  );
  if (reply.status === "ok") await browseSessions("archived", null);
}

async function purgeSession() {
  if (!purge.value || purging.value) return;
  purging.value = true;
  const reply = await action(
    "purge_session",
    { revision: purge.value.revision },
    { epoch: board.epoch, session_id: purge.value.id },
  );
  purging.value = false;
  if (reply.status === "ok") purge.value = null;
}

async function moreHistory(conflicts = false) {
  if (!inspection.value || inspectionLoading.value) return;
  const generation = selectionGeneration;
  inspectionLoading.value = true;
  const reply = await request<HistoryPage<IdeaRevision | EditReceipt>>(
    conflicts ? "idea_conflicts" : "idea_history",
    {
      idea_id: selectedId.value,
      before_id: conflicts ? inspection.value.conflicts_next : inspection.value.history_next,
    },
  );
  if (generation !== selectionGeneration) return;
  inspectionLoading.value = false;
  if (reply.status === "ok") {
    if (conflicts) {
      inspection.value.conflicts.push(...(reply.value.entries as EditReceipt[]));
      inspection.value.conflicts_next = reply.value.next;
    } else {
      inspection.value.history.push(...(reply.value.entries as IdeaRevision[]));
      inspection.value.history_next = reply.value.next;
    }
  } else failure.value = reply.status === "error" ? reply.code : "unavailable";
}

function change(content: Partial<IdeaContent>) {
  if (selectedId.value !== null && writable.value) drafts.change(selectedId.value, content);
}

function publish() {
  if (currentIdea.value) reveal.value = { context: context(), idea: currentIdea.value };
}

function published() {
  reveal.value = null;
  if (selectedId.value !== null) void select(selectedId.value);
}

watch(
  () => board.session?.id,
  () => {
    closePanel();
    sidebarOpen.value = false;
    sessionDialog.value = null;
    composer.value = null;
    reveal.value = null;
  },
);
watch(
  () => board.can_edit,
  (allowed, previous) => {
    if (previous && !allowed) reset("permissions_changed");
  },
);
watch(
  () => board.ideas,
  (ideas) => {
    for (const idea of ideas) drafts.receive(idea);
    const current = ideas.find((idea) => idea.id === selectedId.value);
    if (current && inspection.value) inspection.value.idea = current;
  },
);
</script>
<template>
  <div
    id="brainstorming-workspace"
    class="flex h-full min-h-0 w-full overflow-hidden bg-background"
  >
    <div :class="sidebarOpen ? 'flex w-full md:w-auto' : 'hidden md:flex'">
      <SessionsPane
        :board="board"
        :base-url="baseUrl"
        @create="sessionDialog = 'new'"
        @browse="browseSessions"
        @recover="recover"
        @purge="
          purge = $event;
          failure = null;
        "
      />
    </div>
    <div class="flex min-h-0 min-w-0 flex-1 flex-col" :class="sidebarOpen && 'hidden md:flex'">
      <div
        v-if="board.error || failure || !online"
        role="alert"
        class="flex items-center justify-between gap-3 border-b bg-destructive/5 px-5 py-3 text-sm"
      >
        <span>{{ error(board.error || failure || "offline") }}</span
        ><Button
          size="sm"
          variant="outline"
          @click="
            failure = null;
            sync();
          "
          ><RefreshCw class="size-4" />{{ t("ideation.refresh") }}</Button
        >
      </div>
      <div
        v-if="resetReason"
        role="status"
        class="flex items-center justify-between gap-3 border-b bg-primary/5 px-5 py-3 text-sm"
      >
        <span>{{ t("ideation.resetHelp") }}</span
        ><Button size="sm" variant="ghost" @click="resetReason = null">{{
          t("ideation.dismiss")
        }}</Button>
      </div>
      <div
        v-if="pendingDrafts.length"
        class="flex flex-wrap items-center gap-2 border-b px-5 py-2 text-xs"
        role="status"
      >
        <span>{{ t("ideation.pendingDrafts", { count: pendingDrafts.length }) }}</span>
        <Button
          v-for="item in pendingDrafts.filter(
            (item) => item.context.session_id === board.session?.id,
          )"
          :key="item.idea.id"
          size="sm"
          variant="ghost"
          @click="select(item.idea.id)"
          >{{ item.content.title || t("ideation.untitled") }}</Button
        >
      </div>
      <details
        v-if="drafts.recovered.value.length || savedCompositions.length"
        class="border-b px-5 py-3 text-sm"
      >
        <summary class="cursor-pointer">{{ t("ideation.recoveredDrafts") }}</summary>
        <p class="my-2 text-xs text-muted-foreground">{{ t("ideation.recoveredDraftsHelp") }}</p>
        <div class="max-h-72 space-y-2 overflow-auto">
          <div
            v-for="(content, index) in [...drafts.recovered.value, ...savedCompositions]"
            :key="index"
          >
            <p class="my-2 font-medium">{{ content.title }}</p>
            <IdeaEditor :value="content.body" readonly :label="t('ideation.recoveredDrafts')" />
          </div>
        </div>
      </details>
      <header class="flex flex-wrap items-center gap-3 border-b px-5 py-4">
        <Button
          size="icon-sm"
          variant="ghost"
          class="md:hidden"
          :aria-label="t('ideation.sessions')"
          @click="sidebarOpen = true"
          ><PanelLeft class="size-4"
        /></Button>
        <div class="min-w-32 flex-1">
          <h2 class="truncate text-lg font-semibold">
            {{ board.session?.title || t("ideation.title") }}
          </h2>
          <p
            v-if="board.session?.objective"
            class="mt-1 line-clamp-2 text-sm text-muted-foreground"
          >
            {{ board.session.objective }}
          </p>
        </div>
        <template v-if="board.session">
          <Button
            size="icon-sm"
            variant="ghost"
            :aria-label="t('ideation.sessionSettings')"
            @click="sessionDialog = 'settings'"
            ><Settings2 class="size-4"
          /></Button>
          <Button
            v-if="writable && board.can_manage"
            size="sm"
            variant="outline"
            @click="reveal = { context: context() }"
            ><Send class="size-4" />{{ t("ideation.assistedReveal") }}</Button
          >
          <Button v-if="writable" id="new-brainstorming-idea" size="sm" @click="newIdea()"
            ><Plus class="size-4" />{{ t("ideation.newIdea") }}</Button
          >
        </template>
      </header>
      <p
        v-if="board.session && !writable"
        class="border-b bg-muted/30 px-5 py-2 text-xs text-muted-foreground"
      >
        {{ t(board.session.status === "archived" ? "ideation.archivedHelp" : "ideation.readOnly") }}
      </p>
      <div v-if="board.session" class="flex min-h-0 flex-1">
        <div
          class="min-h-0 min-w-0 flex-1"
          :class="selectedId !== null ? 'hidden xl:flex' : 'flex'"
        >
          <IdeasCollection
            :key="board.session.id"
            :board="board"
            :selected-id="selectedId"
            @select="select($event.id)"
            @browse="action('browse_ideas', { before_id: $event })"
          />
        </div>
        <IdeaPanel
          v-if="inspection"
          :board="board"
          :inspection="inspection"
          :draft="draft"
          :loading="inspectionLoading"
          @close="closePanel"
          @change="change"
          @save="selectedId !== null && drafts.save(selectedId)"
          @resolve="selectedId !== null && drafts.resolve(selectedId, $event)"
          @publish="publish"
          @derive="newIdea(currentIdea)"
          @history="moreHistory(false)"
          @conflicts="moreHistory(true)"
          @source="select"
        />
        <div
          v-else-if="inspectionLoading"
          class="flex w-full items-center justify-center xl:w-100"
          role="status"
        >
          {{ t("ideation.loading") }}
        </div>
      </div>
      <div
        v-else
        class="mx-auto flex max-w-md flex-1 flex-col items-center justify-center gap-4 px-6 text-center"
      >
        <Lightbulb class="size-10 text-primary/60" />
        <h2 class="text-2xl font-semibold">
          {{ t(board.session_missing ? "ideation.sessionMissing" : "ideation.welcome") }}
        </h2>
        <p class="text-sm text-muted-foreground">
          {{ t(board.session_missing ? "ideation.sessionMissingHelp" : "ideation.welcomeHelp") }}
        </p>
        <Button v-if="board.can_edit" @click="sessionDialog = 'new'"
          ><Plus class="size-4" />{{ t("ideation.newSession") }}</Button
        >
      </div>
    </div>
    <SessionDialog
      v-if="sessionDialog"
      :session="sessionDialog === 'settings' ? (board.session ?? undefined) : undefined"
      :context="context()"
      :request="request"
      :members="board.members"
      :can-manage="sessionDialog === 'new' ? board.can_edit : board.can_manage"
      @close="sessionDialog = null"
      @created="sessionCreated"
      @changed="
        sessionDialog = null;
        sync();
      "
    />
    <IdeaComposer
      v-if="composer"
      v-bind="composer"
      :request="request"
      @close="composer = null"
      @created="created"
      @preserve="preserve"
    />
    <RevealDialog
      v-if="reveal"
      v-bind="reveal"
      :request="request"
      @close="reveal = null"
      @published="published"
    />
    <ConfirmDialog
      :open="purge !== null"
      :title="t('ideation.purge')"
      :description="t('ideation.purgeHelp', { title: purge?.title ?? '' })"
      :confirm-text="t('ideation.purge')"
      :cancel-text="t('ideation.cancel')"
      variant="destructive"
      :pending="purging"
      :close-on-confirm="false"
      :error="failure ? error(failure) : undefined"
      @update:open="!$event && (purge = null)"
      @confirm="purgeSession"
    />
  </div>
</template>
