<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from "vue";
import {
  StickyNote,
  Plus,
  History,
  GitBranch,
  Archive,
  Trash2,
  CircleX,
  RotateCcw,
  LayoutDashboard,
  Unplug,
} from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import DashboardContent from "@shell/DashboardContent.vue";
import LiveLink from "@components/navigation/LiveLink.vue";
import { useLive } from "@shared/composables/useLive";
import BrainstormingCanvas from "./components/BrainstormingCanvas.vue";
import SessionDialog from "./components/SessionDialog.vue";
import IdeaHistory from "./components/IdeaHistory.vue";
import IdeaEditor from "./components/IdeaEditor.vue";
import BoardSelect from "./components/BoardSelect.vue";
import { useBoardConnection } from "./composables/useBoardConnection";
import { useCanvasNotes } from "./composables/useCanvasNotes";
import { useBoardText } from "./composables/useBoardText";
import { notePosition } from "./lib/placement";
import type { Point } from "./composables/useCanvasViewport";
import type { Board, Idea, Inspection, HistoryPage, IdeaRevision, EditReceipt } from "./types";
const { board, baseUrl } = defineProps<{ board: Board; baseUrl: string }>();
const { t, error, options, member } = useBoardText();
const selected = ref<number | null>(null),
  editing = ref<number | null>(null);
const settings = ref(false),
  list = ref(false),
  historyOpen = ref(false);
const inspection = ref<Inspection | null>(null),
  inspecting = ref(false);
const failure = ref<string | null>(null),
  resetNotice = ref(false),
  starting = ref(false);
const state = ref("active");
const canvas = ref<InstanceType<typeof BrainstormingCanvas> | null>(null);
const { request, context, online, sync } = useBoardConnection(() => board, reset);
const notes = useCanvasNotes(
  () => board,
  request,
  context,
  (from, to) => {
    if (selected.value === from) selected.value = to;
    if (editing.value === from) editing.value = to;
  },
);
const current = computed(() => notes.notes.value.find((n) => n.id === selected.value));
const writable = computed(() => board.can_edit && board.session?.status === "open");
const own = computed(() => current.value?.author_id === board.current_user_id);
const draft = computed(() =>
  selected.value !== null ? notes.drafts.drafts.get(selected.value) : undefined,
);
const visible = computed(() =>
  notes.notes.value.filter((n) => state.value === "all" || n.state === state.value),
);
const statuses = computed(() =>
  Object.fromEntries([...notes.drafts.drafts.values()].map((d) => [d.idea.id, d.status])),
);
const colors = [
  { id: "yellow", value: "#f5e6a8" },
  { id: "coral", value: "#f8cbbd" },
  { id: "mint", value: "#cbe8d5" },
  { id: "blue", value: "#c9e2f5" },
  { id: "violet", value: "#e2d5f4" },
  { id: "paper", value: "#f4f1e9" },
];
let inspectionGeneration = 0,
  headerEvent: number | undefined;
function reset(reason: string) {
  notes.reset(reason !== "access_changed");
  selected.value = null;
  editing.value = null;
  settings.value = false;
  historyOpen.value = false;
  inspection.value = null;
  inspectionGeneration++;
  resetNotice.value = reason !== "access_changed" && notes.drafts.recovered.value.length > 0;
}
async function locate(note: Idea) {
  list.value = false;
  select(note.id);
  await nextTick();
  canvas.value?.center(note);
  edit(note.id);
}
function finish() {
  if (editing.value !== null) void notes.save(editing.value);
  editing.value = null;
}
function select(id: number | null) {
  if (id !== selected.value) finish();
  selected.value = id;
  historyOpen.value = false;
  inspectionGeneration++;
}
function add(point: Point, source?: Idea) {
  if (!writable.value) return;
  finish();
  const id = notes.add(point, current.value?.canvas?.color, source);
  selected.value = id;
  editing.value = id;
}
function edit(id: number) {
  const note = notes.notes.value.find((n) => n.id === id);
  if (!note || !writable.value || note.author_id !== board.current_user_id) return;
  select(id);
  notes.open(note);
  editing.value = id;
}
function move(id: number, point: Point) {
  const note = notes.notes.value.find((n) => n.id === id);
  notes.move(id, {
    ...point,
    width: note?.canvas?.width ?? 280,
    color: note?.canvas?.color ?? "yellow",
  });
}
function color(value: string) {
  if (!current.value) return;
  notes.move(current.value.id, {
    ...notePosition(current.value),
    width: current.value.canvas?.width ?? 280,
    color: value,
  });
}
function remove(id: number) {
  const note = notes.notes.value.find((n) => n.id === id);
  if (!writable.value || !note || note.author_id !== board.current_user_id) return;
  void notes.remove(id);
  editing.value = null;
  historyOpen.value = false;
}
function changeState(value: "active" | "parked" | "discarded") {
  if (!current.value || !own.value) return;
  notes.open(current.value);
  notes.drafts.change(current.value.id, { state: value });
  void notes.save(current.value.id);
  selected.value = null;
  editing.value = null;
}
async function connect(source: number, target: number, connected: boolean) {
  if (source < 0 || target < 0) {
    failure.value = "save_before_connect";
    return;
  }
  const reply = await request("connect_ideas", { source_id: source, target_id: target, connected });
  if (reply.status === "error") failure.value = reply.code;
}
async function startSession() {
  if (starting.value) return;
  starting.value = true;
  const reply = await request<{ id: number }>("create_session", {
    title: t("ideation.canvas.untitledSession"),
    preset: "openPreset",
  });
  if (reply.status === "ok") await request("open_session", { id: reply.value.id });
  else failure.value = reply.status === "error" ? reply.code : "unavailable";
  if (reply.status === "error" && reply.code === "offline")
    failure.value = "session_creation_unknown";
  else starting.value = false;
}
async function history(more = false) {
  if (selected.value === null || selected.value < 0) return;
  const generation = ++inspectionGeneration;
  historyOpen.value = true;
  inspecting.value = true;
  const reply = more
    ? await request<HistoryPage<IdeaRevision>>("idea_history", {
        idea_id: selected.value,
        before_id: inspection.value?.history_next,
      })
    : await request<Inspection>("inspect_idea", { idea_id: selected.value });
  if (generation !== inspectionGeneration) return;
  inspecting.value = false;
  if (reply.status === "ok") {
    appendHistory(reply.value);
  } else failure.value = reply.status === "error" ? reply.code : "unavailable";
}
async function moreConflicts() {
  if (!inspection.value || selected.value === null) return;
  const generation = ++inspectionGeneration;
  inspecting.value = true;
  const reply = await request<HistoryPage<EditReceipt>>("idea_conflicts", {
    idea_id: selected.value,
    before_id: inspection.value.conflicts_next,
  });
  if (generation !== inspectionGeneration) return;
  inspecting.value = false;
  if (reply.status === "ok" && inspection.value) {
    inspection.value.conflicts.push(...reply.value.entries);
    inspection.value.conflicts_next = reply.value.next;
  } else if (reply.status === "error") failure.value = reply.code;
}
function appendHistory(value: Inspection | HistoryPage<IdeaRevision>) {
  if ("idea" in value) inspection.value = value;
  else if (inspection.value) {
    inspection.value.history.push(...value.entries);
    inspection.value.history_next = value.next;
  }
}
watch(
  () => board.session?.id,
  () => {
    reset("navigation");
    state.value = "active";
    list.value = false;
  },
  { immediate: true },
);
watch(
  () => board.can_edit,
  (now, before) => {
    if (before && !now) reset("access_changed");
  },
);
watch(
  () => board.session?.configuration.private_mode,
  () => {
    historyOpen.value = false;
    inspection.value = null;
    inspectionGeneration++;
    if (current.value && current.value.author_id !== board.current_user_id) select(null);
  },
);
const live = useLive();
onMounted(() => {
  headerEvent = live.handleEvent("board_action", (payload) => {
    if (payload.epoch !== board.epoch || payload.session_id !== board.session?.id) return;
    if (payload.action === "settings") settings.value = true;
  });
});
onUnmounted(() => {
  if (headerEvent !== undefined) live.removeHandleEvent(headerEvent);
});
</script>
<template>
  <div id="brainstorming-workspace" class="relative flex h-full min-h-0 flex-col">
    <div
      v-if="board.error || failure || !online"
      role="alert"
      class="z-40 flex items-center justify-between gap-3 border-b bg-destructive/10 px-4 py-2 text-xs"
    >
      <span>{{ error(board.error || failure || "offline") }}</span
      ><Button
        variant="ghost"
        size="sm"
        @click="
          failure = null;
          sync();
        "
        >{{ t("ideation.refresh") }}</Button
      >
    </div>
    <details
      v-if="resetNotice && notes.drafts.recovered.value.length"
      class="z-40 border-b bg-background p-3 text-xs"
    >
      <summary>{{ t("ideation.recoveredDrafts") }}</summary>
      <div class="max-h-60 space-y-2 overflow-auto py-3">
        <p>{{ t("ideation.recoveredDraftsHelp") }}</p>
        <IdeaEditor
          v-for="(item, index) in notes.drafts.recovered.value"
          :key="index"
          :value="item.body"
          readonly
          :label="t('ideation.recoveredDrafts')"
        />
      </div>
    </details>
    <DashboardContent
      v-if="!board.session"
      :title="t('ideation.title')"
      :subtitle="
        t(board.session_missing ? 'ideation.sessionMissingHelp' : 'ideation.canvas.dashboardHelp')
      "
      :is-empty="!board.sessions.length"
      :empty-message="t('ideation.noSessions')"
      :empty-icon="StickyNote"
    >
      <div class="space-y-2">
        <LiveLink
          v-for="session in board.sessions.filter((s) => !s.deleted_at)"
          :key="session.id"
          :to="`${baseUrl}/${session.id}`"
          mode="patch"
          class="flex items-center gap-3 rounded-lg border p-4 transition-colors hover:bg-accent/40"
          ><StickyNote class="size-5 text-muted-foreground" />
          <div>
            <p class="text-sm font-medium">{{ session.title }}</p>
            <p v-if="session.objective" class="text-xs text-muted-foreground">
              {{ session.objective }}
            </p>
          </div></LiveLink
        >
      </div>
      <template #supplementary
        ><Button v-if="board.can_edit" :disabled="starting" @click="startSession"
          ><Plus class="size-4" />{{ t("ideation.newSession") }}</Button
        ></template
      >
    </DashboardContent>
    <div v-else class="relative min-h-0 flex-1">
      <BrainstormingCanvas
        v-if="!list"
        ref="canvas"
        :key="`${board.epoch}:${board.session.id}`"
        :notes="visible"
        :selected-id="selected"
        :editing-id="editing"
        :writable="writable"
        :members="board.members"
        :statuses="statuses"
        :context="context()"
        @add="add"
        @select="select"
        @edit="edit"
        @change="notes.change"
        @finish="finish"
        @move="move"
        @connect="connect"
        @remove="remove"
        @list="list = true"
      >
        <template #session>
          <Popover
            ><PopoverTrigger class="toolbar-btn gap-2">{{ t(`ideation.${state}`) }}</PopoverTrigger
            ><PopoverContent class="w-56 p-3"
              ><BoardSelect
                v-model="state"
                :label="t('ideation.state')"
                :options="options(['active', 'parked', 'discarded', 'all'])" /></PopoverContent
          ></Popover>
        </template>
        <template #selection>
          <div v-if="current" class="surface-panel flex items-center gap-1 p-1.5 whitespace-nowrap">
            <template v-if="writable"
              ><Popover
                ><PopoverTrigger class="toolbar-btn" :aria-label="t('ideation.canvas.color')"
                  ><span
                    class="size-4 rounded-full border border-foreground/10"
                    :style="{
                      background: colors.find((c) => c.id === (current?.canvas?.color ?? 'yellow'))
                        ?.value,
                    }" /></PopoverTrigger
                ><PopoverContent class="flex w-auto gap-2 p-2"
                  ><button
                    v-for="item in colors"
                    :key="item.id"
                    type="button"
                    class="size-6 rounded-full border border-black/10 ring-offset-2 ring-offset-background focus-visible:ring-2 focus-visible:ring-ring"
                    :style="{ background: item.value }"
                    :aria-label="t(`ideation.canvas.colors.${item.id}`)"
                    :aria-pressed="current.canvas?.color === item.id"
                    @click="color(item.id)" /></PopoverContent></Popover
            ></template>
            <ToolbarTooltip v-if="current.id > 0" :label="t('ideation.history')"
              ><button
                type="button"
                class="toolbar-btn"
                :aria-label="t('ideation.history')"
                @click="history()"
              >
                <History class="size-3.5" /></button
            ></ToolbarTooltip>
            <ToolbarTooltip v-if="writable" :label="t('ideation.derive')"
              ><button
                type="button"
                class="toolbar-btn"
                :aria-label="t('ideation.derive')"
                @click="
                  add(
                    {
                      x: notePosition(current).x + (current.canvas?.width ?? 280) + 50,
                      y: notePosition(current).y,
                    },
                    current,
                  )
                "
              >
                <GitBranch class="size-3.5" /></button
            ></ToolbarTooltip>
            <Popover v-if="current.canvas?.links?.length"
              ><PopoverTrigger class="toolbar-btn" :aria-label="t('ideation.canvas.connections')"
                ><Unplug class="size-3.5" /></PopoverTrigger
              ><PopoverContent class="w-64 space-y-1"
                ><button
                  v-for="id in current.canvas.links"
                  :key="id"
                  type="button"
                  class="flex w-full items-center gap-2 rounded p-2 text-left text-xs hover:bg-accent"
                  :disabled="!writable"
                  @click="connect(current!.id, id, false)"
                >
                  <Unplug class="size-3 shrink-0" /><span class="truncate">{{
                    notes.notes.value.find((n) => n.id === id)?.preview ||
                    t("ideation.canvas.connection")
                  }}</span>
                </button></PopoverContent
              ></Popover
            >
            <template v-if="own && writable && current.id > 0"
              ><ToolbarTooltip
                :label="t(current.state === 'active' ? 'ideation.parked' : 'ideation.active')"
                ><button
                  type="button"
                  class="toolbar-btn"
                  :aria-label="
                    t(current.state === 'active' ? 'ideation.parked' : 'ideation.active')
                  "
                  @click="changeState(current.state === 'active' ? 'parked' : 'active')"
                >
                  <Archive v-if="current.state === 'active'" class="size-3.5" /><RotateCcw
                    v-else
                    class="size-3.5"
                  /></button></ToolbarTooltip
            ></template>
            <ToolbarTooltip
              v-if="own && writable && current.id > 0 && current.state !== 'discarded'"
              :label="t('ideation.canvas.discard')"
              ><button
                type="button"
                class="toolbar-btn"
                :aria-label="t('ideation.canvas.discard')"
                @click="changeState('discarded')"
              >
                <CircleX class="size-3.5" /></button
            ></ToolbarTooltip>
            <template v-if="own && writable">
              <ToolbarTooltip :label="t('ideation.canvas.deleteHelp')"
                ><button
                  type="button"
                  class="toolbar-btn"
                  :aria-label="t('ideation.canvas.delete')"
                  :disabled="notes.deleting.has(current.id)"
                  @click="remove(current.id)"
                >
                  <Trash2 class="size-3.5" /></button></ToolbarTooltip
            ></template>
          </div>
          <div
            v-if="selected !== null && (notes.errors.get(selected) || draft?.error)"
            role="alert"
            class="surface-panel mt-2 flex max-w-sm items-center gap-2 whitespace-normal p-2 text-xs"
          >
            <span>{{ error(notes.errors.get(selected) || draft?.error || "unavailable") }}</span
            ><Button size="sm" variant="ghost" @click="notes.retry(selected!)">{{
              t("ideation.retry")
            }}</Button>
          </div>
          <div v-if="draft?.conflict" class="surface-panel mt-2 w-80 space-y-2 p-3 text-xs">
            <p>{{ t("ideation.conflictHelp") }}</p>
            <IdeaEditor
              :value="draft.conflict.current.body"
              readonly
              :label="t('ideation.currentVersion')"
            /><Button size="sm" variant="ghost" @click="notes.drafts.resolve(selected!, false)">{{
              t("ideation.useCurrent")
            }}</Button
            ><Button size="sm" @click="notes.drafts.resolve(selected!, true)">{{
              t("ideation.saveMine")
            }}</Button>
          </div>
        </template>
      </BrainstormingCanvas>
      <div v-else class="h-full overflow-auto p-4 lg:p-6">
        <DashboardContent
          :title="board.session.title"
          :subtitle="board.session.objective ?? undefined"
          ><div class="flex items-center gap-2">
            <Button variant="outline" size="sm" @click="list = false"
              ><LayoutDashboard class="size-4" />{{ t("ideation.canvas.back") }}</Button
            ><BoardSelect
              v-model="state"
              :label="t('ideation.state')"
              :options="options(['active', 'parked', 'discarded', 'all'])"
            /><Button
              v-if="writable"
              size="sm"
              @click="
                list = false;
                add({ x: 0, y: 0 });
              "
              ><Plus class="size-4" />{{ t("ideation.newIdea") }}</Button
            >
          </div>
          <div class="divide-y rounded-lg border">
            <button
              v-for="note in visible"
              :key="note.id"
              type="button"
              class="flex w-full items-start gap-3 p-4 text-left hover:bg-accent/30"
              @click="locate(note)"
            >
              <StickyNote class="mt-1 size-4 shrink-0 text-muted-foreground" />
              <div>
                <p v-if="note.title" class="text-sm font-medium">{{ note.title }}</p>
                <p class="text-sm">{{ note.body.replace(/<[^>]*>/g, " ") }}</p>
                <p class="mt-2 text-xs text-muted-foreground">
                  {{ member(note.author_id, board.members) }} ·
                  {{ t(`ideation.${note.state}`) }}
                </p>
              </div>
            </button>
          </div></DashboardContent
        >
      </div>
      <p
        v-if="!writable"
        class="surface-panel pointer-events-none absolute right-3 top-3 px-3 py-2 text-xs text-muted-foreground"
      >
        {{ t(board.session.status === "archived" ? "ideation.archivedHelp" : "ideation.readOnly") }}
      </p>
      <div v-if="board.ideas_next" class="surface-panel absolute right-3 top-3 z-30 p-1">
        <Button
          size="sm"
          variant="ghost"
          @click="request('browse_ideas', { before_id: board.ideas_next })"
          >{{ t("ideation.canvas.more") }}</Button
        >
      </div>
    </div>
    <SessionDialog
      v-if="settings && board.session"
      :session="board.session"
      :context="context()"
      :request="request"
      :members="board.members"
      :can-manage="board.can_manage"
      @close="settings = false"
      @changed="
        settings = false;
        sync();
      "
    />
    <IdeaHistory
      v-if="historyOpen"
      :inspection="inspection"
      :loading="inspecting"
      :can-edit="own && writable"
      @close="
        historyOpen = false;
        inspectionGeneration++;
      "
      @more="history(true)"
      @more-conflicts="moreConflicts"
      @restore="
        current && notes.open(current);
        selected !== null && notes.drafts.change(selected, $event);
        historyOpen = false;
      "
    />
  </div>
</template>
