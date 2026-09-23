import { provide } from "vue";
import { useI18n } from "vue-i18n";
import { useLive, type LiveInterface } from "@shared/composables/useLive";
import type { BrainstormingCommentsState } from "../commentTypes";

/**
 * Shared comment components keep their ordinary event contract; this boundary
 * binds every request to the board generation and the selected discussion context.
 */
export function useCommentBridge(
  state: () => BrainstormingCommentsState,
  board: () => { epoch: string; sessionId: number },
) {
  const live = useLive();
  const { t } = useI18n();
  const message = (code: unknown) =>
    t(`brainstormingComments.${code === "stale" ? "stale" : "unavailable"}`);
  provide<LiveInterface>("_live_vue", {
    ...live,
    pushEvent(event, payload, callback, onError) {
      const current = state();
      live.pushEvent(
        event,
        {
          ...payload,
          epoch: board().epoch,
          session_id: board().sessionId,
          comment_context: current.context,
          ...(event === "comments_open"
            ? { idea_id: current.ideaId, group_id: current.groupId ?? null }
            : {}),
        },
        (reply) =>
          callback?.(
            reply?.ok === false && !event.startsWith("comments_follow") && event !== "comments_read"
              ? { ...reply, error: message(reply.error) }
              : reply,
          ),
        onError,
      );
    },
  });
  return { message };
}
