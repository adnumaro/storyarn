<script setup lang="ts">
import { AtSign, LoaderCircle, Send, X } from "@lucide/vue";
import { computed, reactive, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import { useLive } from "@shared/composables/useLive";
import { clearCommentDraft, readCommentDraft, updateCommentDraft } from "./commentDraftStorage";
import type { CommentMember, CommentPosition, CommentUiConfig } from "./types";

interface Draft {
  body: string;
  mentionIds: number[];
  requestId: string | null;
  fingerprint: string | null;
  pending: boolean;
  error: string | null;
}

const {
  sourceId = null,
  threadId = null,
  parentId = null,
  position = null,
  draftId = null,
  draftStorageKey = null,
  members,
  disabled = false,
  ui,
} = defineProps<{
  sourceId?: number | null;
  threadId?: number | null;
  parentId?: number | null;
  position?: CommentPosition | null;
  draftId?: string | null;
  draftStorageKey?: string | null;
  members: CommentMember[];
  disabled?: boolean;
  ui: CommentUiConfig;
}>();

const emit = defineEmits<{ sent: [] }>();
const live = useLive();
const { t } = useI18n();
const drafts = reactive(new Map<string, Draft>());
const memberSearch = ref("");
const mentionOpen = ref(false);
const submittedDraftKey = ref<string | null>(null);
const translationKey = (name: string) => `${ui.i18nPrefix}.${name}`;
const domId = (name: string) => `${ui.domScope}-comment-${name}`;

const draftKey = computed(() => {
  if (threadId != null) return `thread:${threadId}:parent:${parentId}`;
  if (draftStorageKey) return `stored:${draftStorageKey}`;
  if (draftId) return `draft:${draftId}`;
  if (sourceId != null) return `source:${sourceId}`;
  if (position) return `canvas:${position.x}:${position.y}`;
  return "canvas:unplaced";
});

function initialDraft(): Draft {
  const stored = threadId == null ? readCommentDraft(draftStorageKey) : null;
  return {
    body: stored?.body ?? "",
    mentionIds: stored?.mentionIds ?? [],
    requestId: stored?.requestId ?? null,
    fingerprint: stored?.fingerprint ?? null,
    pending: false,
    error: null,
  };
}

const draft = computed(() => {
  const key = draftKey.value;
  let value = drafts.get(key);
  if (!value) {
    drafts.set(key, initialDraft());
    value = drafts.get(key)!;
  }
  return value;
});

watch(draftKey, (key) => {
  if (submittedDraftKey.value && submittedDraftKey.value !== key) submittedDraftKey.value = null;
});
watch([() => draft.value.body, () => [...draft.value.mentionIds]], ([body, mentionIds]) => {
  if (threadId != null || submittedDraftKey.value === draftKey.value) return;
  updateCommentDraft(draftStorageKey, { body: body as string, mentionIds: mentionIds as number[] });
});
const availableMembers = computed(() =>
  members.filter((member): member is CommentMember & { id: number } => member.id != null),
);
const selectedMembers = computed(() =>
  availableMembers.value.filter((member) => draft.value.mentionIds.includes(member.id)),
);
const filteredMembers = computed(() =>
  availableMembers.value.filter((member) =>
    member.display_name.toLocaleLowerCase().includes(memberSearch.value.toLocaleLowerCase()),
  ),
);
const canSend = computed(
  () =>
    !disabled &&
    !draft.value.pending &&
    draft.value.body.trim().length > 0 &&
    (threadId != null ? parentId != null : sourceId != null || position != null),
);

function toggleMention(memberId: number) {
  const current = draft.value;
  if (current.pending || disabled) return;
  if (current.mentionIds.includes(memberId)) {
    current.mentionIds = current.mentionIds.filter((id) => id !== memberId);
  } else if (current.mentionIds.length < 50) {
    current.mentionIds.push(memberId);
  }
}

function ensureRequestIdentity(current: Draft, fingerprint: string, storageKey: string | null) {
  if (current.fingerprint === fingerprint && current.requestId) return;
  current.requestId = crypto.randomUUID();
  current.fingerprint = fingerprint;
  if (threadId == null)
    updateCommentDraft(storageKey, {
      requestId: current.requestId,
      fingerprint: current.fingerprint,
    });
}

function submit() {
  if (!canSend.value) return;
  const current = draft.value;
  const submittedComposerKey = draftKey.value;
  const submittedStorageKey = draftStorageKey;
  const submittedTopLevelThread = threadId == null;
  const body = current.body.trim();
  const mentionIds = [
    ...new Set(current.mentionIds.filter((id) => members.some((member) => member.id === id))),
  ].sort((left, right) => left - right);
  const createPosition = threadId == null && position ? { x: position.x, y: position.y } : null;
  const fingerprint = JSON.stringify({
    sourceId,
    createSourceKey: ui.createSourceKey,
    threadId,
    parentId,
    position: createPosition,
    body,
    mentionIds,
  });
  ensureRequestIdentity(current, fingerprint, submittedStorageKey);
  const createTarget = ui.createSourceKey ? { [ui.createSourceKey]: sourceId } : {};
  const payload = {
    body,
    mention_user_ids: mentionIds,
    client_request_id: current.requestId,
    ...(threadId == null
      ? { ...createTarget, ...(createPosition ? { position: createPosition } : {}) }
      : { thread_id: threadId, parent_id: parentId }),
  };
  current.pending = true;
  current.error = null;
  live.pushEvent(
    threadId == null ? "comments_create" : "comments_reply",
    payload,
    (reply) => {
      current.pending = false;
      if (reply.ok === true) {
        if (submittedTopLevelThread) {
          if (draftKey.value === submittedComposerKey)
            submittedDraftKey.value = submittedComposerKey;
          clearCommentDraft(submittedStorageKey);
        }
        current.body = "";
        current.mentionIds = [];
        current.requestId = null;
        current.fingerprint = null;
        if (draft.value === current) emit("sent");
      } else {
        current.error =
          typeof reply.error === "string" ? reply.error : t(translationKey("send_failed"));
      }
    },
    () => {
      current.pending = false;
      current.error = t(translationKey("send_failed"));
    },
  );
}
</script>

<template>
  <form class="space-y-2" :data-testid="`${ui.domScope}-comment-composer`" @submit.prevent="submit">
    <label :for="domId('body')" class="text-xs font-medium">{{
      threadId == null ? $t(translationKey("new_thread")) : $t(translationKey("reply"))
    }}</label>
    <textarea
      :id="domId('body')"
      v-model="draft.body"
      class="min-h-24 w-full resize-y rounded-md border border-input bg-background px-3 py-2 text-sm outline-none transition-shadow placeholder:text-muted-foreground focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-50"
      :placeholder="$t(translationKey('placeholder'))"
      :disabled="disabled || draft.pending"
      maxlength="10000"
      @keydown.ctrl.enter.prevent="submit"
      @keydown.meta.enter.prevent="submit"
    />
    <div v-if="selectedMembers.length" class="flex flex-wrap gap-1" aria-live="polite">
      <button
        v-for="member in selectedMembers"
        :key="member.id"
        type="button"
        class="inline-flex items-center gap-1 rounded-full bg-primary/10 px-2 py-1 text-xs text-primary"
        :disabled="disabled || draft.pending"
        :aria-label="$t(translationKey('remove_mention'), { name: member.display_name })"
        @click="toggleMention(member.id)"
      >
        <AtSign class="size-3" />{{ member.display_name }}<X class="size-3" />
      </button>
    </div>
    <p v-if="draft.error" role="alert" class="text-xs text-destructive">{{ draft.error }}</p>
    <div class="flex items-center justify-between gap-2">
      <Popover v-model:open="mentionOpen">
        <PopoverTrigger as-child>
          <Button
            variant="ghost"
            size="sm"
            type="button"
            :disabled="disabled || draft.pending || !members.length"
            class="gap-1.5 text-xs"
            ><AtSign class="size-3.5" />{{ $t(translationKey("mention")) }}</Button
          >
        </PopoverTrigger>
        <PopoverContent class="w-64 p-2" align="start">
          <input
            v-model="memberSearch"
            :aria-label="$t(translationKey('search_people'))"
            :placeholder="$t(translationKey('search_people'))"
            class="mb-2 w-full rounded-md border border-input px-2 py-1.5 text-sm"
          />
          <div class="max-h-48 space-y-0.5 overflow-y-auto">
            <button
              v-for="member in filteredMembers"
              :key="member.id"
              type="button"
              class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm transition-colors hover:bg-accent"
              :class="{ 'bg-accent': draft.mentionIds.includes(member.id) }"
              :aria-pressed="draft.mentionIds.includes(member.id)"
              @click="toggleMention(member.id)"
            >
              <AtSign class="size-3.5 text-muted-foreground" />{{ member.display_name }}
            </button>
            <p v-if="!filteredMembers.length" class="px-2 py-2 text-xs text-muted-foreground">
              {{ $t(translationKey("no_people")) }}
            </p>
          </div>
        </PopoverContent>
      </Popover>
      <Button :id="domId('send')" type="submit" size="sm" class="gap-1.5" :disabled="!canSend"
        ><LoaderCircle v-if="draft.pending" class="size-3.5 animate-spin" /><Send
          v-else
          class="size-3.5"
        />{{ $t(translationKey("send")) }}</Button
      >
    </div>
  </form>
</template>
