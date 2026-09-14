import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { useLive } from "@shared/composables/useLive";
import type { CommentStatus, CommentsPanelState, CommentUiConfig } from "./types";

export type CommentThreadActions = ReturnType<typeof useCommentThreadActions>;

/**
 * Thread-level actions shared by the conversation header and footer: resolve /
 * reopen (revision-checked), follow, mark read and copy link. One request at a
 * time; a reply for a superseded thread is ignored.
 */
export function useCommentThreadActions(
  state: () => CommentsPanelState,
  ui: CommentUiConfig,
  permalink: () => string | null,
) {
  const live = useLive();
  const { t } = useI18n();
  const pending = ref(false);
  const error = ref<string | null>(null);
  const linkCopied = ref(false);
  let token: symbol | null = null;
  let copiedTimer: ReturnType<typeof setTimeout> | null = null;
  const key = (name: string) => `${ui.i18nPrefix}.${name}`;

  const thread = computed(() => state().thread);
  const sourceAvailable = computed(() => thread.value?.source.status === "available");
  const canChangeStatus = computed(
    () => Boolean(thread.value) && state().canComment && sourceAvailable.value,
  );

  watch(
    () => thread.value?.id,
    () => {
      token = null;
      pending.value = false;
      error.value = null;
    },
    { flush: "sync" },
  );

  function request(event: string, payload: Record<string, unknown>) {
    const current = thread.value;
    if (!current || pending.value) return;
    const mine = Symbol();
    token = mine;
    pending.value = true;
    error.value = null;
    const finish = (message: string | null) => {
      if (token !== mine || thread.value?.id !== current.id) return;
      token = null;
      pending.value = false;
      error.value = message;
    };
    live.pushEvent(
      event,
      { thread_id: current.id, ...payload },
      (reply) => {
        if (reply.ok === true) finish(null);
        else finish(typeof reply.error === "string" ? reply.error : t(key("update_failed")));
      },
      () => finish(t(key("update_failed"))),
    );
  }

  function setStatus(status: CommentStatus) {
    if (!canChangeStatus.value || !thread.value) return;
    request("comments_set_status", { status, expected_revision: thread.value.revision });
  }

  function toggleFollow() {
    if (!thread.value) return;
    request("comments_follow", { following: !thread.value.following });
  }

  function markRead() {
    if (!thread.value?.last_message_id) return;
    request("comments_read", { message_id: thread.value.last_message_id });
  }

  async function copyLink() {
    const url = permalink();
    if (!url || typeof navigator === "undefined" || !navigator.clipboard) return;
    try {
      await navigator.clipboard.writeText(url);
      linkCopied.value = true;
      if (copiedTimer) clearTimeout(copiedTimer);
      copiedTimer = setTimeout(() => (linkCopied.value = false), 2000);
    } catch {
      error.value = t(key("copy_failed"));
    }
  }

  return {
    pending,
    error,
    linkCopied,
    canChangeStatus,
    sourceAvailable,
    setStatus,
    toggleFollow,
    markRead,
    copyLink,
  };
}

/** The permalink of the current page pointing at a thread, built from the live location. */
export function currentPagePermalink(threadId: number): string | null {
  if (typeof window === "undefined") return null;
  const url = new URL(window.location.href);
  url.searchParams.set("thread", String(threadId));
  return url.toString();
}
