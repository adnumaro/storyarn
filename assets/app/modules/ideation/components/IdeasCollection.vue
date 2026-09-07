<script setup lang="ts">
import { computed, ref } from "vue";
import {
  Search,
  LayoutGrid,
  List,
  Lock,
  Users,
  Lightbulb,
  ChevronLeft,
  ChevronRight,
} from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import BoardSelect from "./BoardSelect.vue";
import { useBoardText } from "../composables/useBoardText";
import type { Board, Idea } from "../types";

const { board, selectedId } = defineProps<{ board: Board; selectedId: number | null }>();
const emit = defineEmits<{ select: [idea: Idea]; browse: [before: number | null] }>();
const { t, options, member } = useBoardText();
const query = ref("");
const state = ref("active");
const audience = ref("all");
const view = ref<"cards" | "list">("cards");
const visible = computed(() =>
  board.ideas.filter((idea) => {
    if (state.value !== "all" && idea.state !== state.value) return false;
    if (audience.value === "mine" && idea.author_id !== board.current_user_id) return false;
    if (["shared", "private"].includes(audience.value) && idea.visibility !== audience.value)
      return false;
    return `${idea.title ?? ""} ${idea.preview}`
      .toLocaleLowerCase()
      .includes(query.value.toLocaleLowerCase());
  }),
);
</script>
<template>
  <div class="flex min-h-0 flex-1 flex-col">
    <div class="flex flex-wrap items-center gap-2 border-b px-5 py-3">
      <div class="relative min-w-36 flex-1">
        <Search class="pointer-events-none absolute top-2.5 left-3 size-4 text-muted-foreground" />
        <Input
          v-model="query"
          class="pl-9"
          :placeholder="t('ideation.search')"
          :aria-label="t('ideation.search')"
        />
      </div>
      <div class="w-36">
        <BoardSelect
          v-model="state"
          :label="t('ideation.state')"
          :options="options(['all', 'active', 'parked', 'discarded'])"
        />
      </div>
      <div class="w-32">
        <BoardSelect
          v-model="audience"
          :label="t('ideation.visibility')"
          :options="options(['all', 'mine', 'private', 'shared'])"
        />
      </div>
      <div class="flex rounded-md border p-0.5" role="group" :aria-label="t('ideation.view')">
        <Button
          size="icon-sm"
          :variant="view === 'cards' ? 'secondary' : 'ghost'"
          :aria-label="t('ideation.cards')"
          :aria-pressed="view === 'cards'"
          @click="view = 'cards'"
          ><LayoutGrid class="size-4"
        /></Button>
        <Button
          size="icon-sm"
          :variant="view === 'list' ? 'secondary' : 'ghost'"
          :aria-label="t('ideation.list')"
          :aria-pressed="view === 'list'"
          @click="view = 'list'"
          ><List class="size-4"
        /></Button>
      </div>
      <p class="w-full text-xs text-muted-foreground">
        {{ t("ideation.pageSearchHelp", { shown: visible.length, loaded: board.ideas.length }) }}
      </p>
    </div>
    <div class="min-h-0 flex-1 overflow-y-auto p-5">
      <div
        v-if="!visible.length"
        class="mx-auto flex max-w-sm flex-col items-center py-20 text-center"
      >
        <Lightbulb class="mb-4 size-8 text-primary/60" />
        <h3 class="font-medium">
          {{ t(board.ideas.length ? "ideation.noMatches" : "ideation.emptyIdeas") }}
        </h3>
        <p class="mt-2 text-sm text-muted-foreground">{{ t("ideation.emptyIdeasHelp") }}</p>
      </div>
      <ul
        v-else
        :class="
          view === 'cards'
            ? 'grid grid-cols-[repeat(auto-fill,minmax(230px,1fr))] gap-3'
            : 'space-y-2'
        "
        :aria-label="t('ideation.ideas')"
      >
        <li v-for="idea in visible" :key="idea.id">
          <button
            :id="`idea-card-${idea.id}`"
            type="button"
            class="group flex w-full flex-col items-stretch rounded-xl border bg-card p-4 text-left shadow-xs transition-colors hover:border-primary/50 focus-visible:ring-2 focus-visible:ring-ring"
            :class="[
              selectedId === idea.id && 'border-primary bg-primary/5',
              view === 'cards' && 'h-full min-h-44',
            ]"
            :aria-pressed="selectedId === idea.id"
            @click="emit('select', idea)"
          >
            <span class="flex items-center justify-between gap-2 text-xs text-muted-foreground">
              <span class="flex items-center gap-1.5"
                ><Lock v-if="idea.visibility === 'private'" class="size-3" /><Users
                  v-else
                  class="size-3"
                />{{ t(`ideation.${idea.visibility}`) }}</span
              >
              <span>{{ t(`ideation.${idea.state}`) }}</span>
            </span>
            <span class="mt-3 block line-clamp-2 text-sm font-semibold">{{
              idea.title || t("ideation.untitled")
            }}</span>
            <span
              class="mt-1 block text-sm text-muted-foreground"
              :class="view === 'cards' ? 'line-clamp-4' : 'line-clamp-1'"
              >{{ idea.preview }}</span
            >
            <span
              class="mt-4 flex items-center justify-between gap-2 text-xs text-muted-foreground"
            >
              <span>{{
                idea.author_id === board.current_user_id
                  ? t("ideation.you")
                  : member(idea.author_id, board.members)
              }}</span>
              <span
                v-if="idea.visibility === 'shared' && idea.has_unpublished_changes"
                class="text-primary"
                >{{ t("ideation.unpublished") }}</span
              >
            </span>
          </button>
        </li>
      </ul>
    </div>
    <footer
      class="flex flex-wrap items-center justify-between gap-2 border-t px-5 py-2 text-xs text-muted-foreground"
    >
      <span>{{ t("ideation.counts", board.counts) }}</span>
      <div v-if="board.ideas_next || board.idea_before" class="flex gap-1">
        <Button
          size="sm"
          variant="ghost"
          :disabled="!board.idea_before"
          @click="emit('browse', null)"
          ><ChevronLeft class="size-4" />{{ t("ideation.first") }}</Button
        >
        <Button
          size="sm"
          variant="ghost"
          :disabled="!board.ideas_next"
          @click="emit('browse', board.ideas_next)"
          >{{ t("ideation.next") }}<ChevronRight class="size-4"
        /></Button>
      </div>
    </footer>
  </div>
</template>
