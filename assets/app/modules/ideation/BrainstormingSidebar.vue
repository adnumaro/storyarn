<script setup lang="ts">
import { onMounted, onUnmounted, reactive, ref } from "vue";
import {
  Plus,
  StickyNote,
  ArchiveRestore,
  Trash2,
  ChevronLeft,
  ChevronRight,
  Bookmark,
} from "@lucide/vue";
import SidebarFrame from "@shell/SidebarFrame.vue";
import LiveLink from "@components/navigation/LiveLink.vue";
import ConfirmDialog from "@components/ConfirmDialog.vue";
import { Button } from "@components/ui/button";
import BoardSelect from "./components/BoardSelect.vue";
import { useBoardConnection } from "./composables/useBoardConnection";
import { useBoardText } from "./composables/useBoardText";
import type { Board, Session } from "./types";
const { board, baseUrl } = defineProps<{ board: Board; baseUrl: string }>();
const { t, error, options } = useBoardText();
const currentPath = ref("");
const currentQuery = ref(new URLSearchParams());
const failure = ref<string | null>(null);
const pending = ref(false);
const purge = ref<Session | null>(null);
// A manual collapse or expand wins over the automatic "open the current session".
const toggled = reactive(new Map<number, boolean>());
const { request, context } = useBoardConnection(
  () => board,
  () => {
    purge.value = null;
    pending.value = false;
  },
);
function routeChanged() {
  currentPath.value = window.location.pathname;
  currentQuery.value = new URLSearchParams(window.location.search);
}
onMounted(() => {
  routeChanged();
  window.addEventListener("phx:navigate", routeChanged);
});
onUnmounted(() => window.removeEventListener("phx:navigate", routeChanged));
function closeMobile() {
  if (!window.matchMedia("(min-width: 1024px)").matches)
    window.dispatchEvent(
      new CustomEvent("storyarn:main-sidebar-change", { detail: { open: false } }),
    );
}
function sessionPath(session: Session) {
  return `${baseUrl}/${session.id}`;
}
function isCurrent(session: Session) {
  return currentPath.value === sessionPath(session);
}
// A session with one round is a leaf: rounds only appear once there are two.
function hasChildren(session: Session) {
  return (session.rounds?.length ?? 0) > 1 || (session.parked_count ?? 0) > 0;
}
function isOpen(session: Session) {
  return toggled.get(session.id) ?? isCurrent(session);
}
function toggle(session: Session) {
  toggled.set(session.id, !isOpen(session));
}
function roundActive(session: Session, roundId: number) {
  return isCurrent(session) && currentQuery.value.get("round") === String(roundId);
}
function laterActive(session: Session) {
  return isCurrent(session) && currentQuery.value.get("view") === "later";
}
function sessionRowActive(session: Session) {
  return isCurrent(session) && !currentQuery.value.has("round") && !currentQuery.value.has("view");
}
async function run(event: string, session?: Session) {
  if (pending.value) return;
  pending.value = true;
  failure.value = null;
  const reply = await request(
    event,
    { revision: session?.revision },
    { ...context(), session_id: session?.id ?? null },
  );
  const unknown =
    event === "create_session" && reply.status === "error" && reply.code === "offline";
  pending.value = unknown;
  if (reply.status === "error") failure.value = unknown ? "session_creation_unknown" : reply.code;
  else {
    purge.value = null;
    if (event === "create_session") closeMobile();
  }
}
function browse(status: string, before: number | null = null) {
  void request("browse_sessions", { status, before_id: before });
}
</script>
<template>
  <SidebarFrame
    active-tool="brainstorming"
    :dashboard-url="baseUrl"
    :on-dashboard="currentPath === baseUrl"
  >
    <div class="mb-3 flex items-center justify-between px-2 pt-1">
      <span class="text-xs font-medium text-muted-foreground">{{ t("ideation.sessions") }}</span>
      <Button
        v-if="board.can_edit"
        id="new-brainstorming-session"
        variant="ghost"
        size="icon-sm"
        :disabled="pending"
        :aria-label="t('ideation.newSession')"
        @click="run('create_session')"
        ><Plus class="size-4"
      /></Button>
    </div>
    <BoardSelect
      :model-value="board.session_status"
      :label="t('ideation.sessionStatus')"
      :options="options(['open', 'archived', 'replaced'])"
      @update:model-value="browse($event)"
    />
    <p v-if="board.error || failure" role="alert" class="px-2 py-3 text-xs text-destructive">
      {{ error(board.error || failure || "unavailable") }}
    </p>
    <p v-if="board.session_status === 'replaced'" class="px-2 py-3 text-xs text-muted-foreground">
      {{ t("ideation.legacySnapshotHelp") }}
    </p>
    <nav class="mt-3 space-y-0.5" :aria-label="t('ideation.sessions')">
      <div v-for="session in board.sessions" :key="session.id">
        <template v-if="!session.deleted_at">
          <div
            :id="`brainstorming-tree-session-${session.id}`"
            class="group flex items-center gap-1 rounded-md pr-1 text-sm transition-colors"
            :class="
              sessionRowActive(session)
                ? 'bg-accent text-accent-foreground font-medium'
                : 'text-muted-foreground hover:bg-accent/50'
            "
          >
            <button
              v-if="hasChildren(session)"
              type="button"
              class="inline-flex size-5 shrink-0 items-center justify-center rounded hover:bg-accent"
              :aria-expanded="isOpen(session)"
              :aria-label="session.title"
              @click.stop.prevent="toggle(session)"
            >
              <ChevronRight
                :class="['size-3 transition-transform', isOpen(session) && 'rotate-90']"
              />
            </button>
            <span v-else class="size-5 shrink-0" />
            <LiveLink
              :to="sessionPath(session)"
              mode="patch"
              class="flex min-w-0 flex-1 items-center gap-2 py-2 pr-1"
              :aria-current="isCurrent(session) ? 'page' : undefined"
              @click="closeMobile"
              ><StickyNote class="size-4 shrink-0" /><span class="truncate">{{
                session.title
              }}</span></LiveLink
            >
          </div>
          <div
            v-if="hasChildren(session) && isOpen(session)"
            :id="`brainstorming-tree-rounds-${session.id}`"
            class="space-y-0.5"
          >
            <LiveLink
              v-for="round in session.rounds ?? []"
              :id="`brainstorming-tree-round-${round.id}`"
              :key="round.id"
              :to="`${sessionPath(session)}?round=${round.id}`"
              mode="patch"
              class="flex items-center gap-2 rounded-md py-1.5 pl-9 pr-2 text-[13px] transition-colors"
              :class="
                roundActive(session, round.id)
                  ? 'bg-accent text-accent-foreground font-medium'
                  : 'text-muted-foreground hover:bg-accent/50'
              "
              :title="round.prompt ?? undefined"
              :data-status="round.status"
              @click="closeMobile"
            >
              <span
                aria-hidden="true"
                class="size-1.5 shrink-0 rounded-full"
                :class="round.status === 'active' ? 'bg-primary' : 'bg-transparent'"
              />
              <span
                v-if="round.prompt"
                class="shrink-0 text-[11px] font-semibold tabular-nums text-muted-foreground/80"
                >{{ t("ideation.rounds.short", { number: round.number }) }}</span
              >
              <span class="truncate">{{
                round.prompt ?? t("ideation.rounds.number", { number: round.number })
              }}</span>
            </LiveLink>
            <LiveLink
              v-if="session.parked_count"
              :id="`brainstorming-tree-later-${session.id}`"
              :to="`${sessionPath(session)}?view=later`"
              mode="patch"
              class="flex items-center gap-2 rounded-md py-1.5 pl-9 pr-2 text-[13px] transition-colors"
              :class="
                laterActive(session)
                  ? 'bg-accent text-accent-foreground font-medium'
                  : 'text-muted-foreground hover:bg-accent/50'
              "
              @click="closeMobile"
            >
              <Bookmark class="size-3.5 shrink-0" />
              <span class="flex-1 truncate">{{ t("ideation.forLater") }}</span>
              <span class="text-[11px] tabular-nums">{{ session.parked_count }}</span>
            </LiveLink>
          </div>
        </template>
        <div v-else class="space-y-2 rounded-md px-2 py-2">
          <p class="truncate text-sm">{{ session.title }}</p>
          <div class="flex gap-1">
            <Button
              v-if="session.can_manage"
              size="sm"
              variant="ghost"
              :disabled="pending"
              @click="run('recover_session', session)"
              ><ArchiveRestore class="size-3.5" />{{ t("ideation.recover") }}</Button
            ><Button
              v-if="board.is_owner"
              variant="ghost"
              size="icon-sm"
              :aria-label="t('ideation.purge')"
              @click="purge = session"
              ><Trash2 class="size-3.5"
            /></Button>
          </div>
        </div>
      </div>
      <p v-if="!board.sessions.length" class="px-2 py-6 text-xs text-muted-foreground">
        {{ t("ideation.noSessions") }}
      </p>
    </nav>
    <div
      v-if="board.sessions_next || board.session_before"
      class="mt-3 flex justify-between border-t pt-2"
    >
      <Button
        variant="ghost"
        size="icon-sm"
        :disabled="!board.session_before"
        :aria-label="t('ideation.first')"
        @click="browse(board.session_status)"
        ><ChevronLeft class="size-4"
      /></Button>
      <Button
        variant="ghost"
        size="icon-sm"
        :disabled="!board.sessions_next"
        :aria-label="t('ideation.next')"
        @click="browse(board.session_status, board.sessions_next)"
        ><ChevronRight class="size-4"
      /></Button>
    </div>
  </SidebarFrame>
  <ConfirmDialog
    :open="purge !== null"
    :title="t('ideation.purge')"
    :description="t('ideation.purgeHelp', { title: purge?.title ?? '' })"
    :confirm-text="t('ideation.purge')"
    :cancel-text="t('ideation.cancel')"
    variant="destructive"
    :pending="pending"
    :close-on-confirm="false"
    :error="failure ? error(failure) : undefined"
    @update:open="!$event && (purge = null)"
    @confirm="purge && run('purge_session', purge)"
  />
</template>
