<script setup lang="ts">
import { AtSign, LoaderCircle, Send, X } from "@lucide/vue";
import { computed, reactive, ref } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import { useLive } from "@shared/composables/useLive";
import type { CommentMember } from "../../../../types/comments";

interface Draft {
  body: string;
  mentionIds: number[];
  requestId: string | null;
  fingerprint: string | null;
  pending: boolean;
  error: string | null;
}

const {
  nodeId,
  threadId = null,
  parentId = null,
  members,
  disabled = false,
} = defineProps<{
  nodeId: number | null;
  threadId?: number | null;
  parentId?: number | null;
  members: CommentMember[];
  disabled?: boolean;
}>();

const emit = defineEmits<{ sent: [] }>();
const live = useLive();
const { t } = useI18n();
const drafts = reactive(new Map<string, Draft>());
const memberSearch = ref("");
const mentionOpen = ref(false);
const draft = computed(() => {
  const key = threadId == null ? `node:${nodeId}` : `thread:${threadId}:parent:${parentId}`;
  let value = drafts.get(key);
  if (!value) {
    drafts.set(key, {
      body: "",
      mentionIds: [],
      requestId: null,
      fingerprint: null,
      pending: false,
      error: null,
    });
    value = drafts.get(key)!;
  }
  return value;
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
    (threadId != null ? parentId != null : nodeId != null),
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

function submit() {
  if (!canSend.value) return;
  const current = draft.value;
  const body = current.body.trim();
  const mentionIds = [
    ...new Set(current.mentionIds.filter((id) => members.some((member) => member.id === id))),
  ].sort((left, right) => left - right);
  const fingerprint = JSON.stringify({ nodeId, threadId, parentId, body, mentionIds });
  if (current.fingerprint !== fingerprint || !current.requestId) {
    current.requestId = crypto.randomUUID();
    current.fingerprint = fingerprint;
  }
  const payload = {
    body,
    mention_user_ids: mentionIds,
    client_request_id: current.requestId,
    ...(threadId == null ? { node_id: nodeId } : { thread_id: threadId, parent_id: parentId }),
  };
  current.pending = true;
  current.error = null;
  live.pushEvent(
    threadId == null ? "comments_create" : "comments_reply",
    payload,
    (reply) => {
      current.pending = false;
      if (reply.ok === true) {
        current.body = "";
        current.mentionIds = [];
        current.requestId = null;
        current.fingerprint = null;
        emit("sent");
      } else {
        current.error =
          typeof reply.error === "string" ? reply.error : t("flows.comments.send_failed");
      }
    },
    () => {
      current.pending = false;
      current.error = t("flows.comments.send_failed");
    },
  );
}
</script>

<template>
  <form class="space-y-2" data-testid="flow-comment-composer" @submit.prevent="submit">
    <label for="flow-comment-body" class="text-xs font-medium">{{
      threadId == null ? $t("flows.comments.new_thread") : $t("flows.comments.reply")
    }}</label>
    <textarea
      id="flow-comment-body"
      v-model="draft.body"
      class="min-h-24 w-full resize-y rounded-md border border-input bg-background px-3 py-2 text-sm outline-none transition-shadow placeholder:text-muted-foreground focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-50"
      :placeholder="$t('flows.comments.placeholder')"
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
        :aria-label="$t('flows.comments.remove_mention', { name: member.display_name })"
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
            ><AtSign class="size-3.5" />{{ $t("flows.comments.mention") }}</Button
          >
        </PopoverTrigger>
        <PopoverContent class="w-64 p-2" align="start">
          <input
            v-model="memberSearch"
            :aria-label="$t('flows.comments.search_people')"
            :placeholder="$t('flows.comments.search_people')"
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
              {{ $t("flows.comments.no_people") }}
            </p>
          </div>
        </PopoverContent>
      </Popover>
      <Button id="flow-comment-send" type="submit" size="sm" class="gap-1.5" :disabled="!canSend"
        ><LoaderCircle v-if="draft.pending" class="size-3.5 animate-spin" /><Send
          v-else
          class="size-3.5"
        />{{ $t("flows.comments.send") }}</Button
      >
    </div>
  </form>
</template>
