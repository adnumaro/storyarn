<script setup lang="ts">
import { AtSign, LoaderCircle, Send, X } from "@lucide/vue";
import { computed, nextTick, reactive, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import UserAvatar from "@components/UserAvatar.vue";
import { Button } from "@components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import { useLive } from "@shared/composables/useLive";
import { clearCommentDraft, readCommentDraft, updateCommentDraft } from "./commentDraftStorage";
import type {
  CommentContextReference,
  CommentMember,
  CommentPosition,
  CommentUiConfig,
} from "./types";

interface Draft {
  body: string;
  mentionIds: number[];
  requestId: string | null;
  fingerprint: string | null;
  pending: boolean;
  error: string | null;
}

type Member = CommentMember & { id: number };

/** Where an unsent text lives: the draft identity and the browser storage key. */
export interface CommentComposerStorage {
  draftId?: string | null;
  key?: string | null;
}

/** Whom the composer answers and as whom. */
export interface CommentComposerAnswering {
  /** The message being answered when it is not the root; shown as a cancelable chip. */
  to?: CommentMember | null;
  /** A restored reply target whose message is not loaded yet. */
  previous?: boolean;
  /** The current user's name, drawn as the avatar beside the reply field. */
  authorName?: string | null;
}

const {
  sourceId = null,
  threadId = null,
  parentId = null,
  position = null,
  context,
  storage = {},
  members,
  disabled = false,
  ui,
  answering = {},
} = defineProps<{
  sourceId?: number | null;
  threadId?: number | null;
  parentId?: number | null;
  position?: CommentPosition | null;
  context?: CommentContextReference | null;
  storage?: CommentComposerStorage;
  members: CommentMember[];
  disabled?: boolean;
  ui: CommentUiConfig;
  answering?: CommentComposerAnswering;
}>();

const emit = defineEmits<{ sent: []; cancelReply: [] }>();
const live = useLive();
const { t } = useI18n();
const drafts = reactive(new Map<string, Draft>());
const textarea = ref<HTMLTextAreaElement | null>(null);
const focused = ref(false);
const mentionQuery = ref<string | null>(null);
const mentionIndex = ref(0);
const clearingDrafts = new WeakSet<Draft>();
const translationKey = (name: string) => `${ui.i18nPrefix}.${name}`;
const domId = (name: string) => `${ui.domScope}-comment-${name}`;
const isReply = computed(() => threadId != null);
const draftId = computed(() => storage.draftId ?? null);
const draftStorageKey = computed(() => storage.key ?? null);
const replyTo = computed(() => answering.to ?? null);
const replyToPrevious = computed(() => answering.previous === true);
const authorName = computed(() => answering.authorName ?? null);
const storageKey = computed(() => {
  if (threadId == null) return draftStorageKey.value;
  return ui.persistReplyDraft && draftStorageKey.value
    ? `${draftStorageKey.value}:thread:${threadId}:parent:${parentId}`
    : null;
});

const draftKey = computed(() => {
  if (storageKey.value) return `stored:${storageKey.value}`;
  if (threadId != null) return `thread:${threadId}:parent:${parentId}`;
  if (draftId.value) return `draft:${draftId.value}`;
  if (sourceId != null) return `source:${sourceId}`;
  if (position) return `canvas:${position.x}:${position.y}`;
  return "canvas:unplaced";
});

function initialDraft(): Draft {
  const stored = readCommentDraft(storageKey.value);
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

watch(
  [() => draft.value.body, () => [...draft.value.mentionIds]],
  ([body, mentionIds]) => {
    if (clearingDrafts.has(draft.value)) return;
    updateCommentDraft(storageKey.value, {
      body: body as string,
      mentionIds: mentionIds as number[],
    });
  },
  { flush: "sync" },
);

/** A reply field stays one line until it is focused or holds text. */
const expanded = computed(
  () =>
    !isReply.value ||
    focused.value ||
    draft.value.body.length > 0 ||
    replyTo.value != null ||
    replyToPrevious.value,
);
const availableMembers = computed(() =>
  members.filter((member): member is Member => member.id != null),
);
const mentionCandidates = computed(() => {
  const query = (mentionQuery.value ?? "").toLocaleLowerCase();
  return availableMembers.value.filter((member) =>
    member.display_name.toLocaleLowerCase().includes(query),
  );
});
const mentionOpen = computed(
  () =>
    ui.mentionsEnabled !== false &&
    mentionQuery.value != null &&
    mentionCandidates.value.length > 0,
);
const canSend = computed(
  () =>
    !disabled &&
    !draft.value.pending &&
    draft.value.body.trim().length > 0 &&
    (threadId != null ? parentId != null : sourceId != null || position != null),
);

watch(mentionCandidates, () => (mentionIndex.value = 0));

/** Members whose `@Name` is still present in the text; typing over a name unmentions them. */
function syncMentionIds() {
  const current = draft.value;
  current.mentionIds = current.mentionIds.filter((id) => {
    const member = availableMembers.value.find((candidate) => candidate.id === id);
    return member != null && current.body.includes(`@${member.display_name}`);
  });
}

function detectMentionQuery() {
  const field = textarea.value;
  if (!field) return;
  const before = field.value.slice(0, field.selectionStart ?? field.value.length);
  const match = /(?:^|\s)@([^\s@]*)$/.exec(before);
  mentionQuery.value = match ? match[1] : null;
}

function onInput() {
  syncMentionIds();
  detectMentionQuery();
}

function openMentionPicker() {
  if (disabled || draft.value.pending || !availableMembers.value.length) return;
  const field = textarea.value;
  if (!field) return;
  field.focus();
  const caret = field.selectionStart ?? field.value.length;
  const before = field.value.slice(0, caret);
  const needsSpace = before.length > 0 && !/\s$/.test(before);
  const insertion = `${needsSpace ? " " : ""}@`;
  draft.value.body = `${before}${insertion}${field.value.slice(caret)}`;
  nextTick(() => {
    const next = caret + insertion.length;
    field.setSelectionRange(next, next);
    mentionQuery.value = "";
  });
}

function insertMention(member: Member) {
  const field = textarea.value;
  const current = draft.value;
  if (!field) return;
  const caret = field.selectionStart ?? current.body.length;
  const before = current.body.slice(0, caret);
  const start = before.search(/(?:^|\s)@[^\s@]*$/);
  const head = start === -1 ? before : before.slice(0, start) + (start > 0 ? " " : "");
  const insertion = `@${member.display_name} `;
  current.body = `${head}${insertion}${current.body.slice(caret)}`;
  if (!current.mentionIds.includes(member.id) && current.mentionIds.length < 50) {
    current.mentionIds.push(member.id);
  }
  mentionQuery.value = null;
  nextTick(() => {
    const next = head.length + insertion.length;
    field.focus();
    field.setSelectionRange(next, next);
  });
}

function onKeydown(event: KeyboardEvent) {
  if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
    event.preventDefault();
    submit();
    return;
  }
  if (!mentionOpen.value) return;
  const count = mentionCandidates.value.length;
  if (event.key === "ArrowDown") {
    event.preventDefault();
    mentionIndex.value = (mentionIndex.value + 1) % count;
  } else if (event.key === "ArrowUp") {
    event.preventDefault();
    mentionIndex.value = (mentionIndex.value - 1 + count) % count;
  } else if (event.key === "Enter" || event.key === "Tab") {
    event.preventDefault();
    insertMention(mentionCandidates.value[mentionIndex.value]);
  } else if (event.key === "Escape") {
    event.preventDefault();
    event.stopPropagation();
    mentionQuery.value = null;
  }
}

function onBlur() {
  focused.value = false;
  // Let a click on a mention candidate land before the list disappears.
  setTimeout(() => {
    if (!focused.value) mentionQuery.value = null;
  }, 150);
}

function ensureRequestIdentity(current: Draft, fingerprint: string, storageKey: string | null) {
  if (current.fingerprint === fingerprint && current.requestId) return;
  current.requestId = crypto.randomUUID();
  current.fingerprint = fingerprint;
  updateCommentDraft(storageKey, {
    requestId: current.requestId,
    fingerprint: current.fingerprint,
  });
}

function createContextReference(): CommentContextReference | null | undefined {
  if (threadId != null || context === undefined) return undefined;
  if (context === null) return null;
  return {
    type: context.type,
    id: context.id,
    ...(context.offset === undefined
      ? {}
      : { offset: context.offset ? { x: context.offset.x, y: context.offset.y } : null }),
  };
}

function clearSubmittedDraft(
  key: string | null,
  requestId: string | null,
  fingerprint: string,
  body: string,
  mentionIds: string,
) {
  const stored = readCommentDraft(key);
  if (!stored) return;
  if (
    stored.requestId === requestId &&
    stored.fingerprint === fingerprint &&
    stored.body?.trim() === body &&
    JSON.stringify(stored.mentionIds ?? []) === mentionIds
  )
    clearCommentDraft(key);
}

function buildPayload(current: Draft, body: string, mentionIds: number[]) {
  const createPosition = threadId == null && position ? { x: position.x, y: position.y } : null;
  const createContext = createContextReference();
  const fingerprint = JSON.stringify({
    sourceId,
    createSourceKey: ui.createSourceKey,
    threadId,
    parentId,
    position: createPosition,
    context: createContext,
    body,
    mentionIds,
  });
  ensureRequestIdentity(current, fingerprint, storageKey.value);
  const createTarget = ui.createSourceKey ? { [ui.createSourceKey]: sourceId } : {};
  const payload = {
    body,
    mention_user_ids: mentionIds,
    client_request_id: current.requestId,
    ...(threadId == null
      ? {
          ...createTarget,
          ...(createPosition ? { position: createPosition } : {}),
          ...(createContext !== undefined ? { context: createContext } : {}),
        }
      : { thread_id: threadId, parent_id: parentId }),
  };
  return { payload, fingerprint };
}

function submit() {
  if (!canSend.value) return;
  const current = draft.value;
  const submittedStorageKey = storageKey.value;
  const storedMentionIds = JSON.stringify(current.mentionIds);
  const body = current.body.trim();
  const mentionIds = [
    ...new Set(current.mentionIds.filter((id) => members.some((member) => member.id === id))),
  ].sort((left, right) => left - right);
  const { payload, fingerprint } = buildPayload(current, body, mentionIds);
  current.pending = true;
  current.error = null;
  mentionQuery.value = null;
  live.pushEvent(
    threadId == null ? "comments_create" : "comments_reply",
    payload,
    (reply) => {
      current.pending = false;
      if (reply.ok === true) {
        clearingDrafts.add(current);
        current.body = "";
        current.mentionIds = [];
        current.requestId = null;
        current.fingerprint = null;
        clearSubmittedDraft(
          submittedStorageKey,
          payload.client_request_id,
          fingerprint,
          body,
          storedMentionIds,
        );
        clearingDrafts.delete(current);
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
  <form
    class="flex items-start gap-2"
    :data-testid="`${ui.domScope}-comment-composer`"
    @submit.prevent="submit"
  >
    <UserAvatar
      v-if="isReply && authorName"
      :display-name="authorName"
      size="xs"
      class="mt-1.5 shrink-0"
    />
    <!-- The composer box anchors the mention list; `open` is controlled, so the
         trigger's own click toggle is ignored. -->
    <Popover :open="mentionOpen">
      <PopoverTrigger as-child>
        <div
          class="min-w-0 flex-1 rounded-lg border bg-background transition-[border-color,box-shadow]"
          :class="
            expanded && focused
              ? 'border-ring ring-[3px] ring-ring/20'
              : 'border-input hover:border-ring/60'
          "
        >
          <div
            v-if="replyTo || replyToPrevious"
            class="flex items-center gap-2 border-b border-border px-2.5 py-1 text-[11px] text-muted-foreground"
          >
            <span class="min-w-0 flex-1 truncate">{{
              replyTo
                ? $t(translationKey("replying_to"), { name: replyTo.display_name })
                : $t(translationKey("reply_to_previous"))
            }}</span>
            <button
              type="button"
              class="shrink-0 rounded p-0.5 hover:text-foreground"
              :aria-label="$t(translationKey('cancel_reply'))"
              @click="emit('cancelReply')"
            >
              <X class="size-3" />
            </button>
          </div>
          <label :for="domId('body')" class="sr-only">{{
            isReply ? $t(translationKey("reply")) : $t(translationKey("new_thread"))
          }}</label>
          <textarea
            :id="domId('body')"
            ref="textarea"
            v-model="draft.body"
            class="block w-full resize-none bg-transparent px-2.5 text-sm outline-none placeholder:text-muted-foreground disabled:opacity-50"
            :class="expanded ? 'min-h-16 py-2' : 'h-8 py-1.5 leading-5 md:h-8'"
            :rows="expanded ? 2 : 1"
            :placeholder="
              isReply ? $t(translationKey('reply_placeholder')) : $t(translationKey('placeholder'))
            "
            :disabled="disabled || draft.pending"
            maxlength="10000"
            @focus="focused = true"
            @blur="onBlur"
            @input="onInput"
            @click="detectMentionQuery"
            @keyup.left.right="detectMentionQuery"
            @keydown="onKeydown"
          />
          <p v-if="draft.error" role="alert" class="px-2.5 pb-1 text-xs text-destructive">
            {{ draft.error }}
          </p>
          <div
            v-if="expanded"
            class="flex items-center gap-2 px-1.5 pb-1.5 pl-2.5 text-[11px] text-muted-foreground"
          >
            <Button
              v-if="ui.mentionsEnabled !== false"
              variant="ghost"
              size="icon-xs"
              type="button"
              class="-ml-1 size-5 text-muted-foreground"
              :aria-label="$t(translationKey('mention'))"
              :title="$t(translationKey('mention'))"
              :disabled="disabled || draft.pending || !availableMembers.length"
              @mousedown.prevent
              @click="openMentionPicker"
              ><AtSign class="size-3"
            /></Button>
            <span class="hidden sm:inline">{{ $t(translationKey("mention_hint")) }}</span>
            <span class="hidden sm:inline">{{ $t(translationKey("send_hint")) }}</span>
            <span class="flex-1" />
            <Button
              :id="domId('send')"
              type="submit"
              size="xs"
              class="gap-1"
              :disabled="!canSend"
              @mousedown.prevent
              ><LoaderCircle v-if="draft.pending" class="size-3 animate-spin" /><Send
                v-else
                class="size-3"
              />{{ $t(translationKey("send")) }}</Button
            >
          </div>
        </div>
      </PopoverTrigger>
      <PopoverContent
        align="start"
        side="bottom"
        :side-offset="4"
        class="w-64 p-1"
        :aria-label="$t(translationKey('search_people'))"
        @open-auto-focus.prevent
        @close-auto-focus.prevent
      >
        <ul role="listbox" class="max-h-48 overflow-y-auto">
          <li
            v-for="(member, index) in mentionCandidates"
            :key="member.id"
            role="option"
            :aria-selected="index === mentionIndex"
            class="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-sm"
            :class="{ 'bg-accent': index === mentionIndex }"
            @mousedown.prevent
            @mouseenter="mentionIndex = index"
            @click="insertMention(member)"
          >
            <UserAvatar :display-name="member.display_name" size="xs" />
            <span class="truncate">{{ member.display_name }}</span>
          </li>
        </ul>
      </PopoverContent>
    </Popover>
  </form>
</template>
