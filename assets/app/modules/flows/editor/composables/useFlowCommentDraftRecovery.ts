import { nextTick, onUnmounted, watch } from "vue";
import {
  clearCommentDraft,
  readCommentDraft,
  updateCommentDraft,
} from "@components/comments/commentDraftStorage";
import type { CommentMagneticInitial } from "@components/comments/commentMagnetism";
import type { FlowCommentsPanelState } from "../../types/comments";
import type { useLive } from "@shared/composables/useLive";

interface FlowDraftRecoveryOptions {
  state: () => FlowCommentsPanelState;
  storageKey: () => string | null;
  placement: () => CommentMagneticInitial | null;
  ready: () => boolean;
  live: ReturnType<typeof useLive>;
}

interface DraftSnapshot {
  key: string | null;
  open: boolean;
  canvas: boolean;
  threadId: number | null;
  placement: CommentMagneticInitial | null;
}

function draftClosed(current: DraftSnapshot, previous?: DraftSnapshot) {
  return (
    previous?.canvas &&
    previous.open &&
    previous.placement &&
    !previous.threadId &&
    !current.open &&
    !current.threadId &&
    !current.placement
  );
}

/** Recover only canvas drafts; node-scoped Sequence composers keep their own storage. */
export function useFlowCommentDraftRecovery(options: FlowDraftRecoveryOptions) {
  let disposed = false;
  let restoringKey: string | null = null;
  let request = 0;

  function canRestore() {
    const state = options.state();
    return (
      options.ready() &&
      state.canComment &&
      !state.placing &&
      !state.open &&
      !state.thread &&
      !state.draftPosition
    );
  }

  function restoreStoredDraft() {
    const key = options.storageKey();
    if (!key || restoringKey === key || !canRestore()) return;
    const stored = readCommentDraft(key);
    if (stored?.coordinateSpace !== "canvas" || !stored.position) return;
    const position = stored.position;
    restoringKey = key;
    const currentRequest = ++request;
    const active = () => !disposed && request === currentRequest && options.storageKey() === key;
    const finish = () => {
      if (active()) restoringKey = null;
    };
    options.live.pushEvent(
      "comments_place",
      { node_id: null, ...position, context: stored.context ?? null },
      (reply) => {
        if (!active()) return;
        if (
          reply.ok !== true &&
          reply.context_unavailable === true &&
          stored.context &&
          canRestore()
        ) {
          options.live.pushEvent(
            "comments_place",
            { node_id: null, ...position, context: null },
            finish,
            finish,
          );
        } else finish();
      },
      finish,
    );
  }

  watch(
    () => ({
      key: options.storageKey(),
      open: options.state().open,
      canvas: options.state().presentation === "canvas",
      threadId: options.state().thread?.id ?? null,
      placement: options.placement(),
    }),
    (current, previous) => {
      if (current.placement)
        updateCommentDraft(current.key, { coordinateSpace: "canvas", ...current.placement });
      if (current.key !== previous?.key) return;
      if (draftClosed(current, previous)) clearCommentDraft(current.key);
    },
    { immediate: true },
  );
  watch(options.storageKey, async () => {
    request++;
    restoringKey = null;
    await nextTick();
    if (!disposed) restoreStoredDraft();
  });
  // A newer interaction invalidates recovery even if the user closes it before
  // the old reply arrives (closed -> new draft -> closed is not the same state).
  watch(
    () => [
      options.state().open,
      options.state().placing,
      options.state().thread?.id,
      options.state().draftId,
    ],
    () => {
      if (!canRestore()) {
        request++;
        restoringKey = null;
      }
    },
    { flush: "sync" },
  );
  onUnmounted(() => {
    disposed = true;
    request++;
  });
  return { restoreStoredDraft };
}
