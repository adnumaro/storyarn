import { nextTick, onUnmounted, watch } from "vue";
import {
  clearCommentDraft,
  readCommentDraft,
  updateCommentDraft,
} from "@components/comments/commentDraftStorage";
import type { CommentMagneticInitial } from "@components/comments/commentMagnetism";
import type { SceneCommentsPanelState } from "../../types/comments";
import type { useLive } from "@shared/composables/useLive";

interface SceneDraftRecoveryOptions {
  state: () => SceneCommentsPanelState;
  storageKey: () => string | null;
  placement: () => CommentMagneticInitial | null;
  ready: () => boolean;
  live: ReturnType<typeof useLive>;
}

/** Recover Scene drafts without clearing text on LiveView reconnect. */
export function useSceneCommentDraftRecovery(options: SceneDraftRecoveryOptions) {
  let disposed = false;
  let restoringKey: string | null = null;
  let request = 0;
  let recoveryAllowed = true;

  function canRestore() {
    const state = options.state();
    return (
      recoveryAllowed &&
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
      if (active()) {
        restoringKey = null;
        recoveryAllowed = false;
      }
    };
    options.live.pushEvent(
      "comments_place",
      { ...position, context: stored.context ?? null },
      (reply) => {
        if (!active()) return;
        if (
          reply.ok !== true &&
          reply.context_unavailable === true &&
          stored.context &&
          canRestore()
        ) {
          options.live.pushEvent("comments_place", { ...position, context: null }, finish, finish);
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
    (current) => {
      if (current.placement)
        updateCommentDraft(current.key, { coordinateSpace: "canvas", ...current.placement });
    },
    { immediate: true },
  );
  watch(options.storageKey, async () => {
    request++;
    recoveryAllowed = true;
    restoringKey = null;
    await nextTick();
    if (!disposed) restoreStoredDraft();
  });
  // A newer interaction disables recovery until the next mount/key, including
  // deliberate closes caused by tool switches followed by a canvas resize. It invalidates recovery even if the user closes it before
  // the old reply arrives (closed -> new draft -> closed is not the same state).
  watch(
    () => [
      options.state().open,
      options.state().placing,
      options.state().thread?.id,
      options.state().draftId,
    ],
    () => {
      request++;
      restoringKey = null;
      recoveryAllowed = false;
    },
    { flush: "sync" },
  );
  onUnmounted(() => {
    disposed = true;
    request++;
  });
  function discardStoredDraft() {
    request++;
    recoveryAllowed = false;
    restoringKey = null;
    if (options.placement()) clearCommentDraft(options.storageKey());
  }
  return { restoreStoredDraft, discardStoredDraft };
}
