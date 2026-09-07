<script setup lang="ts">
import { onMounted, onUnmounted, ref } from "vue";
import { Plus, StickyNote, ArchiveRestore, Trash2, ChevronLeft, ChevronRight } from "@lucide/vue";
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
const failure = ref<string | null>(null);
const pending = ref(false);
const purge = ref<Session | null>(null);
const { request, context } = useBoardConnection(
  () => board,
  () => {
    purge.value = null;
    pending.value = false;
  },
);
function routeChanged() {
  currentPath.value = window.location.pathname;
}
onMounted(() => {
  routeChanged();
  window.addEventListener("phx:page-loading-stop", routeChanged);
});
onUnmounted(() => window.removeEventListener("phx:page-loading-stop", routeChanged));
function closeMobile() {
  if (!window.matchMedia("(min-width: 1024px)").matches)
    window.dispatchEvent(
      new CustomEvent("storyarn:main-sidebar-change", { detail: { open: false } }),
    );
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
        <LiveLink
          v-if="!session.deleted_at"
          :to="`${baseUrl}/${session.id}`"
          mode="patch"
          class="flex items-center gap-2 rounded-md px-2 py-2 text-sm transition-colors hover:bg-accent/50"
          :class="
            currentPath === `${baseUrl}/${session.id}`
              ? 'bg-accent text-accent-foreground font-medium'
              : 'text-muted-foreground'
          "
          :aria-current="currentPath === `${baseUrl}/${session.id}` ? 'page' : undefined"
          @click="closeMobile"
          ><StickyNote class="size-4 shrink-0" /><span class="truncate">{{
            session.title
          }}</span></LiveLink
        >
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
