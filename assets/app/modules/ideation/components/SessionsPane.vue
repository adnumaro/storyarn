<script setup lang="ts">
import { Lightbulb, Plus, ArchiveRestore, Trash2, ChevronLeft, ChevronRight } from "@lucide/vue";
import { Button } from "@components/ui/button";
import LiveLink from "@components/navigation/LiveLink.vue";
import BoardSelect from "./BoardSelect.vue";
import { useBoardText } from "../composables/useBoardText";
import type { Board, Session } from "../types";

const { board, baseUrl } = defineProps<{ board: Board; baseUrl: string }>();
const emit = defineEmits<{
  create: [];
  browse: [status: string, before: number | null];
  recover: [session: Session];
  purge: [session: Session];
}>();
const { t, options } = useBoardText();
</script>
<template>
  <nav
    class="flex w-full shrink-0 flex-col border-r bg-muted/20 md:w-60"
    :aria-label="t('ideation.sessions')"
  >
    <div class="flex items-center justify-between px-4 py-4">
      <h1 class="flex items-center gap-2 text-sm font-semibold">
        <Lightbulb class="size-4 text-primary" />{{ t("ideation.title") }}
      </h1>
      <Button
        v-if="board.can_edit"
        id="new-brainstorming-session"
        size="icon-sm"
        variant="ghost"
        :aria-label="t('ideation.newSession')"
        @click="emit('create')"
        ><Plus class="size-4"
      /></Button>
    </div>
    <div class="px-3 pb-3">
      <BoardSelect
        :model-value="board.session_status"
        :label="t('ideation.sessionStatus')"
        :options="options(['open', 'archived', 'replaced'])"
        @update:model-value="emit('browse', $event, null)"
      />
    </div>
    <div class="min-h-0 flex-1 overflow-y-auto px-2 pb-3">
      <p v-if="board.session_status === 'replaced'" class="px-2 pb-3 text-xs text-muted-foreground">
        {{ t("ideation.legacySnapshotHelp") }}
      </p>
      <p v-if="!board.sessions.length" class="px-2 py-8 text-sm text-muted-foreground">
        {{ t("ideation.noSessions") }}
      </p>
      <div
        v-for="session in board.sessions"
        :key="session.id"
        class="mb-1 rounded-lg"
        :class="session.id === board.session?.id ? 'bg-primary/10' : ''"
      >
        <LiveLink
          v-if="!session.deleted_at"
          :to="`${baseUrl}/${session.id}`"
          mode="patch"
          class="block rounded-lg p-3 transition-colors hover:bg-muted focus-visible:ring-2 focus-visible:ring-ring"
          :aria-current="session.id === board.session?.id ? 'page' : undefined"
        >
          <span class="line-clamp-2 text-sm font-medium">{{ session.title }}</span>
          <span v-if="session.objective" class="mt-1 line-clamp-2 text-xs text-muted-foreground">{{
            session.objective
          }}</span>
        </LiveLink>
        <div v-else class="space-y-2 p-3">
          <p class="text-sm font-medium">{{ session.title }}</p>
          <p class="text-xs text-muted-foreground">{{ t("ideation.replacedHelp") }}</p>
          <div class="flex gap-1">
            <Button
              v-if="session.can_manage"
              size="sm"
              variant="outline"
              @click="emit('recover', session)"
              ><ArchiveRestore class="size-3" />{{ t("ideation.recover") }}</Button
            >
            <Button
              v-if="board.is_owner"
              size="icon-sm"
              variant="ghost"
              :aria-label="t('ideation.purge')"
              @click="emit('purge', session)"
              ><Trash2 class="size-4 text-destructive"
            /></Button>
          </div>
        </div>
      </div>
    </div>
    <div
      v-if="board.sessions_next || board.session_before"
      class="flex items-center justify-between border-t p-3"
    >
      <Button
        size="sm"
        variant="ghost"
        :disabled="!board.session_before"
        @click="emit('browse', board.session_status, null)"
        ><ChevronLeft class="size-4" />{{ t("ideation.first") }}</Button
      >
      <Button
        size="sm"
        variant="ghost"
        :disabled="!board.sessions_next"
        @click="emit('browse', board.session_status, board.sessions_next)"
        >{{ t("ideation.next") }}<ChevronRight class="size-4"
      /></Button>
    </div>
  </nav>
</template>
