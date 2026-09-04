<script setup lang="ts">
import {
  ArrowLeft,
  AtSign,
  Check,
  CheckCheck,
  CornerUpLeft,
  MessageCircle,
  RotateCcw,
  X,
} from "@lucide/vue";
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import { useLive } from "@shared/composables/useLive";
import FlowCommentComposer from "./FlowCommentComposer.vue";
import type {
  CommentStatus,
  CommentStatusFilter,
  FlowCommentsPanelState,
} from "../../../../types/comments";

const { state, embedded = false } = defineProps<{
  state: FlowCommentsPanelState;
  embedded?: boolean;
}>();
const live = useLive();
const { t, locale } = useI18n();
const replyToId = ref<number | null>(null);
const statusPending = ref(false);
const localError = ref<string | null>(null);
let statusRequestToken: symbol | null = null;
const filter = computed(() => state.statusFilter ?? "open");
const sourceAvailable = computed(() => !state.thread || state.thread.source.status === "available");
const composerEnabled = computed(
  () =>
    state.canComment &&
    sourceAvailable.value &&
    (state.thread
      ? state.thread.status === "open"
      : state.selectedNodeId != null || state.draftPosition != null),
);
const firstMessage = computed(
  () => state.messages.find((message) => message.parent_id == null) ?? state.messages[0],
);
const replyParentId = computed(
  () => replyToId.value ?? state.thread?.root_message_id ?? firstMessage.value?.id ?? null,
);
const replyTo = computed(() => state.messages.find((message) => message.id === replyToId.value));

watch(
  () => state.thread?.id,
  () => {
    statusRequestToken = null;
    replyToId.value = null;
    localError.value = null;
    statusPending.value = false;
  },
  { flush: "sync" },
);

function formatDate(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.valueOf())
    ? ""
    : new Intl.DateTimeFormat(locale.value, { dateStyle: "medium", timeStyle: "short" }).format(
        date,
      );
}

function selectFilter(event: Event) {
  const status = (event.target as HTMLSelectElement).value as CommentStatusFilter;
  live.pushEvent("comments_filter", { status });
}

function changeStatus(status: CommentStatus) {
  const thread = state.thread;
  if (!thread || !state.canComment || !sourceAvailable.value || statusPending.value) return;
  const requestToken = Symbol();
  statusRequestToken = requestToken;
  statusPending.value = true;
  localError.value = null;
  live.pushEvent(
    "comments_set_status",
    { thread_id: thread.id, status, expected_revision: thread.revision },
    (reply) => {
      if (statusRequestToken !== requestToken || state.thread?.id !== thread.id) return;
      statusRequestToken = null;
      statusPending.value = false;
      if (reply.ok !== true)
        localError.value =
          typeof reply.error === "string" ? reply.error : t("flows.comments.update_failed");
    },
    () => {
      if (statusRequestToken !== requestToken || state.thread?.id !== thread.id) return;
      statusRequestToken = null;
      statusPending.value = false;
      localError.value = t("flows.comments.update_failed");
    },
  );
}
</script>

<template>
  <div id="flow-comments-content" class="space-y-4 pb-2">
    <p
      v-if="state.error || localError"
      role="alert"
      class="rounded-md bg-destructive/10 p-2 text-xs text-destructive"
    >
      {{ localError || state.error }}
    </p>

    <template v-if="state.thread">
      <div class="space-y-2">
        <Button
          v-if="!embedded"
          variant="ghost"
          size="sm"
          class="-ml-2 gap-1.5 text-xs text-muted-foreground"
          @click="live.pushEvent('comments_open', {})"
          ><ArrowLeft class="size-3.5" />{{ $t("flows.comments.all_threads") }}</Button
        >
        <div class="flex items-start justify-between gap-2">
          <div class="min-w-0">
            <p class="truncate text-sm font-medium">
              {{
                state.thread.source.type === "flow_canvas"
                  ? $t("flows.comments.canvas_label")
                  : state.thread.source.label
              }}
            </p>
            <p class="mt-1 flex items-center gap-1 text-xs text-muted-foreground">
              <CheckCheck v-if="state.thread.status === 'resolved'" class="size-3.5" />{{
                $t(`flows.comments.${state.thread.status}`)
              }}
            </p>
          </div>
          <Button
            v-if="state.canComment && sourceAvailable"
            id="flow-comment-status"
            variant="outline"
            size="sm"
            class="shrink-0 gap-1.5 text-xs"
            :disabled="statusPending"
            @click="changeStatus(state.thread.status === 'open' ? 'resolved' : 'open')"
            ><Check v-if="state.thread.status === 'open'" class="size-3.5" /><RotateCcw
              v-else
              class="size-3.5"
            />{{
              $t(
                state.thread.status === "open" ? "flows.comments.resolve" : "flows.comments.reopen",
              )
            }}</Button
          >
        </div>
      </div>
      <p
        v-if="!sourceAvailable"
        role="status"
        class="rounded-md bg-muted p-2 text-xs text-muted-foreground"
      >
        {{
          $t(
            state.thread.source.type === "flow_canvas"
              ? "flows.comments.canvas_unavailable"
              : "flows.comments.unavailable",
          )
        }}
      </p>
      <ol class="space-y-3" aria-live="polite" :aria-label="$t('flows.comments.messages')">
        <li
          v-for="message in state.messages"
          :id="`flow-comment-message-${message.id}`"
          :key="message.id"
          class="rounded-lg border border-border bg-background p-3"
          :class="{ 'ring-1 ring-primary': replyToId === message.id }"
        >
          <div class="mb-2 flex items-center gap-2">
            <img
              v-if="message.author.avatar_url"
              :src="message.author.avatar_url"
              alt=""
              class="size-6 rounded-full object-cover"
            />
            <span
              v-else
              class="flex size-6 shrink-0 items-center justify-center rounded-full bg-muted text-[10px] font-semibold"
              aria-hidden="true"
              >{{ message.author.display_name.slice(0, 2).toUpperCase() }}</span
            >
            <div class="min-w-0">
              <p class="truncate text-xs font-medium">{{ message.author.display_name }}</p>
              <time :datetime="message.inserted_at" class="text-[10px] text-muted-foreground">{{
                formatDate(message.inserted_at)
              }}</time>
            </div>
          </div>
          <p class="whitespace-pre-wrap break-words text-sm leading-relaxed">
            {{ message.body }}
          </p>
          <div v-if="message.mentions.length" class="mt-2 flex flex-wrap gap-1">
            <span
              v-for="(member, index) in message.mentions"
              :key="member.id ?? `deleted-${index}`"
              class="inline-flex items-center gap-0.5 rounded bg-primary/10 px-1.5 py-0.5 text-xs text-primary"
              ><AtSign class="size-3" />{{ member.display_name }}</span
            >
          </div>
          <Button
            v-if="composerEnabled"
            variant="ghost"
            size="sm"
            class="-mb-1 -ml-2 mt-1 gap-1.5 text-xs text-muted-foreground"
            :aria-label="$t('flows.comments.reply_to', { name: message.author.display_name })"
            @click="replyToId = message.id"
            ><CornerUpLeft class="size-3" />{{ $t("flows.comments.reply") }}</Button
          >
        </li>
      </ol>
      <Button
        v-if="state.messageNextCursor"
        variant="ghost"
        size="sm"
        class="w-full"
        @click="live.pushEvent('comments_load_messages', {})"
        >{{ $t("flows.comments.load_messages") }}</Button
      >
      <p
        v-if="state.thread.status === 'resolved' && sourceAvailable"
        class="rounded-md bg-muted p-2 text-xs text-muted-foreground"
      >
        {{ $t("flows.comments.resolved_hint") }}
      </p>
    </template>

    <template v-else-if="!embedded">
      <div class="flex items-center justify-between gap-2">
        <p class="text-xs text-muted-foreground">
          {{
            state.selectedNodeId == null
              ? $t("flows.comments.flow_threads")
              : state.selectedNodeLabel ||
                $t("flows.comments.node_label", { id: state.selectedNodeId })
          }}
        </p>
        <select
          id="flow-comments-filter"
          :value="filter"
          :aria-label="$t('flows.comments.filter')"
          class="rounded-md border border-input bg-background px-2 py-1 text-xs"
          @change="selectFilter"
        >
          <option value="open">{{ $t("flows.comments.open") }}</option>
          <option value="resolved">{{ $t("flows.comments.resolved") }}</option>
          <option value="all">{{ $t("flows.comments.all") }}</option>
        </select>
      </div>
      <div
        v-if="!state.threads.length"
        class="rounded-lg border border-dashed border-border px-4 py-6 text-center"
      >
        <MessageCircle class="mx-auto mb-2 size-6 text-muted-foreground/60" />
        <p class="text-sm font-medium">{{ $t("flows.comments.empty") }}</p>
        <p class="mt-1 text-xs leading-relaxed text-muted-foreground">
          {{
            state.canComment ? $t("flows.comments.empty_hint") : $t("flows.comments.readonly_hint")
          }}
        </p>
      </div>
      <ol v-else class="space-y-2" :aria-label="$t('flows.comments.threads')">
        <li v-for="thread in state.threads" :key="thread.id">
          <button
            :id="`flow-comment-thread-${thread.id}`"
            type="button"
            class="w-full rounded-lg border border-border p-3 text-left transition-colors hover:border-primary/40 hover:bg-muted/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            @click="live.pushEvent('comments_select_thread', { thread_id: thread.id })"
          >
            <div class="flex items-center justify-between gap-2">
              <span class="truncate text-xs font-medium">{{
                thread.source.type === "flow_canvas"
                  ? $t("flows.comments.canvas_label")
                  : thread.source.label
              }}</span
              ><CheckCheck
                v-if="thread.status === 'resolved'"
                class="size-3.5 shrink-0 text-muted-foreground"
                :aria-label="$t('flows.comments.resolved')"
              />
            </div>
            <p v-if="thread.preview" class="mt-1.5 line-clamp-2 break-words text-sm">
              {{ thread.preview }}
            </p>
            <div
              class="mt-2 flex items-center justify-between gap-2 text-[11px] text-muted-foreground"
            >
              <span class="truncate">{{ thread.author.display_name }}</span
              ><span class="flex shrink-0 items-center gap-1"
                ><MessageCircle class="size-3" />{{ thread.message_count }}</span
              >
            </div>
            <p
              v-if="thread.source.status === 'unavailable'"
              class="mt-1 text-[11px] text-muted-foreground"
            >
              {{ $t("flows.comments.source_unavailable") }}
            </p>
          </button>
        </li>
      </ol>
      <Button
        v-if="state.nextCursor"
        variant="ghost"
        size="sm"
        class="w-full"
        @click="live.pushEvent('comments_load_more', {})"
        >{{ $t("flows.comments.load_threads") }}</Button
      >
    </template>

    <div
      v-if="state.canComment"
      v-show="composerEnabled"
      :class="{ 'border-t border-border pt-3': !embedded || state.thread }"
    >
      <div
        v-if="replyTo"
        class="mb-2 flex items-center justify-between gap-2 rounded-md bg-muted p-2 text-xs"
      >
        <span class="truncate">{{
          $t("flows.comments.reply_to", { name: replyTo.author.display_name })
        }}</span
        ><button
          type="button"
          :aria-label="$t('flows.comments.cancel_reply')"
          @click="replyToId = null"
        >
          <X class="size-3.5" />
        </button>
      </div>
      <FlowCommentComposer
        :node-id="state.selectedNodeId"
        :position="state.draftPosition ?? null"
        :draft-id="state.draftId ?? null"
        :thread-id="state.thread?.id ?? null"
        :parent-id="replyParentId"
        :members="state.members"
        :disabled="!composerEnabled"
        @sent="replyToId = null"
      />
    </div>
    <p v-if="!state.canComment" class="text-xs text-muted-foreground">
      {{ $t("flows.comments.readonly_hint") }}
    </p>
    <p
      v-else-if="
        !state.thread &&
        state.selectedNodeId == null &&
        !state.draftPosition &&
        state.threads.length
      "
      class="text-xs text-muted-foreground"
    >
      {{ $t("flows.comments.empty_hint") }}
    </p>
  </div>
</template>
