<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import { X, History, GitBranch, Send, Save, RefreshCw } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import BoardSelect from "./BoardSelect.vue";
import IdeaEditor from "./IdeaEditor.vue";
import { useBoardText } from "../composables/useBoardText";
import type { Draft } from "../composables/useIdeaDrafts";
import type { Board, IdeaContent, Inspection } from "../types";

const { board, inspection, draft, loading } = defineProps<{
  board: Board;
  inspection: Inspection;
  draft?: Draft;
  loading: boolean;
}>();
const emit = defineEmits<{
  close: [];
  change: [content: Partial<IdeaContent>];
  save: [];
  resolve: [keepMine: boolean];
  publish: [];
  derive: [];
  history: [];
  conflicts: [];
  source: [id: number];
}>();
const { t, error, member, options } = useBoardText();
const heading = ref<HTMLElement>();
const idea = computed(() => draft?.idea ?? inspection.idea);
const content = computed(() => draft?.content ?? idea.value);
const editable = computed(() =>
  Boolean(draft && board.can_edit && board.session?.status === "open"),
);
const historyOpen = ref(false);
watch(
  () => inspection.idea.id,
  async () => {
    historyOpen.value = false;
    await nextTick();
    heading.value?.focus();
  },
  { immediate: true },
);
</script>
<template>
  <aside
    class="flex h-full min-h-0 w-full shrink-0 flex-col border-l bg-background xl:w-100 2xl:w-112"
    :aria-label="t('ideation.ideaDetails')"
  >
    <div class="flex items-center justify-between border-b px-4 py-3">
      <h2 ref="heading" tabindex="-1" class="text-sm font-semibold outline-none">
        {{ t("ideation.ideaDetails") }}
      </h2>
      <Button
        size="icon-sm"
        variant="ghost"
        :aria-label="t('ideation.close')"
        @click="emit('close')"
        ><X class="size-4"
      /></Button>
    </div>
    <div class="min-h-0 flex-1 space-y-4 overflow-y-auto p-4">
      <p class="text-xs text-muted-foreground">
        {{ member(idea.author_id, board.members) }} ·
        {{ t("ideation.revision", { number: idea.revision }) }} ·
        {{ t(`ideation.${idea.visibility}`) }}
      </p>
      <template v-if="editable">
        <label for="idea-title" class="block text-sm font-medium">{{
          t("ideation.ideaTitle")
        }}</label>
        <Input
          id="idea-title"
          :model-value="content.title ?? ''"
          :maxlength="160"
          :placeholder="t('ideation.titleOptional')"
          @update:model-value="emit('change', { title: String($event) })"
        />
      </template>
      <h3 v-else class="text-lg font-semibold">{{ content.title || t("ideation.untitled") }}</h3>
      <IdeaEditor
        :value="content.body"
        :readonly="!editable"
        :label="t('ideation.body')"
        @change="emit('change', { body: $event })"
        @save="emit('save')"
      />
      <div class="space-y-2">
        <label class="text-sm font-medium">{{ t("ideation.state") }}</label>
        <BoardSelect
          :model-value="content.state"
          :disabled="!editable"
          :label="t('ideation.state')"
          :options="options(['active', 'parked', 'discarded'])"
          @update:model-value="emit('change', { state: $event as IdeaContent['state'] })"
        />
        <p class="text-xs text-muted-foreground">{{ t("ideation.stateHelp") }}</p>
      </div>
      <div v-if="draft" class="space-y-2" aria-live="polite">
        <p class="text-xs text-muted-foreground">{{ t(`ideation.saveStatus.${draft.status}`) }}</p>
        <p v-if="draft.error" role="alert" class="text-sm text-destructive">
          {{ error(draft.error) }}
        </p>
        <Button
          v-if="editable && draft.status !== 'saved' && draft.status !== 'conflict'"
          size="sm"
          variant="outline"
          :disabled="draft.status === 'saving'"
          @click="emit('save')"
          ><Save class="size-4" />{{
            t(draft.status === "error" ? "ideation.retry" : "ideation.save")
          }}</Button
        >
      </div>
      <div
        v-if="draft?.conflict"
        class="space-y-3 rounded-lg border border-warning/40 bg-warning/5 p-3"
      >
        <h4 class="text-sm font-semibold">{{ t("ideation.conflictTitle") }}</h4>
        <p class="text-xs text-muted-foreground">{{ t("ideation.conflictHelp") }}</p>
        <p class="text-sm font-medium">
          {{ draft.conflict.current.title }} · {{ t(`ideation.${draft.conflict.current.state}`) }}
        </p>
        <IdeaEditor
          :value="draft.conflict.current.body"
          readonly
          :label="t('ideation.currentVersion')"
        />
        <div class="flex flex-wrap gap-2">
          <Button size="sm" variant="outline" @click="emit('resolve', false)">{{
            t("ideation.useCurrent")
          }}</Button>
          <Button v-if="editable" size="sm" @click="emit('resolve', true)">{{
            t("ideation.saveMine")
          }}</Button>
        </div>
      </div>
      <p v-if="!editable" class="rounded-lg bg-muted p-3 text-xs text-muted-foreground">
        {{ t("ideation.authorOnlyHelp") }}
      </p>
      <div v-if="editable" class="space-y-2 rounded-lg border p-3">
        <p class="text-xs text-muted-foreground">
          {{
            t(idea.visibility === "private" ? "ideation.privateHelp" : "ideation.publishedHelp", {
              number: idea.published_revision ?? 0,
            })
          }}
        </p>
        <p
          v-if="idea.publication_consent === 'facilitator_assisted'"
          class="text-xs text-muted-foreground"
        >
          {{ t("ideation.assistedConsentHelp") }}
        </p>
        <Button
          v-if="idea.has_unpublished_changes"
          size="sm"
          :disabled="draft?.status !== 'saved'"
          @click="emit('publish')"
          ><Send class="size-4" />{{ t("ideation.publishRevision") }}</Button
        >
      </div>
      <Button
        v-if="board.can_edit && board.session?.status === 'open'"
        size="sm"
        variant="outline"
        @click="emit('derive')"
        ><GitBranch class="size-4" />{{ t("ideation.derive") }}</Button
      >
      <Button
        v-if="idea.source_idea_id"
        size="sm"
        variant="ghost"
        @click="emit('source', idea.source_idea_id)"
        >{{ t("ideation.source", { number: idea.source_revision }) }}</Button
      >
      <div class="border-t pt-3">
        <Button
          size="sm"
          variant="ghost"
          :aria-expanded="historyOpen"
          @click="historyOpen = !historyOpen"
          ><History class="size-4" />{{ t("ideation.history") }}</Button
        >
        <div v-if="historyOpen" class="mt-3 space-y-3">
          <details
            v-for="revision in inspection.history"
            :key="revision.id"
            class="rounded-lg border p-3"
          >
            <summary class="cursor-pointer text-sm">
              {{ t("ideation.revision", { number: revision.number }) }} ·
              {{ t(`ideation.${revision.state}`) }}
            </summary>
            <p class="my-2 text-sm font-medium">{{ revision.title }}</p>
            <IdeaEditor :value="revision.body" readonly :label="t('ideation.history')" />
            <Button
              v-if="editable && draft?.status === 'saved'"
              size="sm"
              variant="outline"
              class="mt-2"
              @click="
                emit('change', {
                  title: revision.title,
                  body: revision.body,
                  state: revision.state,
                })
              "
              >{{ t("ideation.useText") }}</Button
            >
          </details>
          <Button
            v-if="inspection.history_next !== null"
            size="sm"
            variant="outline"
            :disabled="loading"
            @click="emit('history')"
            ><RefreshCw class="size-4" />{{ t("ideation.moreHistory") }}</Button
          >
          <details
            v-for="receipt in inspection.conflicts"
            :key="`conflict-${receipt.id}`"
            class="rounded-lg border p-3"
          >
            <summary class="cursor-pointer text-sm">
              {{ t("ideation.recoveredConflict", { number: receipt.base_revision }) }}
            </summary>
            <p class="my-2 text-sm">
              {{ receipt.attempted.title }} · {{ t(`ideation.${receipt.attempted.state}`) }}
            </p>
            <IdeaEditor
              :value="receipt.attempted.body"
              readonly
              :label="t('ideation.conflictTitle')"
            />
            <Button
              v-if="editable && draft?.status === 'saved'"
              size="sm"
              variant="outline"
              class="mt-2"
              @click="emit('change', receipt.attempted)"
              >{{ t("ideation.useText") }}</Button
            >
          </details>
          <Button
            v-if="inspection.conflicts_next !== null"
            size="sm"
            variant="outline"
            :disabled="loading"
            @click="emit('conflicts')"
            >{{ t("ideation.moreConflicts") }}</Button
          >
        </div>
      </div>
    </div>
  </aside>
</template>
